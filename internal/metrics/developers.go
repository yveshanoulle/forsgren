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
//     stored by the commits format v1) is not guessed to be anyone's: it is
//     counted as unknown, and the unknown authors cell says how many and
//     their share of the deployed commits;
//   - so is a commit by GitHub's placeholder login invalid-email-address
//     (placeholderLogin, ignoring case), GitHub's answer for an author email
//     it links to no account, which is no person (forsgren#355); the stored
//     line keeps the login, so the counting side decides, for the lines
//     stored before as for the new ones;
//   - a commit without a login stored before the commits format v3, with
//     neither parents nor a committer date, is legacy data (forsgren#345,
//     step 3), a placeholder one never, since GitHub named it: when those
//     are more than half of the deployed commits, the unknown cell says so plainly
//     (Yves's wording on #344). It is incomplete attribution, never called an
//     estimate; the unknown commits stored with their lineage, which GitHub
//     links to no account, are not called legacy data.
//
// The result holds counts only, never a login (decision 274).

import (
	"fmt"
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
	// Unknown counts the commits without a login, which Count leaves out.
	Unknown int
	// Legacy counts the Unknown commits stored before the commits format v3,
	// with neither parents nor a committer date (forsgren#345, step 3).
	Legacy int
	// Commits counts the distinct commits deployed in the window, the bots'
	// included.
	Commits int
}

// botSuffix ends the login of every GitHub bot account.
const botSuffix = "[bot]"

// placeholderLogin is the login GitHub answers for a commit author whose
// email links to no account (forsgren#355): no person, so no developer.
const placeholderLogin = "invalid-email-address"

// The Developers are two columns of the TBD page (forsgren#387, step 2):
// developers, the count, and unknown authors, the commits left out of it and
// their share. A project without a deployed commit has no data, a dash in
// both; one whose commits are all bots' has 0 developers, a count.

// CountCell is the count of developers, "3"; "-" for a project without a
// deployed commit.
func (d Developers) CountCell() string {
	if d.Commits == 0 {
		return noNumber
	}
	return fmt.Sprint(d.Count)
}

// UnknownCell is the commits without a known author and their share of the
// window's distinct deployed commits, bots' included, in whole percent rounded
// down, "170 (14%)"; "-" for a project without a deployed commit. When the
// legacy commits are more than half of the deployed ones it ends with
// legacyNote (forsgren#345, step 3, Yves's wording on #344).
func (d Developers) UnknownCell() string {
	if d.Commits == 0 {
		return noNumber
	}
	cell := fmt.Sprintf("%d (%d%%)", d.Unknown, 100*d.Unknown/d.Commits)
	if mostOf(d.Legacy, d.Commits) {
		return cell + cellSeparator + d.legacyNote()
	}
	return cell
}

// legacyNote says the unknown authors are legacy data, "legacy data", and when
// some of them are not, how many are: "3 of them legacy data", the others
// stored with their lineage, which GitHub links to no account. It is
// incomplete attribution, never called an estimate.
func (d Developers) legacyNote() string {
	if d.Legacy < d.Unknown {
		return fmt.Sprintf("%d of them legacy data", d.Legacy)
	}
	return "legacy data"
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

// add counts the deployed commit c, its author in logins under the name named
// gives it, and whether it is unknown, and legacy data: no login stored before
// the commits format v3.
func (d *Developers) add(logins map[string]bool, named map[string]string, c history.Commit) {
	d.Commits++
	d.Unknown += noteAuthor(logins, named, c.Author)
	if c.Author == "" && c.Legacy() {
		d.Legacy++
	}
}

// noteAuthor adds a human login to logins, ignoring case and under the name
// named gives it, and returns 1 for a commit without one or with GitHub's
// placeholder, 0 otherwise; a bot's login is left out, grouped or not.
func noteAuthor(logins map[string]bool, named map[string]string, login string) int {
	switch {
	case login == "", strings.EqualFold(login, placeholderLogin):
		return 1
	case !strings.HasSuffix(login, botSuffix):
		key := strings.ToLower(login)
		if name, grouped := named[key]; grouped {
			key = name
		}
		logins[key] = true
	}
	return 0
}
