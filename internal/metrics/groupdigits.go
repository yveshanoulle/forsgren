package metrics

import "strconv"

// ThousandsSpace is the separator GroupDigits writes between the groups of
// three digits: U+202F NARROW NO-BREAK SPACE, which never breaks a line
// (forsgren#528, decision #529 B). The page renderer swaps it for the comma
// or for nothing when the config's thousands_separator says so.
const ThousandsSpace = " "

// GroupDigits is the count n written with a narrow no-break space between
// each group of three digits, "1 282": the one writer of every count the pages
// show. A minus sign stays in front of the digits. Only whole counts pass
// through it; a decimal keeps its point and its digits as they are.
func GroupDigits(n int) string {
	digits := strconv.Itoa(n)
	sign := ""
	if n < 0 {
		sign, digits = "-", digits[1:]
	}
	for i := len(digits) - 3; i > 0; i -= 3 {
		digits = digits[:i] + ThousandsSpace + digits[i:]
	}
	return sign + digits
}
