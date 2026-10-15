package config

// The page keys (forsgren#159, #200): issues_page, days_page,
// numbers_scoring_page and history_page, each true, unlisted or false.

import (
	"slices"

	"go.yaml.in/yaml/v3"
)

// PageMode is how an optional page is handled (forsgren#200): PageOn, the page
// is generated and in the menu; PageUnlisted, it is generated, has no menu entry
// and asks search engines to skip it; PageOff, it is not generated.
type PageMode string

// The three values of a page key, as the file writes them.
const (
	PageOn       PageMode = "true"
	PageUnlisted PageMode = "unlisted"
	PageOff      PageMode = "false"
)

// pageModeValues are the values a page key accepts, in the order the settings
// page lists them.
var pageModeValues = []PageMode{PageOn, PageUnlisted, PageOff}

// pageKey is the key of an optional page (forsgren#159, #200): its refusal and
// its default PageMode.
type pageKey struct {
	sentinel error
	key      string
	def      PageMode
}

// The page keys and their defaults (forsgren#200): the issues page is listed,
// the days page is not generated, and the numbers and scoring page and the
// history page are unlisted.
var (
	issuesPage         = pageKey{ErrIssuesPage, "issues_page", PageOn}
	daysPage           = pageKey{ErrDaysPage, "days_page", PageOff}
	numbersScoringPage = pageKey{ErrNumbersScoringPage, "numbers_scoring_page", PageUnlisted}
	historyPage        = pageKey{ErrHistoryPage, "history_page", PageUnlisted}
)

// pageKeys are the page keys, in the order of the settings page.
var pageKeys = []pageKey{issuesPage, daysPage, numbersScoringPage, historyPage}

// isPageKey says whether key is one of the page keys.
func isPageKey(key string) bool {
	return slices.ContainsFunc(pageKeys, func(k pageKey) bool { return k.key == key })
}

// mode is the key as written, its default when the file has none (a key
// without a value is none): only the literals true, unlisted and false, never
// a quoted or numeric value, nor yes; otherwise the default and the Rejection,
// which wraps the key's sentinel (forsgren#183, #200).
func (k pageKey) mode(n yaml.Node) (PageMode, *Rejection) {
	if !hasValue(n) {
		return k.def, nil
	}
	if mode, ok := readPageMode(n); ok {
		return mode, nil
	}
	return k.def, refusable{k.sentinel, k.key, string(k.def)}.reject(n, "use true, unlisted or false")
}

// readPageMode is the PageMode a node writes, when it writes one: a value of
// pageModeValues as a plain scalar, never a quoted one (forsgren#200).
func readPageMode(n yaml.Node) (PageMode, bool) {
	mode := PageMode(n.Value)
	quoted := n.Style&(yaml.DoubleQuotedStyle|yaml.SingleQuotedStyle) != 0
	return mode, !quoted && slices.Contains(pageModeValues, mode)
}

// pageModeNames are the PageModes as written in the file.
func pageModeNames() []string {
	out := make([]string, len(pageModeValues))
	for i, m := range pageModeValues {
		out[i] = string(m)
	}
	return out
}
