// Package needs is what each forsgren release declares an installation needs:
// a permission, a secret, a file or a config key (forsgren#73). The
// declarations are needs.yml, built into the binary.
//
// An entry introduced in version X applies to X and to every later version.
package needs

import (
	_ "embed" // The declarations are embedded.
)

// declared is needs.yml, the one text of what the releases need.
//
//go:embed needs.yml
var declared string

// Need is one thing an installation needs, from the release that introduced
// it on: what to check (Kind and the fields its check reads) and Steps, the
// human-readable remediation.
type Need struct {
	Version    string `yaml:"version"`
	Kind       string `yaml:"kind"`
	Workflow   string `yaml:"workflow"`
	Permission string `yaml:"permission"`
	Access     string `yaml:"access"`
	Steps      string `yaml:"steps"`
}

// For returns the needs that apply to the running version.
func For(version string) ([]Need, error) {
	return nil, nil
}
