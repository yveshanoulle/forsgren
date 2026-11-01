package main

import (
	"go/parser"
	"go/token"
	"strings"
	"testing"
)

// The local guard for CodeQL's go/incorrect-integer-conversion
// (forsgren#608): no integer conversion to a type narrower than 64 bits of a
// number parsed with 64 bits, unless the same function compares it with a
// math.Max bound that fits the type first. intconversion_check_test.go holds
// the checker and its limits.

// TestNoUnboundedConversionOfA64BitParse judges every non-test Go file of
// the module.
func TestNoUnboundedConversionOfA64BitParse(t *testing.T) {
	findings, files := checkModuleConversions(t, "../..", convChecker{bounds: true, wrappers: true})
	if files < 10 {
		t.Fatalf("judged %d Go files; the walk lost the module", files)
	}
	if len(findings) > 0 {
		t.Errorf("unbounded conversions of a 64-bit parse result:\n%s", strings.Join(findings, "\n"))
	}
}

// fixtureParseNumber is internal/history's parseNumber, the wrapper the
// fixtures convert the result of.
const fixtureParseNumber = `
func parseNumber(column, s string) (int64, error) {
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, err
	}
	return n, nil
}
`

// conversionFixtures are the shapes the guard refuses (want names the
// finding) and accepts (want empty).
var conversionFixtures = []struct {
	name, body, want string
}{
	{"before forsgren#608", `
func toProgressRow(f []string) (progressRow, error) {
	read, err := parseNumber("read", f[1])
	if err != nil {
		return progressRow{}, err
	}
	left, err := parseNumber("left", f[2])
	return progressRow{Read: int(read), Left: int(left)}, err
}`, "fixture.go:17: int(read) converts the 64-bit result of parseNumber"},
	{"parseCount without its bound", `
func parseCount(column, s string) (int, error) {
	n, err := parseNumber(column, s)
	if err != nil || n < 0 {
		return 0, err
	}
	return int(n), nil
}`, "fixture.go:16: int(n) converts the 64-bit result of parseNumber"},
	{"strconv straight", `
func width(s string) int32 {
	w, _ := strconv.ParseUint(s, 10, 64)
	return int32(w)
}`, "fixture.go:13: int32(w) converts the 64-bit result of strconv.ParseUint"},
	{"a field", `
func (p *push) read(s string) (err error) {
	p.Commits, err = parseNumber("commits", s)
	p.Shown = int(p.Commits)
	return err
}`, "fixture.go:13: int(p.Commits) converts the 64-bit result of parseNumber"},
	{"bound after the conversion", `
func late(s string) int {
	n, _ := parseNumber("n", s)
	c := int(n)
	if n > math.MaxInt32 {
		return 0
	}
	return c
}`, "fixture.go:13: int(n) converts"},
	{"bound too wide for int", `
func wide(s string) int {
	n, _ := parseNumber("n", s)
	if n > math.MaxInt {
		return 0
	}
	return int(n)
}`, "with no bound of math.MaxInt32 or less compared before it"},
	{"parseCount", `
func parseCount(column, s string) (int, error) {
	n, err := parseNumber(column, s)
	if err != nil || n < 0 {
		return 0, err
	}
	if n > math.MaxInt32 {
		return 0, err
	}
	return int(n), nil
}`, ""},
	{"a 32-bit parse", `
func small(s string) int32 {
	n, _ := strconv.ParseInt(s, 10, 32)
	return int32(n)
}`, ""},
	{"kept as int64", `
func kept(s string) time.Time {
	n, _ := parseNumber("n", s)
	return time.Unix(n, 0)
}`, ""},
}

// checkFixture is what checker finds in a fixture: its body after
// fixtureParseNumber, in one file.
func checkFixture(t *testing.T, checker convChecker, body string) []string {
	t.Helper()
	src := "package fixture\n" + fixtureParseNumber + body + "\n"
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "fixture.go", src, 0)
	if err != nil {
		t.Fatalf("fixture does not parse: %v", err)
	}
	return checker.check(fset, []fileAt{{file, "fixture.go"}})
}

// TestConversionGuardJudgesTheShapes refuses each unbounded shape naming
// file, line and reason, and accepts the bounded ones.
func TestConversionGuardJudgesTheShapes(t *testing.T) {
	for _, fx := range conversionFixtures {
		got := strings.Join(checkFixture(t, convChecker{bounds: true, wrappers: true}, fx.body), "\n")
		if (fx.want == "") != (got == "") || !strings.Contains(got, fx.want) {
			t.Errorf("%s: findings %q, want %q", fx.name, got, fx.want)
		}
	}
}

// TestConversionGuardWithoutTheBoundRuleRefusesParseCount is the mutation
// proof of the bound rule: a checker that never sees a bound refuses the
// real parseCount, for the reason that it has none.
func TestConversionGuardWithoutTheBoundRuleRefusesParseCount(t *testing.T) {
	findings, _ := checkModuleConversions(t, "../../internal/history", convChecker{wrappers: true})
	got := strings.Join(findings, "\n")
	want := "internal/history/file.go"
	reason := "int(n) converts the 64-bit result of parseNumber (strconv.ParseInt) " +
		"with no bound of math.MaxInt32 or less compared before it"
	if !strings.Contains(got, want) || !strings.Contains(got, reason) {
		t.Errorf("without the bound rule: findings %q, want %s refused: %s", got, want, reason)
	}
}

// TestConversionGuardWithoutWrappersMissesTheFixture is the mutation proof
// of the wrapper tracking: without it the shape before forsgren#608, which
// converts parseNumber's result, passes.
func TestConversionGuardWithoutWrappersMissesTheFixture(t *testing.T) {
	body := conversionFixtures[0].body
	if got := checkFixture(t, convChecker{bounds: true}, body); len(got) > 0 {
		t.Errorf("without wrapper tracking: findings %q, want none", got)
	}
	if got := checkFixture(t, convChecker{bounds: true, wrappers: true}, body); len(got) != 2 {
		t.Errorf("with wrapper tracking: findings %q, want read and left", got)
	}
}
