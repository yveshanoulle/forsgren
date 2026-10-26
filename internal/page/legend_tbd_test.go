package page

import (
	"strings"
	"testing"
)

// legendTbdText are the sentences of the legend's TBD page section as a reader's page (forsgren#448):
// question headings, what the numbers mean, the names, the five notes and the link to the technical
// reference. The calculation detail is in docs/pages-and-views.md.
var legendTbdText = []string{
	"Trunk-based development means integrating small changes into the main branch often",
	"The TBD page is one table with a row for each project, and under it a row for each label or service",
	"All figures cover the last 30 days, the DORA window",
	"By default, the table shows the median of each measure, the middle value",
	"The mean is the average. p90 is the value that nine tenths of the values are no larger " +
		"than",
	"A dash means there is not enough data to calculate the figure. It does not mean zero",
	"When all three figures are shown, the columns of time to main, time to deploy, commits per push and commits " +
		"per deployment carry their measure for a screen reader, such as the mean of time to main",
	"The Notes below the table say what each number means",
	"They explain estimates, a lower bound, a stand-in time and bots that are not counted",
	"Missing data is shown as a dash, a no-data row or a not-readable cell, not as a note",
	"The Mainline Interval is the time between commits reaching the main branch",
	"A shorter interval means changes are integrated more often",
	"It measures the commits on the main line: the commits that landed on the main branch one " +
		"after another",
	"A commit that a merge brought in from a branch is not on the main line, but the merge " +
		"commit is",
	"Each commit is placed at the time it landed, its committer date",
	"Only commits that deployments of the last 30 days shipped are measured, each once",
	"Fewer than two commits make no interval, so the cell is a dash",
	"When forsgren does not know the committer date of a commit, it places the commit at its " +
		"author date",
	"Time to main per commit is how old one change is when it reaches the main branch",
	"For each commit it runs from the author date of the commit to the push that brought it " +
		"to main",
	"The pushes come from GitHub's activity list of the default branch of each repository",
	"Push data starts when forsgren first collects it, so older pushes are not looked up " +
		"afterwards",
	"The clock starts at the author date of the commit: when the commit was written",
	"It stops at the push to main that brought the commit, at the time GitHub records for " +
		"that push",
	"A commit counts once, at its first push. A commit written after its push counts as 0",
	"The Mainline Interval is about how often changes land on main",
	"Time to main per commit is about how old one change is when it lands",
	"One is a rhythm and the other is an age",
	"Time to deploy per commit is how old one change is when it is first deployed",
	"For each commit it runs from the author date of the commit to the first deployment that " +
		"contains it",
	"A commit written after its deployment counts as 0",
	"Volume shows three numbers",
	"Commits is the number of commits the pushes of the window brought to the main branch, " +
		"each counted once",
	"Only the main line of a push counts, so a merge counts as its merge commit",
	"Pushes is the number of pushes. Deployments is the number of successful deployments",
	"Commits per push is how many commits reach main in each push",
	"A push whose commits could not be counted, such as a force push, is left out",
	"Commits per deployment is how many commits on the main line a deployment brought",
	"The commits a merge brought in from a branch count as the one merge commit",
	"Smaller batches are generally easier to review, test and troubleshoot",
	"Shares of commits shows how the commits of Volume reached main",
	"All four are shares of the same Commits number, in whole percent rounded down",
	"Direct: commits that did not come through a pull request",
	"a branch merged locally and then pushed",
	"PR: commits that came through a pull request",
	"A commit counts as PR when it is the merge commit of a merged pull request, or when a " +
		"pull request merge brought it to main",
	"Unknown: commits whose author GitHub links to no account",
	"Bots: commits made by automated accounts",
	"Direct and PR add up to 100%, give or take the rounding",
	"Unknown and Bots overlap Direct and PR; they are not additional categories",
	"Developers is the number of distinct people who authored the commits deployed in the " +
		"last 30 days",
	"including the commits a merge brought in from a branch",
	"A person who commits from several email addresses counts once",
	"Several GitHub accounts can be configured to count as one person",
	"Bots and commits whose author GitHub links to no account are left out",
	"The page shows the number only, never who the developers are",
	"a larger team may naturally integrate more commits",
	"Short Mainline Interval and short PR Lead Time: changes are integrated often and quickly",
	"Short Mainline Interval and long PR Lead Time: changes reach main often, but some spend " +
		"a long time on branches",
	"Long Mainline Interval and short PR Lead Time: changes are integrated quickly when they " +
		"happen, but integration is rare",
	"Long Mainline Interval and long PR Lead Time: changes are integrated rarely and spend a " +
		"long time waiting",
	"No single number proves that a team practises trunk-based development",
	"A project with no deployed commit, no final deployment (a failed one counts), no push " +
		"and no merged pull request in the last 30 days shows one sentence across its row: " +
		"currently no data for this project in the last 30 days",
	"It has no note markers",
	"A service row with no final deployment (a failed one counts) and no deployed commit in the last " +
		"30 days shows currently no data for this service in the last 30 days",
	"Pushes and pull requests do not count for a service",
	"A label row follows the rule for a project",
	"A project with data in any one of these keeps its figures, and a single column without " +
		"data keeps its dash",
	"Some figures are estimates when stored information is incomplete",
	"Push activity not readable means the token forsgren collects with was refused the read " +
		"of the pushes of a repository of the project",
	"Pull requests not readable means the token forsgren collects with was refused the pull " +
		"request read",
	"Deployment numbers are never shown in their place",
	"Pushes not collected yet means no push has been collected yet",
	"No pull requests have been collected yet means the collection has not read any pull " +
		"request yet",
	"Mainline Interval and Mainline Lead Time are the two metrics of the Mainline Throughput " +
		"Indicator",
	"This page shows PR Lead Time for the work that goes through pull requests, and Time to main for " +
		"every change, direct pushes included",
	"Time to main is described in its own part",
	"Time to main is the stretch of a change's lead time from its commit to the main branch",
	"The Mainline Throughput Indicator has one lead time, the Mainline Lead Time",
	"Measured on pull requests alone, it leaves out teams that push straight to main",
	"pushing straight to main is very much what trunk-based development is about",
	"So this page shows the Mainline Lead Time in full, and two views of it",
	"the full measure: every commit that reached main in the last 30 days, from its author date to the " +
		"earliest push that brought it to main",
	"pushed directly, brought by a merge commit, rebased or squashed",
	"It is a view of the merged pull requests, and it counts people only",
	"Mainline Lead Time is the one number for all of it",
	"Mainline Lead Time and Time to main count different commits",
	"The full measure leaves the merge commits themselves out",
	"The commits that the merge brought in from the branch stay, each from its own author date",
	"Time to main keeps the merge commit and leaves the branch commits out",
	"The conflict resolution inside a merge commit is not measured",
	"A squash merge replaces the commits of its pull request by one new commit",
	"the commits of the pull request in place of the squash commit, each from its own author date, never both",
	"A squash commit is detected when it has one parent, is the merge commit of its pull request and its " +
		"push brought one commit",
	"A squash inside a push of several commits is not detected",
	"The original commits of a squash count at the push of the squash commit",
	"The merge time of the pull request never stands in for it: without that push, the originals are not " +
		"counted at all",
	"Bots count in Mainline Lead Time, as in Time to main. PR Lead Time does not count them",
	"Pushes whose commits are not known, such as a force push or a push with too many commits to read, are " +
		"left out: their data is incomplete, so their commits are not counted, not even as 0 (note 6)",
	"the merge and squash branch commits of that time are missing, so the figure may read short (note 7)",
	"The note goes away by itself once the whole window lies after the change",
	"a dash below two commits for the median and below ten for the p90, and a negative time counts as 0",
	"The full Mainline Lead Time covers every commit that reached main",
	"(6) Pushes left out: their commits are not known (incomplete data), not counted as 0. It applies to " +
		"Mainline Lead Time",
	"(7) History still filling: merge and squash branch commits from before this version are missing. It " +
		"applies to Mainline Lead Time",
	"for work that goes through a pull request: from the first commit of the pull request to its merge",
	"for the commits on the main line that a push brought to main, direct pushes included: from the " +
		"author date of the commit to the push that brought it",
	"The commits a merge brought in from a branch are not counted there; the merge commit is",
	"A team that works with pull requests reads PR Lead Time first. A team that pushes to main reads " +
		"Time to main first. A team that works both ways has both",
	"The table shows the median by default, so the figure is the median time to main",
	"The first row of a project is its total, over all of its repositories and deployments",
	"A project has a row under its total for each label and each service that the configuration gives it",
	"The rows under the total are sorted by label, ignoring case",
	"A label row is one repository, with every measure of that repository",
	"A service row is one deployment task of a repository",
	"Time to deploy per commit, Deployments, Commits per deployment and Developers, counted over the " +
		"deployments of that task and the commits they shipped",
	"Per repository: see the project row",
	"The Notes list gives the name of such a row as Project: label, for example Acme Shop: Website",
	"(1) Mostly estimated: commits timed by author date. It applies to the Mainline Interval",
	"(2) Commits timed by author date. It applies to the Mainline Interval",
	"(3) A lower bound: a first commit time of a pull request was cut. It applies to PR Lead " +
		"Time",
	"(4) Pull requests timed by their created time. It applies to PR Lead Time",
	"(5) Bot pull requests not counted. It applies to PR Lead Time",
	"one line for each kind of note that occurs, with the projects it applies to and their " +
		"counts",
	"The exact calculations are in the technical reference",
	"Pages and views, the section The TBD page",
}

// legendLeadText are the sentences that say what PR Lead Time counts (forsgren#256 step 3, worded again in
// forsgren#448): the scope of #342, the cut and stood-in times, and the people of #349 and #355.
var legendLeadText = []string{
	"PR Lead Time is the time from the first commit of a pull request to its merge",
	"the earliest author date of its commits",
	"It counts the pull requests merged in the last 30 days, by their merge time",
	"A first commit dated after the merge counts as 0",
	"It includes only merged pull requests opened by people",
	"Pull requests opened by bots and changes pushed directly to main are not included",
	"In a workflow that mixes both, this column covers only the changes that came through " +
		"pull requests",
	"the Direct share shows how many",
	"That is not proof of direct commits",
	"so the lead time is a lower bound (note 3)",
	"the created time of the pull request stands in for the first commit time (note 4)",
	"Pull requests opened by bots are not counted (note 5)",
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
	"is the name this page gives to the Mainline Lead Time",
	"forsgren's own",
	"Forsgren uses no abbreviation",
	"by their author date",
	"next to each other by author date",
	"were made, by author date",
	"who made the commits it counts",
	"Mainline Lead Time is not on this page yet",
	"It will show how long a commit takes",
	"Work pushed straight to the main branch is not in it",
	"Why are there two lead times?",
	"as two numbers",
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
	"In each group of three columns the mean is the average",
	"is in five columns: mean, deviation, median, p90 and gaps",
	"The column gaps is how many gaps",
	"A dash in all five columns",
	"deviation",
	"commits timed by author date, or 3 · 1 commit timed by author date",
	"The cell in gaps",
	"Mostly estimated: 7 of 13 commits timed by author date.",
	"mean ± deviation (pull requests)",
	"pull requests merged within 24 hours of their first commit",
	"the count reads (4, 1 cut)",
	"1 pull request timed by its created time",
	"3 bot pull requests not counted",
	"PR Lead Time has one column: pull requests",
	"are columns of their own",
	"tbd_figures",
	"tbd_page",
	"first-parent",
	"pushes_denied.csv",
	"pulls_denied.csv",
	"nearest-rank",
	"3 h 22",
	"legacy",
	"a 403",
	"Every number is of the last 30 days",
	"Work pushed straight to the main branch is in the push groups",
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
// Mainline Interval and PR Lead Time are in the legend once, and the TBD page does not repeat them.
func TestLegendSaysEachTbdSentenceOnce(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	for _, once := range []string{"It includes only merged pull requests opened by people",
		"Fewer than two commits make no interval, so the cell is a dash",
		"Each commit is placed at the time it landed, its committer date",
		"deployments of the last 30 days shipped"} {
		if n := strings.Count(got, once); n != 1 {
			t.Errorf("want %q once in the legend, got %d", once, n)
		}
	}
}

// legendTbdGroups are the sub-headings of the legend's TBD page section (forsgren#404, forsgren#448): the
// question headings in reading order. Each has its id, its text and one sentence of its part that must
// follow it.
var legendTbdGroups = []struct{ id, title, sentence string }{
	{"tbd-general", "How do I read the numbers?", "A dash means there is not enough data"},
	{"tbd-rows", "What are the rows under a project?", "The first row of a project is its total"},
	{"tbd-mainline-interval", "Mainline Interval (How often do changes reach main?)",
		"The Mainline Interval is the time between commits"},
	{"tbd-time-to-main-per-commit", "Time to main (How long does a change take to reach main?)",
		"Time to main per commit is how old one change"},
	{"tbd-time-to-main-clock", "Time to main clock (When does it start and stop?)",
		"The clock starts at the author date"},
	{"tbd-interval-versus-time-to-main", "Mainline Interval and Time to main (How do they differ?)",
		"One is a rhythm and the other is an age"},
	{"tbd-time-to-deploy-per-commit", "Time to deploy per commit (How long does a change take to be deployed?)",
		"Time to deploy per commit is how old one change"},
	{"tbd-pr-lead-time", "PR Lead Time (How long does a pull request take to merge?)",
		"PR Lead Time is the time from the first commit"},
	{"tbd-mainline-lead-time", "Mainline Lead Time (Why are there three lead times?)",
		"The Mainline Throughput Indicator has one lead time"},
	{"tbd-volume", "Volume (How much work is integrated at once?)", "Volume shows three numbers"},
	{"tbd-shares-of-commits", "Shares of commits (How does work reach main?)",
		"Shares of commits shows how the commits"},
	{"tbd-developers", "Developers (How many developers contribute?)",
		"Developers is the number of distinct people"},
	{"tbd-what-to-look-for", "What should I look for?", "No single number proves"},
	{"tbd-missing-data", "What if data is missing or incomplete?", "Some figures are estimates"},
	{"tbd-names", "Where do the names come from?", "Mainline Interval and Mainline Lead Time are the two metrics"},
	{"tbd-notes", "Notes", "(1) Mostly estimated"},
	{"tbd-reference", "Where is the calculation explained?", "The exact calculations are in the technical reference"},
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

// legendLeadVersusDeployText are the sentences of the legend's Time to deploy per commit part that say how it
// differs from Lead time for changes (forsgren#421, worded for the main line in forsgren#448).
var legendLeadVersusDeployText = []string{
	"Lead time for changes (the DORA pages) and Time to deploy per commit both time a commit " +
		"from its author date to a deployment, over the same last 30 days, and a negative time " +
		"counts as 0",
	"Lead time for changes counts every commit a deployment brought, also the commits a merge " +
		"brought in from a branch, once for each deployment that shipped it, and shows the median " +
		"with its DORA Quick Check level",
	"Time to deploy per commit counts only the commits of the main line, a merge as its merge " +
		"commit, each once, at its first deployment, and shows the median, or the mean, the " +
		"median and the p90 when all three are shown",
	"With several services the same commit is deployed several times, and Lead time for " +
		"changes, which counts the later deployments too, comes out longer",
}

// TestLegendSaysHowLeadTimeAndTimeToDeployDiffer (forsgren#421): the Time to
// deploy per commit part carries the paragraph, and the Lead time for changes
// part points to it by the heading id.
func TestLegendSaysHowLeadTimeAndTimeToDeployDiffer(t *testing.T) {
	got := rendered(t, "legend.html", calculated())
	section := legendTbdSection(t, got)
	for _, want := range wordingWhere(legendLeadVersusDeployText, section, false) {
		t.Errorf("want %q in the TBD page section", want)
	}
	_, lead, _ := strings.Cut(got, "<h2>Lead time for changes</h2>")
	lead, _, _ = strings.Cut(lead, "<h2>")
	if !strings.Contains(lead, `<a href="#tbd-time-to-deploy-per-commit">Time to deploy per commit</a>`) {
		t.Errorf("want a link to #tbd-time-to-deploy-per-commit in the Lead time for changes part, got %q", lead)
	}
}
