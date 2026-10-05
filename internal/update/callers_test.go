package update

import (
	"maps"
	"slices"
	"testing"
)

// TestCallerWorkflowsNamesTheWorkflowEachCallerCalls: forsgren.yml calls
// metrics.yml and forsgren-update.yml calls auto_update.yml; the map is a copy,
// so changing it changes no caller.
func TestCallerWorkflowsNamesTheWorkflowEachCallerCalls(t *testing.T) {
	want := map[string]string{
		".github/workflows/forsgren.yml":        "metrics.yml",
		".github/workflows/forsgren-update.yml": "auto_update.yml",
	}
	got := CallerWorkflows()
	if !maps.Equal(got, want) {
		t.Errorf("CallerWorkflows() = %v, want %v", got, want)
	}
	clear(got)
	if paths := Callers(); !slices.Equal(paths, slices.Sorted(maps.Keys(want))) {
		t.Errorf("Callers() = %v after changing the copy, want %v", paths, slices.Sorted(maps.Keys(want)))
	}
}
