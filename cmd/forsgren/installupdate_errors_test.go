package main

import (
	"maps"
	"slices"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/update"
)

// Keys of the answers of installAnswers.
const (
	installRef      = "GET /repos/acme/data/git/ref/heads/main"
	installMetrics  = "GET /repos/acme/data/contents/.github/workflows/forsgren.yml"
	installUpdateYM = "GET /repos/acme/data/contents/.github/workflows/forsgren-update.yml"
	installRefMove  = "PATCH /repos/acme/data/git/refs/heads/main"
)

// TestInstallUpdateIsExit2WhenSomethingFails: no head, a caller that cannot
// be read, a caller with no pin line, no caller at the head and a ref update
// the server refuses are each exit 2 with nothing on stdout, naming
// install-update and what failed.
func TestInstallUpdateIsExit2WhenSomethingFails(t *testing.T) {
	notFound := answer{404, `{"message": "Not Found"}`}
	cases := []struct {
		name   string
		change map[string]answer
		parts  []string
	}{
		{"no head", map[string]answer{installRef: notFound}, []string{"ref/heads/main"}},
		{"a caller that cannot be read", map[string]answer{installMetrics: {500, `{"message": "boom"}`}},
			[]string{"forsgren.yml"}},
		{"a caller with no pin line", map[string]answer{installMetrics: contentsAnswer(t, "jobs: {}\n")},
			[]string{".github/workflows/forsgren.yml", "metrics.yml"}},
		{"no caller at the head", map[string]answer{installMetrics: notFound, installUpdateYM: notFound},
			[]string{"no caller file", "main"}},
		{"a ref update the server refuses", map[string]answer{installRefMove: {422, `{"message": "no"}`}},
			[]string{"moving the branch main"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			answers := installAnswers(t)
			maps.Copy(answers, c.change)
			serveRecorded(t, answers)
			t.Setenv("GITHUB_TOKEN", "sesame-sesame-sesame")
			wantExit2(t, runOutcome(installFlags()), append([]string{"install-update"}, c.parts...)...)
		})
	}
}

// TestInstallUpdateSkipsACallerThatIsNotAtTheHead: an installation with only
// forsgren.yml gets that one file moved, in the tree and nowhere else.
func TestInstallUpdateSkipsACallerThatIsNotAtTheHead(t *testing.T) {
	answers := installAnswers(t)
	answers[installUpdateYM] = answer{404, `{"message": "Not Found"}`}
	sent := serveRecorded(t, answers)
	t.Setenv("GITHUB_TOKEN", "sesame-sesame-sesame")
	got := runOutcome(installFlags())
	if got.code != 0 {
		t.Fatalf("want exit 0, got %d, %q, stderr %q", got.code, got.stdout, got.stderr)
	}
	want := map[string]string{".github/workflows/forsgren.yml": callerBody(
		update.Target{Workflow: "metrics.yml", Version: "v0.1.4", SHA: newPinSHA})}
	if tree := treeContents(sent.bodyJSON(t, "POST /repos/acme/data/git/trees")); !maps.Equal(tree, want) {
		t.Errorf("want the tree files %v, got %v", want, tree)
	}
}

// TestInstallUpdateRefusesFlagsThatAreNoValueOfTheirKind: a repository that is
// no owner/name, a version that is no release version and a sha that is no
// 40-hex are usage errors naming the flag and the value, with no request.
func TestInstallUpdateRefusesFlagsThatAreNoValueOfTheirKind(t *testing.T) {
	cases := map[string][]string{
		"--repo":    {"--repo", "acme", "--branch", "main", "--version", "v0.1.4", "--sha", newPinSHA},
		"--version": {"--repo", "acme/data", "--branch", "main", "--version", "0.1.4", "--sha", newPinSHA},
		"--sha":     {"--repo", "acme/data", "--branch", "main", "--version", "v0.1.4", "--sha", "abc"},
	}
	for flag, args := range cases {
		asked := recordedAPI(t, map[string]answer{})
		value := args[slices.Index(args, flag)+1]
		wantExit2(t, runOutcome(append([]string{"install-update"}, args...)), "install-update", flag, value)
		if paths := asked(); len(paths) != 0 {
			t.Errorf("%s: want no request, got %v", flag, paths)
		}
	}
}

// TestInstallUpdateIsExit2WhenTheGitHubClientCannotBeMade: a base URL the
// client refuses is exit 2 naming install-update and the URL.
func TestInstallUpdateIsExit2WhenTheGitHubClientCannotBeMade(t *testing.T) {
	old := githubAPI
	githubAPI = "no-such-scheme"
	t.Cleanup(func() { githubAPI = old })
	wantExit2(t, runOutcome(installFlags()), "install-update", "no-such-scheme")
}
