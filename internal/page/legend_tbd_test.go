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
	"The TBD page (trunk-based development) is one table with a row for each project",
	"Its columns are in groups, and the name of a group says what it counts",
	"First come Mainline Interval, Time to main per commit, Time to deploy per commit and PR Lead Time. " +
		"Then come Volume, Commits per push, Commits per deployment, Shares of commits and Developers",
	"Every number is of the last 30 days",
	"The push groups read the pushes to the main branch, from GitHub's activity list of the default branch " +
		"of each repository",
	"Push data starts with the release that collects it: a project shows the pushes from the day forsgren first " +
		"collected them, and older pushes are not looked up afterwards",
	"Volume has three columns",
	"Commits is the number of commits the pushes brought to the main branch, each commit is counted a single " +
		"time, at its first push",
	"Only the first-parent chain of a push counts, so the commits a merge brought in from a branch are left " +
		"out and the merge commit counts",
	"Pushes is the number of pushes. Deployments is the number of successful deployments",
	"A deployment is a GitHub release, a deployment to an environment or a run of a workflow, as the project " +
		"is measured. It is shown as the number only, for example 85",
	"Shares of commits has four columns: Direct, PR, Unknown and Bots",
	"PR is the share of pull request commits, and Unknown the share of commits of an unknown author",
	"All four are shares of the same Commits number, in whole percent rounded down, so they read alike",
	"A commit is a pull request commit when it is the merge commit of a merged pull request, or when a pull " +
		"request merge brought it to the main branch",
	"Every other commit is direct, so these two shares add up to 100%, give or take the rounding",
	"Unknown and Bots are counted in addition, whatever else the commit is",
	"An unknown author is a commit whose author GitHub links to no account, or the placeholder author " +
		"invalid-email-address. A bot is a commit whose author login ends in [bot]",
	"Time to main per commit is a duration. For each commit it runs from the author date of the commit to " +
		"the push that brought it to the main branch",
	"A commit authored after its push counts as 0",
	"Commits per push is a count of commits, not a duration: how many commits each push brought to the " +
		"first-parent chain",
	"A push whose commits could not be counted, such as a force push, is left out of these three columns",
	"Time to deploy per commit is a duration. For each commit it runs from the author date of the commit " +
		"to the first deployment that contains it",
	"for a deployment to an environment, when the deployment was created; for a workflow, when its run " +
		"started; for a release, when the release was published",
	"A commit authored after its deployment counts as 0",
	"Commits per deployment is a count of commits: how many commits each deployment brought to the " +
		"first-parent chain, the merge commit of a pull request included",
	"A deployment without a known chain is left out",
	"In each group of three columns the mean is the average",
	"The median is the middle value, or the mean of the two middle values when there is an even number of them",
	"p90 is the nearest-rank percentile: the value at position 0.9 × the number of values, rounded up, of " +
		"the values sorted from the smallest, so nine tenths of the values are no larger than it",
	"The median needs two values and p90 needs ten values, and each is a dash until then",
	"A duration is written like 3 h 22, which is 3 hours and 22 minutes, 2 h for whole hours, 7 m for " +
		"minutes, &lt; 1 m under a minute and 1 d 6 h from a day on, each part cut down, never rounded up. " +
		"A count has one decimal when it is not whole, for example 1.5",
	"Push activity not readable means the token forsgren collects with was refused the read of the pushes " +
		"of a repository of the project (a 403, recorded in data/pushes_denied.csv)",
	"Deployment numbers are never shown in its place",
	"Pushes not collected yet means no push has been collected yet",
	"The Mainline Interval of each project is in five columns: mean, deviation, median, p90 and gaps, one number each",
	"The mean is the average, and the deviation is the sample standard deviation of the time between " +
		"commits landing on the main branch, by their committer date",
	"The column gaps is how many gaps the other four columns are made from, for example 1162",
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
	"The cell in gaps then ends with how many commits are timed this way, written " +
		"3 · 2 commits timed by author date, or 3 · 1 commit timed by author date",
	"Those commits are not looked up again, so the note stays until their deployments leave the window",
	"A dash in all five columns means fewer than two commits",
	"With one gap the mean and the gaps are shown, and the deviation and the median are dashes, " +
		"because a sample deviation and a median need two gaps",
	"between deployed commits, not every commit of the mainline",
	"The median and the 90th percentile (p90) of the gaps are columns of their own",
	"The median is the middle gap, or the mean of the two middle gaps when there is an even number of them",
	"p90 is the nearest-rank percentile: the gap at position 0.9 × the number of gaps, rounded up, of the gaps " +
		"sorted from the shortest, so nine tenths of the gaps are no longer than it",
	"The median needs two gaps and p90 needs ten gaps",
	"With fewer than ten gaps p90 would only be the longest gap",
	"A mean far above the median, and a deviation far above the mean, point at a few long gaps among short ones",
	"Developers has one column: developers",
	"The column developers is the number of people who made the commits deployed in the " +
		"window, those a merge brought in included: the distinct GitHub accounts of their authors, " +
		"so a person who commits from several email addresses counts once",
	"Logins listed together in a same_developer group of the config count as one developer, " +
		"with or without capital letters; the stored commits keep each login",
	"A bot account, whose GitHub login ends in [bot], is not a developer, and its commits are left out",
	"A commit whose author GitHub links to no account is not guessed to be anyone's, and GitHub's " +
		"placeholder author invalid-email-address is not a developer either",
	"A project with no deployed commit shows a dash, and a project whose commits are all by bots has 0 developers",
	"The page shows the number only, never who the developers are",
	"The interval is not divided by it: a team of ten makes more commits than one person with the same habits",
	"The two metrics are read together",
	"The Mainline Interval shows how often the deployed commits landed on the main branch, " +
		"by committer date, in the window",
	"A short interval with a long lead time points at long-lived branches",
	"The TBD page is listed by default (tbd_page: true): it is generated and in the menu. " +
		"Set tbd_page: unlisted to generate it with no menu entry, so that search engines are asked to skip it, " +
		"or tbd_page: false to not generate it.",
}

// legendLeadText are the sentences that say what each number of the Mainline
// Lead Time column counts (forsgren#256 step 3): the scope of #342, the cell's
// parts, the lower bound and the stand-ins, the people of #349 and #355, the
// legacy format as Yves worded it on #356, and what not readable means.
var legendLeadText = []string{
	"PR Lead Time has one column: pull requests",
	"The pull requests column covers merged human pull requests only, " +
		"not every change that reaches the main branch",
	"Work pushed straight to the main branch is in the push groups and the Direct share, " +
		"so a pull request stands in for the life of a branch",
	"In a workflow that mixes both, this column covers only the changes that came through pull requests",
	"Each pull request merged in the last 30 days, counted by its merge time, " +
		"gives one lead time: from its first commit, " +
		"the earliest author date of its commits, to the merge",
	"A first commit dated after the merge counts as 0",
	"mean ± deviation (pull requests), for example 3 h ± 1 h (4)",
	"the deviation the sample standard deviation (n-1)",
	"50% (2 of 4) pull requests merged within 24 hours of their first commit",
	"The share is rounded down, and a lead time of at most 24 hours counts as within, the same boundary everywhere",
	"There is no pass or fail verdict",
	"The Mainline Interval uses the committer date: how often changes reach the main branch",
	"PR Lead Time uses the author date of the first commit up to the merge time",
	"That lead time is a lower bound: the count reads (4, 1 cut) and the cell adds the mean is a lower bound",
	"A cut pull request can make the mean too low, and it can make the share merged within 24 hours too high",
	"the created time of the pull request stands in for the first commit time",
	"1 pull request timed by its created time, or 2 pull requests timed by their created time",
	"Only a GitHub account of the type User is a person",
	"3 bot pull requests not counted",
	"is not counted either, and the cell does not say how many",
	"a pull request in the legacy format has no known author type",
	"The placeholder author invalid-email-address",
	"is an unknown author, not a developer",
	"Mostly estimated: 7 of 13 commits timed by author date.",
	"shows a dash in pull requests: no human pull request was merged in this period, and its changes may go " +
		"directly to the main branch, which the Direct share shows",
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
	for _, want := range wordingWhere(legendLeadText, section, false) {
		t.Errorf("want %q in the TBD page section", want)
	}
	for _, never := range wordingWhere(legendLeadNever, section, true) {
		t.Errorf("want no %q in the TBD page section", never)
	}
}

// wordingWhere are the sentences of wordings whose presence in section is
// present, so the sentences missing or the ones that should not be there.
func wordingWhere(wordings []string, section string, present bool) []string {
	var found []string
	for _, w := range wordings {
		if strings.Contains(section, w) == present {
			found = append(found, w)
		}
	}
	return found
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
	"Work pushed straight to the main branch is not in it",
	"and that changes may go straight to the main branch",
	"mean ± deviation (gaps)",
	"2 commits without a known author are not counted",
	"excluded (legacy data)",
	"median 5 min · p90 1 h",
	"A dash means fewer than two commits",
	"the number leaves it out and the cell says how many",
	"Developers has two columns",
	"counted in the column unknown authors",
	"The column is written 170 (14%)",
	"the cell ends with legacy data",
	"Commits in the legacy format have no known author and count as unknown authors",
	"Mainline Lead Time has three columns: direct, pull requests and batch size",
	"The direct column is",
	"The batch size column is",
	"forsgren sees no push time",
	"pull request merges cannot be told apart yet",
	"2 deployments of unknown lineage not counted",
	"which the direct column shows",
	"Then come Mainline Lead Time, Mainline Interval and Developers",
	"A project measured by releases alone reads, for example, 85 releases",
	"Direct, Pull requests, Unknown authors and Bots",
	"Unknown authors and Bots are counted in addition",
	"A duration is written like 2 h 5 min",
	"Mainline Lead Time has one column: pull requests",
	"Mainline Lead Time uses the author date of the first commit up to the merge time",
	"Mainline Lead Time shows how long the changes",
	"written 2 pull requests of unknown author not counted",
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
	tbdHeading, historyHeading := "<h2>Trunk-based development [TBD]</h2>", "<h2>History page (BETA)</h2>"
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
	_, section, found := strings.Cut(legend, "<h2>Trunk-based development [TBD]</h2>")
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
	for _, once := range []string{"The pull requests column covers merged human pull requests only", "each commit once",
		"A dash in all five columns means fewer than two commits", "sample standard deviation of the time between commits",
		"deployments of the last 30 days shipped"} {
		if n := strings.Count(got, once); n != 1 {
			t.Errorf("want %q once in the legend, got %d", once, n)
		}
	}
}

// legendTbdGroups are the sub-headings of the legend's TBD page section
// (forsgren#404): a general part first, then one for each group of the TBD
// table in table order, with the push states last. Each has its id, its text
// and one sentence of its group that must follow it.
var legendTbdGroups = []struct{ id, title, sentence string }{
	{"tbd-general", "General", "Every number is of the last 30 days"},
	{"tbd-mainline-interval", "Mainline Interval", "The Mainline Interval of each project is in five columns"},
	{"tbd-time-to-main-per-commit", "Time to main per commit", "Time to main per commit is a duration"},
	{"tbd-time-to-deploy-per-commit", "Time to deploy per commit", "Time to deploy per commit is a duration"},
	{"tbd-pr-lead-time", "PR Lead Time", "PR Lead Time has one column"},
	{"tbd-volume", "Volume", "Volume has three columns"},
	{"tbd-commits-per-push", "Commits per push", "Commits per push is a count of commits"},
	{"tbd-commits-per-deployment", "Commits per deployment", "Commits per deployment is a count of commits"},
	{"tbd-shares-of-commits", "Shares of commits", "Shares of commits has four columns"},
	{"tbd-developers", "Developers", "The column developers is the number of people"},
	{"tbd-push-states", "Push states", "Pushes not collected yet means no push has been collected yet"},
}

// TestLegendTbdSectionHasASubHeadingForEachGroup (forsgren#404): the TBD
// section has exactly these h3 headings with their ids in this order, and a
// sentence of each group follows its heading before the next one.
func TestLegendTbdSectionHasASubHeadingForEachGroup(t *testing.T) {
	section := legendTbdSection(t, rendered(t, "legend.html", calculated()))
	parts := strings.Split(section, "<h3 ")
	if len(parts)-1 != len(legendTbdGroups) {
		t.Fatalf("want %d h3 headings in the TBD section, got %d", len(legendTbdGroups), len(parts)-1)
	}
	for i, g := range legendTbdGroups {
		part := parts[i+1]
		head := `id="` + g.id + `">` + g.title + "</h3>"
		if !strings.HasPrefix(part, head) {
			t.Errorf("want heading %d to be %q, got %.60q", i+1, head, part)
		}
		if !strings.Contains(part, g.sentence) {
			t.Errorf("want %q after the heading %q", g.sentence, g.title)
		}
	}
}
