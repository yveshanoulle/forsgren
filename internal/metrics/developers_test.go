package metrics

import (
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// by is the commit of acme/app with the given sha, authored a day and deployed
// an hour before now, by the made-up GitHub login (empty: unknown).
func by(login, sha string) history.Commit {
	c := shopAuthored(sha, day)
	c.Author = login
	return c
}

// shopDevelopers is Acme Shop's Developers over the commits, in the 30 day
// window.
func shopDevelopers(commits ...history.Commit) Developers {
	return shopDevelopersGrouped(nil, commits...)
}

// shopDevelopersGrouped is shopDevelopers with the same_developer groups.
func shopDevelopersGrouped(groups [][]string, commits ...history.Commit) Developers {
	return MainlineDevelopers(projects, Data{Commits: commits}, now, groups)[0]
}

// TestDevelopersCountEachLoginOnce (forsgren#273, step 2): the developers are
// the distinct logins of the counted commits; a login of several commits is
// one developer, and GitHub logins ignore case, so octo-dev and Octo-Dev are
// one developer too.
func TestDevelopersCountEachLoginOnce(t *testing.T) {
	commits := []history.Commit{
		by("octo-dev", "a1"), by("mona-dev", "a2"), by("octo-dev", "a3"), by("Octo-Dev", "a4"),
	}
	want := Developers{Project: "Acme Shop", Count: 2, Commits: 4}
	if got := shopDevelopers(commits...); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
}

// TestDevelopersLeaveBotsOut (forsgren#273, step 2): a bot account, its login
// ending in [bot] as Dependabot's does, is no developer, and its commits are
// not unknown either: they are left out.
func TestDevelopersLeaveBotsOut(t *testing.T) {
	commits := []history.Commit{
		by("dependabot[bot]", "a1"), by("acme-helper[bot]", "a2"), by("octo-dev", "a3"),
	}
	want := Developers{Project: "Acme Shop", Count: 1, Commits: 3}
	if got := shopDevelopers(commits...); got != want || got.UnknownCell() != "0 (0%)" {
		t.Errorf("want %+v and no unknown author, got %+v and the cell %q", want, got, got.UnknownCell())
	}
	if got := shopDevelopers(by("dependabot[bot]", "a1")); got.Count != 0 {
		t.Errorf("a project with only bot commits has no developer, got %+v", got)
	}
}

// TestDevelopersNameTheUnknownAuthors (forsgren#273, step 2): a commit without
// a login (GitHub links it to no account, or it was stored by the commits
// format v1) is not guessed to be anyone's: it is counted as unknown and the
// unknown authors cell names how many and their share (forsgren#387, step 2).
func TestDevelopersNameTheUnknownAuthors(t *testing.T) {
	cases := []struct {
		name    string
		commits []history.Commit
		want    Developers
		cell    string
	}{
		{"none unknown", []history.Commit{by("octo-dev", "a1")}, Developers{Count: 1, Commits: 1}, "0 (0%)"},
		{"one unknown", []history.Commit{by("octo-dev", "a1"), by("", "a2")}, Developers{Count: 1, Unknown: 1, Commits: 2},
			"1 (50%)"},
		{"two unknown", []history.Commit{by("", "a1"), by("octo-dev", "a2"), by("", "a3")},
			Developers{Count: 1, Unknown: 2, Commits: 3}, "2 (66%)"},
		{"only unknown", []history.Commit{by("", "a1"), by("", "a2")}, Developers{Unknown: 2, Commits: 2},
			"2 (100%)"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := shopDevelopers(c.commits...)
			c.want.Project = "Acme Shop"
			if got != c.want || got.UnknownCell() != c.cell {
				t.Errorf("want %+v and cell %q, got %+v and cell %q", c.want, c.cell, got, got.UnknownCell())
			}
		})
	}
}

// TestDevelopersCountTheMainlineCommits (forsgren#273, step 2): the commits
// counted are the Mainline Interval's: deployed in the DORA window, each
// commit once by repository (ignoring case) and SHA, in the project whose
// config lists the repository, in the order of projects.
func TestDevelopersCountTheMainlineCommits(t *testing.T) {
	unknownTwice := by("", "a2")
	unknownTwice.DeploymentID = 2
	unknownUpper := by("", "a2")
	unknownUpper.Repository = "ACME/App"
	old := authored("acme/app", "a3", 50*day, 40*day)
	old.Author = "old-dev"
	tools := authored("acme/cli", "c1", day, time.Hour)
	tools.Author = "tool-dev"
	gone := authored("acme/gone", "d1", day, time.Hour)
	gone.Author = "gone-dev"
	commits := []history.Commit{by("octo-dev", "a1"), by("", "a2"), unknownTwice, unknownUpper, old, tools, gone}
	want := []Developers{
		{Project: "Acme Shop", Count: 1, Unknown: 1, Commits: 2}, {Project: "Acme Tools", Count: 1, Commits: 1},
	}
	if got := MainlineDevelopers(projects, Data{Commits: commits}, now, nil); !slices.Equal(got, want) {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if got := MainlineDevelopers(projects[:1], Data{Commits: commits, DoraDays: 90}, now, nil)[0]; got.Count != 2 {
		t.Errorf("90 days: want the commit deployed 40 days ago counted, got %+v", got)
	}
}

// TestDevelopersHoldNoLogin (forsgren#273, decision 274): the count and its
// cells are numbers and words, never a login, so no page can show one.
func TestDevelopersHoldNoLogin(t *testing.T) {
	got := shopDevelopers(by("octo-dev", "a1"), by("", "a2"), by("dependabot[bot]", "a3"))
	shown := fmt.Sprintf("%+v %s %s", got, got.CountCell(), got.UnknownCell())
	for _, login := range []string{"octo-dev", "dependabot"} {
		if strings.Contains(shown, login) {
			t.Errorf("the developers show the login %q: %s", login, shown)
		}
	}
	if got.Count != 1 || got.Unknown != 1 {
		t.Errorf("want 1 developer and 1 unknown, got %+v", got)
	}
}

// TestDevelopersCells (forsgren#387, step 2): the Developers group is two
// cells, the count of developers, and the unknown authors, their commits and
// their share of the window's distinct deployed commits, bots' included, in
// whole percent rounded down, "170 (14%)"; a project without a deployed commit
// has no data, a dash in both, while a project whose commits are all bots' has
// 0 developers, a count.
func TestDevelopersCells(t *testing.T) {
	for _, c := range []struct {
		name string
		in   Developers
		want string
	}{
		{"none", Developers{}, "- | -"},
		{"all known", Developers{Count: 3, Commits: 4}, "3 | 0 (0%)"},
		{"one unknown", Developers{Count: 1, Unknown: 1, Commits: 2}, "1 | 1 (50%)"},
		{"only unknown", Developers{Count: 0, Unknown: 2, Commits: 2}, "0 | 2 (100%)"},
		{"only bots", Developers{Commits: 3}, "0 | 0 (0%)"},
		{"rounded down", Developers{Count: 5, Unknown: 170, Commits: 1200}, "5 | 170 (14%)"},
		{"two of three", Developers{Count: 1, Unknown: 2, Commits: 3}, "1 | 2 (66%)"},
		{"just under all", Developers{Count: 1, Unknown: 199, Commits: 200}, "1 | 199 (99%)"},
		{"under one percent", Developers{Count: 9, Unknown: 1, Commits: 150}, "9 | 1 (0%)"},
	} {
		if got := c.in.CountCell() + " | " + c.in.UnknownCell(); got != c.want {
			t.Errorf("%s: %+v: want the cells %q, got %q", c.name, c.in, c.want, got)
		}
	}
}

// TestDevelopersTakeGitHubsPlaceholderForAnUnknownAuthor (forsgren#355): GitHub
// answers a commit whose author email links to no account with the
// placeholder login invalid-email-address; that is no person, so it is no
// developer: its commits are counted with the other unknown-author ones,
// ignoring case as logins do, whatever commits format stored them. They are
// no legacy data either, which is an empty author stored before the commits
// format v3, so the legacy cell says how many of the unknown ones are.
func TestDevelopersTakeGitHubsPlaceholderForAnUnknownAuthor(t *testing.T) {
	commits := []history.Commit{
		by("invalid-email-address", "a1"), by("Invalid-Email-Address", "a2"), by("octo-dev", "a3"),
		legacyBy("invalid-email-address", "a4"),
	}
	want := Developers{Project: "Acme Shop", Count: 1, Unknown: 3, Commits: 4}
	if got := shopDevelopers(commits...); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
	mostlyLegacy := shopDevelopers(legacyBy("", "a1"), legacyBy("", "a2"), legacyBy("", "a3"),
		by("invalid-email-address", "a4"))
	cell := "4 (100%) · 3 of them legacy data"
	if got := mostlyLegacy.UnknownCell(); got != cell {
		t.Errorf("want the cell %q, got %q (%+v)", cell, got, mostlyLegacy)
	}
}

// TestDevelopersMergeEachSameDeveloperGroup (forsgren#361, step 2): the logins
// of one group are one developer, compared without case; a login outside
// every group counts as before; a group of which one login appears counts
// that one, and a group none of whose logins appears counts nothing.
func TestDevelopersMergeEachSameDeveloperGroup(t *testing.T) {
	pair := [][]string{{"maintainer", "assistant-account"}}
	cases := []struct {
		name    string
		groups  [][]string
		commits []history.Commit
		want    int
	}{
		{"two logins of a group", pair, []history.Commit{by("maintainer", "a1"), by("assistant-account", "a2")}, 1},
		{"without case", pair, []history.Commit{by("Maintainer", "a1"), by("ASSISTANT-account", "a2")}, 1},
		{"group written in other case", [][]string{{"Maintainer", "Assistant-Account"}},
			[]history.Commit{by("maintainer", "a1"), by("assistant-account", "a2")}, 1},
		{"a login outside every group", pair,
			[]history.Commit{by("maintainer", "a1"), by("assistant-account", "a2"), by("mona-dev", "a3")}, 2},
		{"only one login of the group", pair, []history.Commit{by("assistant-account", "a1")}, 1},
		{"no login of the group", pair, []history.Commit{by("mona-dev", "a1")}, 1},
		{"no groups", nil, []history.Commit{by("maintainer", "a1"), by("assistant-account", "a2")}, 2},
		{"two groups", [][]string{{"a-one", "a-two"}, {"b-one", "b-two"}},
			[]history.Commit{by("a-one", "a1"), by("a-two", "a2"), by("b-two", "a3"), by("b-one", "a4")}, 2},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := shopDevelopersGrouped(c.groups, c.commits...); got.Count != c.want || got.Commits != len(c.commits) {
				t.Errorf("want %d developers over %d commits, got %+v", c.want, len(c.commits), got)
			}
		})
	}
}

// TestDevelopersKeepBotsOutOfGroups (forsgren#361, step 2): a bot login stays
// no developer when a group lists it, and the human it is grouped with still
// counts once.
func TestDevelopersKeepBotsOutOfGroups(t *testing.T) {
	groups := [][]string{{"maintainer", "helper[bot]"}}
	got := shopDevelopersGrouped(groups, by("helper[bot]", "a1"))
	if got.Count != 0 || got.Unknown != 0 {
		t.Errorf("a grouped bot alone is no developer, got %+v", got)
	}
	if got := shopDevelopersGrouped(groups, by("helper[bot]", "a1"), by("maintainer", "a2")); got.Count != 1 {
		t.Errorf("the human of the group counts once, got %+v", got)
	}
}
