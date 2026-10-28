package config

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"go.yaml.in/yaml/v3"
)

// toConfig turns the file as written into a Config, or names the first
// mistake in it: the version first, wherever it stands in the file, then
// the projects and their repositories in file order.
func (f fileConfig) toConfig() (Config, error) {
	if err := checkVersion(f.Version); err != nil {
		return Config{}, err
	}
	cfg := f.settings()
	if f.Projects == nil {
		return Config{}, fmt.Errorf("%w: list at least one under the projects key, or use projects: [] for none",
			ErrNoProjects)
	}
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

// settings is the Config of the file's optional top-level keys (forsgren#46,
// #58, #157, #159, #178): each as written, or its default when the file has
// none; a value forsgren does not accept is a Rejection, and the key's default
// is in force (forsgren#183). dora_days is checked against the history_days in
// force.
func (f fileConfig) settings() Config {
	view, viewRejection := checkView(f.View)
	auto, autoRejection := autoUpdate.value(f.AutoUpdate)
	level, levelRejection := checkAutoUpdateLevel(f.AutoUpdateLevel)
	days, daysRejection := historyDays.check(f.HistoryDays)
	chunk, chunkRejection := historyChunkDays.check(f.HistoryChunkDays)
	hours, hoursRejection := workingHours.check(f.WorkingHours)
	doraDays, doraRejection := checkDoraDays(f.DoraDays, days)
	issues, issuesRejection := issuesPage.mode(f.IssuesPage)
	daysOn, daysOnRejection := daysPage.mode(f.DaysPage)
	numbersScoring, numbersScoringRejection := numbersScoringPage.mode(f.NumbersScoringPage)
	historyOn, historyRejection := historyPage.mode(f.HistoryPage)
	tbdOn, tbdRejection := tbdPage.mode(f.TbdPage)
	figures, figuresRejection := checkTbdFigures(f.TbdFigures)
	groups, groupsRejection := checkSameDeveloper(f.SameDeveloper)
	separator, decimal, separatorRejections := f.separators()
	on, onRejections := f.switches()
	rejected := rejections(append(append([]*Rejection{viewRejection, autoRejection, levelRejection, daysRejection,
		chunkRejection, hoursRejection, doraRejection, issuesRejection, daysOnRejection, numbersScoringRejection,
		historyRejection, tbdRejection, figuresRejection, groupsRejection}, separatorRejections...), onRejections...)...)
	written := f.written(rejected)
	return Config{Version: FormatVersion, View: view, AutoUpdate: auto, AutoUpdateLevel: level,
		HistoryDays: days, HistoryChunkDays: chunk, WorkingHours: hours, WorkingHoursSet: written["working_hours"],
		DoraDays: doraDays, DoraDaysSet: written["dora_days"], IssuesPage: issues, DaysPage: daysOn,
		NumbersScoringPage: numbersScoring, HistoryPage: historyOn, TbdPage: tbdOn,
		TbdFigures: figures, ThousandsSeparator: separator, DecimalSeparator: decimal, SameDeveloper: groups,
		HideTbdTimeToMain: !on.tbdTimeToMain, HideTbdPRLeadTime: !on.tbdPRLeadTime,
		HideTbdBotPRLeadTime: !on.tbdBotPRLeadTime, HideSubRows: !on.subRows,
		HideWeekPage: !on.weekPage, written: written, Rejected: rejected}
}

// rejections are the non-nil rejections, in the order of settingKeys, the
// order of the settings page (forsgren#183).
func rejections(all ...*Rejection) []Rejection {
	var rejected []Rejection
	for _, k := range settingKeys {
		for _, r := range all {
			if r != nil && r.Key == k.key {
				rejected = append(rejected, *r)
			}
		}
	}
	return rejected
}

// written is the optional keys the file gives a value, by key, nil when it
// gives none: a key without a value is none, as for the numbers, and so is a
// key that is rejected, whose default is in force (forsgren#74, #183).
func (f fileConfig) written(rejected []Rejection) map[string]bool {
	var keys map[string]bool
	for key, node := range map[string]yaml.Node{"view": f.View, "auto_update": f.AutoUpdate,
		"auto_update_level": f.AutoUpdateLevel, "history_days": f.HistoryDays,
		"history_chunk_days": f.HistoryChunkDays, "working_hours": f.WorkingHours, "dora_days": f.DoraDays,
		"issues_page": f.IssuesPage, "days_page": f.DaysPage, "numbers_scoring_page": f.NumbersScoringPage,
		"history_page": f.HistoryPage, "tbd_page": f.TbdPage, "tbd_figures": f.TbdFigures,
		"thousands_separator": f.ThousandsSeparator, "decimal_separator": f.DecimalSeparator,
		"same_developer": f.SameDeveloper, "tbd_time_to_main": f.TbdTimeToMain, "tbd_pr_lead_time": f.TbdPRLeadTime,
		"tbd_bot_pr_lead_time": f.TbdBotPRLeadTime, "sub_rows": f.SubRows, "week_page": f.WeekPage} {
		keys = mark(keys, key, hasValue(node))
	}
	for _, r := range rejected {
		delete(keys, r.Key)
	}
	return keys
}

// mark adds key to keys when on, making the map on the first one.
func mark(keys map[string]bool, key string, on bool) map[string]bool {
	if !on {
		return keys
	}
	if keys == nil {
		keys = map[string]bool{}
	}
	keys[key] = true
	return keys
}

// numberKey is a key that is a whole number of a unit, days or hours
// (forsgren#57, #71): its refusal, its unit, its default and its upper limit.
type numberKey struct {
	sentinel error
	key      string
	unit     string
	def      int
	min, max int
}

var (
	historyDays = numberKey{ErrHistoryDays, "history_days", "days", DefaultHistoryDays,
		MinHistoryDays, MaxHistoryDays}
	historyChunkDays = numberKey{ErrHistoryChunkDays, "history_chunk_days", "days",
		DefaultHistoryChunkDays, 1, MaxHistoryChunkDays}
	workingHours = numberKey{ErrWorkingHours, "working_hours", "hours", DefaultWorkingHours, 1, MaxWorkingHours}
)

// hasValue says whether a key has a value: a key left out, or written without
// one, is none.
func hasValue(n yaml.Node) bool { return n.Kind != 0 && n.ShortTag() != "!!null" }

// integer is the node's integer, when it is a YAML integer, never a quoted
// value.
func integer(n yaml.Node) (int, bool) {
	v, err := strconv.Atoi(n.Value)
	return v, err == nil && n.ShortTag() == "!!int"
}

// whole is the node's integer, when it is one from its minimum to the key's limit.
func (k numberKey) whole(n yaml.Node) (int, bool) {
	v, isInt := integer(n)
	return v, isInt && v >= k.min && v <= k.max
}

// check is the key as written, its default when the file has none (a key
// without a value is none): a whole number from its minimum to its limit, never a
// quoted value; otherwise the default and the Rejection (forsgren#183).
func (k numberKey) check(n yaml.Node) (int, *Rejection) {
	if !hasValue(n) {
		return k.def, nil
	}
	if v, ok := k.whole(n); ok {
		return v, nil
	}
	return k.def, refusable{k.sentinel, k.key, strconv.Itoa(k.def)}.reject(n,
		fmt.Sprintf("use a whole number of %s from %d to %d", k.unit, k.min, k.max))
}

// checkDoraDays is dora_days as written, DefaultDoraDays when the file has
// none (a key without a value is none): the integer 30, 90 or 180, never a
// quoted value, and no longer than history_days, which the history must reach
// back; otherwise DefaultDoraDays and the Rejection (forsgren#183). The
// history_days is the one in force, at least MinHistoryDays, so the default
// window always fits (forsgren#178).
func checkDoraDays(n yaml.Node, historyDays int) (int, *Rejection) {
	if !hasValue(n) {
		return DefaultDoraDays, nil
	}
	days, isInt := integer(n)
	if !isInt || !isDoraWindow(days) {
		return DefaultDoraDays, doraDaysKey.reject(n,
			fmt.Sprintf("use %d, %d or %d", DefaultDoraDays, DoraDays90, DoraDays180))
	}
	if days > historyDays {
		return DefaultDoraDays, doraDaysKey.reject(n,
			fmt.Sprintf("history_days is %d, so the history cannot reach back %d days; "+
				"raise history_days to at least %d or use a shorter window", historyDays, days, days))
	}
	return days, nil
}

// doraDaysKey is dora_days as a Rejection names it, DefaultDoraDays in force
// (forsgren#183).
var doraDaysKey = refusable{ErrDoraDays, "dora_days", strconv.Itoa(DefaultDoraDays)}

// isDoraWindow says whether days is one of the windows dora_days can name.
func isDoraWindow(days int) bool {
	return slices.Contains(doraWindows, days)
}

// checkAutoUpdateLevel is the level as written, DefaultLevel when the file has
// none (a key without a value is none), or DefaultLevel and the Rejection
// naming the valid values (forsgren#58, #157, #183).
func checkAutoUpdateLevel(n yaml.Node) (string, *Rejection) {
	if !hasValue(n) {
		return DefaultLevel, nil
	}
	if slices.Contains(levelValues, n.Value) {
		return n.Value, nil
	}
	return DefaultLevel, refusable{ErrAutoUpdateLevel, "auto_update_level", DefaultLevel}.reject(n,
		fmt.Sprintf("use %s, %s or %s", LevelPatch, LevelMinor, LevelMajor))
}

// booleans are the only spellings of a boolean key (forsgren#58).
var booleans = map[string]bool{"true": true, "false": false}

// booleanKey is a key that is true or false (forsgren#58): its refusal and its
// default.
type booleanKey struct {
	sentinel error
	key      string
	def      bool
}

var autoUpdate = booleanKey{ErrAutoUpdate, "auto_update", false}

// value is the key as written, its default when the file has none (a key
// without a value is none): only the literals true and false, never a quoted
// or numeric value, nor yes; the refusal wraps the key's sentinel.
func (k booleanKey) value(n yaml.Node) (bool, *Rejection) {
	if !hasValue(n) {
		return k.def, nil
	}
	on, literal := booleans[n.Value]
	if literal && n.ShortTag() == "!!bool" {
		return on, nil
	}
	return k.def, refusable{k.sentinel, k.key, strconv.FormatBool(k.def)}.reject(n, "use true or false")
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

// checkView is the view as written, empty when the file has none (a key
// without a value is none), or empty and the Rejection naming the valid
// values (forsgren#183).
func checkView(n yaml.Node) (string, *Rejection) {
	if !hasValue(n) {
		return "", nil
	}
	if slices.Contains(viewValues, n.Value) {
		return n.Value, nil
	}
	return "", refusable{ErrView, "view", ViewStandard}.reject(n,
		fmt.Sprintf("use %s, %s or %s", ViewStandard, ViewNumbers, ViewScoring))
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
	repositories, err := p.toRepositories(seen)
	return Project{Name: p.Name, Repositories: repositories}, err
}

// toRepositories checks the project's repositories in file order, and that
// no label of the project is used twice (forsgren#38).
func (p fileProject) toRepositories(seen *names) ([]Repository, error) {
	var out []Repository
	labels := map[string]bool{}
	for _, r := range p.Repositories {
		repo, err := r.toRepository(p.Name, seen)
		if err != nil {
			return nil, err
		}
		if err := claimLabels(labels, repo); err != nil {
			return nil, fmt.Errorf("project %q: repository %q: %w", p.Name, repo.Name, err)
		}
		out = append(out, repo)
	}
	return out, nil
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
	if r.Deployments != nil {
		return r.toRuledRepository(where)
	}
	deployment, err := parseDeployment(r.Deployment)
	if err != nil {
		return Repository{}, fmt.Errorf("%s: %w %q: %w", where, ErrDeployment, r.Deployment, err)
	}
	label, services, err := r.labels(deployment.Kind)
	if err != nil {
		return Repository{}, fmt.Errorf("%s: %w: %w", where, ErrLabel, err)
	}
	return Repository{Name: r.Name, Deployment: deployment, Label: label,
		Services: services.labels, Paths: services.paths}, nil
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
