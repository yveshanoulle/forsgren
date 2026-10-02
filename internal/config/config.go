// Package config reads and validates an installation's forsgren.config.yml.
package config

import "errors"

// FormatVersion is the one config format version this forsgren reads.
const FormatVersion = 1

// DefaultEnvironment is the GitHub environment a repository deploys to when
// its config names no deployment.
const DefaultEnvironment = "production"

// DeploymentKind says what counts as a deployment of a repository.
type DeploymentKind int

// The three deployment forms of config v1 (forsgren#6).
const (
	Environment DeploymentKind = iota + 1
	Workflow
	Release
)

// Deployment is one repository's deployment definition.
type Deployment struct {
	Kind DeploymentKind
	Name string
}

// Repository is one measured GitHub repository.
type Repository struct {
	Name       string
	Deployment Deployment
}

// Project groups repositories.
type Project struct {
	Name         string
	Repositories []Repository
}

// Config is a validated forsgren.config.yml.
type Config struct {
	Version  int
	Projects []Project
}

// The refusals Load names.
var (
	ErrRead                = errors.New("stub")
	ErrEmpty               = errors.New("stub")
	ErrSyntax              = errors.New("stub")
	ErrVersionMissing      = errors.New("stub")
	ErrVersionUnsupported  = errors.New("stub")
	ErrNoProjects          = errors.New("stub")
	ErrProjectName         = errors.New("stub")
	ErrDuplicateProject    = errors.New("stub")
	ErrNoRepositories      = errors.New("stub")
	ErrRepositoryName      = errors.New("stub")
	ErrDuplicateRepository = errors.New("stub")
	ErrDeployment          = errors.New("stub")
)

var errNotImplemented = errors.New("config: not implemented yet")

// Load reads and validates the config file at path.
func Load(path string) (Config, error) {
	return parse([]byte(path))
}

func parse(data []byte) (Config, error) {
	_ = data
	return Config{}, errNotImplemented
}

// RepositoryCount is the number of repositories over all projects.
func (c Config) RepositoryCount() int {
	return 0
}
