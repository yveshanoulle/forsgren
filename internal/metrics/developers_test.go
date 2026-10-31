package metrics

import (
	"fmt"
	"hash/fnv"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// authored is a commit of repository with the given sha, authored and
// committed ago before now and shipped by a deployment created deployedAgo
// before now. It is the only commit of its deployment (its ID made from the
// repository and the sha) and has a parent outside it, so its lineage is
// known and it is on the first-parent chain (forsgren#254), placed at its
// committer date, the same as its author date.
func authored(repository, sha string, ago, deployedAgo time.Duration) history.Commit {
	id := fnv.New32a()
	_, _ = id.Write([]byte(strings.ToLower(repository) + "@" + sha))
	return history.Commit{
		Repository: repository, Kind: history.KindEnvironment, DeploymentID: int64(id.Sum32()) + 1000, SHA: sha,
		AuthoredAt: now.Add(-ago), DeployedAt: now.Add(-deployedAgo),
		Parents: []string{"parent-of-" + sha}, CommittedAt: now.Add(-ago),
	}
}

// shopAuthored is a commit of acme/app authored ago before now, deployed an
// hour ago.
func shopAuthored(sha string, ago time.Duration) history.Commit {
	return authored("acme/app", sha, ago, time.Hour)
}

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
	if got := shopDevelopers(commits...); got != want {
		t.Errorf("want %+v and no unknown author, got %+v", want, got)
	}
	if got := shopDevelopers(by("dependabot[bot]", "a1")); got.Count != 0 {
		t.Errorf("a project with only bot commits has no developer, got %+v", got)
	}
}

// TestDevelopersNameTheUnknownAuthors (forsgren#273, step 2): a commit without
// a login (GitHub links it to no account, or it was stored by the commits
// format v1) is not guessed to be anyone's: it is counted as unknown.
func TestDevelopersNameTheUnknownAuthors(t *testing.T) {
	cases := []struct {
		name    string
		commits []history.Commit
		want    Developers
	}{
		{"none unknown", []history.Commit{by("octo-dev", "a1")}, Developers{Count: 1, Commits: 1}},
		{"one unknown", []history.Commit{by("octo-dev", "a1"), by("", "a2")}, Developers{Count: 1, Commits: 2}},
		{"two unknown", []history.Commit{by("", "a1"), by("octo-dev", "a2"), by("", "a3")},
			Developers{Count: 1, Commits: 3}},
		{"only unknown", []history.Commit{by("", "a1"), by("", "a2")}, Developers{Commits: 2}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := shopDevelopers(c.commits...)
			c.want.Project = "Acme Shop"
			if got != c.want {
				t.Errorf("want %+v, got %+v", c.want, got)
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
		{Project: "Acme Shop", Count: 1, Commits: 2}, {Project: "Acme Tools", Count: 1, Commits: 1},
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
	shown := fmt.Sprintf("%+v %s", got, got.CountCell())
	for _, login := range []string{"octo-dev", "dependabot"} {
		if strings.Contains(shown, login) {
			t.Errorf("the developers show the login %q: %s", login, shown)
		}
	}
	if got.Count != 1 || got.Commits != 3 {
		t.Errorf("want 1 developer and 1 unknown, got %+v", got)
	}
}

// TestDevelopersCountCell (forsgren#387, step 2; forsgren#397, step 5): the
// Developers column is the count of developers; a project without a deployed
// commit has no data, a dash, while one whose commits are all bots' has 0
// developers, a count.
func TestDevelopersCountCell(t *testing.T) {
	for _, c := range []struct {
		name string
		in   Developers
		want string
	}{
		{"none", Developers{}, "-"},
		{"all known", Developers{Count: 3, Commits: 4}, "3"},
		{"only unknown", Developers{Count: 0, Commits: 2}, "0"},
		{"only bots", Developers{Commits: 3}, "0"},
	} {
		if got := c.in.CountCell(); got != c.want {
			t.Errorf("%s: %+v: want the cell %q, got %q", c.name, c.in, c.want, got)
		}
	}
}

// TestDevelopersTakeGitHubsPlaceholderForNoDeveloper (forsgren#355): GitHub
// answers a commit whose author email links to no account with the
// placeholder login invalid-email-address; that is no person, so it is no
// developer, ignoring case as logins do, whatever commits format stored it.
func TestDevelopersTakeGitHubsPlaceholderForNoDeveloper(t *testing.T) {
	commits := []history.Commit{
		by("invalid-email-address", "a1"), by("Invalid-Email-Address", "a2"), by("octo-dev", "a3"),
		legacyBy("invalid-email-address", "a4"),
	}
	if got := shopDevelopers(commits...); got.Count != 1 || got.Commits != 4 {
		t.Errorf("want 1 developer over 4 commits, got %+v", got)
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
	if got.Count != 0 {
		t.Errorf("a grouped bot alone is no developer, got %+v", got)
	}
	if got := shopDevelopersGrouped(groups, by("helper[bot]", "a1"), by("maintainer", "a2")); got.Count != 1 {
		t.Errorf("the human of the group counts once, got %+v", got)
	}
}
