package config

import (
	"errors"
	"slices"
	"testing"
)

// separatorsOf loads the file (and the valid projects) and returns the
// separators in force and the rejections, failing t on a load error.
func separatorsOf(t *testing.T, file string) (pair [2]string, rejected []Rejection, written map[string]bool) {
	t.Helper()
	got, err := parse([]byte(file + valid))
	if err != nil {
		t.Fatalf("file %q: want no error, got %v", file, err)
	}
	return [2]string{got.ThousandsSeparator, got.DecimalSeparator}, got.Rejected, got.written
}

// TestDecimalSeparatorAcceptsPointAndComma (forsgren#536): point and comma are
// accepted as written; a file without the key has the default, point.
func TestDecimalSeparatorAcceptsPointAndComma(t *testing.T) {
	for file, want := range map[string]string{"": "point", "decimal_separator:\n": "point",
		"decimal_separator: point\n": "point", "decimal_separator: comma\n": "comma"} {
		pair, rejected, _ := separatorsOf(t, file)
		if pair[1] != want || len(rejected) != 0 {
			t.Errorf("file %q: want %q and no rejection, got %q, %v", file, want, pair[1], rejected)
		}
	}
}

// TestDecimalSeparatorRefusesAnUnknownValue (forsgren#536): any other value is
// a Rejection naming the two values, the default stays in force.
func TestDecimalSeparatorRefusesAnUnknownValue(t *testing.T) {
	pair, rejected, _ := separatorsOf(t, "decimal_separator: period\n")
	if pair[1] != "point" {
		t.Fatalf("want the default in force, got %q", pair[1])
	}
	wantRejection(t, rejected, ErrDecimalSeparator,
		[4]string{"decimal_separator", "period", "use point or comma", "point"})
}

// conflict is a pair of separators that are the same mark, and the mark.
type conflict struct{ thousands, decimal, mark string }

// TestTheSameMarkForBothSeparatorsIsRefusedAndBothRevert (forsgren#536,
// decision #537 A): comma with comma and period with point are the same mark;
// both keys are rejected with a reason naming both written values and the
// resolved mark, and both defaults are in force.
func TestTheSameMarkForBothSeparatorsIsRefusedAndBothRevert(t *testing.T) {
	for _, c := range []conflict{{"comma", "comma", ","}, {"period", "point", "."}} {
		file := "thousands_separator: " + c.thousands + "\ndecimal_separator: " + c.decimal + "\n"
		pair, rejected, written := separatorsOf(t, file)
		if pair != [2]string{"narrow_space", "point"} || len(written) != 0 {
			t.Fatalf("%v: want both defaults and neither key written, got %q, %v", c, pair, written)
		}
		wantConflict(t, rejected, c)
	}
}

// wantConflict fails t unless rejected is one Rejection for each separator
// key, in order, with the reason of a conflict over c's mark and the key's
// default, each unwrapping to its key's sentinel.
func wantConflict(t *testing.T, rejected []Rejection, c conflict) {
	t.Helper()
	reason := "thousands_separator " + c.thousands + " and decimal_separator " + c.decimal + " are both the mark \"" +
		c.mark + "\"; use different marks; both separators revert to their defaults, narrow_space and point"
	want := [][4]string{{"thousands_separator", c.thousands, reason, "narrow_space"},
		{"decimal_separator", c.decimal, reason, "point"}}
	var got [][4]string
	for _, r := range rejected {
		got = append(got, [4]string{r.Key, r.Written, r.Reason, r.Default})
	}
	if !slices.Equal(got, want) {
		t.Fatalf("want rejections %q, got %q", want, got)
	}
	wantSentinels(t, rejected)
}

// wantSentinels fails t unless the two rejections unwrap to the sentinels of
// thousands_separator and decimal_separator.
func wantSentinels(t *testing.T, rejected []Rejection) {
	t.Helper()
	if !errors.Is(&rejected[0], ErrThousandsSeparator) || !errors.Is(&rejected[1], ErrDecimalSeparator) {
		t.Errorf("want the rejections to unwrap to their keys' sentinels, got %v", rejected)
	}
}

// TestAPeriodWithTheDefaultPointIsRefused (forsgren#536, decision #537 A): the
// resolved marks count, so period for the thousands with no decimal_separator
// written meets the default point; only the written key is rejected, its
// reason names the default, and both defaults are in force.
func TestAPeriodWithTheDefaultPointIsRefused(t *testing.T) {
	pair, rejected, _ := separatorsOf(t, "thousands_separator: period\n")
	if pair != [2]string{"narrow_space", "point"} {
		t.Fatalf("want both defaults, got %q", pair)
	}
	wantRejection(t, rejected, ErrThousandsSeparator, [4]string{"thousands_separator", "period",
		"thousands_separator period and decimal_separator point (the default) are both the mark \".\"; " +
			"use different marks; both separators revert to their defaults, narrow_space and point", "narrow_space"})
}

// TestOtherSeparatorPairsAreAccepted (forsgren#536): every pair that is not
// the same mark stands as written.
func TestOtherSeparatorPairsAreAccepted(t *testing.T) {
	for _, want := range [][2]string{{"period", "comma"}, {"comma", "point"}, {"none", "comma"}, {"none", "point"},
		{"narrow_space", "comma"}, {"narrow_space", "point"}} {
		pair, rejected, _ := separatorsOf(t, "thousands_separator: "+want[0]+"\ndecimal_separator: "+want[1]+"\n")
		if pair != want || len(rejected) != 0 {
			t.Errorf("%v: want it accepted as written, got %q, %v", want, pair, rejected)
		}
	}
}
