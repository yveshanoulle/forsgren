// Package needs is what each forsgren release declares an installation needs:
// a permission, a secret, a file or a config key (forsgren#73). The
// declarations are needs.yml, built into the binary.
//
// An entry introduced in version X applies to X and to every later version.
package needs

import (
	_ "embed" // The declarations are embedded.
	"fmt"
	"slices"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
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
	File       string `yaml:"file"`
	// Key is the top-level key of forsgren.config.yml that a need of kind
	// config_key asks for.
	Key string `yaml:"key"`
	// Secret is the name of the environment variable through which the
	// workflow passes a secret to forsgren, which a need of kind secret asks
	// for: forsgren can only see a secret that arrives that way.
	Secret string `yaml:"secret"`
	Steps  string `yaml:"steps"`
}

// For returns the needs that apply to the running version: those introduced
// in it or in an earlier one, versions compared as numbers (0.3.10 is later
// than 0.3.7). A version that is not three dot-separated numbers, a
// declaration that cannot be read, and a declaration of a kind that has no
// check, whatever its version, are errors.
func For(version string) ([]Need, error) {
	return forVersion(declared, version)
}

// forVersion is For over the declarations in text.
func forVersion(text, version string) ([]Need, error) {
	running, err := numbers(version)
	if err != nil {
		return nil, err
	}
	var all []Need
	if err := yaml.Unmarshal([]byte(text), &all); err != nil {
		return nil, fmt.Errorf("needs.yml: %w", err)
	}
	var applying []Need
	for _, n := range all {
		introduced, err := numbers(n.Version)
		if err != nil {
			return nil, fmt.Errorf("needs.yml: %w", err)
		}
		if _, known := checks[n.Kind]; !known {
			return nil, fmt.Errorf("needs.yml: kind %q has no check", n.Kind)
		}
		if slices.Compare(introduced[:], running[:]) <= 0 {
			applying = append(applying, n)
		}
	}
	return applying, nil
}

// numbers is the three numbers of a version, with or without a leading "v".
func numbers(version string) ([3]int, error) {
	var n [3]int
	parts := strings.Split(strings.TrimPrefix(version, "v"), ".")
	if len(parts) != len(n) {
		return n, fmt.Errorf("version %q is not three dot-separated numbers", version)
	}
	for i, part := range parts {
		v, err := strconv.Atoi(part)
		if err != nil {
			return n, fmt.Errorf("version %q is not three dot-separated numbers", version)
		}
		n[i] = v
	}
	return n, nil
}
