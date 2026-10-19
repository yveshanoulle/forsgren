package github

// The request budget (forsgren#64, decision #238). GitHub says on every
// answer how many requests the token has left (X-RateLimit-Remaining), how
// many it gets an hour (X-RateLimit-Limit) and when that count starts over
// (X-RateLimit-Reset). A client built WithBudgetMargin sends no further
// request once Remaining is below the margin, max(100, 5% of Limit), so
// the rest of the hour is left to the run's last steps and to anything else
// using the token. A request GitHub refuses at 0 stays ErrRateLimit.

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"time"
)

// ErrBudget: the token's hourly request budget is nearly used, so the client
// sends no further request until it resets.
var ErrBudget = errors.New("GitHub's request budget is nearly used")

const (
	// budgetFloor is the fewest requests left that the margin ever is.
	budgetFloor = 100
	// budgetShare is the share of the limit that the margin is, 5%, as 1/20.
	budgetShare = 20
)

// budget is what the last answers said: the requests left (known only once
// an answer said), the hourly limit, 0 when none said, and when the count
// starts over.
type budget struct {
	left, limit int
	known       bool
	reset       time.Time
}

// WithBudgetMargin makes c stop before the budget is gone: once an answer
// says fewer requests are left than the margin, every call returns ErrBudget,
// naming the repository and the reset time, until that time has passed. It
// returns c.
func (c *Client) WithBudgetMargin() *Client {
	c.margin = true
	return c
}

// noteBudget notes the rate-limit headers of an answer; a header that is
// missing or not a number leaves what was known.
func (c *Client) noteBudget(h http.Header) {
	if left, ok := number(h.Get("X-RateLimit-Remaining")); ok {
		c.budget.left, c.budget.known = left, true
	}
	if limit, ok := number(h.Get("X-RateLimit-Limit")); ok {
		c.budget.limit = limit
	}
	if reset, ok := number(h.Get("X-RateLimit-Reset")); ok {
		c.budget.reset = time.Unix(int64(reset), 0)
	}
}

// number is the whole number in s, not negative.
func number(s string) (int, bool) {
	n, err := strconv.Atoi(s)
	return n, err == nil && n >= 0
}

// Reserve is nil, or the ErrBudget of a call about repo, worded as
// checkBudget's, when the client has a margin and fewer than n requests are
// spare above it: a request may still be sent while Remaining has not fallen
// below the margin, so n more after this one fit when Remaining is at least
// the margin plus n. A caller that needs n requests after this one to finish
// what it starts stops here instead (forsgren#64, decision #239). Nil too
// before any answer said, and once the reset time has passed.
func (c *Client) Reserve(repo string, n int) error {
	b := c.budget
	if !c.margin || b.spare(time.Now()) >= n {
		return nil
	}
	return fmt.Errorf("%s: %w (%d of %d left); it resets at %s", repo, ErrBudget, b.left, b.limit,
		b.reset.UTC().Format(time.RFC3339))
}

// margin is the fewest requests left that the client sends one in: the
// larger of the floor and 5% of the limit.
func (b budget) margin() int { return max(budgetFloor, b.limit/budgetShare) }

// spare is how many requests are left above the margin, as many as there can
// be when no answer said yet or the count has started over by now.
func (b budget) spare(now time.Time) int {
	if !b.known || !now.Before(b.reset) {
		return math.MaxInt
	}
	return b.left - b.margin()
}
