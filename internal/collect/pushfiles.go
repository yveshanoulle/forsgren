package collect

// The pushed commits whose files are read after the deployed ones
// (forsgren#589, step 4): every commit of data/push_commits.csv of a
// repository, first-parent and branch commits alike, with no line in
// data/commit_files.csv and not already in the deployed list, each SHA once
// whatever brought it, the newest push first, then the newest author date. A
// commit several pushes brought is placed at the earliest of them, when it
// reached the branch; a push not in data/pushes.csv places its commits last.

import (
	"cmp"
	"maps"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// PushFilesFilledFile is the name, next to the history, of the file that
// notes which repositories had the files of all their pushed commits read
// (forsgren#589).
const PushFilesFilledFile = "push_files_filled.csv"

// pushFilesFilledFile is the path of the push files filled file next to o's
// history.
func (o Options) pushFilesFilledFile() string {
	return filepath.Join(filepath.Dir(o.History), PushFilesFilledFile)
}

// filesTodo is the commits whose files a read asks for, in order: the first
// deployed of them deployed commits, the rest pushed ones.
type filesTodo struct {
	shas     []string
	deployed int
}

// pushedLeft says whether a read that reached the first reached commits of t
// left a pushed commit unread.
func (t filesTodo) pushedLeft(reached int) bool { return len(t.shas) > max(reached, t.deployed) }

// deployedRead says whether read got past every deployed commit of t with
// none GitHub does not have: one keeps the deployed commits from being noted
// as filled, a pushed one does not.
func (t filesTodo) deployedRead(read fileRead) bool {
	return read.reached >= t.deployed && !slices.ContainsFunc(read.missed, t.isDeployed)
}

// isDeployed says whether the i-th commit of t is a deployed one.
func (t filesTodo) isDeployed(i int) bool { return i < t.deployed }

// noteFileMarks notes repo's deployed commits filled once read got past them
// with none missing, and notes its pushed commits read when none is left
// unread, or takes that mark away when one is.
func (o Options) noteFileMarks(h held, repo string, todo filesTodo, read fileRead) {
	if todo.deployedRead(read) && !filledBefore(h.filesFilled, repo) {
		o.noteFilled(h.filesFilled, repo)
	}
	switch {
	case todo.pushedLeft(read.reached):
		delete(h.pushFiles, strings.ToLower(repo))
	case !filledBefore(h.pushFiles, repo):
		o.noteFilled(h.pushFiles, repo)
	}
}

// pushedAt is when a pushed commit reached the branch and when it was
// authored, the order of the read.
type pushedAt struct {
	sha            string
	pushed, author time.Time
}

// pushedWithoutFiles is repo's pushed commits not in read, newest push
// first; it adds them to read.
func (o Options) pushedWithoutFiles(repo string, read map[string]bool) ([]string, error) {
	commits, err := loadOrNone(o.pushCommitsFile(), history.LoadPushCommits)
	if err != nil {
		return nil, err
	}
	pushes, err := loadOrNone(o.pushesFile(), history.LoadPushes)
	if err != nil {
		return nil, err
	}
	return unreadPushedNewestFirst(repo, commits, pushTimes(repo, pushes), read), nil
}

// pushTimes is when each push of repo was made, by its after SHA.
func pushTimes(repo string, pushes []history.Push) map[string]time.Time {
	times := map[string]time.Time{}
	for _, p := range pushes {
		if at, seen := times[p.After]; strings.EqualFold(p.Repository, repo) && (!seen || p.PushedAt.Before(at)) {
			times[p.After] = p.PushedAt
		}
	}
	return times
}

// unreadPushedNewestFirst is the SHAs of repo's pushed commits not in read,
// each once at its earliest push, the newest push first, then the newest
// author date; it adds them to read.
func unreadPushedNewestFirst(repo string, commits []history.PushCommit, times map[string]time.Time,
	read map[string]bool) []string {
	placed := map[string]pushedAt{}
	for _, c := range commits {
		if strings.EqualFold(c.Repository, repo) && !read[c.SHA] {
			place(placed, pushedAt{sha: c.SHA, pushed: times[c.After], author: c.AuthoredAt})
		}
	}
	todo := slices.SortedFunc(maps.Values(placed), newestPushFirst)
	shas := make([]string, len(todo))
	for i, p := range todo {
		shas[i] = p.sha
		read[p.sha] = true
	}
	return shas
}

// place keeps p in placed unless its commit is there at an earlier push.
func place(placed map[string]pushedAt, p pushedAt) {
	if at, seen := placed[p.sha]; !seen || p.pushed.Before(at.pushed) {
		placed[p.sha] = p
	}
}

// newestPushFirst orders by push time, then author date, newest first, then
// by SHA.
func newestPushFirst(a, b pushedAt) int {
	return cmp.Or(b.pushed.Compare(a.pushed), b.author.Compare(a.author), cmp.Compare(a.sha, b.sha))
}
