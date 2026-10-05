package main

import "testing"

// Made-up commit of the release v0.1.4, the newest within level patch of an
// installation at v0.1.3, in the fixtures below.
const patchReleaseSHA = "4444444444444444444444444444444444444444"

// minorBumpPatch is the patch of Dependabot's bump of the pin in forsgren.yml
// from v0.1.3 to v0.2.0, a minor update.
const minorBumpPatch = "@@ -14 +14 @@\n" +
	"-    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@" + oldPinSHA + " # v0.1.3\n" +
	"+    uses: yveshanoulle/forsgren/.github/workflows/metrics.yml@" + newPinSHA + " # v0.2.0\n"

// forsgrenAPI is the path of forsgren's own repository on the API.
const forsgrenAPI = "/repos/yveshanoulle/forsgren/"

// beyondLevelAnswers are the answers of a pull request that only the level
// leaves for a human: Dependabot's minor bump from v0.1.3 to v0.2.0 at level
// patch, v0.2.0 published with its tag at the pin, and forsgren's list of
// releases as given.
func beyondLevelAnswers(t *testing.T, releases answer) map[string]answer {
	t.Helper()
	return map[string]answer{
		"/repos/acme/data/pulls/7": {200, `{"user": {"login": "dependabot[bot]"}}`},
		"/repos/acme/data/pulls/7/files": changedFiles(t,
			map[string]string{"filename": ".github/workflows/forsgren.yml", "patch": minorBumpPatch}),
		forsgrenAPI + "releases":             releases,
		forsgrenAPI + "releases/tags/v0.2.0": {200, `{"tag_name": "v0.2.0"}`},
		forsgrenAPI + "commits/tags/v0.2.0":  {200, newPinSHA},
		forsgrenAPI + "commits/tags/v0.1.4":  {200, patchReleaseSHA},
	}
}

// beyondLeft is what check-update says of the pull request of
// beyondLevelAnswers when it leaves it for a human.
const beyondLeft = "left for a human: v0.1.3 to v0.2.0 is a minor update; auto_update_level is patch\n"

// TestCheckUpdateInstallsTheNewestReleaseWithinTheLevelOfAPullRequestBeyondIt
// (forsgren#62, step 3): an installation at v0.1.3 and level patch gets a
// pull request to v0.2.0, a minor update, which only the level leaves for a
// human. forsgren has a release v0.1.4 within the level, so check-update
// exits 3 and says on stdout `install v0.1.3 to v0.1.4 at <sha>` and, on the
// next line, why the pull request itself stays for a human.
func TestCheckUpdateInstallsTheNewestReleaseWithinTheLevelOfAPullRequestBeyondIt(t *testing.T) {
	recordedAPI(t, beyondLevelAnswers(t, answer{200, `[` +
		`{"id": 2, "tag_name": "v0.2.0", "draft": false, "prerelease": false},` +
		`{"id": 1, "tag_name": "v0.1.4", "draft": false, "prerelease": false}]`}))
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	want := outcome{code: 3, stdout: "install v0.1.3 to v0.1.4 at " + patchReleaseSHA + "\n" + beyondLeft}
	if got != want {
		t.Errorf("want exit 3 and %q, got %d, %q, stderr %q", want.stdout, got.code, got.stdout, got.stderr)
	}
}

// TestCheckUpdateIsExit2WhenTheReleaseListFailsOnAPullRequestBeyondTheLevel:
// a 500 on forsgren's list of releases is neither a leave for a human nor an
// install: exit 2, nothing on stdout, check-update and the request on stderr.
func TestCheckUpdateIsExit2WhenTheReleaseListFailsOnAPullRequestBeyondTheLevel(t *testing.T) {
	recordedAPI(t, beyondLevelAnswers(t, answer{500, `{"message":"boom"}`}))
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	wantExit2(t, got, "check-update", forsgrenAPI+"releases")
}

// TestCheckUpdateLeavesAPullRequestBeyondTheLevelForAHumanWhenNoReleaseIsWithinIt:
// forsgren's only release newer than v0.1.3 is the v0.2.0 the pull request
// moves to, beyond level patch: the pull request is left for a human, exit 1
// with only the one line, as before forsgren#62.
func TestCheckUpdateLeavesAPullRequestBeyondTheLevelForAHumanWhenNoReleaseIsWithinIt(t *testing.T) {
	recordedAPI(t, beyondLevelAnswers(t, answer{200,
		`[{"id": 2, "tag_name": "v0.2.0", "draft": false, "prerelease": false}]`}))
	got := checkUpdateRun(argsOf(updateFlags(t), "config", "repo", "pull")...)
	if want := (outcome{code: 1, stdout: beyondLeft}); got != want {
		t.Errorf("want exit 1 and %q, got %d, %q, stderr %q", want.stdout, got.code, got.stdout, got.stderr)
	}
}
