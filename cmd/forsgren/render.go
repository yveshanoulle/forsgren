package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/collect"
	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/metrics"
	"github.com/yveshanoulle/forsgren/internal/page"
)

// dataWithoutConfig is the usage error of --data alone: the history is
// grouped by the config's projects, so it has nothing to report on without.
const dataWithoutConfig = "render: --data <path> needs --config <path>, which lists the projects"

// calculatedLayout is how the page shows the render time: UTC, to the minute
// (forsgren#28). Format cuts the seconds off, so the minute shown never lies
// ahead of the moment the numbers were counted back from.
const calculatedLayout = "2006-01-02 15:04"

// sourceDateEpoch is the environment variable that pins renderTime.
const sourceDateEpoch = "SOURCE_DATE_EPOCH"

// renderOptions are render's flags: the required --out, the optional
// --config, --data and --latest (empty when absent).
type renderOptions struct {
	out, config, data, latest string
	needsCheck, prCheck       string
	waitingPR                 int
}

// render writes the site. With --config it also reads the installation's
// forsgren.config.yml, so the page can say when no projects are configured
// yet (forsgren#12); with --data as well it reads the history and the
// commits, failures and issues files next to it, and shows each project's
// deployment frequency, lead time for changes, failed deployment recovery
// time, change fail rate and deployment rework rate, counted back from now,
// and the rows of the days and issues pages (forsgren#76, #89, #123).
// Without --config (the repository's own build has no installation config)
// the page is the placeholder, with the render time in its footer.
func render(args []string, stdout, stderr io.Writer) int {
	o, ok := renderFlags(args, stderr)
	if !ok {
		return 2
	}
	at, err := renderTime()
	if err != nil {
		return failed(stderr, "render", err)
	}
	data, err := pageData(o, at, stderr)
	if err != nil {
		return failed(stderr, "render", err)
	}
	n, err := page.WriteSite(o.out, data)
	if err != nil {
		return failed(stderr, "render", err)
	}
	_, _ = fmt.Fprintf(stdout, "rendered %d page(s) into %s\n", n, o.out)
	return 0
}

// renderTime is the moment the page says it was calculated at: the clock,
// or, when SOURCE_DATE_EPOCH (the reproducible-builds variable, Unix
// seconds, 0 or more; a negative value is refused) is set, that second, so Scripts/build_site.sh and its fixture
// render the same page twice and compare it with the golden file without
// stripping the time (forsgren#41, step 3).
func renderTime() (time.Time, error) {
	epoch := os.Getenv(sourceDateEpoch)
	if epoch == "" {
		return now(), nil
	}
	seconds, err := strconv.ParseInt(epoch, 10, 64)
	if err != nil || seconds < 0 {
		return time.Time{}, fmt.Errorf("%s must be Unix seconds, 0 or more, got %q", sourceDateEpoch, epoch)
	}
	return time.Unix(seconds, 0), nil
}

// pageData is what the page shows for the options at the render time at; a
// setting of the config that is not accepted is warned about on stderr.
func pageData(o renderOptions, at time.Time, stderr io.Writer) (page.Data, error) {
	data := page.Placeholder(runningVersion())
	data.DevCommit = devCommit(buildInfo())
	data.AsOf = at.UTC().Format(calculatedLayout)
	data.Latest, data.WaitingPR = o.latest, o.waitingPR
	data.NeedsCheck, data.PRListCut = o.needsCheck, o.prCheck == statusTruncated
	data.Settings = settingsOf(config.Config{})
	if o.config == "" {
		return data, nil
	}
	cfg, err := loadConfig(o.config, stderr)
	if err != nil {
		return data, err
	}
	data.NoProjects = len(cfg.Projects) == 0
	data.View = cfg.View
	data.WorkingHours, data.WorkingHoursSet = cfg.WorkingHours, cfg.WorkingHoursSet
	data.DoraDays, data.DoraDaysSet = cfg.DoraDays, cfg.DoraDaysSet
	data.Settings = settingsOf(cfg)
	data.TbdFigures = cfg.TbdFigures
	data.ThousandsSeparator = cfg.ThousandsSeparator
	data.HideTbdTimeToMain, data.HideTbdPRLeadTime = cfg.HideTbdTimeToMain, cfg.HideTbdPRLeadTime
	data.HideTbdBotPRLeadTime, data.HideSubRows = cfg.HideTbdBotPRLeadTime, cfg.HideSubRows
	data.HistoryDays = cfg.HistoryDays
	data.Hidden, data.Unlisted = pagesInMode(cfg, config.PageOff), pagesInMode(cfg, config.PageUnlisted)
	if o.data == "" {
		return data, nil
	}
	return withHistory(data, cfg, o.data, at)
}

// pagesInMode are the pages whose key the config sets to mode, by page name:
// with PageOff the pages the site leaves out, with PageUnlisted the pages it
// writes without a menu entry (forsgren#159, #55, #68, #199, #200).
func pagesInMode(cfg config.Config, mode config.PageMode) map[string]bool {
	pages := map[string]bool{}
	for name, m := range pageModes(cfg) {
		pages[name] = m == mode
	}
	return pages
}

// pageModes is the PageMode of each optional page, by page name: the one place
// a page is tied to its key.
func pageModes(cfg config.Config) map[string]config.PageMode {
	return map[string]config.PageMode{page.IssuesPage: cfg.IssuesPage, page.DaysPage: cfg.DaysPage,
		page.NumbersScoringPage: cfg.NumbersScoringPage, page.HistoryPage: cfg.HistoryPage,
		page.TbdPage: cfg.TbdPage, page.WeekPage: weekMode(cfg)}
}

// weekMode is how the Week page is handled (forsgren#531, step 3, decision
// #533 A): listed, or with week_page: false unlisted, which is written, reachable
// by its address, out of the menu and asking search engines to skip it.
func weekMode(cfg config.Config) config.PageMode {
	if cfg.HideWeekPage {
		return config.PageUnlisted
	}
	return config.PageOn
}

// issueDays is how many UTC days the days page shows, ending yesterday
// (forsgren#76, forsgren#123, forsgren#128).
const issueDays = 30

// withHistory is data with what the history at path shows: the table's rows
// and the rows of the days and issues pages (forsgren#89, forsgren#123),
// from the issues file next to the history (data/issues.csv beside
// data/deployments.csv), at the render time at.
func withHistory(data page.Data, cfg config.Config, path string, at time.Time) (page.Data, error) {
	metricsData, err := metricsDataOf(cfg, path)
	if err != nil {
		return data, err
	}
	data.Rows = page.Table(metrics.Rows(cfg.Projects, metricsData, at))
	data.History = metrics.History(cfg.Projects, metricsData, at, cfg.HistoryDays)
	data.FirstDeployment, _ = metrics.FirstDeployment(cfg.Projects, metricsData)
	data.PullsUncollected = absent(beside(path, collect.PullsFile))
	data.TbdMetrics = metrics.TbdRows(cfg.Projects, metricsData, at, cfg.SameDeveloper)
	data.Week = metrics.WeekOf(cfg.Projects, metricsData, at)
	events, err := issueEventsOf(path)
	if err != nil {
		return data, err
	}
	data.IssueDays = metrics.IssueDays(events, at, issueDays)
	data.IssueRows = metrics.IssueRows(events, at)
	return withBugsCut(data, path)
}

// withBugsCut is data with BugsIncomplete set on every issue row when the bugs
// cut file beside the history at path (data/issue_bugs_cut.csv) names a
// repository whose bug read stopped at its page cap (forsgren#140). A missing
// file names none; any other refusal fails the render, naming the file.
func withBugsCut(data page.Data, path string) (page.Data, error) {
	cut, err := history.LoadBugsCut(beside(path, collect.BugsCutFile))
	if err != nil || len(cut) == 0 {
		return data, err
	}
	for i := range data.IssueDays {
		data.IssueDays[i].BugsIncomplete = true
	}
	for i := range data.IssueRows {
		data.IssueRows[i].BugsIncomplete = true
	}
	return data, nil
}

// issueEventsOf is the issue events beside the history at path, each marked as
// a bug when the bug flags file beside it (data/issue_bugs.csv) says its issue
// is one (forsgren#126). A missing bug flags file marks none.
func issueEventsOf(path string) ([]history.IssueEvent, error) {
	events, err := loadOrNone(beside(path, collect.IssuesFile), history.LoadIssueEvents)
	if err != nil {
		return nil, err
	}
	bugs, err := loadOrNone(beside(path, collect.IssueBugsFile), history.LoadIssueBugs)
	if err != nil {
		return nil, err
	}
	return markBugs(events, bugs), nil
}

// markBugs is events with Bug set on those of an issue that bugs says is a bug.
func markBugs(events []history.IssueEvent, bugs []history.IssueBug) []history.IssueEvent {
	isBug := make(map[history.IssueKey]bool, len(bugs))
	for _, b := range bugs {
		isBug[b.Key()] = b.Bug
	}
	marked := make([]history.IssueEvent, len(events))
	for i, e := range events {
		e.Bug = isBug[e.IssueKey()]
		marked[i] = e
	}
	return marked
}

// metricsDataOf is what the table's rows and the history page are counted
// from (forsgren#38): the history at path (deployment frequency and,
// forsgren#17, recovery time), the commits file next to it
// (data/commits.csv beside data/deployments.csv, lead time, forsgren#16), the
// failure issues that count (failuresOf; with the history change fail rate,
// forsgren#18, and rework rate, forsgren#39) and the reach beside it
// (data/reach.csv, how far back each repository was read; none when missing,
// then nothing is read for the history page, forsgren#68) and the pull
// request files beside it (withPulls).
func metricsDataOf(cfg config.Config, path string) (metrics.Data, error) {
	records, err := loadOrNone(path, history.Load)
	if err != nil {
		return metrics.Data{}, err
	}
	commits, err := loadOrNone(beside(path, collect.CommitsFile), history.LoadCommits)
	if err != nil {
		return metrics.Data{}, err
	}
	failures, err := failuresOf(path)
	if err != nil {
		return metrics.Data{}, err
	}
	reach, err := loadReach(beside(path, collect.ReachFile))
	if err != nil {
		return metrics.Data{}, err
	}
	data, err := withPulls(metrics.Data{Records: records, Commits: commits, Failures: failures,
		WorkingHours: cfg.WorkingHours, DoraDays: cfg.DoraDays, Reach: reach}, path)
	if err != nil {
		return metrics.Data{}, err
	}
	return withCommitFiles(data, path)
}

// withPulls is data with what PR Lead Time reads beside the history at
// path: the merged pull requests (data/pulls.csv, forsgren#256; none when
// missing, which the TBD page says, see absent) and the repositories whose
// pull request read GitHub refused (data/pulls_denied.csv, forsgren#337; none
// when missing) and the commits of the merged pull requests
// (data/pull_commits.csv, forsgren#463; none when missing) and the
// repositories whose fill of them is done (data/pull_commits_filled.csv,
// forsgren#470; none when missing). An unknown or malformed file of any
// fails the render.
func withPulls(data metrics.Data, path string) (metrics.Data, error) {
	pulls, err := loadOrNone(beside(path, collect.PullsFile), history.LoadPullRequests)
	if err != nil {
		return metrics.Data{}, err
	}
	denied, err := history.LoadPullsDenied(beside(path, collect.PullsDeniedFile))
	if err != nil {
		return metrics.Data{}, err
	}
	commits, err := loadOrNone(beside(path, collect.PullCommitsFile), history.LoadPullCommits)
	if err != nil {
		return metrics.Data{}, err
	}
	filled, err := history.LoadPullCommitsFilled(beside(path, collect.PullCommitsFilledFile))
	if err != nil {
		return metrics.Data{}, err
	}
	data.Pulls, data.PullsDenied, data.PullCommits, data.PullsFilled = pulls, denied.Times(), commits, filled
	return data, nil
}

// absent says whether no file is at path. metricsDataOf has read the file
// that withHistory asks about, so any refusal but a missing file has failed
// the render before.
func absent(path string) bool {
	_, err := os.Stat(path)
	return errors.Is(err, fs.ErrNotExist)
}

// loadReach is the reach at path with each repository lower-case, as collect
// keeps and compares them (forsgren#196).
func loadReach(path string) (history.Reach, error) {
	reach, err := history.LoadReach(path)
	if err != nil {
		return nil, err
	}
	folded := make(history.Reach, len(reach))
	for repository, at := range reach {
		folded[strings.ToLower(repository)] = at
	}
	return folded, nil
}

// failuresOf is the failure issues beside the history at path
// (data/failures.csv) less those the withdrawn file beside it
// (data/failures_withdrawn.csv) takes back (forsgren#155), as issueEventsOf
// joins the bug flags to the issue events. A missing withdrawn file takes
// back none.
func failuresOf(path string) ([]history.Failure, error) {
	failures, err := loadOrNone(beside(path, collect.FailuresFile), history.LoadFailures)
	if err != nil {
		return nil, err
	}
	withdrawn, err := loadOrNone(beside(path, collect.WithdrawnFile), history.LoadWithdrawals)
	if err != nil {
		return nil, err
	}
	return history.WithoutWithdrawn(failures, withdrawn), nil
}

// beside is the path of the file name in the folder of the history at path:
// data/<name> beside data/deployments.csv.
func beside(path, name string) string { return filepath.Join(filepath.Dir(path), name) }

// loadOrNone reads the file at path with load. A missing file holds
// nothing: a new installation renders before its first collect has stored
// anything. Any other refusal (an unknown version, a malformed line) is
// load's own error, which names the file.
func loadOrNone[T any](path string, load func(string) ([]T, error)) ([]T, error) {
	lines, err := load(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	return lines, err
}

// renderFlags parses render's arguments. It returns false once the usage
// error is on stderr.
func renderFlags(args []string, stderr io.Writer) (renderOptions, bool) {
	flags := newFlags("render", stderr)
	var o renderOptions
	flags.StringVar(&o.out, "out", "", "directory to write the site into")
	flags.StringVar(&o.config, "config", "", "the forsgren.config.yml the page reports on (optional)")
	flags.StringVar(&o.data, "data", "",
		"the history the page counts, data/deployments.csv, commits.csv, failures.csv, issues.csv beside it "+
			"(optional, needs --config)")
	flags.StringVar(&o.latest, "latest", "",
		"the newest forsgren release, as latest-release prints it; the footer names it when it is newer (optional)")
	flags.IntVar(&o.waitingPR, "waiting-pr", 0,
		"the open Dependabot pull request for that release, as waiting-pull-request prints it (optional, 1 or more)")
	flags.StringVar(&o.prCheck, "pr-check", "",
		"how the lookup of the waiting pull request went, as waiting-pull-request --status writes it; truncated "+
			"makes the footer say the pull request is unknown (optional)")
	flags.StringVar(&o.needsCheck, "needs-check", "",
		"how the check of what this version needs went: ok, no-access, rate-limited or failed (optional)")
	if err := flags.Parse(args); err != nil {
		return o, false
	}
	switch {
	case o.out == "":
		_, _ = fmt.Fprintln(stderr, "render: --out <dir> is required")
		return o, false
	case o.data != "" && o.config == "":
		_, _ = fmt.Fprintln(stderr, dataWithoutConfig)
		return o, false
	case !isPullRequestNumber(flags, o.waitingPR):
		_, _ = fmt.Fprintf(stderr, "render: --waiting-pr <number> must be a pull request's number, 1 or more, got %d\n",
			o.waitingPR)
		return o, false
	}
	return o, true
}

// isPullRequestNumber says whether render's --waiting-pr, when it was given,
// is a pull request's number, 1 or more; leaving the flag out means none.
func isPullRequestNumber(flags *flag.FlagSet, number int) bool {
	given := false
	flags.Visit(func(f *flag.Flag) { given = given || f.Name == "waiting-pr" })
	return !given || number >= 1
}

// settingsOf are the rows of the settings page: the top-level keys, then the
// per-repository settings as counts (forsgren#512).
func settingsOf(cfg config.Config) []config.Setting {
	return append(cfg.Settings(), cfg.RepositorySettings()...)
}
