package config

import (
	"reflect"
	"testing"
	"time"
)

// The stored deployments a repository takes back (forsgren#667): a list of
// {task, before}, before optional.

// withExclude is valid with extra lines added to its repository.
func withExclude(extra string) string { return withLabels(extra) }

const twoExclusions = "        exclude:\n" +
	"          - task: beta-upload\n" +
	"            before: 2026-06-01T00:00:00Z\n" +
	"          - task: \"old-beta\"\n"

// TestExcludeIsReadWithItsOptionalBefore: each exclusion keeps its task and
// its before as a time, zero when it is left out, in file order.
func TestExcludeIsReadWithItsOptionalBefore(t *testing.T) {
	got, err := parse([]byte(withExclude(twoExclusions)))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	want := []Exclusion{
		{Task: "beta-upload", Before: time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)},
		{Task: "old-beta"},
	}
	if r := got.Projects[0].Repositories[0]; !reflect.DeepEqual(r.Exclude, want) {
		t.Errorf("want exclusions %+v, got %+v", want, r.Exclude)
	}
}

// TestExcludeIsReadOnARepositoryWithDeploymentRules: the `deployments:` form
// takes exclusions too.
func TestExcludeIsReadOnARepositoryWithDeploymentRules(t *testing.T) {
	got, err := parse([]byte(withDeployments(twoRules + "        exclude:\n          - task: old-beta\n")))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	if r := got.Projects[0].Repositories[0]; !reflect.DeepEqual(r.Exclude, []Exclusion{{Task: "old-beta"}}) {
		t.Errorf("want the exclusion of old-beta, got %+v", r.Exclude)
	}
}

// exclusionOf is valid with one exclusion of task deploy, before written as
// value.
func exclusionOf(value string) string {
	return withExclude("        exclude:\n          - task: deploy\n            before: " + value + "\n")
}

// TestExcludeRefusesABeforeThatIsNoRFC3339Time: a date alone, a time without
// its zone, words, a number and a list fail Load by name, naming the
// repository and the task.
func TestExcludeRefusesABeforeThatIsNoRFC3339Time(t *testing.T) {
	where := `project "Acme": repository "acme/app": invalid exclude: task "deploy": before `
	checkRefusals(t, []refusal{
		{"date alone", exclusionOf("2026-06-01"), ErrExclude,
			where + `"2026-06-01" is not an RFC 3339 time such as 2026-06-01T00:00:00Z`},
		{"no zone", exclusionOf(`"2026-06-01T00:00:00"`), ErrExclude, where + `"2026-06-01T00:00:00" is not`},
		{"words", exclusionOf("yesterday"), ErrExclude, where + `"yesterday" is not`},
		{"number", exclusionOf("20260601"), ErrExclude, where + `"20260601" is not`},
		{"list", exclusionOf("[2026-06-01T00:00:00Z]"), ErrExclude, where + `"[2026-06-01T00:00:00Z]" is not`},
	})
}

// TestExcludeRefusesAnExclusionWithoutATask: a task left out, empty or of
// blanks fails Load by name; a key other than task and before, a task that is
// no text and an exclude that is no list are syntax errors.
func TestExcludeRefusesAnExclusionWithoutATask(t *testing.T) {
	where := `project "Acme": repository "acme/app": invalid exclude: task "`
	checkRefusals(t, []refusal{
		{"no task", withExclude("        exclude:\n          - before: 2026-06-01T00:00:00Z\n"), ErrExclude,
			where + `": a task is empty`},
		{"empty task", withExclude("        exclude:\n          - task: \"\"\n"), ErrExclude, where + `": a task is empty`},
		{"blank task", withExclude("        exclude:\n          - task: \" \"\n"), ErrExclude, where + ` ": a task is empty`},
		{"unknown key", withExclude("        exclude:\n          - task: a\n            after: x\n"), ErrSyntax,
			`line 9: unknown key "after"`},
		{"task a number", withExclude("        exclude:\n          - task: 5\n"), ErrSyntax,
			"line 8: cannot use !!int `5` here: labels and tasks are text"},
		{"exclude a mapping", withExclude("        exclude:\n          task: a\n"), ErrSyntax, "line 8: cannot"},
	})
}
