package config

// The tbd_figures key (forsgren#423): which figures the TBD table shows for
// each measure, the median alone or the mean, the median and the 90th
// percentile.

import (
	"slices"

	"go.yaml.in/yaml/v3"
)

// tbdFiguresValues are the values tbd_figures accepts, in the order the
// settings page lists them.
var tbdFiguresValues = []string{TbdFiguresMedian, TbdFiguresAll}

// tbdFiguresKey is tbd_figures as a Rejection names it, DefaultTbdFigures in
// force.
var tbdFiguresKey = refusable{ErrTbdFigures, "tbd_figures", DefaultTbdFigures}

// checkTbdFigures is tbd_figures as written, DefaultTbdFigures when the file
// has none (a key without a value is none), or DefaultTbdFigures and the
// Rejection naming the valid values.
func checkTbdFigures(n yaml.Node) (string, *Rejection) {
	if !hasValue(n) {
		return DefaultTbdFigures, nil
	}
	if n.Kind == yaml.ScalarNode && slices.Contains(tbdFiguresValues, n.Value) {
		return n.Value, nil
	}
	return DefaultTbdFigures, tbdFiguresKey.reject(n, "use "+TbdFiguresMedian+" or "+TbdFiguresAll)
}
