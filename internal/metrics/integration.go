package metrics

// Integration (forsgren#622, step 1; decision #621, option A): how often each
// developer of a project gets commits onto main, as a distribution over the
// developers, read from the pushes of the DORA window and never a login.
//
//   - the commits are those of PushMeasures.Commits (pushesInWindow,
//     commitsOfPushes): distinct first-parent commits of the pushes of the
//     window, each at its earliest push, so a developer who works through pull
//     requests is timed at the merge push, not at their own commits;
//   - a developer is a login ignoring case, as Developers counts them: bots
//     (botSuffix), commits without a login and GitHub's placeholder login are
//     left out (isPerson) and the logins of a same_developer group are one;
//     a developer is active when they have a commit in the window;
//   - a working day is a UTC Monday to Friday; the window holds the working
//     days of the UTC dates from its first instant's date to now's date,
//     both included (WorkingDays); a weekend commit is a commit, not a day;
//   - PerDay is each active developer's commits (weekend ones included) over
//     the window's working days; Regular counts the developers with a commit
//     on at least 4 of every 5 of them (days * 5 >= 4 * WorkingDays), so the
//     page writes the share from the counts;
//   - Freshness is the working days after the date of a developer's last
//     commit up to now's date (0 when it is today's); Gap is each developer's
//     longest run of working days between two consecutive commits (the
//     working days after the earlier one's date up to the later one's), over
//     the developers with two commits or more, and GapLongest the longest
//     of them;
//   - each spread follows the existing rules (spread.go: median from two,
//     p90 from ten); the result holds counts and durations in working days,
//     never a login.

import (
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// Integration is one project's integration measures over its active
// developers.
type Integration struct {
	Project string
	// Active is the developers with a commit in the window, Regular those
	// with a commit on at least 4 of every 5 working days, of WorkingDays.
	Active, Regular, WorkingDays int
	// PerDay is the commits per working day of each developer, Freshness the
	// working days since each one's last commit, Gap the longest gap in
	// working days of each developer with two commits or more.
	PerDay, Freshness, Gap CountSpread
	// GapLongest is the longest Gap of any developer, in working days.
	GapLongest int
}

// IntegrationOf returns the Integration of each project, in the order of
// projects, from the data's stored pushes at the render time now, over its
// DORA window; groups are the config's same_developer.
func IntegrationOf(projects []config.Project, data Data, now time.Time, groups [][]string) []Integration {
	index := indexOf(projects)
	tips, _ := pushesInWindow(make([]PushMeasures, len(projects)), index, data, now)
	named := developerNames(groups)
	times := make([]map[string][]time.Time, len(projects))
	for i := range times {
		times[i] = map[string][]time.Time{}
	}
	for _, c := range commitsOfPushes(index, data, tips) {
		if !isPerson(c.author) {
			continue
		}
		key := strings.ToLower(c.author)
		if name, grouped := named[key]; grouped {
			key = name
		}
		times[c.project][key] = append(times[c.project][key], c.at)
	}
	start := now.Add(-time.Duration(data.window()) * day)
	out := make([]Integration, len(projects))
	for i, p := range projects {
		out[i] = integrationFrom(p.Name, times[i], start, now)
	}
	return out
}

// integrationFrom is the Integration of a project from the commit times of each
// of its developers, over the window from start to now.
func integrationFrom(project string, developers map[string][]time.Time, start, now time.Time) Integration {
	out := Integration{Project: project, Active: len(developers),
		WorkingDays: workingDaysAfter(dateOf(start).AddDate(0, 0, -1), now)}
	var perDay, freshness, gaps []float64
	for _, commits := range developers {
		slices.SortFunc(commits, time.Time.Compare)
		perDay = append(perDay, float64(len(commits))/float64(max(out.WorkingDays, 1)))
		freshness = append(freshness, float64(workingDaysAfter(commits[len(commits)-1], now)))
		if workedDays(commits)*5 >= 4*out.WorkingDays {
			out.Regular++
		}
		if longest, ok := longestGap(commits); ok {
			gaps = append(gaps, float64(longest))
			out.GapLongest = max(out.GapLongest, longest)
		}
	}
	out.PerDay, out.Freshness, out.Gap = countSpreadOf(perDay), countSpreadOf(freshness), countSpreadOf(gaps)
	return out
}

// workedDays is the number of working days with a commit among commits.
func workedDays(commits []time.Time) int {
	days := map[time.Time]bool{}
	for _, c := range commits {
		if isWorkingDay(c) {
			days[dateOf(c)] = true
		}
	}
	return len(days)
}

// longestGap is the longest gap in working days between neighbours of the
// sorted commits; false for fewer than two commits.
func longestGap(commits []time.Time) (int, bool) {
	longest := 0
	for i := 1; i < len(commits); i++ {
		longest = max(longest, workingDaysAfter(commits[i-1], commits[i]))
	}
	return longest, len(commits) > 1
}

// dateOf is the UTC date of t, at midnight.
func dateOf(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

// isWorkingDay says whether t falls on a UTC Monday to Friday.
func isWorkingDay(t time.Time) bool {
	w := t.UTC().Weekday()
	return w != time.Saturday && w != time.Sunday
}

// workingDaysAfter counts the working days whose UTC date is after the date
// of from and not after the date of to.
func workingDaysAfter(from, to time.Time) int {
	count, last := 0, dateOf(to)
	for d := dateOf(from).AddDate(0, 0, 1); !d.After(last); d = d.AddDate(0, 0, 1) {
		count += boolCount(isWorkingDay(d))
	}
	return count
}
