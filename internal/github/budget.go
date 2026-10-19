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

// checkBudget is nil, or the ErrBudget of a call about repo when the client
// has a margin, the last answer left fewer requests than it, and the reset
// time is still to come.
func (c *Client) checkBudget(repo string) error {
	b := c.budget
	if !c.margin || !b.atMargin(time.Now()) {
		return nil
	}
	return fmt.Errorf("%s: %w (%d of %d left); it resets at %s", repo, ErrBudget, b.left, b.limit,
		b.reset.UTC().Format(time.RFC3339))
}

// atMargin says whether an answer said fewer requests are left than the
// margin, max(100, 5% of the limit), and the count has not started over by
// now.
func (b budget) atMargin(now time.Time) bool {
	if !b.known {
		return false
	}
	return b.left < max(budgetFloor, b.limit/budgetShare) && now.Before(b.reset)
}
