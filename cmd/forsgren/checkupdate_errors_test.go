package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// checkUpdateRun runs check-update with args.
func checkUpdateRun(args ...string) outcome {
	return runOutcome(append([]string{"check-update"}, args...))
}

// runOutcome runs the command line args.
func runOutcome(args []string) outcome {
	var stdout, stderr strings.Builder
	code := run(args, &stdout, &stderr)
	return outcome{code, stdout.String(), stderr.String()}
}

// configFile writes content to a forsgren.config.yml of its own and returns
// its path.
func configFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// updateFlags are check-update's three flags, with a valid config.
func updateFlags(t *testing.T) map[string]string {
	t.Helper()
	return map[string]string{"config": configFile(t, autoUpdateConfig), "repo": "acme/data", "pull": "7"}
}

// argsOf is flags as a command line, each as --name value, in the order of
// names; a name that flags lacks is left out.
func argsOf(flags map[string]string, names ...string) []string {
	var args []string
	for _, name := range names {
		if value, ok := flags[name]; ok {
			args = append(args, "--"+name, value)
		}
	}
	return args
}

// wantExit2 fails unless got is exit 2 with every part on stderr.
func wantExit2(t *testing.T, got outcome, parts ...string) {
	t.Helper()
	if got.code != 2 || got.stdout != "" {
		t.Errorf("want exit 2 and nothing on stdout, got %d, %q", got.code, got.stdout)
	}
	for _, part := range parts {
		if !strings.Contains(got.stderr, part) {
			t.Errorf("want %q on stderr, got %q", part, got.stderr)
		}
	}
}

// TestCheckUpdateNeedsItsThreeFlags: leaving out --config, --repo or --pull
// is a usage error that names the flag.
func TestCheckUpdateNeedsItsThreeFlags(t *testing.T) {
	names := []string{"config", "repo", "pull"}
	for _, missing := range names {
		flags := updateFlags(t)
		delete(flags, missing)
		wantExit2(t, checkUpdateRun(argsOf(flags, names...)...), "--"+missing)
	}
}

// TestCheckUpdateNeedsAPositivePullNumber: a pull request's number is 1 or
// more, written as digits; anything else is a usage error naming --pull.
func TestCheckUpdateNeedsAPositivePullNumber(t *testing.T) {
	for _, number := range []string{"0", "-3", "x", "7a", "1.5"} {
		flags := updateFlags(t)
		flags["pull"] = number
		wantExit2(t, checkUpdateRun(argsOf(flags, "config", "repo", "pull")...), "--pull", number)
	}
}

// TestCheckUpdateNeedsARepositoryName: a --repo that is not one owner/name
// is a usage error naming --repo, before any request.
func TestCheckUpdateNeedsARepositoryName(t *testing.T) {
	for _, repo := range []string{"acme", "acme/", "ac me/data", "acme/.."} {
		flags := updateFlags(t)
		flags["repo"] = repo
		wantExit2(t, checkUpdateRun(argsOf(flags, "config", "repo", "pull")...), "--repo", repo)
	}
}

// TestCheckUpdateNamesAConfigItCannotUse: a config that is missing or invalid
// is exit 2, and the message names the file.
func TestCheckUpdateNamesAConfigItCannotUse(t *testing.T) {
	invalid := configFile(t, oneRepository+"auto_update: yes\n")
	for _, path := range []string{filepath.Join(t.TempDir(), "missing.yml"), invalid} {
		flags := updateFlags(t)
		flags["config"] = path
		wantExit2(t, checkUpdateRun(argsOf(flags, "config", "repo", "pull")...), path)
	}
}

// answer is the status and the body a test server gives one path.
type answer struct {
	code int
	body string
}

// serveAPI points the commands at a test server run by handler, for this test
// only.
func serveAPI(t *testing.T, handler http.HandlerFunc) {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	old := githubAPI
	githubAPI = srv.URL
	t.Cleanup(func() { githubAPI = old })
}

// answerPaths points the commands at a test server that gives each path its
// answer, and 404 to any other.
func answerPaths(t *testing.T, answers map[string]answer) {
	t.Helper()
	serveAPI(t, func(w http.ResponseWriter, r *http.Request) {
		a, ok := answers[r.URL.Path]
		if !ok {
			a = answer{code: http.StatusNotFound, body: `{"message":"Not Found"}`}
		}
		w.WriteHeader(a.code)
		_, _ = w.Write([]byte(a.body))
	})
}

// mergeableAnswers are the answers of a pull request that check-update would
// merge: Dependabot's patch bump, its release published, its tag at the pin.
func mergeableAnswers(t *testing.T) map[string]answer {
	t.Helper()
	files := jsonOf(t, []map[string]string{{"filename": ".github/workflows/forsgren.yml", "patch": bumpPatch}})
	return map[string]answer{
		"/repos/acme/data/pulls/7":                          {200, `{"user": {"login": "dependabot[bot]"}}`},
		"/repos/acme/data/pulls/7/files":                    {200, files},
		"/repos/yveshanoulle/forsgren/releases/tags/v0.1.4": {200, `{"tag_name": "v0.1.4"}`},
		"/repos/yveshanoulle/forsgren/commits/tags/v0.1.4":  {200, newPinSHA},
	}
}

// TestCheckUpdateIsExit2WhenGitHubFails: an error answer to the pull request,
// its files, the release or its tag is not a reason to leave the pull request
// for a human, nor to merge it: exit 2, nothing on stdout, and the status of
// the failed call on stderr.
func TestCheckUpdateIsExit2WhenGitHubFails(t *testing.T) {
	failing := map[string]answer{
		"/repos/acme/data/pulls/7":                          {500, `{"message":"boom"}`},
		"/repos/acme/data/pulls/7/files":                    {403, `{"message":"no"}`},
		"/repos/yveshanoulle/forsgren/releases/tags/v0.1.4": {500, `{"message":"boom"}`},
		"/repos/yveshanoulle/forsgren/commits/tags/v0.1.4":  {500, `{"message":"boom"}`},
	}
	for path, a := range failing {
		answers := mergeableAnswers(t)
		answers[path] = a
		answerPaths(t, answers)
		flags := updateFlags(t)
		wantExit2(t, checkUpdateRun(argsOf(flags, "config", "repo", "pull")...),
			"check-update", fmt.Sprint(a.code))
	}
}

// TestCheckUpdateIsExit2WhenTheFileListIsCutAtThePageLimit: files that were
// not read could be anything, so a pull request with more files than the
// client reads is exit 2, never a merge on the files seen: the first page is
// the pin bump, and every page names a next one.
func TestCheckUpdateIsExit2WhenTheFileListIsCutAtThePageLimit(t *testing.T) {
	answers := mergeableAnswers(t)
	serveAPI(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/repos/acme/data/pulls/7/files" {
			a := answers[r.URL.Path]
			w.WriteHeader(a.code)
			_, _ = w.Write([]byte(a.body))
			return
		}
		page, _ := strconv.Atoi(r.URL.Query().Get("page"))
		page = max(1, page)
		w.Header().Set("Link", fmt.Sprintf(`<%s%s?page=%d&per_page=100>; rel="next"`,
			githubAPI, r.URL.Path, page+1))
		body := `[{"filename": "other.yml", "patch": ""}]`
		if page == 1 {
			body = answers[r.URL.Path].body
		}
		_, _ = w.Write([]byte(body))
	})
	flags := updateFlags(t)
	wantExit2(t, checkUpdateRun(argsOf(flags, "config", "repo", "pull")...), "check-update", "files")
}
