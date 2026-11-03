package metrics

// The cells of the TBD page's Integration group (forsgren#622, step 2) that
// are not a spread's own: the share of the active developers who integrate on
// most working days, and the longest gap of any developer. The spreads' cells
// are CountSpread's.

// RegularCell is the share of the active developers with a commit on at least 4
// of every 5 working days, as the page's shares are written (shareOf); a dash
// without an active developer.
func (i Integration) RegularCell() string { return shareOf(i.Regular, i.Active) }

// GapLongestCell is the longest gap of any developer in working days, a whole
// number; a dash while no developer has two commits.
func (i Integration) GapLongestCell() string {
	if i.Gap.Count == 0 {
		return noNumber
	}
	return GroupDigits(i.GapLongest)
}
