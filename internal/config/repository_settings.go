package config

import "fmt"

// notSetDefault is the Default column of the two repository settings.
const notSetDefault = "not set"

// RepositorySettings are the two settings that live on a repository, not at
// the top of the file, as the settings page shows them (forsgren#512):
// `deployments` and `paths`. They are not in Settings, whose keys are the
// file's top-level keys, so the drift tests over Settings stay about those.
// The Value says only how many are set, never a name, label, path,
// environment or workflow of a repository, because the page is public; it is
// empty when none is set.
func (c Config) RepositorySettings() []Setting {
	var t repositoryTotals
	for _, p := range c.Projects {
		for _, r := range p.Repositories {
			t.add(r)
		}
	}
	return []Setting{
		repositorySetting("deployments", deploymentsCount(t.repositories, t.rules)),
		repositorySetting("paths", pathsCount(t.services, t.rulesWithPaths)),
	}
}

// repositoryTotals are the counts the two settings say.
type repositoryTotals struct{ repositories, rules, services, rulesWithPaths int }

// add counts one repository.
func (t *repositoryTotals) add(r Repository) {
	if len(r.Rules) > 0 {
		t.repositories++
		t.rules += len(r.Rules)
	}
	t.services += len(r.Paths)
	for _, rule := range r.Rules {
		if len(rule.Paths) > 0 {
			t.rulesWithPaths++
		}
	}
}

// repositorySetting is a setting with the count sentence as its value.
func repositorySetting(key, value string) Setting {
	return Setting{Key: key, Value: value, Default: notSetDefault, Set: value != ""}
}

// deploymentsCount is the sentence for repositories written with
// `deployments:`, empty for none.
func deploymentsCount(repositories, rules int) string {
	if repositories == 0 {
		return ""
	}
	return fmt.Sprintf("set on %s (%s)",
		counted(repositories, "repository", "repositories"), counted(rules, "rule", "rules"))
}

// pathsCount is the sentence for services and rules that have paths, empty
// for none.
func pathsCount(services, rules int) string {
	switch {
	case services > 0 && rules > 0:
		return fmt.Sprintf("set on %s and %s", counted(services, "service", "services"), counted(rules, "rule", "rules"))
	case services > 0:
		return "set on " + counted(services, "service", "services")
	case rules > 0:
		return "set on " + counted(rules, "rule", "rules")
	}
	return ""
}

// counted is n with the singular or plural noun.
func counted(n int, one, many string) string {
	if n == 1 {
		return fmt.Sprintf("%d %s", n, one)
	}
	return fmt.Sprintf("%d %s", n, many)
}
