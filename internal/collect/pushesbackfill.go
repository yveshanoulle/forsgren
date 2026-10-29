package collect

// The fill of the older pushes (forsgren#583, step 2). A repository with a
// line in data/pushes_cut.csv has pushes older than its stored ones that no
// read reached: the first read stopped at the page cap, and every later read
// starts at the read mark. After its push read and the fill of the pull
// request openers, each run reads more of its activity list, newest first, a
// page at a time (Client.ActivityPage, one request each, Client.Reserve
// first), up to the client's page cap (10 pages by default) per run:
//
//   - GitHub pages the list by an after cursor, which holds its place across
//     runs, so data/pushes_fill.csv keeps, per repository, the cursor of the
//     next page to read. Without a line the fill starts at the top: its first
//     pages hold stored pushes only, which cost a request each and no compare;
//   - each push not stored yet is compared and stored as the push read stores
//     a new one (comparePush: data/push_commits.csv first, then
//     data/pushes.csv), so nothing is stored twice;
//   - the fill stops at the first push older than history_days back, which it
//     neither compares nor stores, and when the list ends;
//   - after each page the cut moves to the oldest push read so far, and the
//     cursor to the next page: a run that stops inside a page reads that page
//     again, at most one page more, and skips what it stored;
//   - a missing contents: read writes the denied mark, as the push read does;
//     a budget stop keeps what was stored and the cursor and adds the
//     repository to the report's pushes-fill-cut lines; neither fails the
//     run. Any other error fails the repository after storing.
//
// Removing the cut line once the fill reaches the end of the list or
// history_days is a later step (forsgren#583, step 3).

import (
	"context"
	"errors"
	"path/filepath"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// pushesFillFile is the path of the pushes fill file next to o's history.
func (o Options) pushesFillFile() string {
	return filepath.Join(filepath.Dir(o.History), PushesFillFile)
}

// fillFile is the markFile of data/pushes_fill.csv: the times are kept in
// mark and the cursors beside them in cursors.
func fillFile(mark *history.Reach, cursors *map[string]string, path string) markFile {
	return markFile{
		held: mark,
		path: path,
		load: func(path string) (history.Reach, error) {
			fill, err := history.LoadPushesFill(path)
			*cursors = fill.Cursors()
			return fill.Times(), err
		},
		save: func(path string, times history.Reach) error {
			return history.SavePushesFill(path, history.PushesFillOf(times, *cursors))
		},
	}
}

// fillPushes reads repo's older pushes when it has a cut line, up to the page
// cap; see the top of this file for what ends it.
func (o Options) fillPushes(ctx context.Context, h held, repo string) error {
	if _, cut := h.pushesCut[strings.ToLower(repo)]; !cut {
		return nil
	}
	branch, err := o.defaultBranch(ctx, h, repo)
	if err == nil {
		err = o.fillPages(ctx, h, filled{repo, branch})
	}
	return o.endPushesFill(h, repo, err)
}

// filled is the branch a push fill reads, of its repository.
type filled struct{ repo, branch string }

// fillPages reads up to the page cap of f's activity list from its cursor
// on, stopping when the list ends or reaches history_days back.
func (o Options) fillPages(ctx context.Context, h held, f filled) error {
	for range o.Client.MaxPages() {
		if more, err := o.fillPage(ctx, h, f); !more || err != nil {
			return err
		}
	}
	return nil
}

// fillPage reads and stores the page of f's activity list at its cursor and
// moves the cursor on; it says whether the fill goes on.
func (o Options) fillPage(ctx context.Context, h held, f filled) (bool, error) {
	key := strings.ToLower(f.repo)
	if err := o.Client.Reserve(f.repo, 1); err != nil {
		return false, err
	}
	list, err := o.Client.ActivityPage(ctx, f.repo, f.branch, h.fillCursors[key])
	if err != nil {
		return false, err
	}
	ended, err := o.storeFillPage(ctx, h, f.repo, list.Activities)
	if err != nil {
		return false, err
	}
	return o.moveFill(h, key, list, ended), nil
}

// moveFill moves the fill of the repository key on to list's next page, or
// ends it when list or history_days (ended) is its end; it says whether the
// fill goes on.
func (o Options) moveFill(h held, key string, list github.ActivityList, ended bool) bool {
	if ended || list.Next == "" {
		o.endFill(h, key, ended || list.Created)
		return false
	}
	h.fillCursors[key], h.pushesFilledAt[key] = list.Next, wholeSecond(o.Now)
	return true
}

// endFill ends the fill of the repository key (forsgren#583, step 3): its cut
// line and cursor go, and it needs no reach check any more. A fill that was
// not complete (the list ended without the creation of the branch, before
// history_days back) notes the oldest push read as GitHub's end.
func (o Options) endFill(h held, key string, complete bool) {
	if !complete {
		h.githubEnd[key] = h.pushesCut[key]
	}
	delete(h.pushesCut, key)
	delete(h.fillCursors, key)
	delete(h.pushesFilledAt, key)
	h.pushesChecked[key] = wholeSecond(o.Now)
}

// pushesGitHubEndFile is the path of the pushes github end file next to o's
// history.
func (o Options) pushesGitHubEndFile() string {
	return filepath.Join(filepath.Dir(o.History), PushesGitHubEndFile)
}

// storeFillPage compares and stores the pushes of one page that are not
// stored yet, down to history_days back, and moves the cut to the oldest
// push of the page; it says whether the page reached history_days back.
func (o Options) storeFillPage(ctx context.Context, h held, repo string, page []github.Activity) (bool, error) {
	var read pushesRead
	ended := false
	for _, a := range page {
		if a.PushedAt.Before(o.earliest) {
			ended = true
			break
		}
		push := pushOf(repo, a)
		read.oldest = push.PushedAt
		if h.pushes[push.Key()] {
			continue
		}
		counted, commits, err := o.comparePush(ctx, push)
		if err != nil {
			return ended, errors.Join(err, o.storeFilled(h, repo, read))
		}
		read.pushes, read.commits = append(read.pushes, counted), append(read.commits, commits...)
	}
	return ended, o.storeFilled(h, repo, read)
}

// storeFilled stores what a fill page read and moves the cut to its oldest
// push.
func (o Options) storeFilled(h held, repo string, read pushesRead) error {
	if _, err := history.AppendPushCommits(o.pushCommitsFile(), read.commits); err != nil {
		return err
	}
	if _, err := history.AppendPushes(o.pushesFile(), read.pushes); err != nil {
		return err
	}
	for _, p := range read.pushes {
		h.pushes[p.Key()] = true
	}
	key := strings.ToLower(repo)
	if !read.oldest.IsZero() && read.oldest.Before(h.pushesCut[key]) {
		h.pushesCut[key] = wholeSecond(read.oldest)
	}
	return nil
}

// endPushesFill says what an ended fill fails: a refusal writes the denied
// mark and a budget stop is reported, neither fails the repository.
func (o Options) endPushesFill(h held, repo string, err error) error {
	switch {
	case errors.Is(err, github.ErrPushesDenied):
		o.warn("collect: %v; its older pushes are not read, the rest is collected\n", err)
		o.notePushesDenied(h, repo)
		return nil
	case errors.Is(err, github.ErrBudget):
		o.warn("collect: %s: the fill of the older pushes was cut short: %v; "+
			"what was read is stored, the next run continues\n", repo, err)
		o.reportPushesFillCut(repo)
		return nil
	}
	return err
}

// reportPushesFillCut adds repo, whose fill of the older pushes the budget
// cut short, to the report (forsgren#583).
func (o Options) reportPushesFillCut(repo string) {
	if o.Report != nil {
		o.Report.PushesFillCut = append(o.Report.PushesFillCut, repo)
	}
}
