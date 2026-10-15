// Package config reads and validates an installation's forsgren.config.yml:
// which repositories forsgren measures, grouped into projects, and what
// counts as a deployment of each (forsgren#6).
//
// The file is what an installation's owner owns, next to data/ (forsgren#4),
// so every mistake in it is refused by name, never skipped: an unknown key
// is an error (a typo must not silently do nothing), and so is a missing or
// other format version.
//
// The format, version 1:
//
//	version: 1
//	view: numbers                          # optional, standard, numbers or scoring
//	auto_update: true                      # optional, true or false, off when absent (forsgren#58)
//	auto_update_level: patch               # optional, patch, minor or major, major when absent (forsgren#157)
//	projects:
//	  - name: Acme
//	    repositories:
//	      - name: acme/app                 # owner/name on GitHub
//	        deployment: release            # optional, see Deployment
//	        label: App                     # optional, see labels.go
//
// An installation that measures nothing yet writes `projects: []`; a file
// whose projects key is missing or has no value is refused, so a forgotten
// list is never taken for an empty one (forsgren#12).
package config

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

// FormatVersion is the one config format version this forsgren reads. A
// file of any other version, or of none, is refused: a change to the format
// gets a new version, so an old forsgren never misreads a newer file.
const FormatVersion = 1

// The views the root page can show (forsgren#46, #47): the standard cells,
// the numbers only, and each metric's DORA Quick Check score.
const (
	ViewStandard = "standard"
	ViewNumbers  = "numbers"
	ViewScoring  = "scoring"
)

// The levels auto_update_level can name (forsgren#58): the largest step of
// a forsgren update that merges itself.
const (
	LevelPatch = "patch"
	LevelMinor = "minor"
	LevelMajor = "major"

	// DefaultLevel is the level used when the file writes none (forsgren#157).
	DefaultLevel = LevelMajor
)

// The days the first run collects (forsgren#57): the default, and the most
// history_days can name (five years).
const (
	DefaultHistoryDays = 365
	MinHistoryDays     = 30
	MaxHistoryDays     = 1825
)

// The days each run adds until history_days is reached (forsgren#57): the
// default, and the most history_chunk_days can name.
const (
	DefaultHistoryChunkDays = 100
	MaxHistoryChunkDays     = 365
)

// The hours of a working day (forsgren#71): the default, and the most
// working_hours can name.
const (
	DefaultWorkingHours = 8
	MaxWorkingHours     = 24
)

// The days the DORA numbers count back (forsgren#178): the default, and the
// two longer windows dora_days can name besides it.
const (
	DefaultDoraDays = 30
	DoraDays90      = 90
	DoraDays180     = 180
)

// DoraWindow is the DORA window in days for a DoraDays value: days, or
// DefaultDoraDays when it is 0, as in a Config that was not loaded from a
// file (forsgren#178).
func DoraWindow(days int) int {
	if days == 0 {
		return DefaultDoraDays
	}
	return days
}

// DefaultEnvironment is the GitHub environment a repository deploys to when
// its config names no deployment.
const DefaultEnvironment = "production"

// DeploymentKind says what counts as a deployment of a repository.
type DeploymentKind int

// The three deployment forms of config v1 (Yves's ruling on forsgren#6).
const (
	// Environment: a GitHub Deployment to the named environment whose
	// status is success. `environment=<name>`; the default, with
	// DefaultEnvironment, when a repository names no deployment.
	Environment DeploymentKind = iota + 1
	// Workflow: a successful run on main of the named workflow file.
	// `workflow=<file>.yml` (or .yaml).
	Workflow
	// Release: a published GitHub Release (App Store apps, tools).
	// `release`.
	Release
)

// Deployment is one repository's deployment definition.
type Deployment struct {
	Kind DeploymentKind
	// Name is the environment for Environment, the workflow file name for
	// Workflow, and empty for Release.
	Name string
}

// Repository is one measured GitHub repository.
type Repository struct {
	// Name is owner/name, as written in the file.
	Name       string
	Deployment Deployment
	// Label names the repository's row under its project; empty for none
	// (forsgren#38).
	Label string
	// Services maps a deployment task to the label of its row under the
	// project; nil for none (forsgren#38).
	Services map[string]string
}

// Project groups the repositories that ship one product; the page shows
// each project's metrics in its own section (forsgren#6).
type Project struct {
	Name         string
	Repositories []Repository
}

// Config is a validated forsgren.config.yml.
type Config struct {
	Version int
	// View is the view the site's root page shows, as written: "standard",
	// "numbers" or "scoring", empty when the file has no view key
	// (forsgren#46).
	View string
	// AutoUpdate is whether the merge workflow for Dependabot's forsgren pin
	// updates is on (forsgren#58); off when the file has no auto_update key.
	AutoUpdate bool
	// AutoUpdateLevel is how far an update may go before it merges itself,
	// as written: "patch", "minor" or "major", empty when the file has no
	// auto_update_level key (forsgren#58).
	AutoUpdateLevel string
	// HistoryDays is how many days of history are collected, 365 when the
	// file has no history_days key (forsgren#57).
	HistoryDays int
	// HistoryChunkDays is how many days back each run adds until HistoryDays
	// is reached, 100 when the file has no history_chunk_days key
	// (forsgren#57).
	HistoryChunkDays int
	// WorkingHours is how many hours a working day is, 8 when the file has
	// no working_hours key (forsgren#71).
	WorkingHours int
	// WorkingHoursSet says whether the file has a working_hours key, so the
	// legend can tell a configured day from the default (forsgren#71).
	WorkingHoursSet bool
	// DoraDays is how many days the DORA numbers count back, 30 when the file
	// has no dora_days key (forsgren#178).
	DoraDays int
	// DoraDaysSet says whether the file has an accepted dora_days key, so the
	// legend can tell a configured window from the default (forsgren#178).
	DoraDaysSet bool
	// IssuesPage is whether the issues page is generated, true when the file
	// has no issues_page key (forsgren#159).
	IssuesPage bool
	// DaysPage is whether the days page (Daily) is generated, false when the
	// file has no days_page key (forsgren#159).
	DaysPage bool
	// NumbersScoringPage is whether the numbers and scoring page is
	// generated, false when the file has no numbers_scoring_page key
	// (forsgren#55).
	NumbersScoringPage bool
	// written is the optional keys the file writes, by key (forsgren#74).
	written  map[string]bool
	Projects []Project
	// Rejected are the settings the file writes that are not accepted, in the
	// order of the settings page (settingKeys); the default is in force for
	// each (forsgren#183).
	Rejected []Rejection
}

// Rejection is one setting the file writes that forsgren does not accept: its
// key, the value as written, why not, and the default used instead. Its
// message is the refusal's it was before forsgren#183, and it unwraps to the
// key's Err sentinel.
type Rejection struct {
	Key, Written, Reason, Default string
	sentinel                      error
}

// Error is `invalid <key> "<written>": <reason>`.
func (r *Rejection) Error() string {
	return fmt.Sprintf("%v %q: %s", r.sentinel, r.Written, r.Reason)
}

// refusable is one setting as a Rejection names it: its Err sentinel, its key
// and its default as the settings page writes it.
type refusable struct {
	sentinel error
	key, def string
}

// reject is the rejection of the setting written as n, for the reason, with
// its default in force instead (forsgren#183).
func (s refusable) reject(n yaml.Node, reason string) *Rejection {
	return &Rejection{Key: s.key, Written: writtenOf(n), Reason: reason, Default: s.def, sentinel: s.sentinel}
}

// Unwrap is the key's Err sentinel.
func (r *Rejection) Unwrap() error { return r.sentinel }

// The refusals Load names. Each error Load returns wraps exactly one of
// them, so a caller can tell them apart with errors.Is; the message adds
// where in the file and why.
var (
	ErrRead                = errors.New("cannot read the config file")
	ErrEmpty               = errors.New("the config file is empty")
	ErrSyntax              = errors.New("not a valid forsgren config")
	ErrVersionMissing      = errors.New("version is missing")
	ErrVersionUnsupported  = errors.New("unsupported version")
	ErrNoProjects          = errors.New("no projects")
	ErrProjectName         = errors.New("a project has no name")
	ErrDuplicateProject    = errors.New("duplicate project name")
	ErrNoRepositories      = errors.New("the project has no repositories")
	ErrRepositoryName      = errors.New("not an owner/name repository")
	ErrDuplicateRepository = errors.New("listed twice")
	ErrDeployment          = errors.New("invalid deployment")
	ErrLabel               = errors.New("invalid label")
	ErrView                = errors.New("invalid view")
	ErrAutoUpdate          = errors.New("invalid auto_update")
	ErrAutoUpdateLevel     = errors.New("invalid auto_update_level")
	ErrHistoryDays         = errors.New("invalid history_days")
	ErrHistoryChunkDays    = errors.New("invalid history_chunk_days")
	ErrWorkingHours        = errors.New("invalid working_hours")
	ErrDoraDays            = errors.New("invalid dora_days")
	ErrIssuesPage          = errors.New("invalid issues_page")
	ErrDaysPage            = errors.New("invalid days_page")
	ErrNumbersScoringPage  = errors.New("invalid numbers_scoring_page")
)

// Load reads and validates the config file at path. Every error names the
// path first.
func Load(path string) (Config, error) {
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return Config{}, fmt.Errorf("%s: %w: %w", path, ErrRead, err)
	}
	cfg, err := parse(data)
	if err != nil {
		return Config{}, fmt.Errorf("%s: %w", path, err)
	}
	return cfg, nil
}

// RepositoryCount is the number of repositories over all projects.
func (c Config) RepositoryCount() int {
	n := 0
	for _, p := range c.Projects {
		n += len(p.Repositories)
	}
	return n
}

// parse decodes and validates the content of a config file.
func parse(data []byte) (Config, error) {
	file, err := decode(data)
	if err != nil {
		return Config{}, err
	}
	return file.toConfig()
}

// The file as written, before validation. Version is a pointer so a missing
// version is told apart from `version: 0`; Projects is nil for a missing key
// or a null value and empty but not nil for `projects: []`.
type fileConfig struct {
	Version    *int      `yaml:"version"`
	View       yaml.Node `yaml:"view"`
	AutoUpdate yaml.Node `yaml:"auto_update"`
	// AutoUpdateLevel is the node as written, like AutoUpdate, so a list or
	// mapping is not accepted by name, not refused as syntax (forsgren#183).
	AutoUpdateLevel yaml.Node `yaml:"auto_update_level"`
	// HistoryDays is the node as written, so a non-integer is refused by name.
	HistoryDays yaml.Node `yaml:"history_days"`
	// HistoryChunkDays is the node as written, like HistoryDays.
	HistoryChunkDays yaml.Node `yaml:"history_chunk_days"`
	// WorkingHours is the node as written, like HistoryDays (forsgren#71).
	WorkingHours yaml.Node `yaml:"working_hours"`
	// DoraDays is the node as written, like HistoryDays (forsgren#178).
	DoraDays yaml.Node `yaml:"dora_days"`
	// IssuesPage, DaysPage and NumbersScoringPage are the nodes as written,
	// so a non-boolean is refused by name (forsgren#159, forsgren#55).
	IssuesPage         yaml.Node     `yaml:"issues_page"`
	DaysPage           yaml.Node     `yaml:"days_page"`
	NumbersScoringPage yaml.Node     `yaml:"numbers_scoring_page"`
	Projects           []fileProject `yaml:"projects"`
}

type fileProject struct {
	Name         string           `yaml:"name"`
	Repositories []fileRepository `yaml:"repositories"`
}

type fileRepository struct {
	Name       string        `yaml:"name"`
	Deployment string        `yaml:"deployment"`
	Label      *text         `yaml:"label"`
	Services   map[text]text `yaml:"services"`
}

// decode reads exactly one YAML document strictly: an unknown key or a value
// of the wrong kind is ErrSyntax, as is a second document.
func decode(data []byte) (fileConfig, error) {
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var file fileConfig
	err := dec.Decode(&file)
	if errors.Is(err, io.EOF) {
		return file, ErrEmpty
	}
	if err != nil {
		return file, syntaxError(err)
	}
	var next yaml.Node
	if err := dec.Decode(&next); !errors.Is(err, io.EOF) {
		return file, fmt.Errorf("%w: more than one YAML document (---); the config is one", ErrSyntax)
	}
	return file, nil
}

// The YAML library's wordings of one reason, matched across line breaks: a
// key or a value in the file can hold one, a space or a semicolon.
var (
	unknownKey = regexp.MustCompile(`(?s)field (.+) not found in type [^\s;]+`)
	wrongKind  = regexp.MustCompile(`(?s)cannot unmarshal (!!\w+) (.*) into [^\s;]+`)
)

// syntaxError words a YAML library error for the owner of the file: its line
// numbers kept, the Go type names it mentions dropped, and on one line, a
// line break the file put in it written as \n. check-config prints it into
// a workflow log, where a line that starts with :: would run as a workflow
// command (forsgren#9).
func syntaxError(err error) error {
	reasons := []string{strings.TrimPrefix(err.Error(), "yaml: ")}
	var typeErr *yaml.TypeError
	if errors.As(err, &typeErr) {
		reasons = typeErr.Errors
	}
	worded := make([]string, len(reasons))
	for i, reason := range reasons {
		worded[i] = ownerWords(reason)
	}
	msg := strings.Join(worded, "; ")
	msg = strings.ReplaceAll(strings.ReplaceAll(msg, "\r", `\r`), "\n", `\n`)
	return fmt.Errorf("%w: %s", ErrSyntax, msg)
}

// ownerWords rewords one reason of the YAML library without Go's type names:
// an unknown key, quoted as Go quotes a string, and a value of the wrong kind.
func ownerWords(reason string) string {
	if m := unknownKey.FindStringSubmatch(reason); m != nil {
		return strings.Replace(reason, m[0], "unknown key "+strconv.Quote(m[1]), 1)
	}
	return wrongKind.ReplaceAllString(reason, "cannot use $1 $2 here")
}

// Setting is one optional key of the file with the value forsgren uses
// (forsgren#74): Set says whether the file writes the key, Value is its
// default when it does not. A key the file writes with a value forsgren does
// not accept is not Set: Value is the default in force, Written is the value
// as written and Reason says why it is not accepted (forsgren#183); both are
// empty for any other key.
type Setting struct {
	Key, Value      string
	Set             bool
	Written, Reason string
}

// settingKey is one optional key: its name, its default as written in the
// legend and the value of a Config as written (forsgren#74).
type settingKey struct {
	key, def string
	value    func(Config) string
}

// settingKeys is the one list of optional keys, in the order Settings gives
// them, so a new key is listed by adding it here.
var settingKeys = []settingKey{
	{"view", ViewStandard, func(c Config) string { return c.View }},
	{"auto_update", "false", func(c Config) string { return strconv.FormatBool(c.AutoUpdate) }},
	{"auto_update_level", DefaultLevel, func(c Config) string { return c.AutoUpdateLevel }},
	{"history_days", strconv.Itoa(DefaultHistoryDays), func(c Config) string { return strconv.Itoa(c.HistoryDays) }},
	{"history_chunk_days", strconv.Itoa(DefaultHistoryChunkDays),
		func(c Config) string { return strconv.Itoa(c.HistoryChunkDays) }},
	{"working_hours", strconv.Itoa(DefaultWorkingHours), func(c Config) string { return strconv.Itoa(c.WorkingHours) }},
	{"dora_days", strconv.Itoa(DefaultDoraDays), func(c Config) string { return strconv.Itoa(c.DoraDays) }},
	{"issues_page", "true", func(c Config) string { return strconv.FormatBool(c.IssuesPage) }},
	{"days_page", "false", func(c Config) string { return strconv.FormatBool(c.DaysPage) }},
	{"numbers_scoring_page", "false", func(c Config) string { return strconv.FormatBool(c.NumbersScoringPage) }},
}

// Settings lists every optional key in the order of settingKeys: the value
// the file writes, or the default for a key it leaves out or does not accept;
// a rejected key also carries the value as written and the reason
// (forsgren#74, #183).
func (c Config) Settings() []Setting {
	list := make([]Setting, len(settingKeys))
	for i, k := range settingKeys {
		list[i] = c.setting(k)
	}
	return list
}

// setting is the Setting of one optional key.
func (c Config) setting(k settingKey) Setting {
	s := Setting{Key: k.key, Value: k.def, Set: c.written[k.key]}
	if s.Set {
		s.Value = k.value(c)
	}
	for _, r := range c.Rejected {
		if r.Key == k.key {
			s.Written, s.Reason = r.Written, r.Reason
		}
	}
	return s
}
