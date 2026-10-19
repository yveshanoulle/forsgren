package collect

// The collect report (forsgren#64, step 3): what a run left incomplete, for
// the job summary to say so. A successful run means collection operated
// correctly, not that all requested history was collected (decision #238).
// collect fills a Report while it runs, forsgren writes it to the
// --cut-report file, and run-summary reads it back, all through this shape:
//
//	# forsgren collect report v1
//	incomplete resets=2026-10-01T01:00:00Z
//	cut acme/app kept=2026-06-22 recent=discarded issues=unread progress=stalled
//	failed acme/web secondary-rate-limit
//
// The second line is `complete` or `incomplete resets=<UTC RFC 3339>`. A
// `cut` line names a repository cut short at the budget: `kept` is the UTC
// day its read mark moved to (`none` when it kept no day), `recent` says
// what became of the read of what is new (`read` whole, `kept` in part,
// `discarded`), `issues` is always `unread` (a cut repository stores nothing
// of its issues) and `progress` is `yes` when it kept something, `no` the
// first run it kept nothing, `stalled` when it kept nothing again.
// A `failed` line names a repository that failed on a rate limit.

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// What a cut repository's recent read became, and how it progressed.
const (
	RecentRead      = "read"
	RecentKept      = "kept"
	RecentDiscarded = "discarded"

	ProgressYes     = "yes"
	ProgressNo      = "no"
	ProgressStalled = "stalled"

	FailedPrimary   = "primary-rate-limit"
	FailedSecondary = "secondary-rate-limit"
	FailedOther     = "error"
)

// reportVersion is the report's first line.
const reportVersion = "# forsgren collect report v1"

// ErrReport: a file that is not a collect report.
var ErrReport = errors.New("not a collect report")

// Cut is one repository cut short at the request budget.
type Cut struct {
	Repository string
	// Kept is the start of the UTC day the read mark moved to; zero: none.
	Kept     time.Time
	Recent   string
	Progress string
}

// Failed is one repository that failed, and how: a Failed* word.
type Failed struct{ Repository, Kind string }

// Report is what a run left incomplete or failed.
type Report struct {
	Cuts   []Cut
	Failed []Failed
	// Reset is when the request budget starts over, UTC; zero when no
	// repository was cut short.
	Reset time.Time
}

// Render is the report's file text.
func (r Report) Render() string {
	var b strings.Builder
	b.WriteString(reportVersion + "\n")
	if len(r.Cuts) == 0 {
		b.WriteString("complete\n")
	} else {
		fmt.Fprintf(&b, "incomplete resets=%s\n", r.Reset.UTC().Format(time.RFC3339))
	}
	for _, c := range r.Cuts {
		kept := "none"
		if !c.Kept.IsZero() {
			kept = c.Kept.UTC().Format(time.DateOnly)
		}
		fmt.Fprintf(&b, "cut %s kept=%s recent=%s issues=unread progress=%s\n", c.Repository, kept, c.Recent, c.Progress)
	}
	for _, f := range r.Failed {
		fmt.Fprintf(&b, "failed %s %s\n", f.Repository, f.Kind)
	}
	return b.String()
}

// ParseReport is the report in text, the reverse of Render; anything else is
// ErrReport.
func ParseReport(text string) (Report, error) {
	lines := strings.Split(strings.TrimSuffix(text, "\n"), "\n")
	if len(lines) < 2 || lines[0] != reportVersion {
		return Report{}, fmt.Errorf("%w: it does not start with %q", ErrReport, reportVersion)
	}
	var r Report
	if err := r.parseStatus(lines[1]); err != nil {
		return Report{}, err
	}
	for _, line := range lines[2:] {
		if err := r.parseLine(line); err != nil {
			return Report{}, err
		}
	}
	return r, nil
}

// parseStatus reads the second line.
func (r *Report) parseStatus(line string) error {
	if line == "complete" {
		return nil
	}
	value, ok := strings.CutPrefix(line, "incomplete resets=")
	reset, err := time.Parse(time.RFC3339, value)
	if !ok || err != nil {
		return fmt.Errorf("%w: status line %q", ErrReport, line)
	}
	r.Reset = reset
	return nil
}

// parseLine reads a cut or failed line.
func (r *Report) parseLine(line string) error {
	f := strings.Fields(line)
	switch {
	case len(f) == 3 && f[0] == "failed":
		r.Failed = append(r.Failed, Failed{f[1], f[2]})
	case len(f) == 6 && f[0] == "cut":
		c, err := parseCut(f[1:])
		if err != nil {
			return fmt.Errorf("%w: %q: %w", ErrReport, line, err)
		}
		r.Cuts = append(r.Cuts, c)
	default:
		return fmt.Errorf("%w: line %q", ErrReport, line)
	}
	return nil
}

// parseCut reads the five fields after "cut".
func parseCut(f []string) (Cut, error) {
	c := Cut{Repository: f[0]}
	values := make([]string, 4)
	for i, key := range []string{"kept=", "recent=", "issues=", "progress="} {
		v, ok := strings.CutPrefix(f[i+1], key)
		if !ok {
			return c, fmt.Errorf("want %s", key)
		}
		values[i] = v
	}
	c.Recent, c.Progress = values[1], values[3]
	if values[0] != "none" {
		kept, err := time.Parse(time.DateOnly, values[0])
		if err != nil {
			return c, err
		}
		c.Kept = kept
	}
	return c, nil
}

// ReadReport reads the report file at path; a missing file is the error from
// os.ReadFile, for the caller to call unknown.
func ReadReport(path string) (Report, error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return Report{}, err
	}
	return ParseReport(string(data))
}
