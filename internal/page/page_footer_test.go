package page

import (
	"strings"
	"testing"
)

// released is the placeholder page data with latest as forsgren's latest
// release and waitingPR as the pull request that bumps to it, 0 for none.
func released(latest string, waitingPR int) Data {
	data := Placeholder(testVersion)
	data.Latest, data.WaitingPR = latest, waitingPR
	return data
}

// TestEveryPageNamesFiveMetrics (forsgren#39): with rework rate as the
// table's fifth column, every page's footer names five DORA metrics
// (forsgren#41: in the footer's paragraph; the table's caption says "DORA
// metrics", forsgren#45).
func TestEveryPageNamesFiveMetrics(t *testing.T) {
	wantOnEveryPage(t, acmeTable(), " Metrics from GitHub data.")
}

// TestEveryPageEndsWithTheFooter (forsgren#41, step 1): every page's footer
// opens with the same one paragraph: Forsgren linked to forsgren.be (forsgren#162), its
// version, what it is and, when numbers were calculated, when (UTC); no
// Install link anywhere (forsgren#45). Without a calculation time the
// "Calculated at" sentence is left out. Settings and Legend follow the
// paragraph on every page (forsgren#128).
func TestEveryPageEndsWithTheFooter(t *testing.T) {
	head := `<p><a href="https://forsgren.be/">Forsgren</a> ` + testVersion + ` ` +
		`Metrics from GitHub data.`
	cases := map[string]struct {
		data Data
		want string
	}{
		"with data":    {acmeTable(), head + " " + footerReport},
		"without data": {Placeholder(testVersion), head + "</p>"},
	}
	for name, c := range cases {
		for _, page := range PageNames() {
			t.Run(name+" "+page, func(t *testing.T) {
				got := rendered(t, page, c.data)
				if !strings.Contains(got, "  <footer>\n    "+c.want+"\n") {
					t.Errorf("want the footer %q to open the footer, got:\n%s", c.want, got)
				}
				wantNoInstallLink(t, got)
			})
		}
	}
}

// wantNoInstallLink fails when the page still has the Install link or the
// forsgren-template repository it pointed to (forsgren#45).
func wantNoInstallLink(t *testing.T, got string) {
	t.Helper()
	wantNone(t, "the page", got, "Install", "forsgren-template")
}

// TestNoPageShowsASiteNameLine (forsgren#41, step 2): the header carries no
// visible text on either page, the footer names Forsgren.
func TestNoPageShowsASiteNameLine(t *testing.T) {
	wantOnNoPage(t, acmeTable(), `class="site-name"`)
}

// TestFooterShowsTheTimeWithoutRows (forsgren#41, step 3; it reverses
// forsgren#28's "the time with Rows only"): a page with an AsOf and no Rows
// still says when it was calculated.
func TestFooterShowsTheTimeWithoutRows(t *testing.T) {
	wantOnEveryPage(t, calculated(), footerReport)
}

// TestFooterNamesANewerRelease (forsgren#40, step 4, option 2): when a newer
// forsgren release exists, the version line of the footer says so, on every
// page, with the numbers compared as numbers.
func TestFooterNamesANewerRelease(t *testing.T) {
	wantOnEveryPage(t, released(newerVersion(), 0), testVersion+" · "+newerVersion()+" is available")
}

// TestFooterNamesNoReleaseThatIsNotNewer (forsgren#40, step 4): up to date,
// ahead of the latest release, or an unknown or unreadable latest release:
// the footer adds nothing.
func TestFooterNamesNoReleaseThatIsNotNewer(t *testing.T) {
	for _, latest := range []string{"", testVersion, "0.1.2", "0.0.10", "banana"} {
		t.Run("latest "+latest, func(t *testing.T) {
			wantOnNoPage(t, released(latest, 0), " is available")
		})
	}
}

// TestFooterNamesTheWaitingPullRequest (forsgren#40, step 5, option 1): a
// newer release whose Dependabot pull request is open is named with the
// pull request's number, instead of "is available"; no repository appears.
func TestFooterNamesTheWaitingPullRequest(t *testing.T) {
	data := released(newerVersion(), 7)
	wantOnEveryPage(t, data, testVersion+" · "+newerVersion()+" is waiting in pull request #7 (merge it to update)")
	wantOnNoPage(t, data, " is available")
}

// TestFooterNamesNoWaitingPullRequestWithoutANewerRelease (forsgren#40, step
// 5): with no pull request, "is available" stays; up to date, a pull request
// number alone adds nothing.
func TestFooterNamesNoWaitingPullRequestWithoutANewerRelease(t *testing.T) {
	available := rendered(t, "index.html", released(newerVersion(), 0))
	wantAll(t, "without a pull request", available, newerVersion()+" is available")
	wantNone(t, "without a pull request", available, "waiting")
	wantNone(t, "up to date", rendered(t, "index.html", released(testVersion, 7)), "pull request #", " is available")
}

// TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs (forsgren#40, review of
// step 7): the news of a newer release, available or waiting in a pull
// request, is a sentence of its own; it never runs on into "The five DORA
// metrics" ("9.9.10 is available The five ..."), on every page.
func TestFooterEndsTheReleaseNewsBeforeWhatForsgrenIs(t *testing.T) {
	for waiting, want := range map[int]string{
		0: testVersion + " · " + newerVersion() + " is available. Metrics from GitHub data",
		7: testVersion + " · " + newerVersion() +
			" is waiting in pull request #7 (merge it to update). Metrics from GitHub data",
	} {
		wantOnEveryPage(t, released(newerVersion(), waiting), want)
	}
}
