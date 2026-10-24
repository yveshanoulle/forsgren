package config

// The same_developer key (forsgren#361, decision #360): groups of GitHub
// logins that count as one developer.

import (
	"fmt"
	"strings"

	"go.yaml.in/yaml/v3"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// sameDeveloperKey is same_developer as a Rejection names it: no groups in
// force, written as an empty list.
var sameDeveloperKey = refusable{ErrSameDeveloper, "same_developer", "[]"}

// sameDeveloperShape is the reason for a value that is not a list of lists.
const sameDeveloperShape = "use a list of lists of GitHub logins, such as [[maintainer, assistant-account]]"

// claimed is where a login, compared without case, was first listed.
type claimed map[string]int

// checkSameDeveloper is the groups as written, none when the file has none (a
// key without a value is none), or none and the Rejection naming the first
// mistake: all or nothing, so a half-applied list never changes a count
// (forsgren#361). A login in two groups, an empty group, a group of one and a
// login that is not the shape of a GitHub login are refused.
func checkSameDeveloper(n yaml.Node) ([][]string, *Rejection) {
	if !hasValue(n) {
		return nil, nil
	}
	if n.Kind != yaml.SequenceNode {
		return nil, sameDeveloperKey.reject(n, sameDeveloperShape)
	}
	seen := claimed{}
	groups := make([][]string, 0, len(n.Content))
	for i, group := range n.Content {
		logins, reason := checkGroup(i+1, group, seen)
		if reason != "" {
			return nil, sameDeveloperKey.reject(n, reason)
		}
		groups = append(groups, logins)
	}
	return groups, nil
}

// checkGroup is the logins of the group at 1-based position number, or why
// not; seen holds the logins of the groups before it and gains this one's.
func checkGroup(number int, group *yaml.Node, seen claimed) ([]string, string) {
	if group.Kind != yaml.SequenceNode {
		return nil, sameDeveloperShape
	}
	if len(group.Content) < 2 {
		return nil, tooFew(number, group.Content)
	}
	logins := make([]string, 0, len(group.Content))
	for _, login := range group.Content {
		if reason := claim(seen, number, login); reason != "" {
			return nil, reason
		}
		logins = append(logins, login.Value)
	}
	return logins, ""
}

// tooFew is why a group of fewer than two logins is refused.
func tooFew(number int, logins []*yaml.Node) string {
	if len(logins) == 0 {
		return fmt.Sprintf("group %d is empty; list two or more logins", number)
	}
	return fmt.Sprintf("group %d has one login, %q; list two or more logins", number, logins[0].Value)
}

// claim records that the group at number lists the login, or says why it
// cannot: not a login, or already listed (case is ignored).
func claim(seen claimed, number int, login *yaml.Node) string {
	if login.Kind != yaml.ScalarNode || !history.IsLogin(login.Value) {
		return fmt.Sprintf("%q in group %d is not a GitHub login", writtenOf(*login), number)
	}
	key := strings.ToLower(login.Value)
	first, listed := seen[key]
	if !listed {
		seen[key] = number
		return ""
	}
	if first == number {
		return fmt.Sprintf("login %q is listed twice in group %d (case is ignored)", login.Value, number)
	}
	return fmt.Sprintf("login %q is in group %d and in group %d (case is ignored)", login.Value, number, first)
}

// flowGroups is the groups in YAML's flow form, as the settings page shows
// them: [[maintainer, assistant-account]], [] for none.
func flowGroups(groups [][]string) string {
	parts := make([]string, len(groups))
	for i, g := range groups {
		parts[i] = "[" + strings.Join(g, ", ") + "]"
	}
	return "[" + strings.Join(parts, ", ") + "]"
}
