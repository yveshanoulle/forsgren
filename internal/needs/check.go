package needs

// Installation is the installation a need is checked against: the checkout
// of its repository, which is the working directory of a metrics run.
type Installation struct {
	Root string
}

// Missing returns the needs of all that are not in place in the
// installation at.
func Missing(all []Need, at Installation) []Need {
	return nil
}
