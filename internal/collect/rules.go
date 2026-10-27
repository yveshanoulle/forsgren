package collect

// Several deployment rules for one repository (forsgren#498, step 2). Each
// rule is read as a repository with that one rule is: its own source (kind
// and name) sets its window, its deployments are compared within its own
// streams, and the commits are the ones of its new successes. The rules are
// read one after the other and what they read is stored together.
//
// A repository has one reach (data/reach.csv), so it may not pass what any
// rule has read:
//   - a rule with nothing stored is read as a first run is, its first chunk,
//     though the repository has a reach noted;
//   - the reach moves to the latest of the reaches the rules give, a rule
//     that leaves it counting as the reach it is at, and stays when that is
//     where it is;
//   - a rule cut short by the budget ends the reading: the rules after it are
//     unread, so the reach cannot pass what they would have read.
//
// A newly added rule therefore moves the reach forward to the start of its
// first chunk, and the established rules re-read, deduplicated by key, the
// chunks they hold already until the reach is back where it was.

import (
	"context"
	"maps"
	"strings"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/history"
)

// deploymentsOfRules reads the deployment rules of the repository r, one
// after the other.
func (o Options) deploymentsOfRules(ctx context.Context, h held, project string, r config.Repository) (whole, error) {
	var out whole
	var reaches []time.Time
	var cutErr error
	rules, repo := r.DeploymentRules(), r.Name
	for _, rule := range rules {
		x := ruleRead{project, repo, rule.Deployment}
		w, err := o.deploymentsOfRule(ctx, h.readingFrom(repo, rule.Deployment), x)
		if _, cut := cutOf(err); err != nil && !cut {
			return whole{}, err
		}
		out = out.join(w, len(reaches) == 0)
		reaches = append(reaches, w.reach)
		if cutErr = err; err != nil {
			break
		}
	}
	out.reach = h.reachAfter(repo, reaches, len(rules)-len(reaches))
	return out, cutErr
}

// join is w after what the rules before it read, first saying it is the first.
func (w whole) join(next whole, first bool) whole {
	if first {
		return next
	}
	merged := w.merge(next.found)
	merged.win, merged.recent = next.win, next.recent
	merged.oldest = earliestSeen(w.oldest, next.oldest)
	return whole{merged, append(w.commits, next.commits...)}
}

// earliestSeen is the earlier of a and b, a zero one being none read.
func earliestSeen(a, b time.Time) time.Time {
	if a.IsZero() {
		return b
	}
	if b.IsZero() {
		return a
	}
	return earlier(a, b)
}

// readingFrom is h as the read of rule d of repo sees it: a rule with nothing
// stored sees no reach of the repository, so it reads its first chunk.
func (h held) readingFrom(repo string, d config.Deployment) held {
	s := sourceOf(history.Record{Repository: repo, Kind: kindOf(d.Kind), Name: d.Name})
	_, stored := h.newest[s]
	key := strings.ToLower(repo)
	if _, noted := h.reach[key]; stored || !noted {
		return h
	}
	h.reach = maps.Clone(h.reach)
	delete(h.reach, key)
	return h
}

// reachAfter is where the reach of repo moves to after its rules gave
// reaches (zero: it stays), unread more rules not read. A rule that leaves the
// reach, and a rule not read, count as the reach repo is at; the new reach is
// the latest of them, and it stays when that is where it is or is unknown.
func (h held) reachAfter(repo string, reaches []time.Time, unread int) time.Time {
	current := h.reach[strings.ToLower(repo)]
	var latest time.Time
	for _, r := range reachesOr(current, reaches, unread) {
		if r.IsZero() {
			return time.Time{}
		}
		latest = later(latest, r)
	}
	if latest.Equal(current) {
		return time.Time{}
	}
	return latest
}

// reachesOr is reaches with current in place of each zero one, and unread
// more of current.
func reachesOr(current time.Time, reaches []time.Time, unread int) []time.Time {
	out := make([]time.Time, 0, len(reaches)+unread)
	for _, r := range reaches {
		if r.IsZero() {
			r = current
		}
		out = append(out, r)
	}
	for range unread {
		out = append(out, current)
	}
	return out
}
