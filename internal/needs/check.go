package needs

import (
	"os"
	"path/filepath"
)

// Installation is the installation a need is checked against: the checkout
// of its repository, which is the working directory of a metrics run.
type Installation struct {
	Root string
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

// inPlace reports whether the need n is in place in the installation at. A
// need of kind file is in place when its file can be stat-ed in the checkout;
// any stat failure, not only a file that does not exist, counts as not in
// place, since the installation cannot show the file. A kind this version does
// not check is not in place either, so that no need passes unchecked.
func inPlace(n Need, at Installation) bool {
	return n.Kind == "file" && fileExists(filepath.Join(at.Root, n.File))
}

// fileExists reports whether path can be stat-ed.
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
