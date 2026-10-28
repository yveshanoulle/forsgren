package metrics

import "testing"

// TestCountSpreadCellsShowTwoSignificantDigitsRoundedToTheNearest
// (forsgren#492, decision #493 A): under 10 one decimal always shown, from 10
// a whole number, half rounded up; a value that rounds to 10.0 reads 10.
func TestCountSpreadCellsShowTwoSignificantDigitsRoundedToTheNearest(t *testing.T) {
	for _, c := range []struct {
		in   float64
		want string
	}{
		{0, "0.0"}, {1, "1.0"}, {2.45, "2.5"}, {2.449, "2.4"}, {7, "7.0"},
		{9.94, "9.9"}, {9.95, "10"}, {9.99, "10"}, {10, "10"},
		{10.49, "10"}, {10.5, "11"}, {55, "55"}, {1234.5, "1\u202f235"},
	} {
		s := CountSpread{Count: 1, Mean: c.in}
		if got := s.MeanCell(); got != dec(c.want) {
			t.Errorf("%v: want %q, got %q", c.in, c.want, got)
		}
	}
}

// TestCountSpreadCells: a dash where the value is not shown, else the
// figure of countCell (forsgren#492).
func TestCountSpreadCells(t *testing.T) {
	for name, c := range map[string]struct {
		in   CountSpread
		want [3]string
	}{
		"none":  {CountSpread{}, [3]string{"-", "-", "-"}},
		"whole": {CountSpread{Count: 3, Mean: 2, Median: 2}, [3]string{"2.0", "2.0", "-"}},
		"half":  {CountSpread{Count: 2, Mean: 1.5, Median: 1.5}, [3]string{"1.5", "1.5", "-"}},
		"ten":   {CountSpread{Count: 10, Mean: 5.56, Median: 5.5, P90: 9}, [3]string{"5.6", "5.5", "9.0"}},
		"big":   {CountSpread{Count: 10, Mean: 55, Median: 10.5, P90: 99.4}, [3]string{"55", "11", "99"}},
	} {
		got := [3]string{c.in.MeanCell(), c.in.MedianCell(), c.in.P90Cell()}
		for i := range c.want {
			c.want[i] = dec(c.want[i])
		}
		if got != c.want {
			t.Errorf("%s: want %v, got %v", name, c.want, got)
		}
	}
}
