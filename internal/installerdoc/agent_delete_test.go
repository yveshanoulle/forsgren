package installerdoc

import (
	"strings"
	"testing"
)

// TestDeleterStartsWithOneQuestion (forsgren#174): agent-delete.md checks
// the login's scopes, notes whether it may delete a repository, and asks the
// person one thing, the address of the report; README.md and the docs link
// it, and it says it is not yet tested until a proof run names its versions.
func TestDeleterStartsWithOneQuestion(t *testing.T) {
	wantAll(t, "step 1", deleterSection(t, "Step 1."),
		"gh auth status", "'repo'", "'delete_repo'",
		"**Ask the person one thing:**", "address of your forsgren report", "Ask nothing else")
	doc := readRepoFile(t, deleterFile)
	wantAll(t, string(deleterFile), doc,
		"\nTested with: not yet tested",
		"\n## Before you start (for the person)")
	for _, path := range []repoFile{"README.md", "docs/updating-and-releases.md"} {
		if !strings.Contains(readRepoFile(t, path), string(deleterFile)) {
			t.Errorf("%s does not link %s", path, deleterFile)
		}
	}
}

// TestDeleterStep2FindsTheInstallationFromItsReport (forsgren#174): step 2
// finds the repository from the report as the upgrader does, refuses only
// forsgren and its template by their exact names, deletes only a forsgren
// installation the login administers, and reads the token route and the
// custom domain's DNS record.
func TestDeleterStep2FindsTheInstallationFromItsReport(t *testing.T) {
	wantAll(t, "step 2", deleterSection(t, "Step 2."),
		"Forsgren</a>",
		"gh api repos/CANDIDATE/pages --jq .cname",
		"`OWNER/REPO` may be `OWNER/forsgren`",
		"exactly `yveshanoulle/forsgren` or `yveshanoulle/forsgren-template`",
		".permissions.admin",
		"yveshanoulle/forsgren/.github/workflows/metrics.yml@",
		"not a forsgren installation",
		"secrets.FORSGREN_TOKEN",
		"dig +short DOMAIN")
	wantAll(t, "the never-do list", deleterSection(t, "What you must never do"),
		"a repository named `forsgren` under another owner is an installation, not forsgren itself")
}

// deleteGo is the go-sentence that lets the agent delete the installation.
const deleteGo = "Reply \"go: delete OWNER/REPO, its page and its custom domain DOMAIN\" to let me delete it."

// TestDeleterStep3ShowsWhatGoesAndWaitsForTheGo (forsgren#174): step 3 says
// in one message that the history in data/ cannot be recovered, offers
// delete (the default), archive and a download first, says what the person
// does, and waits for a go-sentence that names the repository; a bare go is
// refused.
func TestDeleterStep3ShowsWhatGoesAndWaitsForTheGo(t *testing.T) {
	wantAll(t, "step 3", deleterSection(t, "Step 3."),
		"in one message",
		"Never show the person a placeholder",
		"`data/`",
		"cannot be recovered",
		"Delete (the default)",
		"Archive",
		"Download first",
		deleteGo,
		"Reply \"go: archive OWNER/REPO",
		"A bare \"go\"",
		"Nothing is changed before that reply")
}

// TestDeleterStep4DownloadsOutsideTheWorkFolder (forsgren#174): the
// download, when chosen, lands in the start folder, not in WORK, which step
// 8 removes.
func TestDeleterStep4DownloadsOutsideTheWorkFolder(t *testing.T) {
	wantAll(t, "step 4", deleterSection(t, "Step 4."),
		"repos/OWNER/REPO/tarball/BRANCH > START/OWNER-REPO.tar.gz",
		"not in `WORK`",
		"/data/",
		"Not chosen: skip this step")
}

// TestDeleterStep5RemovesTheDomainBeforeTheRepository (forsgren#174): the
// custom domain is removed first, then Pages is switched off, then the
// repository is deleted (with the delete_repo scope the person grants
// themselves) or archived, each read back.
func TestDeleterStep5RemovesTheDomainBeforeTheRepository(t *testing.T) {
	step := deleterSection(t, "Step 5.")
	wantAll(t, "step 5", step,
		"gh api -X PUT repos/OWNER/REPO/pages -F cname=null",
		"gh api -X DELETE repos/OWNER/REPO/pages",
		"'delete_repo'",
		"**Person:**",
		"gh auth refresh -h github.com -s delete_repo",
		"gh repo delete OWNER/REPO --yes",
		"Could not resolve to a Repository",
		"gh repo archive OWNER/REPO --yes",
		".archived",
		"read back")
	order := []string{"-F cname=null", "-X DELETE repos/OWNER/REPO/pages", "gh repo delete OWNER/REPO --yes"}
	at := -1
	for _, want := range order {
		i := strings.Index(step, want)
		if i < at {
			t.Errorf("step 5: %q comes before the step it must follow", want)
		}
		at = i
	}
}

// TestDeleterStep6HandsThePersonDNSAndToken (forsgren#174): the person
// removes the DNS record, decides about the verification TXT record only
// after the CNAME is gone and only when no other site uses the domain,
// revokes the route B token, and may drop the delete_repo scope again.
func TestDeleterStep6HandsThePersonDNSAndToken(t *testing.T) {
	step := deleterSection(t, "Step 6.")
	wantAll(t, "step 6", step,
		"**Person:**",
		"CNAME",
		"_github-pages-challenge-OWNER.PARENT",
		"no other site",
		"Fine-grained tokens",
		"`forsgren OWNER/REPO`",
		"`FORSGREN_TOKEN` secret is gone with the repository",
		"gh auth refresh -h github.com -r delete_repo")
	if strings.Index(step, "remove the CNAME") > strings.Index(step, "_github-pages-challenge") {
		t.Error("step 6 lets the verification go before the CNAME is removed")
	}
}

// TestDeleterStep7ChecksThePageAndTheDomain (forsgren#174): the page answers
// 404 (with retries, Pages can serve the old page a while) and the domain no
// longer points at GitHub through two resolvers.
func TestDeleterStep7ChecksThePageAndTheDomain(t *testing.T) {
	wantAll(t, "step 7", deleterSection(t, "Step 7."),
		"curl -sS -o /dev/null -w '%{http_code}' REPORT",
		"404",
		"at most 10 times",
		"dig +short @1.1.1.1 DOMAIN",
		"`OWNER.github.io.`",
		"a wait, not a failure")
}

// TestDeleterEndsWithTheReportAndLeavesWorkFirst (forsgren#174): step 8
// tells the person in one message and removes WORK after leaving it.
func TestDeleterEndsWithTheReportAndLeavesWorkFirst(t *testing.T) {
	wantAll(t, "step 8", deleterSection(t, "Step 8."), "in one message", "OWNER-REPO.tar.gz")
	found, notLeavingFirst := workRemovals(t, deleterFile)
	for _, r := range notLeavingFirst {
		t.Errorf("line %d %q is not directly preceded by `cd WORK/..`", r.line, r.text)
	}
	if found == 0 {
		t.Error("no `rm -r WORK` found")
	}
}
