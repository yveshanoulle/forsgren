package history

import (
	"slices"
	"strings"
	"time"
)

// Exclusion takes stored deployments back from every metric (forsgren#667):
// those of Repository (compared ignoring case) whose task is Task and, unless
// Before is zero, that were created before Before. The files keep them:
// deployments.csv only grows, so, as failures_withdrawn.csv does for failure
// issues, an exclusion leaves them out when they are counted.
type Exclusion struct {
	Repository string // owner/name
	Task       string
	Before     time.Time
}

// excludes says whether e takes r back.
func (e Exclusion) excludes(r Record) bool {
	return e.names(r) && (e.Before.IsZero() || r.CreatedAt.Before(e.Before))
}

// names says whether r is of e's repository and task, whatever its time.
func (e Exclusion) names(r Record) bool {
	return strings.EqualFold(r.Repository, e.Repository) && r.Task == e.Task
}

// Unmatched are the exclusions whose task no record of their repository has,
// at any time, in the order of exclusions: a typo, or a task of another
// repository, which take nothing back (forsgren#667).
func Unmatched(records []Record, exclusions []Exclusion) []Exclusion {
	return slices.DeleteFunc(slices.Clone(exclusions), func(e Exclusion) bool {
		return slices.ContainsFunc(records, e.names)
	})
}

// excluded says whether any of exclusions takes r back.
func excluded(r Record, exclusions []Exclusion) bool {
	return slices.ContainsFunc(exclusions, func(e Exclusion) bool { return e.excludes(r) })
}

// WithoutExcluded is records less the deployments that exclusions take back,
// in the order of records, and commits less those of the deployments taken
// back, in the order of commits (forsgren#667). A commit whose deployment is
// not in records stays.
func WithoutExcluded(records []Record, commits []Commit, exclusions []Exclusion) ([]Record, []Commit) {
	out := map[key]bool{}
	kept := slices.DeleteFunc(slices.Clone(records), func(r Record) bool {
		if !excluded(r, exclusions) {
			return false
		}
		out[r.key()] = true
		return true
	})
	return kept, slices.DeleteFunc(slices.Clone(commits), func(c Commit) bool { return out[c.key().deployment] })
}
