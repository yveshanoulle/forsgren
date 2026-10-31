package collect

// The files of the deployed commits (forsgren#496, step 3). A service or a
// deployment rule with paths counts only the commits that touch them, so for a
// repository whose services or rules have at least one paths (forsgren#510;
// others never cost a request) every commit of data/commits.csv that has no
// line in data/commit_files.csv gets
// its changed files read, newest deployment first, and appended: the commits
// stored before this existed as well as those a deployment of this run
// brought. They are read LAST for a repository, after its pull requests, the
// fills, the backfill and the push read: the first fill of a big installation
// costs thousands of requests and must not starve fresh data, and a failure
// here fails the repository only once all of that is stored. Every stored
// commit counts, not only those of the DORA window: an installation may widen
// dora_days later.
//
// A commit that was read and changes no file gets one line with an empty
// path, so it is not read again; a list cut at GitHub's 3000 files is stored
// as read and named on stderr. data/commit_files_filled.csv (a mark file, one
// time per repository) says when a run found every stored commit of the
// repository read, the one-time fill done; it is noted at once, since what
// was read is already stored, and it does not stop later commits from being
// read.
//
// After the deployed commits come the pushed ones (forsgren#589, Yves's
// ruling: a service or rule row with paths counts the pushed commits that
// touch them): every commit of data/push_commits.csv, first-parent and branch
// commits alike, with no line yet and not already in the deployed list, each
// SHA once, the newest push first (pushfiles.go), inside the one cap of a run.
// data/push_files_filled.csv notes the repository when a run leaves no pushed
// commit unread (a commit GitHub no longer has is named and does not hold it
// back), and loses its line when a run leaves one unread, older pushes stored
// later included, so the Data page knows its first commit is still being
// read. commit_files_filled.csv keeps its meaning, the deployed commits alone.
// A read ends as the other fills do:
//
//   - a missing contents: read (ErrCommitFilesDenied) stores what was read,
//     notes no fill, says so on stderr and never fails the run; it writes no
//     denied mark, the push read's would blank the TBD page;
//   - a budget stop stores what was read, notes no fill, adds the repository
//     to the report's commit-files-cut lines and never fails the run, so the
//     next run continues with the commits still without lines;
//   - the cap of a run (CommitFilesPerRun, forsgren#589, Yves's ruling): a
//     run asks for the files of at most 1000 commits of a repository; the
//     read stops before the next one, stores what was read, notes no fill,
//     says so on stderr, adds the repository to the report's
//     commit-files-capped lines (planned, so the report stays complete) with
//     the commits read so far and those left (forsgren#593: counted from the
//     lines already stored and the todo, no request) and never fails the
//     run; the next run continues with the commits still without lines;
//   - a commit GitHub does not have (history rewritten) is named on stderr and
//     stays without lines, and for a deployed one the repository is not noted
//     as filled;
//   - any other error stores what was read, notes no fill and fails the
//     repository.

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
	"slices"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// CommitFilesFile is the name, next to the history, of the file that keeps the
// changed files of the deployed commits (forsgren#496).
const CommitFilesFile = "commit_files.csv"

// CommitFilesFilledFile is the name, next to the history, of the file that
// notes which repositories had the files of their stored commits read
// (forsgren#496).
const CommitFilesFilledFile = "commit_files_filled.csv"

// CommitFilesProgressFile is the name, next to the history, of the file that
// keeps how far each repository's commit files read is while it is still
// going (forsgren#594).
const CommitFilesProgressFile = "commit_files_progress.csv"

// CommitFilesPerRun is the most commits whose files one run asks for, per
// repository (forsgren#589, Yves's ruling): a first fill of thousands of
// commits is spread over several runs instead of spending a request budget.
const CommitFilesPerRun = 1000

// errFilesCapped ends a commit files read at CommitFilesPerRun.
var errFilesCapped = errors.New("the commit files stopped at the cap of a run")

// commitFilesFile is the path of the commit files file next to o's history.
func (o Options) commitFilesFile() string {
	return filepath.Join(filepath.Dir(o.History), CommitFilesFile)
}

// commitFilesFilledFile is the path of the commit files filled file next to
// o's history.
func (o Options) commitFilesFilledFile() string {
	return filepath.Join(filepath.Dir(o.History), CommitFilesFilledFile)
}

// checkCommitFiles refuses a commit files file that cannot be read, before
// GitHub is asked anything; a missing one is created by the first append.
func checkCommitFiles(path string) error {
	if _, err := history.LoadCommitFiles(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

// fileRead is what a read of commit files gave: the lines, how many commits
// they are of, where in the todo the commits GitHub does not have are, and
// how many commits of the todo it got past, read or missing.
type fileRead struct {
	lines   []history.CommitFile
	commits int
	missed  []int
	reached int
}

// fillCommitFiles reads the files of the stored commits of r that have none,
// when r has paths, and says how many commits it read; see the top of this
// file for what ends it.
func (o Options) fillCommitFiles(ctx context.Context, h held, r config.Repository) (int, error) {
	if !r.HasPaths() {
		return 0, nil
	}
	todo, err := o.commitsWithoutFiles(r.Name)
	if err != nil {
		return 0, err
	}
	read, err := o.readCommitFiles(ctx, r.Name, todo)
	at := todo.capped(r.Name, read.reached)
	if serr := o.storeFiles(h, at, todo, read); serr != nil {
		return 0, serr
	}
	if o.endedShort(at, err) {
		return read.commits, nil
	}
	return read.commits, err
}

// commitsWithoutFiles is repo's stored commits (ignoring case) that have no
// line in commit_files.csv: the deployed ones, the newest deployment's first,
// then the pushed ones, the newest push's first.
func (o Options) commitsWithoutFiles(repo string) (filesTodo, error) {
	stored, err := loadOrNone(o.commitsFile(), history.LoadCommits)
	if err != nil {
		return filesTodo{}, err
	}
	files, err := loadOrNone(o.commitFilesFile(), history.LoadCommitFiles)
	if err != nil {
		return filesTodo{}, err
	}
	read := map[string]bool{}
	for _, f := range files {
		if strings.EqualFold(f.Repository, repo) {
			read[f.SHA] = true
		}
	}
	done := len(read)
	deployed := unreadNewestFirst(repo, stored, read)
	pushed, err := o.pushedWithoutFiles(repo, read)
	return filesTodo{shas: append(deployed, pushed...), deployed: len(deployed), done: done}, err
}

// loadOrNone is what load reads at path, nothing for a file that is not there.
func loadOrNone[R any](path string, load func(string) ([]R, error)) ([]R, error) {
	records, err := load(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	return records, err
}

// unreadNewestFirst is the SHAs of repo's commits not in read, each once, the
// commit of the newest deployment first (then the newest author date).
func unreadNewestFirst(repo string, commits []history.Commit, read map[string]bool) []string {
	var todo []history.Commit
	for _, c := range commits {
		if strings.EqualFold(c.Repository, repo) && !read[c.SHA] {
			read[c.SHA] = true
			todo = append(todo, c)
		}
	}
	slices.SortStableFunc(todo, func(a, b history.Commit) int {
		if c := b.DeployedAt.Compare(a.DeployedAt); c != 0 {
			return c
		}
		return b.AuthoredAt.Compare(a.AuthoredAt)
	})
	shas := make([]string, len(todo))
	for i, c := range todo {
		shas[i] = c.SHA
	}
	return shas
}

// readCommitFiles is the lines of the files of the commits todo of repo, up
// to the first error that ends the read; Client.Reserve(repo, 1) comes before
// each commit, so a budget stop leaves the one it stops at unread, and the
// read ends with errFilesCapped before a commit past CommitFilesPerRun.
func (o Options) readCommitFiles(ctx context.Context, repo string, todo filesTodo) (fileRead, error) {
	var out fileRead
	for i, sha := range todo.shas {
		out.reached = i
		if i == CommitFilesPerRun {
			return out, errFilesCapped
		}
		if err := o.Client.Reserve(repo, 1); err != nil {
			return out, err
		}
		lines, found, err := o.readOneCommit(ctx, repo, sha)
		if err != nil {
			return out, err
		}
		if !found {
			out.missed = append(out.missed, i)
			continue
		}
		out.lines = append(out.lines, lines...)
		out.commits++
	}
	out.reached = len(todo.shas)
	return out, nil
}

// readOneCommit is the lines of the files of the commit sha of repo, and
// whether GitHub has it: a commit it does not have is named on stderr.
func (o Options) readOneCommit(ctx context.Context, repo, sha string) ([]history.CommitFile, bool, error) {
	lines, err := o.commitFilesOf(ctx, repo, sha)
	if errors.Is(err, github.ErrMissingCommit) {
		o.warn("collect: %s: commit %s: not found: %v; it stays without file lines\n", repo, sha, err)
		return nil, false, nil
	}
	return lines, err == nil, err
}

// commitFilesOf is the lines of one commit's files, one empty-path line when
// it changes none; a list cut at the page limit is named on stderr.
func (o Options) commitFilesOf(ctx context.Context, repo, sha string) ([]history.CommitFile, error) {
	paths, cut, err := o.Client.CommitChangedFiles(ctx, repo, sha)
	if err != nil {
		return nil, err
	}
	if cut {
		o.warn("collect: %s: commit %s: more files than were read (the list was cut at %d page(s)); "+
			"the files read are stored\n", repo, sha, o.Client.MaxPages())
	}
	return commitFileLines(repo, sha, paths), nil
}

// commitFileLines are the lines of the commit sha's paths, each once.
func commitFileLines(repo, sha string, paths []string) []history.CommitFile {
	if len(paths) == 0 {
		return []history.CommitFile{{Repository: repo, SHA: sha}}
	}
	sorted := slices.Compact(slices.Sorted(slices.Values(paths)))
	lines := make([]history.CommitFile, len(sorted))
	for i, p := range sorted {
		lines[i] = history.CommitFile{Repository: repo, SHA: sha, Path: p}
	}
	return lines
}

// reportFilesCut adds repo, whose read of the commit files the budget cut
// short, to the report (forsgren#496).
func (o Options) reportFilesCut(repo string) {
	if o.Report != nil {
		o.Report.FilesCut = append(o.Report.FilesCut, repo)
	}
}

// reportFilesCapped adds c, a read of the commit files that stopped at the
// cap of a run, to the report (forsgren#589), with its counts (forsgren#593).
func (o Options) reportFilesCapped(c CappedFiles) {
	if o.Report != nil {
		o.Report.FilesCapped = append(o.Report.FilesCapped, c)
	}
}

// endedShort says whether err ended the read of at's repository short
// without failing it: a refusal, a budget stop or the cap of a run, each said
// on stderr and the last two in the report, the cap with at's counts.
func (o Options) endedShort(at CappedFiles, err error) bool {
	repo := at.Repository
	switch {
	case errors.Is(err, github.ErrCommitFilesDenied):
		o.warn("collect: %v; the commit files are not read, the rest is collected\n", err)
	case errors.Is(err, github.ErrBudget):
		o.warnFillCut(repo, "commit files", err)
		o.reportFilesCut(repo)
	case errors.Is(err, errFilesCapped):
		o.warn("collect: %s: the commit files stopped at the cap of %d commits a run; "+
			"those read are stored, the next run continues\n", repo, CommitFilesPerRun)
		o.reportFilesCapped(at)
	default:
		return false
	}
	return true
}
