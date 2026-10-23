package page

import (
	"strings"
	"testing"
)

// legendTbdText are the sentences of the legend's TBD page section
// (forsgren#253): the cell format, what is counted and how (the first-parent
// chain at the committer date, and the old approximation the cell names,
// forsgren#254), what a dash is, what comes later and the default of tbd_page.
var legendTbdText = []string{
	"the Mainline Interval of each project",
	"written mean ± deviation (gaps), for example 2 h ± 1 h (3)",
	"the sample standard deviation",
	"the commits that deployments of the last 30 days shipped",
	"each commit once",
	"the time between commits landing on the main branch, by their committer date",
	"A gap is the time between two commits that are next to each other by committer date",
	"Of the commits a deployment shipped, only those of its first-parent chain count: from the deployed commit " +
		"back through the first parent of each commit, the commits that landed on the main branch one after another",
	"The commits a merge brought in from a branch are left out; the merge commit counts, at the time it landed",
	"The committer date is when a commit landed where it is now, after a rebase or a merge; the author date is " +
		"when the change was first written",
	"Commits stored before forsgren kept their parents and committer date have no known chain",
	"For a deployment with those, every commit counts at its author date, the old approximation, and so does a " +
		"commit of the chain that GitHub gave no committer date for",
	"The cell then ends with how many commits are timed this way, written " +
		"2 h ± 1 h (3) · median 2 h · p90 - · 3 commits timed by author date, or 1 commit timed by author date",
	"Those commits are not looked up again, so the note stays until their deployments leave the window",
	"A dash means fewer than two commits",
	"With one gap the mean is shown, and the deviation is a dash",
	"between deployed commits, not every commit of the mainline",
	"Next to them the cell gives the median and the 90th percentile (p90) of the gaps, written median 5 min · p90 1 h",
	"The median is the middle gap, or the mean of the two middle gaps when there is an even number of them",
	"p90 is the nearest-rank percentile: the gap at position 0.9 × the number of gaps, rounded up, of the gaps " +
		"sorted from the shortest, so nine tenths of the gaps are no longer than it",
	"The median needs two gaps and p90 needs ten gaps",
	"With fewer than ten gaps p90 would only be the longest gap",
	"A mean far above the median, and a deviation far above the mean, point at a few long gaps among short ones",
	"Next to the Mainline Interval, Developers is the number of people who made the commits deployed in the " +
		"window, those a merge brought in included: the distinct GitHub accounts of their authors, " +
		"so a person who commits from several email addresses counts once",
	"A bot account, whose GitHub login ends in [bot], is not a developer, and its commits are left out",
	"A commit whose author GitHub links to no account is not guessed to be anyone's: the number leaves it out " +
		"and the cell says how many, written 3 · 2 commits without a known author are not counted",
	"A project with no counted commit has 0 developers",
	"The page shows the number only, never who the developers are",
	"The interval is not divided by it: a team of ten makes more commits than one person with the same habits",
	"The two metrics are read together",
	"The Mainline Interval shows how often the deployed commits landed on the main branch, " +
		"by committer date, in the window",
	"A short interval with a long lead time points at long-lived branches",
	"The TBD page is unlisted by default (tbd_page: unlisted): it is " +
		"generated and can be opened at tbd.html, but it has no menu entry and search" +
		" engines are asked to skip it. Set tbd_page: true to put it in the menu, or " +
		"tbd_page: false to not generate it.",
}

// legendLeadText are the sentences that say what each number of the Mainline
// Lead Time column counts (forsgren#256 step 3): the scope of #342, the cell's
// parts, the lower bound and the stand-ins, the people of #349 and #355, the
// legacy format as Yves worded it on #356, and what not readable means.
var legendLeadText = []string{
	"Mainline Lead Time covers merged human pull requests only, " +
		"not every change that reaches the trunk",
	"Work pushed straight to the main branch is not in it, " +
		"so a pull request stands in for the life of a branch",
	"In a workflow that mixes both, the figure covers only the changes that came through pull requests",
	"Each pull request merged in the last 30 days, counted by its merge time, " +
		"gives one lead time: from its first commit, " +
		"the earliest author date of its commits, to the merge",
	"A first commit dated after the merge counts as 0",
	"mean ± deviation (pull requests), for example 3 h ± 1 h (4)",
	"the deviation the sample standard deviation (n-1)",
	"50% (2 of 4) pull requests merged within 24 hours of their first commit",
	"The share is rounded down, and 24 hours or less counts as within, the same boundary everywhere",
	"There is no pass or fail verdict",
	"The Mainline Interval uses the committer date: how often changes reach the main branch",
	"Mainline Lead Time uses the author date of the first commit up to the merge time",
	"That lead time is a lower bound: the count reads (4, 1 cut) and the cell adds the mean is a lower bound",
	"A cut pull request can make the mean too low and the share merged within 24 hours too high",
	"the created time of the pull request stands in for the first commit time",
	"1 pull request timed by its created time, or 2 pull requests timed by their created time",
	"Only a GitHub account of the type User is a person",
	"3 bot pull requests not counted",
	"2 pull requests of unknown author not counted",
	"a pull request in the legacy format has no known author type",
	"The placeholder author invalid-email-address",
	"is an unknown author, not a developer",
	"Commits in the legacy format have no known author and are not counted",
	"the legacy format says how a record was stored, not why the author is missing",
	"3 developers · 1099 commits without a known author excluded (legacy data)",
	"Mostly estimated: 7 of 13 commits timed by author date.",
	"No human pull requests in this period; changes may go directly to the trunk",
	"That is not proof of direct commits",
	"Pull requests not readable means the token forsgren collects with was refused the pull request read",
	"recorded in data/pulls_denied.csv",
	"No pull requests have been collected yet means the collection has not read any pull request yet",
	"A long interval with a short lead time means few changes, each integrated quickly",
}

// legendLeadNever are claims the data cannot establish: the legacy format is
// not said to be commits stored before v3 (Yves on forsgren#356).
var legendLeadNever = []string{"stored before v3", "stored before the commits format v3"}

// TestLegendSaysWhatEachLeadTimeNumberCounts (forsgren#256 step 3): the TBD
// section of the rendered legend carries every sentence of legendLeadText and
// none of legendLeadNever.
func TestLegendSaysWhatEachLeadTimeNumberCounts(t *testing.T) {
	section := legendTbdSection(t, rendered(t, "legend.html", calculated()))
	for _, want := range legendLeadText {
		if !strings.Contains(section, want) {
			t.Errorf("want %q in the TBD page section", want)
		}
	}
	for _, never := range legendLeadNever {
		if strings.Contains(section, never) {
			t.Errorf("want no %q in the TBD page section", never)
		}
	}
}

// legendTbdRetired are the wordings the TBD page section no longer says
// (forsgren#254): the interval is no longer by author date, and Developers no
// longer counts only the commits the interval counts.
var legendTbdRetired = []string{
	"by their author date",
	"next to each other by author date",
	"were made, by author date",
	"who made the commits it counts",
	"Mainline Lead Time is not on this page yet",
	"It will show how long a commit takes",
}

// TestLegendExplainsTheTbdPage (forsgren#253, forsgren#273): the legend has a
// TBD page section after the History page's, whose sentences name the window
// in force and say what the Developers column counts;
// the Issues pages paragraph lists tbd_page among the page keys and its
// default.
func TestLegendExplainsTheTbdPage(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	section := legendTbdSection(t, got)
	for _, want := range legendTbdText {
		if !strings.Contains(section, want) {
			t.Errorf("want %q in the TBD page section", want)
		}
	}
	data := calculated()
	data.DoraDays = 90
	if !strings.Contains(rendered(t, "legend.html", data), "deployments of the last 90 days shipped") {
		t.Error("want the TBD section to name the window in force")
	}
	tbdHeading, historyHeading := "<h2>Trunk-based development [TBD] (BETA)</h2>", "<h2>History page (BETA)</h2>"
	if strings.Index(got, tbdHeading) < strings.Index(got, historyHeading) {
		t.Error("want the TBD page section after the History page section")
	}
}

// TestLegendRetiresTheAuthorDateWording (forsgren#254): the TBD page section
// no longer says the interval is by author date, nor that Developers counts
// only the commits the interval counts.
func TestLegendRetiresTheAuthorDateWording(t *testing.T) {
	section := legendTbdSection(t, rendered(t, "legend.html", calculated()))
	for _, gone := range legendTbdRetired {
		if strings.Contains(section, gone) {
			t.Errorf("want no %q in the TBD page section", gone)
		}
	}
}

// legendTbdSection is the legend's TBD page section, from its heading up to
// the next heading.
func legendTbdSection(t *testing.T, legend string) string {
	t.Helper()
	_, section, found := strings.Cut(legend, "<h2>Trunk-based development [TBD] (BETA)</h2>")
	if !found {
		t.Fatal("want a TBD page section in the legend")
	}
	section, _, _ = strings.Cut(section, "<h2>")
	return section
}

// TestLegendSaysEachTbdSentenceOnce (forsgren#271): the explanation of the
// Mainline Interval and the Mainline Lead Time line are in the legend once,
// and the TBD page does not repeat them.
func TestLegendSaysEachTbdSentenceOnce(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	for _, once := range []string{"Mainline Lead Time covers merged human pull requests only", "each commit once",
		"A dash means fewer than two commits", "sample standard deviation of the time between commits",
		"deployments of the last 30 days shipped"} {
		if n := strings.Count(got, once); n != 1 {
			t.Errorf("want %q once in the legend, got %d", once, n)
		}
	}
}
