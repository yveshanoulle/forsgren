package needs

import (
	"os"
	"path/filepath"
	"slices"

	"go.yaml.in/yaml/v3"
)

// Installation is the installation a need is checked against: the checkout
// of its repository, which is the working directory of a metrics run.
type Installation struct {
	Root string
	// ConfigKeys are the top-level keys present in the installation's
	// forsgren.config.yml, read by the caller: this package does not parse
	// the config.
	ConfigKeys []string
	// Getenv reads an environment variable of the metrics run, for a need of
	// kind secret: the caller passes os.Getenv.
	Getenv func(string) string
}

// Missing returns the needs of all that are not in place in the
// installation at, in the order of all.
func Missing(all []Need, at Installation) []Need {
	var missing []Need
	for _, n := range all {
		if !inPlace(n, at) {
			missing = append(missing, n)
		}
	}
	return missing
}

// checks maps each kind this version checks to the check that decides whether
// a need of that kind is in place. It is the one list of known kinds: For
// refuses a declaration of a kind absent from it.
var checks = map[string]func(n Need, at Installation) bool{
	"file":       fileInPlace,
	"config_key": configKeyInPlace,
	"permission": permissionInPlace,
	"secret":     secretInPlace,
}

// inPlace reports whether the need n is in place in the installation at,
// by the check for its kind. A kind with no check is not in place, a safety
// net behind For, which refuses such a declaration, so that no need passes
// unchecked.
func inPlace(n Need, at Installation) bool {
	check, ok := checks[n.Kind]
	return ok && check(n, at)
}

// fileInPlace reports whether the file of the need n can be stat-ed in the
// checkout; any stat failure, not only a file that does not exist, counts as
// not in place, since the installation cannot show the file.
func fileInPlace(n Need, at Installation) bool {
	return fileExists(filepath.Join(at.Root, n.File))
}

// configKeyInPlace reports whether the key of the need n is among the
// top-level keys of the installation's config.
func configKeyInPlace(n Need, at Installation) bool {
	return slices.Contains(at.ConfigKeys, n.Key)
}

// secretInPlace reports whether the environment variable of the need n is
// set and non-empty in the metrics run. Getenv must be set.
func secretInPlace(n Need, at Installation) bool {
	return at.Getenv(n.Secret) != ""
}

// fileExists reports whether path can be stat-ed.
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// workflowFile is the part of a workflow that a permission need reads: the
// permissions of each job, as written at job level.
type workflowFile struct {
	Jobs map[string]struct {
		Permissions map[string]string `yaml:"permissions"`
	} `yaml:"jobs"`
}

// permissionInPlace reports whether a job of the workflow of the need n
// grants its permission at its access, or write for a need of read. A
// workflow that cannot be read or parsed is not in place.
func permissionInPlace(n Need, at Installation) bool {
	data, err := os.ReadFile(filepath.Join(at.Root, n.Workflow))
	var wf workflowFile
	return err == nil && yaml.Unmarshal(data, &wf) == nil && grantsPermission(wf, n)
}

// grantsPermission reports whether some job of wf grants the permission of
// the need n at its access, or write when the access is read.
func grantsPermission(wf workflowFile, n Need) bool {
	for _, job := range wf.Jobs {
		if grants(job.Permissions[n.Permission], n.Access) {
			return true
		}
	}
	return false
}

// grants reports whether a grant at level gives access: the same level, or
// write for read.
func grants(level, access string) bool {
	if level == access {
		return true
	}
	return access == "read" && level == "write"
}
