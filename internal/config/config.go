// Package config reads and validates an installation's forsgren.config.yml:
// which repositories forsgren measures, grouped into projects, and what
// counts as a deployment of each (forsgren#6).
//
// The file is what an installation's owner owns, next to data/ (forsgren#4),
// so every mistake in it is refused by name, never skipped: an unknown key
// is an error (a typo must not silently do nothing), and so is a missing or
// other format version.
//
// The format, version 1:
//
//	version: 1
//	projects:
//	  - name: Acme
//	    repositories:
//	      - name: acme/app                 # owner/name on GitHub
//	        deployment: release            # optional, see Deployment
package config

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"go.yaml.in/yaml/v3"
)

// FormatVersion is the one config format version this forsgren reads. A
// file of any other version, or of none, is refused: a change to the format
// gets a new version, so an old forsgren never misreads a newer file.
const FormatVersion = 1

// DefaultEnvironment is the GitHub environment a repository deploys to when
// its config names no deployment.
const DefaultEnvironment = "production"

// DeploymentKind says what counts as a deployment of a repository.
type DeploymentKind int

// The three deployment forms of config v1 (Yves's ruling on forsgren#6).
const (
	// Environment: a GitHub Deployment to the named environment whose
	// status is success. `environment=<name>`; the default, with
	// DefaultEnvironment, when a repository names no deployment.
	Environment DeploymentKind = iota + 1
	// Workflow: a successful run on main of the named workflow file.
	// `workflow=<file>.yml` (or .yaml).
	Workflow
	// Release: a published GitHub Release (App Store apps, tools).
	// `release`.
	Release
)

// Deployment is one repository's deployment definition.
type Deployment struct {
	Kind DeploymentKind
	// Name is the environment for Environment, the workflow file name for
	// Workflow, and empty for Release.
	Name string
}

// Repository is one measured GitHub repository.
type Repository struct {
	// Name is owner/name, as written in the file.
	Name       string
	Deployment Deployment
}

// Project groups the repositories that ship one product; the page shows
// each project's metrics in its own section (forsgren#6).
type Project struct {
	Name         string
	Repositories []Repository
}

// Config is a validated forsgren.config.yml.
type Config struct {
	Version  int
	Projects []Project
}

// The refusals Load names. Each error Load returns wraps exactly one of
// them, so a caller can tell them apart with errors.Is; the message adds
// where in the file and why.
var (
	ErrRead                = errors.New("cannot read the config file")
	ErrEmpty               = errors.New("the config file is empty")
	ErrSyntax              = errors.New("not a valid forsgren config")
	ErrVersionMissing      = errors.New("version is missing")
	ErrVersionUnsupported  = errors.New("unsupported version")
	ErrNoProjects          = errors.New("no projects")
	ErrProjectName         = errors.New("a project has no name")
	ErrDuplicateProject    = errors.New("duplicate project name")
	ErrNoRepositories      = errors.New("the project has no repositories")
	ErrRepositoryName      = errors.New("not an owner/name repository")
	ErrDuplicateRepository = errors.New("listed twice")
	ErrDeployment          = errors.New("invalid deployment")
)

// Load reads and validates the config file at path. Every error names the
// path first.
func Load(path string) (Config, error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return Config{}, fmt.Errorf("%s: %w: %w", path, ErrRead, err)
	}
	cfg, err := parse(data)
	if err != nil {
		return Config{}, fmt.Errorf("%s: %w", path, err)
	}
	return cfg, nil
}

// RepositoryCount is the number of repositories over all projects.
func (c Config) RepositoryCount() int {
	n := 0
	for _, p := range c.Projects {
		n += len(p.Repositories)
	}
	return n
}

// parse decodes and validates the content of a config file.
func parse(data []byte) (Config, error) {
	file, err := decode(data)
	if err != nil {
		return Config{}, err
	}
	return file.toConfig()
}

// The file as written, before validation. Version is a pointer so a missing
// version is told apart from `version: 0`.
type fileConfig struct {
	Version  *int          `yaml:"version"`
	Projects []fileProject `yaml:"projects"`
}

type fileProject struct {
	Name         string           `yaml:"name"`
	Repositories []fileRepository `yaml:"repositories"`
}

type fileRepository struct {
	Name       string `yaml:"name"`
	Deployment string `yaml:"deployment"`
}

// decode reads exactly one YAML document strictly: an unknown key or a value
// of the wrong kind is ErrSyntax, as is a second document.
func decode(data []byte) (fileConfig, error) {
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var file fileConfig
	err := dec.Decode(&file)
	if errors.Is(err, io.EOF) {
		return file, ErrEmpty
	}
	if err != nil {
		return file, syntaxError(err)
	}
	var next yaml.Node
	if err := dec.Decode(&next); !errors.Is(err, io.EOF) {
		return file, fmt.Errorf("%w: more than one YAML document (---); the config is one", ErrSyntax)
	}
	return file, nil
}

var (
	unknownKey = regexp.MustCompile(`field ([^\s;]+) not found in type [^\s;]+`)
	wrongKind  = regexp.MustCompile(`cannot unmarshal (!!\w+) (.*?) into [^\s;]+`)
)

// syntaxError words a YAML library error for the owner of the file: its line
// numbers kept, the Go type names it mentions dropped.
func syntaxError(err error) error {
	msg := strings.TrimPrefix(err.Error(), "yaml: ")
	var typeErr *yaml.TypeError
	if errors.As(err, &typeErr) {
		msg = strings.Join(typeErr.Errors, "; ")
	}
	msg = unknownKey.ReplaceAllString(msg, `unknown key "$1"`)
	msg = wrongKind.ReplaceAllString(msg, "cannot use $1 $2 here")
	return fmt.Errorf("%w: %s", ErrSyntax, msg)
}
