package main

import (
	"os"
	"path/filepath"
	"testing"
)

// templateDependabot is the dependabot.yml of forsgren-template as it stands
// (forsgren#194), the shape installations have.
const templateDependabot = `# Proposes each new forsgren release as a pull request: Dependabot moves the
# pinned ` + "`" + `uses: yveshanoulle/forsgren/.github/workflows/<workflow>@<commit>
# # vX.Y.Z` + "`" + ` lines in .github/workflows/forsgren.yml and forsgren-update.yml to
# the new release's commit and tag. Merging that pull request is the one click
# that updates forsgren (forsgren#14); with auto_update: true in
# forsgren.config.yml, forsgren-update.yml merges it for you (forsgren#58). It
# never touches forsgren.config.yml or data/.
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    # Every day, weekends included: interval daily runs Monday to Friday
    # only, so a release on a Friday evening waited until Monday.
    schedule:
      interval: cron
      cronjob: "0 4 * * *"   # 04:00, before the daily forsgren run
      timezone: UTC
    commit-message:
      prefix: forsgren
    # One pull request per release: Dependabot sees each pinned forsgren
    # workflow as its own dependency, so without this group a release opens
    # one pull request for forsgren.yml and another for forsgren-update.yml
    # (forsgren#61).
    groups:
      forsgren:
        patterns:
          - "yveshanoulle/forsgren/*"
    # A release is proposed once it is 3 days old: a window to replace a bad
    # release before it reaches installations. Set default-days: 0 to get
    # releases at the next daily check (forsgren#14).
    cooldown:
      default-days: 3
`

// writeDependabot writes content as a dependabot.yml in a fresh directory and
// returns its path.
func writeDependabot(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "dependabot.yml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestCooldownDaysReadsTheGithubActionsCooldown (forsgren#194, #195): the days
// are default-days of the github-actions update, as forsgren-template writes
// it, 0 included; a github-actions update that does not name default-days (no
// cooldown, an empty one, or only the semver days, which Dependabot does not
// apply to github-actions) has Dependabot's default of 3. No file, a file that
// is no YAML, a negative number and another ecosystem's cooldown are none.
func TestCooldownDaysReadsTheGithubActionsCooldown(t *testing.T) {
	const head = "version: 2\nupdates:\n"
	const npm = "  - package-ecosystem: npm\n    directory: /\n    cooldown:\n      default-days: 9\n"
	const actions = "  - package-ecosystem: github-actions\n    directory: /\n"
	cases := []struct {
		name, content string
		want          int
	}{
		{"the template's", templateDependabot, 3},
		{"zero", head + actions + "    cooldown:\n      default-days: 0\n", 0},
		{"five", head + actions + "    cooldown:\n      default-days: 5\n", 5},
		{"no cooldown key", head + actions, defaultCooldownDays},
		{"another ecosystem", head + npm, 0},
		{"after another ecosystem", head + npm + actions + "    cooldown:\n      default-days: 4\n", 4},
		{"semver days only", head + actions + "    cooldown:\n      semver-minor-days: 7\n", defaultCooldownDays},
		{"an empty cooldown", head + actions + "    cooldown: {}\n", defaultCooldownDays},
		{"two updates, the one that names it", head + actions + actions + "    cooldown:\n      default-days: 2\n", 2},
		{"not a number", head + actions + "    cooldown:\n      default-days: soon\n", 0},
		{"negative", head + actions + "    cooldown:\n      default-days: -3\n", 0},
		{"not YAML", "updates: [", 0},
		{"empty", "", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := cooldownDays(writeDependabot(t, c.content)); got != c.want {
				t.Errorf("want %d days, got %d", c.want, got)
			}
		})
	}
	if got := cooldownDays(filepath.Join(t.TempDir(), "missing.yml")); got != 0 {
		t.Errorf("want no days for a missing file, got %d", got)
	}
}
