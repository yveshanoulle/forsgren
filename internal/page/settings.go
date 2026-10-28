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
	"view":                 list(config.ViewStandard, config.ViewNumbers, config.ViewScoring),
	"auto_update":          booleanValues,
	"auto_update_level":    list(config.LevelPatch, config.LevelMinor, config.LevelMajor),
	"history_days":         between(config.MinHistoryDays, config.MaxHistoryDays),
	"history_chunk_days":   upTo(config.MaxHistoryChunkDays),
	"working_hours":        upTo(config.MaxWorkingHours),
	"dora_days":            doraWindows,
	"issues_page":          pageValues,
	"days_page":            pageValues,
	"numbers_scoring_page": pageValues,
	"history_page":         pageValues,
	"tbd_page":             pageValues,
	"tbd_figures":          list(config.TbdFiguresMedian, config.TbdFiguresAll),
	"sub_rows":             booleanValues,
	"week_page":            booleanValues,
	"week_commits":         booleanValues,
	"tbd_time_to_main":     booleanValues,
	"tbd_pr_lead_time":     booleanValues,
	"tbd_bot_pr_lead_time": booleanValues,
	"same_developer":       groupsOfLogins,
	"thousands_separator": list(config.ThousandsNarrowSpace, config.ThousandsComma, config.ThousandsPeriod,
		config.ThousandsNone),
	"decimal_separator": list(config.DecimalPoint, config.DecimalComma),
	// Not top-level keys: the per-repository rows of config.RepositorySettings
	// (forsgren#512), outside the drift test over config.Settings.
	"deployments": "per repository, in projects",
	"paths":       "per service or rule, in projects",
}

// doraWindows are the windows dora_days can name, as the page lists them.
var doraWindows = list(strconv.Itoa(config.DefaultDoraDays), strconv.Itoa(config.DoraDays90),
	strconv.Itoa(config.DoraDays180))

// booleanValues are the values of a boolean key, as the page lists them.
var booleanValues = list(strconv.FormatBool(true), strconv.FormatBool(false))

// pageValues are the values of a page key, as the page lists them (forsgren#200).
var pageValues = list(string(config.PageOn), string(config.PageUnlisted), string(config.PageOff))

// groupsOfLogins is what same_developer takes, as the page lists it
// (forsgren#361).
const groupsOfLogins = "groups of two or more GitHub logins"

// list is names written as the page lists them.
func list(names ...string) string { return strings.Join(names, ", ") }

// upTo is the whole numbers from 1 to most.
func upTo(most int) string { return between(1, most) }

// between is the whole numbers from least to most.
func between(least, most int) string { return fmt.Sprintf("%d to %d", least, most) }

// possibleOf is the values the key accepts, empty for a key the page does
// not know; the drift test holds exactly this list to the config loader.
func possibleOf(key string) string { return possibleValues[key] }
