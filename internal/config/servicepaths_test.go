package config

import (
	"reflect"
	"testing"
)

// TestServicePathsAreRead (forsgren#496): a service is the short form
// (label only, no paths) or {label, paths}; the paths are kept per task, as
// written and in order, and a task in the short form has none.
func TestServicePathsAreRead(t *testing.T) {
	got, err := parse([]byte(withLabels(
		"        services:\n" +
			"          deploy-api: {label: API, paths: [api/, shared/, go.mod]}\n" +
			"          deploy-admin:\n" +
			"            label: ADMIN\n" +
			"            paths:\n" +
			"              - admin/\n" +
			"          deploy-ios: IOS\n")))
	if err != nil {
		t.Fatalf("want no error, got %v", err)
	}
	r := got.Projects[0].Repositories[0]
	wantServices := map[string]string{"deploy-api": "API", "deploy-admin": "ADMIN", "deploy-ios": "IOS"}
	if !reflect.DeepEqual(r.Services, wantServices) {
		t.Errorf("want labels %v, got %v", wantServices, r.Services)
	}
	wantPaths := map[string][]string{"deploy-api": {"api/", "shared/", "go.mod"}, "deploy-admin": {"admin/"}}
	if !reflect.DeepEqual(r.Paths, wantPaths) {
		t.Errorf("want paths %v, got %v", wantPaths, r.Paths)
	}
}

// TestParseRefusesWrongServicePaths (forsgren#496): the whole services key
// is one refusal, naming the task and the reason.
func TestParseRefusesWrongServicePaths(t *testing.T) {
	svc := func(body string) string { return withLabels("        services:\n          deploy-api: " + body + "\n") }
	const prefix = `repository "acme/app": invalid label: task "deploy-api": `
	checkRefusals(t, []refusal{
		{"empty paths", svc("{label: API, paths: []}"), ErrLabel, prefix + errNoPaths.Error()},
		{"paths without a value", svc("{label: API, paths: }"), ErrLabel, prefix + "paths lists no path"},
		{"empty path", svc(`{label: API, paths: [""]}`), ErrLabel, prefix + "a path is empty"},
		{"blank path", svc(`{label: API, paths: ["  "]}`), ErrLabel, prefix + "a path is empty"},
		{"absolute path", svc("{label: API, paths: [/api/]}"), ErrLabel, prefix + `path "/api/" is absolute`},
		{"parent path", svc("{label: API, paths: [api/../x/]}"), ErrLabel, prefix + `path "api/../x/" has a .. part`},
		{"dot path", svc("{label: API, paths: [./api/]}"), ErrLabel, prefix + `path "./api/" has a . or empty part`},
		{"empty part", svc("{label: API, paths: [api//x]}"), ErrLabel, prefix + `path "api//x" has a . or empty part`},
		{"glob", svc("{label: API, paths: [api/*.go]}"), ErrLabel, prefix + `path "api/*.go" holds a glob character`},
		{"backslash", svc(`{label: API, paths: ['api\x']}`), ErrLabel, prefix + `path "api\\x" uses a backslash`},
		{"duplicate", svc("{label: API, paths: [api/, shared/, api/]}"), ErrLabel, prefix + `path "api/" is listed twice`},
		{"no label", svc("{paths: [api/]}"), ErrLabel, prefix + "a label is empty"},
		{"unknown key", svc("{label: API, path: [api/]}"), ErrSyntax, `unknown key "path"`},
		{"paths a string", svc("{label: API, paths: api/}"), ErrSyntax, "paths is a list"},
		{"path a number", svc("{label: API, paths: [5]}"), ErrSyntax, "cannot use !!int `5` here"},
		{"service a list", svc("[API]"), ErrSyntax, "a service is a label or {label, paths}"},
	})
}
