// Package collect is `forsgren collect` (forsgren#12, step 5): it reads each
// configured repository's deployments from GitHub by the repository's rule
// and appends the final ones to the history.
package collect

import (
	"context"
	"errors"
	"io"
	"time"

	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/github"
)

// ErrFailed: at least one repository could not be collected.
var ErrFailed = errors.New("repositories failed")

// Options is what one collect run works with.
type Options struct {
	Client  *github.Client
	History string // the path of data/deployments.csv
	Now     time.Time
	Stdout  io.Writer
	Stderr  io.Writer
}

// Run collects every repository of cfg.
func Run(ctx context.Context, cfg config.Config, o Options) error {
	return nil
}
