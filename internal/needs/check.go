package needs

import (
	"os"
	"path/filepath"
	"slices"
)

// Installation is the installation a need is checked against: the checkout
// of its repository, which is the working directory of a metrics run.
type Installation struct {
	Root string
	// ConfigKeys are the top-level keys present in the installation's
	// forsgren.config.yml, read by the caller: this package does not parse
	// the config.
	ConfigKeys []string
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
// a need of that kind is in place. A kind absent from it is not checked.
var checks = map[string]func(n Need, at Installation) bool{
	"file":       fileInPlace,
	"config_key": configKeyInPlace,
}

// inPlace reports whether the need n is in place in the installation at,
// by the check for its kind. A kind this version does not check is not in
// place, so that no need passes unchecked.
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

// fileExists reports whether path can be stat-ed.
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
