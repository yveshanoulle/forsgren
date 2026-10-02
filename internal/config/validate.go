package config

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// toConfig turns the file as written into a Config, or names the first
// mistake in it: the version first, wherever it stands in the file, then
// the projects and their repositories in file order.
func (f fileConfig) toConfig() (Config, error) {
	if err := checkVersion(f.Version); err != nil {
		return Config{}, err
	}
	if len(f.Projects) == 0 {
		return Config{}, fmt.Errorf("%w: list at least one under the projects key", ErrNoProjects)
	}
	cfg := Config{Version: FormatVersion}
	seen := names{projects: map[string]listedProject{}, repositories: map[string]string{}}
	for i, p := range f.Projects {
		project, err := p.toProject(i+1, &seen)
		if err != nil {
			return Config{}, err
		}
		cfg.Projects = append(cfg.Projects, project)
	}
	return cfg, nil
}

func checkVersion(v *int) error {
	if v == nil {
		return fmt.Errorf("%w: write version: %d at the top of the file", ErrVersionMissing, FormatVersion)
	}
	if *v != FormatVersion {
		return fmt.Errorf("%w %d: this forsgren reads version %d", ErrVersionUnsupported, *v, FormatVersion)
	}
	return nil
}

// names holds the names already used in the file, compared ignoring case
// (GitHub's repository names are case-insensitive, and two projects whose
// names differ only in case would read as one on the page).
type names struct {
	projects     map[string]listedProject // lower-cased project name → the project first listed under it
	repositories map[string]string        // lower-cased owner/name → the project that lists it
}

// listedProject is a project name as written, and its 1-based position.
type listedProject struct {
	n    int
	name string
}

// claimProject records the name of the project at 1-based position n, or
// refuses it when an earlier project has it.
func (seen *names) claimProject(n int, name string) error {
	key := strings.ToLower(name)
	if first, ok := seen.projects[key]; ok {
		return fmt.Errorf("project %d %q: %w, the same as project %d %q (case is ignored)",
			n, name, ErrDuplicateProject, first.n, first.name)
	}
	seen.projects[key] = listedProject{n: n, name: name}
	return nil
}

// claimRepository records that the named project lists the repository, or
// refuses it when a project already does; the caller says where.
func (seen *names) claimRepository(project, repository string) error {
	key := strings.ToLower(repository)
	if first, ok := seen.repositories[key]; ok {
		return fmt.Errorf("%w, first in project %q (case is ignored)", ErrDuplicateRepository, first)
	}
	seen.repositories[key] = project
	return nil
}

// toProject checks the project at 1-based position n.
func (p fileProject) toProject(n int, seen *names) (Project, error) {
	if strings.TrimSpace(p.Name) == "" {
		return Project{}, fmt.Errorf("project %d: %w", n, ErrProjectName)
	}
	if err := seen.claimProject(n, p.Name); err != nil {
		return Project{}, err
	}
	if len(p.Repositories) == 0 {
		return Project{}, fmt.Errorf("project %q: %w", p.Name, ErrNoRepositories)
	}
	project := Project{Name: p.Name}
	for _, r := range p.Repositories {
		repo, err := r.toRepository(p.Name, seen)
		if err != nil {
			return Project{}, err
		}
		project.Repositories = append(project.Repositories, repo)
	}
	return project, nil
}

// repositoryName is GitHub's owner/name: an owner of letters, digits and
// hyphens, a repository name of letters, digits, '.', '_' and '-'.
var repositoryName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$`)

// isRepositoryName says whether s is one owner/name; the name . or .. is
// not a repository.
func isRepositoryName(s string) bool {
	return repositoryName.MatchString(s) && !strings.HasSuffix(s, "/.") && !strings.HasSuffix(s, "/..")
}

// toRepository checks one repository of the named project.
func (r fileRepository) toRepository(project string, seen *names) (Repository, error) {
	where := fmt.Sprintf("project %q: repository %q", project, r.Name)
	if !isRepositoryName(r.Name) {
		return Repository{}, fmt.Errorf("%s: %w such as acme/app", where, ErrRepositoryName)
	}
	if err := seen.claimRepository(project, r.Name); err != nil {
		return Repository{}, fmt.Errorf("%s: %w", where, err)
	}
	deployment, err := parseDeployment(r.Deployment)
	if err != nil {
		return Repository{}, fmt.Errorf("%s: %w %q: %w", where, ErrDeployment, r.Deployment, err)
	}
	return Repository{Name: r.Name, Deployment: deployment}, nil
}

var (
	errDeploymentForm = errors.New("use environment=<name>, workflow=<file>.yml or .yaml, or release")
	errEnvironment    = errors.New("the environment has no name")
	errWorkflowFile   = errors.New("the workflow file must end in .yml or .yaml")
	errWorkflowDir    = errors.New("the workflow is a file name in .github/workflows, without a directory")
)

// parseDeployment reads one of the three forms; no deployment (the key
// left out, or empty) is the default, the environment production.
func parseDeployment(s string) (Deployment, error) {
	if s == "" {
		return Deployment{Kind: Environment, Name: DefaultEnvironment}, nil
	}
	if s == "release" {
		return Deployment{Kind: Release}, nil
	}
	if env, ok := strings.CutPrefix(s, "environment="); ok {
		return environment(env)
	}
	if file, ok := strings.CutPrefix(s, "workflow="); ok {
		return workflow(file)
	}
	return Deployment{}, errDeploymentForm
}

func environment(name string) (Deployment, error) {
	if strings.TrimSpace(name) == "" {
		return Deployment{}, errEnvironment
	}
	return Deployment{Kind: Environment, Name: name}, nil
}

func workflow(file string) (Deployment, error) {
	if strings.Contains(file, "/") {
		return Deployment{}, errWorkflowDir
	}
	stem := strings.TrimSuffix(strings.TrimSuffix(file, ".yml"), ".yaml")
	if stem == file || stem == "" {
		return Deployment{}, errWorkflowFile
	}
	return Deployment{Kind: Workflow, Name: file}, nil
}
