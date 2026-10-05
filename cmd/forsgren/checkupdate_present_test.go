package main

import (
	"os"
	"path/filepath"
	"testing"
)

// TestCheckUpdateIsExit2WhenACallerFileCannotBeLookedUp (forsgren#59): a
// caller file that is absent counts as absent, but one whose lookup fails
// otherwise (here permission denied, on the folder above it) leaves the state
// undetermined: exit 2, the file named on stderr, nothing on stdout, so
// nothing merges, though the pull request moves the one caller it could read.
func TestCheckUpdateIsExit2WhenACallerFileCannotBeLookedUp(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can look up any file")
	}
	recordedAPI(t, mergeableAnswers(t))
	flags := updateFlags(t)
	workflows := filepath.Join(filepath.Dir(flags["config"]), ".github", "workflows")
	if err := os.MkdirAll(workflows, 0o750); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(workflows, 0o750) })
	if err := os.Chmod(workflows, 0o000); err != nil {
		t.Fatal(err)
	}
	got := checkUpdateRun(argsOf(flags, "config", "repo", "pull")...)
	wantExit2(t, got, "check-update", ".github/workflows/forsgren-update.yml")
}

// TestCheckUpdateIsExit2WhenTheGitHubClientCannotBeMade: a base URL the
// client refuses is exit 2 naming check-update and the URL, never a decision.
func TestCheckUpdateIsExit2WhenTheGitHubClientCannotBeMade(t *testing.T) {
	old := githubAPI
	githubAPI = "no-such-scheme"
	t.Cleanup(func() { githubAPI = old })
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	wantExit2(t, got, "check-update", "no-such-scheme")
}
