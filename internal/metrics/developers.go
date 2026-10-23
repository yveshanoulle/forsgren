package metrics

// Developers (forsgren#273, step 2) is the number next to the Mainline
// Interval: how many people made the commits it counts, because a team of ten
// makes more commits than one person with the same habits. The interval
// itself is not divided by it.
//
//   - the commits are the Mainline Interval's (distinctInWindow): deployed in
//     the DORA window, each once by repository (ignoring case) and SHA, in the
//     project whose config lists the repository;
//   - a developer is a distinct GitHub login among them (history.Commit's
//     Author), compared ignoring case as GitHub compares logins, so one person
//     is one developer across the email addresses they commit with;
//   - a bot account, whose login ends in [bot] (dependabot[bot] among them),
//     is no developer, and its commits are left out;
//   - a commit without a login (GitHub links it to no account, or it was
//     stored by the commits format v1) is not guessed to be anyone's: it is
//     counted as unknown, and the note says how many.
//
// The result holds counts only, never a login (decision 274).

import (
	"fmt"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// Developers is one project's count of the authors of its Mainline Interval's
// commits.
type Developers struct {
	Project string
	// Count is the number of distinct human logins.
	Count int
	// Unknown counts the commits without a login, which Count leaves out.
	Unknown int
}

// botSuffix ends the login of every GitHub bot account.
const botSuffix = "[bot]"

// Note names the commits whose author is not known, which the count leaves
// out: "2 commits without a known author are not counted"; empty when there
// are none.
func (d Developers) Note() string {
	switch d.Unknown {
	case 0:
		return ""
	case 1:
		return "1 commit without a known author is not counted"
	}
	return fmt.Sprintf("%d commits without a known author are not counted", d.Unknown)
}

// MainlineDevelopers returns the Developers of each project, in the order of
// projects, from the data's stored commits at the render time now, over its
// DORA window: the commits MainlineIntervals counts.
func MainlineDevelopers(projects []config.Project, data Data, now time.Time) []Developers {
	index := indexOf(projects)
	logins := make([]map[string]bool, len(projects))
	out := make([]Developers, len(projects))
	for i, p := range projects {
		logins[i], out[i] = map[string]bool{}, Developers{Project: p.Name}
	}
	counted := distinctInWindow{window: data.window(), now: now, seen: map[string]bool{}}
	for _, c := range data.Commits {
		if i, ok := index.of(c.Repository); ok && counted.admits(c) {
			out[i].Unknown += noteAuthor(logins[i], c.Author)
		}
	}
	for i := range out {
		out[i].Count = len(logins[i])
	}
	return out
}

// noteAuthor adds a human login to logins, ignoring case, and returns 1 for a
// commit without one, 0 otherwise; a bot's login is left out.
func noteAuthor(logins map[string]bool, login string) int {
	switch {
	case login == "":
		return 1
	case !strings.HasSuffix(login, botSuffix):
		logins[strings.ToLower(login)] = true
	}
	return 0
}
