package page

// The settings page's Possible values column (forsgren#141): what each optional
// key of forsgren.config.yml accepts, as the page shows it, built from the
// config package's own constants so the page cannot drift from what check-config
// accepts (TestPossibleValuesAreExactlyWhatCheckConfigAccepts holds the two
// together).

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// possibleValues are the values each key accepts, by key name.
var possibleValues = map[string]string{
	"view":               list(config.ViewStandard, config.ViewNumbers, config.ViewScoring),
	"auto_update":        list(strconv.FormatBool(true), strconv.FormatBool(false)),
	"auto_update_level":  list(config.LevelPatch, config.LevelMinor, config.LevelMajor),
	"history_days":       upTo(config.MaxHistoryDays),
	"history_chunk_days": upTo(config.MaxHistoryChunkDays),
	"working_hours":      upTo(config.MaxWorkingHours),
}

// list is names written as the page lists them.
func list(names ...string) string { return strings.Join(names, ", ") }

// upTo is the whole numbers from 1 to most.
func upTo(most int) string { return fmt.Sprintf("1 to %d", most) }

// possibleListOf is the values the key accepts, empty for a key the page does
// not know; the drift test holds exactly this list to the config loader.
func possibleListOf(key string) string { return possibleValues[key] }
