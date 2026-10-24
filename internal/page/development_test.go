package page

import (
	"bytes"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/buildversion"
)

// footerOf renders the placeholder page for data and returns its footer line.
func footerOf(t *testing.T, data Data) string {
	t.Helper()
	var out bytes.Buffer
	if err := Render(&out, "index.html", data); err != nil {
		t.Fatalf("Render: %v", err)
	}
	html := out.String()
	start := strings.Index(html, "<footer>")
	end := strings.Index(html, "</footer>")
	if start < 0 || end < start {
		t.Fatalf("want a footer, got:\n%s", html)
	}
	return html[start:end]
}

// TestFooterNamesADevelopmentBuildWithoutARelease (forsgren#340): a build with
// no release to name reads "dev (<commit>)" or "dev"; a build after a release
// keeps "<release>+dev (<commit>)"; a release alone is the version.
func TestFooterNamesADevelopmentBuildWithoutARelease(t *testing.T) {
	cases := []struct {
		name, version, commit, want string
	}{
		{"dev with its commit", buildversion.Dev, "c41db9e", "dev (c41db9e) Metrics"},
		{"dev without a commit", buildversion.Dev, "", "dev Metrics"},
		{"a checkout after a release", testVersion, "c41db9e", testVersion + "+dev (c41db9e) Metrics"},
		{"a release", testVersion, "", testVersion + " Metrics"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			data := calculated()
			data.Version, data.DevCommit = c.version, c.commit
			if got := footerOf(t, data); !strings.Contains(got, "</a> "+c.want) {
				t.Errorf("want %q in the footer, got:\n%s", c.want, got)
			}
		})
	}
}

// TestADevelopmentBuildHasNoUpdate (forsgren#340): dev is no release, so no
// release is newer than it.
func TestADevelopmentBuildHasNoUpdate(t *testing.T) {
	if got := (Data{Version: buildversion.Dev, Latest: newerVersion()}).Update(); got != "" {
		t.Errorf("Update() = %q, want none for a development build", got)
	}
}
