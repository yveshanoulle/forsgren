package collect

// A repository's history is read in chunks (forsgren#57). Its first run reads
// the newest history_chunk_days, and every later run reads what is new plus
// ONE older chunk, until history_days is reached. data/reach.csv notes, per
// repository, the date down to which it was read, because the oldest stored
// deployment cannot tell a quiet stretch from an unread one. A repository
// with stored history but no row starts at its oldest stored deployment.

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// ReachFile is the name, next to the history, of the file that notes how far
// back each repository was read.
const ReachFile = "reach.csv"

// reachFile is the path of the reach file next to the history.
func (o Options) reachFile() string { return filepath.Join(filepath.Dir(o.History), ReachFile) }

// windowOf is o with the window of cfg: history_days back at the most, in
// chunks of history_chunk_days.
func (o Options) windowOf(cfg config.Config) Options {
	o.earliest = o.Now.Add(-time.Duration(cfg.HistoryDays) * 24 * time.Hour)
	o.chunk = time.Duration(cfg.HistoryChunkDays) * 24 * time.Hour
	return o
}

// windows are the spans one run reads of one repository: the normal read,
// and the older chunk when there is one (an Until of its own, else none).
type windows struct {
	normal github.Span
	older  github.Span
	first  bool // nothing stored and no reach: the normal read is the first chunk
}

// windows plans the read of base's source. The normal read starts 7 days
// (Lookback) before the newest stored deployment, never before earliest, or,
// with nothing stored, one chunk back. The older chunk ends at the reach, or
// at the oldest stored deployment when no reach is noted.
func (o Options) windows(h held, base history.Record) windows {
	s := sourceOf(base)
	newest, stored := h.newest[s]
	reach, noted := h.reach[strings.ToLower(base.Repository)]
	w := windows{normal: github.Span{Since: later(o.Now.Add(-o.chunk), o.earliest)}, first: !stored && !noted}
	if stored {
		w.normal.Since = later(newest.Add(-Lookback), o.earliest)
	}
	if !noted {
		reach = h.oldest[s]
	}
	w.older = o.olderChunk(reach)
	return w
}

// olderChunk is the chunk before reach, cut at earliest; none (the zero
// Span) when reach is unknown or history_days is reached.
func (o Options) olderChunk(reach time.Time) github.Span {
	if !reach.After(o.earliest) {
		return github.Span{}
	}
	return github.Span{Since: later(reach.Add(-o.chunk), o.earliest), Until: reach}
}

// read reads one repository by its rule: the normal read, then the older
// chunk when there is one. The reach of the result is where the repository's
// reach moves to, or zero when it stays.
func (o Options) read(ctx context.Context, h held, base history.Record, kind config.DeploymentKind) (found, error) {
	base.Kind = kindOf(kind)
	w := o.windows(h, base)
	f, err := o.fetch(ctx, h, base, w.normal)
	if err != nil {
		return found{}, err
	}
	if w.first {
		f.reach = advance(w.normal, f)
	}
	if w.older.Until.IsZero() {
		return f, nil
	}
	g, err := o.fetch(ctx, h, base, w.older)
	if err != nil {
		return found{}, err
	}
	reach := advance(w.older, g)
	f = f.merge(g)
	f.reach = reach
	return f, nil
}

// kindOf is the kind of the history's deployments that a rule stores.
func kindOf(kind config.DeploymentKind) history.Kind {
	switch kind {
	case config.Workflow:
		return history.KindWorkflow
	case config.Release:
		return history.KindRelease
	}
	return history.KindEnvironment
}

// advance is where the reach moves to after span was read as f: the start of
// span, or, when the read was cut off at the page limit, the oldest date
// actually read (zero when it read none, so the reach stays).
func advance(span github.Span, f found) time.Time {
	if f.truncated {
		return f.oldest
	}
	return span.Since
}

// see notes that an item created at t was read.
func (f *found) see(t time.Time) {
	if !t.IsZero() && (f.oldest.IsZero() || t.Before(f.oldest)) {
		f.oldest = t
	}
}

// merge is f and what g read besides.
func (f found) merge(g found) found {
	f.records = append(f.records, g.records...)
	f.notFinal += g.notFinal
	f.truncated = f.truncated || g.truncated
	return f
}

// noteReach moves a repository's reach, unless reach is zero.
func (h held) noteReach(repository string, reach time.Time) {
	if !reach.IsZero() {
		h.reach[strings.ToLower(repository)] = reach
	}
}

// finish is the end of a run: the failed repositories as ErrFailed, joined
// with the errors of saving the marks, each saved when it moved. The marks of
// the repositories that were read are kept even when others failed.
func (o Options) finish(h held, before marks, failed, total int) error {
	var err error
	if failed > 0 {
		err = fmt.Errorf("%d of %d %w", failed, total, ErrFailed)
	}
	return errors.Join(err, o.saveMarks(h, before))
}
