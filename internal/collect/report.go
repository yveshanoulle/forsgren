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
//	pulls-cut acme/shop
//	backfill-cut acme/lib
//	pushes-cut acme/api
//	pull-commits-fill-cut acme/lib
//	push-commits-fill-cut acme/lib
//	pulls-bot-fill-cut acme/lib
//	pushes-fill-cut acme/lib
//	commit-files-cut acme/lib
//	commit-files-capped acme/lib read=4120 left=2340
//	failed acme/web secondary-rate-limit
//
// The second line is `complete` or `incomplete resets=<UTC RFC 3339>`. A
// `cut` line names a repository cut short at the budget: `kept` is the UTC
// day its read mark moved to (`none` when it kept no day), `recent` says
// what became of the read of what is new (`read` whole, `kept` in part,
// `discarded`), `issues` is always `unread` (a cut repository stores nothing
// of its issues) and `progress` is `yes` when it kept something, `no` the
// first run it kept nothing, `stalled` when it kept nothing again.
// A `pulls-cut` line names a repository whose deployments and issues were
// read whole but whose pull requests the budget cut short: incomplete, never
// failed, the rest read by the next run (forsgren#320, decision #307).
// A `backfill-cut` line names a repository whose deployments, issues and pull
// requests were read whole but whose backfill of the legacy commits the budget
// cut short: incomplete, never failed, continued by the next run (forsgren#385).
// A `pushes-cut` line names a repository whose deployments, issues and pull
// requests were read whole but whose pushes to the default branch the budget
// cut short: incomplete, never failed, read again by the next run (forsgren#397).
// A `pull-commits-fill-cut` and a `push-commits-fill-cut` line name a
// repository whose one-time fill of the stored pull requests' commits, or of
// the stored merge pushes' lines, the budget cut short: incomplete, never
// failed, continued by the next run (forsgren#470).
// A `pulls-bot-fill-cut` line names a repository whose one-time fill of the
// bot status of the stored pull requests the budget cut short: the same
// (forsgren#500).
// A `pushes-fill-cut` line names a repository whose fill of the older pushes
// below a page-cap cut the budget cut short: the same (forsgren#583).
// A `commit-files-cut` line names a repository whose read of the changed
// files of its deployed commits the budget cut short: incomplete, never
// failed, continued by the next run (forsgren#496).
// A `commit-files-capped` line names a repository whose read of the changed
// files stopped at the cap of 1000 commits a run (forsgren#589): planned, so
// it leaves the report complete, never failed, continued by the next run;
// `read` is the commits of the repository read so far, this run's included,
// and `left` those still without lines (forsgren#593). A report written
// before that has the repository alone, read with both counts 0.
// A `failed` line names a repository that failed on a rate limit.

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
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

// The reasons a failure issue's `service:` label found no row.
const (
	ServiceUnknown   = "unknown"
	ServiceAmbiguous = "ambiguous"
)

// UnmatchedService is a failure issue whose `service:` label found no single
// row of its repository: Reason is ServiceUnknown or ServiceAmbiguous.
type UnmatchedService struct {
	Repository string
	Issue      int64
	Reason     string
	Label      string
}

// CappedFiles is a repository whose read of the commit files stopped at the
// cap of a run (forsgren#589), with the commits read so far and those left
// (forsgren#593); both 0 for a report written before the counts.
type CappedFiles struct {
	Repository string
	Read, Left int
}

// Counted says whether c carries the counts: a capped read has read at least
// the cap, so only a report from before forsgren#593 has Read 0.
func (c CappedFiles) Counted() bool { return c.Read > 0 }

// Report is what a run left incomplete or failed.
type Report struct {
	Cuts []Cut
	// PullsCut names the repositories whose pull requests alone were cut
	// short at the request budget (forsgren#320, decision #307).
	PullsCut []string
	// BackfillCut names the repositories whose backfill of the legacy commits
	// was cut short at the request budget (forsgren#385).
	BackfillCut []string
	// PushesCut names the repositories whose pushes alone were cut short at
	// the request budget (forsgren#397).
	PushesCut []string
	// PullFillCut and PushFillCut name the repositories whose one-time fill
	// of the stored pull requests' commits, or of the merge pushes' lines,
	// was cut short at the request budget (forsgren#470, step 3).
	PullFillCut, PushFillCut []string
	// PullBotFillCut names the repositories whose one-time fill of the bot
	// status of the stored pull requests was cut short at the request
	// budget (forsgren#500).
	PullBotFillCut []string
	// PushesFillCut names the repositories whose fill of the older pushes
	// below a page-cap cut was cut short at the request budget (forsgren#583).
	PushesFillCut []string
	// FilesCut names the repositories whose read of the files of their
	// deployed commits was cut short at the request budget (forsgren#496).
	FilesCut []string
	// FilesCapped names the repositories whose read of the commit files
	// stopped at the cap of a run (forsgren#589), with how far each read is
	// (forsgren#593). Not incomplete, not failed.
	FilesCapped []CappedFiles
	// ServiceUnmatched names the failure issues whose `service:` label
	// matched no row of their repository, or more than one: counted in the
	// total only (forsgren#515, decision #517). Not incomplete, not failed.
	ServiceUnmatched []UnmatchedService
	Failed           []Failed
	// Reset is when the request budget starts over, UTC; zero when no
	// repository, nor its pull requests, was cut short.
	Reset time.Time
}

// Render is the report's file text.
func (r Report) Render() string {
	var b strings.Builder
	b.WriteString(reportVersion + "\n")
	if !r.incomplete() {
		b.WriteString("complete\n")
	} else {
		fmt.Fprintf(&b, "incomplete resets=%s\n", r.Reset.UTC().Format(time.RFC3339))
	}
	for _, c := range r.Cuts {
		b.WriteString(c.line())
	}
	writeRepositories(&b, "pulls-cut", r.PullsCut)
	writeRepositories(&b, "backfill-cut", r.BackfillCut)
	writeRepositories(&b, "pushes-cut", r.PushesCut)
	writeRepositories(&b, "pull-commits-fill-cut", r.PullFillCut)
	writeRepositories(&b, "push-commits-fill-cut", r.PushFillCut)
	writeRepositories(&b, "pulls-bot-fill-cut", r.PullBotFillCut)
	writeRepositories(&b, "pushes-fill-cut", r.PushesFillCut)
	writeRepositories(&b, "commit-files-cut", r.FilesCut)
	for _, c := range r.FilesCapped {
		fmt.Fprintf(&b, "commit-files-capped %s read=%d left=%d\n", c.Repository, c.Read, c.Left)
	}
	for _, u := range r.ServiceUnmatched {
		fmt.Fprintf(&b, "failure-service %s %d %s %s\n", u.Repository, u.Issue, u.Reason, url.QueryEscape(u.Label))
	}
	for _, f := range r.Failed {
		fmt.Fprintf(&b, "failed %s %s\n", f.Repository, f.Kind)
	}
	return b.String()
}

// writeRepositories writes one line of kind for each of repos.
func writeRepositories(b *strings.Builder, kind string, repos []string) {
	for _, repo := range repos {
		fmt.Fprintf(b, "%s %s\n", kind, repo)
	}
}

// line is the cut line of c.
func (c Cut) line() string {
	kept := "none"
	if !c.Kept.IsZero() {
		kept = c.Kept.UTC().Format(time.DateOnly)
	}
	return fmt.Sprintf("cut %s kept=%s recent=%s issues=unread progress=%s\n", c.Repository, kept, c.Recent, c.Progress)
}

// incomplete says whether the budget cut a repository, its pull requests or
// its backfill of the legacy commits or its pushes short.
func (r Report) incomplete() bool {
	for _, repos := range [][]string{
		r.PullsCut, r.BackfillCut, r.PushesCut, r.PullFillCut, r.PushFillCut, r.PullBotFillCut, r.PushesFillCut,
		r.FilesCut,
	} {
		if len(repos) > 0 {
			return true
		}
	}
	return len(r.Cuts) > 0
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

// lineKind is one kind of line after the status: how many fields it has,
// its first word included, and how the fields after that word are read.
type lineKind struct {
	fields int
	read   func(r *Report, f []string) error
}

// oldFields is, for a line that grew, how many fields it had before, still
// read: a commit-files-capped line without its counts (forsgren#593).
var oldFields = map[string]int{"commit-files-capped": 2}

// lineKinds are the lines a report holds after its status, by first word.
var lineKinds = map[string]lineKind{
	"cut": {6, func(r *Report, f []string) error {
		c, err := parseCut(f)
		r.Cuts = append(r.Cuts, c)
		return err
	}},
	"pulls-cut": {2, func(r *Report, f []string) error {
		r.PullsCut = append(r.PullsCut, f[0])
		return nil
	}},
	"backfill-cut": {2, func(r *Report, f []string) error {
		r.BackfillCut = append(r.BackfillCut, f[0])
		return nil
	}},
	"pushes-cut": {2, func(r *Report, f []string) error {
		r.PushesCut = append(r.PushesCut, f[0])
		return nil
	}},
	"pull-commits-fill-cut": {2, func(r *Report, f []string) error {
		r.PullFillCut = append(r.PullFillCut, f[0])
		return nil
	}},
	"push-commits-fill-cut": {2, func(r *Report, f []string) error {
		r.PushFillCut = append(r.PushFillCut, f[0])
		return nil
	}},
	"pulls-bot-fill-cut": {2, func(r *Report, f []string) error {
		r.PullBotFillCut = append(r.PullBotFillCut, f[0])
		return nil
	}},
	"pushes-fill-cut": {2, func(r *Report, f []string) error {
		r.PushesFillCut = append(r.PushesFillCut, f[0])
		return nil
	}},
	"commit-files-cut": {2, func(r *Report, f []string) error {
		r.FilesCut = append(r.FilesCut, f[0])
		return nil
	}},
	"commit-files-capped": {4, func(r *Report, f []string) error {
		c, err := parseCapped(f)
		r.FilesCapped = append(r.FilesCapped, c)
		return err
	}},
	"failure-service": {5, func(r *Report, f []string) error {
		issue, err := strconv.ParseInt(f[1], 10, 64)
		if err != nil {
			return err
		}
		label, err := url.QueryUnescape(f[3])
		r.ServiceUnmatched = append(r.ServiceUnmatched, UnmatchedService{f[0], issue, f[2], label})
		return err
	}},
	"failed": {3, func(r *Report, f []string) error {
		r.Failed = append(r.Failed, Failed{f[0], f[1]})
		return nil
	}},
}

// parseLine reads a line of one of the lineKinds.
func (r *Report) parseLine(line string) error {
	f := strings.Fields(line)
	if len(f) == 0 {
		return fmt.Errorf("%w: line %q", ErrReport, line)
	}
	kind, ok := lineKinds[f[0]]
	if !ok || (len(f) != kind.fields && len(f) != oldFields[f[0]]) {
		return fmt.Errorf("%w: line %q", ErrReport, line)
	}
	if err := kind.read(r, f[1:]); err != nil {
		return fmt.Errorf("%w: %q: %w", ErrReport, line, err)
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

// parseCapped reads the fields after "commit-files-capped": the repository,
// then read= and left=, or the repository alone (forsgren#593).
func parseCapped(f []string) (CappedFiles, error) {
	c := CappedFiles{Repository: f[0]}
	if len(f) == 1 {
		return c, nil
	}
	var err error
	if c.Read, err = countOf(f[1], "read="); err != nil {
		return c, err
	}
	c.Left, err = countOf(f[2], "left=")
	return c, err
}

// countOf is the count after key in field, a whole number from 0.
func countOf(field, key string) (int, error) {
	v, ok := strings.CutPrefix(field, key)
	if !ok {
		return 0, fmt.Errorf("want %s", key)
	}
	n, err := strconv.ParseUint(v, 10, 31)
	return int(n), err
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
