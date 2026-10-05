package main

import (
	"encoding/base64"
	"encoding/json"
	"io"
	"maps"
	"net/http"
	"slices"
	"sync"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/update"
)

// The made-up head of the branch main of acme/data, its tree, and the tree
// and commit the command creates.
const (
	headCommit    = "5555555555555555555555555555555555555555"
	headTree      = "6666666666666666666666666666666666666666"
	createdTree   = "7777777777777777777777777777777777777777"
	createdCommit = "8888888888888888888888888888888888888888"
)

// callerBody is a caller file of an installation that calls the workflow of
// pin, pinned as it says.
func callerBody(pin update.Target) string {
	return "jobs:\n  call:\n    uses: yveshanoulle/forsgren/.github/workflows/" + pin.Workflow +
		"@" + pin.SHA + " # " + pin.Version + "\n    secrets: inherit\n"
}

// contentsAnswer is GitHub's answer for a file with this content.
func contentsAnswer(t *testing.T, content string) answer {
	t.Helper()
	return answer{200, jsonOf(t, map[string]string{
		"type": "file", "encoding": "base64", "content": base64.StdEncoding.EncodeToString([]byte(content)),
	})}
}

// sentBodies is a test server of the API that answers each "METHOD path" and
// keeps the bodies and the queries it was sent.
type sentBodies struct {
	mu      sync.Mutex
	bodies  map[string]string
	queries map[string]string
}

// serveRecorded points the commands at a server that gives each "METHOD
// path" its answer, 404 to any other, and records what it was sent.
func serveRecorded(t *testing.T, answers map[string]answer) *sentBodies {
	t.Helper()
	sent := &sentBodies{bodies: map[string]string{}, queries: map[string]string{}}
	serveAPI(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		key := r.Method + " " + r.URL.Path
		sent.mu.Lock()
		sent.bodies[key], sent.queries[key] = string(body), r.URL.RawQuery
		sent.mu.Unlock()
		a, ok := answers[key]
		if !ok {
			a = answer{code: http.StatusNotFound, body: `{"message":"Not Found"}`}
		}
		w.WriteHeader(a.code)
		_, _ = w.Write([]byte(a.body))
	})
	return sent
}

// bodyJSON is the JSON body sent to "METHOD path", decoded.
func (s *sentBodies) bodyJSON(t *testing.T, key string) map[string]any {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	var body map[string]any
	if err := json.Unmarshal([]byte(s.bodies[key]), &body); err != nil {
		t.Fatalf("want a JSON body sent to %s, got %q: %v", key, s.bodies[key], err)
	}
	return body
}

// installFlags are install-update's four flags for v0.1.4 on main.
func installFlags() []string {
	return []string{"install-update", "--repo", "acme/data", "--branch", "main", "--version", "v0.1.4", "--sha", newPinSHA}
}

// installAnswers are the answers of acme/data's branch main at headCommit,
// whose two caller files pin v0.1.3, and of the writes that follow.
func installAnswers(t *testing.T) map[string]answer {
	t.Helper()
	git, files := "/repos/acme/data/git/", "/repos/acme/data/contents/.github/workflows/"
	return map[string]answer{
		"GET " + git + "ref/heads/main": {200, `{"object": {"sha": "` + headCommit + `"}}`},
		"GET " + files + "forsgren.yml": contentsAnswer(t, callerBody(
			update.Target{Workflow: "metrics.yml", Version: "v0.1.3", SHA: oldPinSHA})),
		"GET " + files + "forsgren-update.yml": contentsAnswer(t, callerBody(
			update.Target{Workflow: "auto_update.yml", Version: "v0.1.3", SHA: oldPinSHA})),
		"GET " + git + "commits/" + headCommit: {200, `{"tree": {"sha": "` + headTree + `"}}`},
		"POST " + git + "trees":                {201, `{"sha": "` + createdTree + `"}`},
		"POST " + git + "commits":              {201, `{"sha": "` + createdCommit + `"}`},
		"PATCH " + git + "refs/heads/main":     {200, `{"object": {"sha": "` + createdCommit + `"}}`},
	}
}

// TestInstallUpdateMovesBothCallersAtTheHeadInOneCommit (forsgren#62, step
// 4): the caller files are read at the head of the branch (the commit its ref
// is at), each pin is moved to v0.1.4 and its sha, all files are written in
// one commit that follows that head, the ref is moved without force, and the
// command says what it installed and exits 0.
func TestInstallUpdateMovesBothCallersAtTheHeadInOneCommit(t *testing.T) {
	sent := serveRecorded(t, installAnswers(t))
	t.Setenv("GITHUB_TOKEN", "sesame-sesame-sesame")
	got := runOutcome(installFlags())
	want := outcome{code: 0, stdout: "installed v0.1.4 on main as " + createdCommit + "\n"}
	if got != want {
		t.Fatalf("want exit 0 and %q, got %d, %q, stderr %q", want.stdout, got.code, got.stdout, got.stderr)
	}
	wantReadAtHead(t, sent)
	wantCommittedOnHead(t, sent)
}

// wantReadAtHead fails unless both caller files were read at the head commit.
func wantReadAtHead(t *testing.T, sent *sentBodies) {
	t.Helper()
	files := "/repos/acme/data/contents/.github/workflows/"
	for _, name := range []string{"forsgren.yml", "forsgren-update.yml"} {
		if q := sent.queries["GET "+files+name]; q != "ref="+headCommit {
			t.Errorf("%s: want it read at the head commit, got the query %q", name, q)
		}
	}
}

// wantCommittedOnHead fails unless the tree carries both repinned bodies, the
// commit follows the head and the ref moves to it without force.
func wantCommittedOnHead(t *testing.T, sent *sentBodies) {
	t.Helper()
	git := "/repos/acme/data/git/"
	wantContents := map[string]string{
		".github/workflows/forsgren.yml": callerBody(
			update.Target{Workflow: "metrics.yml", Version: "v0.1.4", SHA: newPinSHA}),
		".github/workflows/forsgren-update.yml": callerBody(
			update.Target{Workflow: "auto_update.yml", Version: "v0.1.4", SHA: newPinSHA}),
	}
	if tree := treeContents(sent.bodyJSON(t, "POST "+git+"trees")); !maps.Equal(tree, wantContents) {
		t.Errorf("want the tree files %v, got %v", wantContents, tree)
	}
	if ref := sent.bodyJSON(t, "PATCH "+git+"refs/heads/main"); ref["force"] != false || ref["sha"] != createdCommit {
		t.Errorf("want the ref moved to %s without force, got %v", createdCommit, ref)
	}
	if commit := sent.bodyJSON(t, "POST "+git+"commits"); !slices.Equal(parentsOf(commit), []string{headCommit}) {
		t.Errorf("want the commit to follow the head %s, got %v", headCommit, commit)
	}
}

// treeContents are the path and content of each entry of a tree request.
func treeContents(request map[string]any) map[string]string {
	files := map[string]string{}
	entries, _ := request["tree"].([]any)
	for _, e := range entries {
		entry, _ := e.(map[string]any)
		path, _ := entry["path"].(string)
		content, _ := entry["content"].(string)
		files[path] = content
	}
	return files
}

// parentsOf are the parents of a commit request.
func parentsOf(request map[string]any) []string {
	var parents []string
	list, _ := request["parents"].([]any)
	for _, p := range list {
		s, _ := p.(string)
		parents = append(parents, s)
	}
	return parents
}

// TestInstallUpdateNeedsItsFourFlags: a missing --sha is a usage error, exit
// 2, naming the flag, and nothing is asked of GitHub.
func TestInstallUpdateNeedsItsFourFlags(t *testing.T) {
	asked := recordedAPI(t, map[string]answer{})
	got := runOutcome([]string{"install-update", "--repo", "acme/data", "--branch", "main", "--version", "v0.1.4"})
	wantExit2(t, got, "install-update", "--sha")
	if paths := asked(); len(paths) != 0 {
		t.Errorf("want no request, got %v", paths)
	}
}
