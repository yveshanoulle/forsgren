package metrics

// Developers (forsgren#273, step 2) is the number next to the Mainline
// Interval: how many people made the commits it counts, because a team of ten
// makes more commits than one person with the same habits. The interval
// itself is not divided by it.
//
//   - the commits are the Mainline Interval's window (distinctInWindow):
//     deployed in the DORA window, each once by repository (ignoring case) and
//     SHA, in the project whose config lists the repository; the first-parent
//     judgement of the interval (forsgren#254) does not apply, so the authors
//     of the commits a merge brought in count too;
//   - a developer is a distinct GitHub login among them (history.Commit's
//     Author), compared ignoring case as GitHub compares logins, so one person
//     is one developer across the email addresses they commit with;
//   - the logins of one same_developer group (forsgren#361) are one developer,
//     compared ignoring case, the first login of the group naming it; a login
//     in no group is its own developer, and a group none of whose logins
//     appears counts nothing; the stored commits keep the real login;
//   - a bot account, whose login ends in [bot] (dependabot[bot] among them),
//     is no developer, and its commits are left out;
//   - a commit without a login (GitHub links it to no account, or it was
//     stored by the commits format v1) is not guessed to be anyone's, and so
//     is a commit by GitHub's placeholder login invalid-email-address
//     (placeholderLogin, ignoring case), GitHub's answer for an author email it
//     links to no account, which is no person (forsgren#355): neither is a
//     developer. The TBD page counts them as unknown authors among the pushed
//     commits instead (PushMeasures.UnknownAuthorShare, forsgren#397, step 5).
//
// The result holds counts only, never a login (decision 274).

import (
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// Developers is one project's count of the authors of the commits deployed in
// its Mainline Interval's window.
type Developers struct {
	Project string
	// Count is the number of distinct human logins.
	Count int
	// Commits counts the distinct commits deployed in the window, the bots'
	// included.
	Commits int
}

// botSuffix ends the login of every GitHub bot account.
const botSuffix = "[bot]"

// placeholderLogin is the login GitHub answers for a commit author whose
// email links to no account (forsgren#355): no person, so no developer.
const placeholderLogin = "invalid-email-address"

// The Developers column of the TBD page is the count alone (forsgren#397,
// step 5): the unknown authors moved to the shares of the commits, on the
// push base (PushMeasures.UnknownAuthorShare). A project without a deployed
// commit has no data, a dash; one whose commits are all bots' has 0
// developers, a count.

// CountCell is the count of developers, "3"; "-" for a project without a
// deployed commit.
func (d Developers) CountCell() string {
	if d.Commits == 0 {
		return noNumber
	}
	return GroupDigits(d.Count)
}

// MainlineDevelopers returns the Developers of each project, in the order of
// projects, from the data's stored commits at the render time now, over its
// DORA window: every distinct deployed commit of it, those a merge brought in
// included, which MainlineIntervals leaves out (forsgren#254). The logins of
// each of groups (the config's same_developer) count as one developer.
func MainlineDevelopers(projects []config.Project, data Data, now time.Time, groups [][]string) []Developers {
	index := indexOf(projects)
	logins := make([]map[string]bool, len(projects))
	out := make([]Developers, len(projects))
	for i, p := range projects {
		logins[i], out[i] = map[string]bool{}, Developers{Project: p.Name}
	}
	named := developerNames(groups)
	counted := distinctInWindow{window: data.window(), now: now, seen: map[string]bool{}}
	for _, c := range data.Commits {
		if i, ok := index.of(c.Repository); ok && counted.admits(c) {
			out[i].add(logins[i], named, c)
		}
	}
	for i := range out {
		out[i].Count = len(logins[i])
	}
	return out
}

// developerNames maps each lower-cased login of groups to the lower-cased
// first login of its group, the name its developer counts under.
func developerNames(groups [][]string) map[string]string {
	named := map[string]string{}
	for _, g := range groups {
		for _, login := range g {
			named[strings.ToLower(login)] = strings.ToLower(g[0])
		}
	}
	return named
}

// add counts the deployed commit c and its author in logins under the name
// named gives it, ignoring case; a commit without a login or with GitHub's
// placeholder has no developer, and a bot's login is left out, grouped or
// not.
func (d *Developers) add(logins map[string]bool, named map[string]string, c history.Commit) {
	d.Commits++
	if !isPerson(c.Author) {
		return
	}
	key := strings.ToLower(c.Author)
	if name, grouped := named[key]; grouped {
		key = name
	}
	logins[key] = true
}

// isPerson says whether login is a person's: not empty, not GitHub's
// placeholder and not a bot's.
func isPerson(login string) bool {
	return login != "" && !strings.EqualFold(login, placeholderLogin) && !strings.HasSuffix(login, botSuffix)
}
