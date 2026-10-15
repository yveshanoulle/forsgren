package main

import (
	"fmt"
	"io"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// loadConfig is config.Load, and for each setting the file writes that
// forsgren does not accept, one warning line on stderr: the file, the refusal's
// text and the default in use (forsgren#183). The value as written is in the
// text quoted, so a line break or a control character in it is escaped and the
// warning stays one line, which a workflow log never runs as a command.
func loadConfig(path string, stderr io.Writer) (config.Config, error) {
	cfg, err := config.Load(path)
	for _, r := range cfg.Rejected {
		_, _ = fmt.Fprintf(stderr, "config: warning: %s: %s; using the default %s\n", path, r.Error(), r.Default)
	}
	return cfg, err
}
