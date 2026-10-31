package config

import (
	"slices"
	"strconv"
	"strings"
	"testing"
)

// TestTbdFiguresIsRead (forsgren#423, Yves's ruling on #423): the optional
// top-level tbd_figures key, as written: median or all; median when the key is
// left out or has no value, and only a key with an accepted value counts as
// written.
func TestTbdFiguresIsRead(t *testing.T) {
	cases := []struct {
		name, file, want string
		written          bool
	}{
		{"absent", "", TbdFiguresMedian, false},
		{"no value", "tbd_figures:\n", TbdFiguresMedian, false},
		{"median", "tbd_figures: median\n", TbdFiguresMedian, true},
		{"all", "tbd_figures: all\n", TbdFiguresAll, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := parse([]byte(c.file + valid))
			if err != nil || len(got.Rejected) != 0 {
				t.Fatalf("want nothing rejected and no error, got %v, %v", got.Rejected, err)
			}
			wantFigures(t, got, c.want, c.written)
		})
	}
}

// wantFigures fails t unless got has the figures want in force and the key
// counted as written, or not, as written says.
func wantFigures(t *testing.T, got Config, want string, written bool) {
	t.Helper()
	if got.TbdFigures != want {
		t.Errorf("want the figures %q, got %q", want, got.TbdFigures)
	}
	if got.written["tbd_figures"] != written {
		t.Errorf("want the key written %v, got %v", written, got.written)
	}
}

// TestTbdFiguresDefaultIsMedian (forsgren#423): the default is the median
// alone, the constant the settings page lists.
func TestTbdFiguresDefaultIsMedian(t *testing.T) {
	if DefaultTbdFigures != "median" || TbdFiguresAll != "all" {
		t.Errorf("want the default median and the other value all, got %q and %q", DefaultTbdFigures, TbdFiguresAll)
	}
}

// TestRejectedTbdFiguresFallsBackToMedian (forsgren#423, #183): any other
// value, a quoted one and another case included, is not accepted: median is in
// force, the key is not written, and the rejection names the key, the value as
// written and the valid values.
func TestRejectedTbdFiguresFallsBackToMedian(t *testing.T) {
	for _, written := range []string{"All", "mean", "both", "1", "true", ""} {
		t.Run(written, func(t *testing.T) {
			got, err := parse([]byte("tbd_figures: " + strconv.Quote(written) + "\n" + valid))
			if err != nil {
				t.Fatal(err)
			}
			wantFigures(t, got, TbdFiguresMedian, false)
			wantRejection(t, got.Rejected, ErrTbdFigures,
				[4]string{"tbd_figures", written, "use median or all", TbdFiguresMedian})
		})
	}
}

// TestAcceptedTbdFigures (forsgren#423, #79): the values Accepted names, in
// the order of the settings page.
func TestAcceptedTbdFigures(t *testing.T) {
	if got := Accepted("tbd_figures"); !slices.Equal(got, []string{"median", "all"}) {
		t.Errorf("want median and all, got %v", got)
	}
}

// TestStarterShowsTbdFiguresCommentedOut (forsgren#423): the starter has the
// key as a comment, with its two values, and no line that sets it, so an
// installation without the key sees the median only.
func TestStarterShowsTbdFiguresCommentedOut(t *testing.T) {
	var commented bool
	for _, line := range starterLines() {
		commented = commented || strings.HasPrefix(line, "# tbd_figures: median")
		if strings.HasPrefix(line, "tbd_figures:") {
			t.Errorf("want the starter not to set tbd_figures, got %q", line)
		}
	}
	if !commented || !strings.Contains(Starter, "all") {
		t.Errorf("want a commented line `# tbd_figures: median` in the starter, got:\n%s", Starter)
	}
}

// TestStarterSaysAllShowsTheStandardDeviation (forsgren#588, step 2, decision
// #599 A): the starter's tbd_figures comment names the four figures of all,
// the standard deviation the fourth.
func TestStarterSaysAllShowsTheStandardDeviation(t *testing.T) {
	text := strings.Join(strings.Fields(strings.ReplaceAll(Starter, "\n#", "\n")), " ")
	const want = "change median to all to show the mean, the median, the 90th percentile and the " +
		"standard deviation of each measure instead"
	if !strings.Contains(text, want) {
		t.Errorf("want %q in the starter, got:\n%s", want, Starter)
	}
}
