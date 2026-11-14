package installerdoc

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// templateUpdateWait is the update wait, in days, that forsgren-template's
// .github/dependabot.yml gives a new installation (`cooldown: default-days`,
// forsgren#678; 3 before it).
const templateUpdateWait = 7

// waitMention is one place a file names the template's update wait: the
// pattern's one group is a number, which must be templateUpdateWait plus
// plus.
type waitMention struct {
	file    repoFile
	where   string
	pattern *regexp.Regexp
	plus    int
}

// waitMentions are every place the agents and the docs name the update wait a
// new installation gets.
var waitMentions = []waitMention{
	{installerFile, "the installer's update-wait question",
		regexp.MustCompile("must be before Dependabot proposes it\\. Default: `(\\d+)`"), 0},
	{installerFile, "the installer's plan",
		regexp.MustCompile(`The update wait, when it is not (\d+) \(step 11 changes it\)`), 0},
	{installerFile, "the installer's go-question",
		regexp.MustCompile(`only when the update wait is not (\d+):`), 0},
	{installerFile, "the installer's step 11 condition",
		regexp.MustCompile(`only when the person's answer is not (\d+)`), 0},
	{installerFile, "the installer's step 11 check",
		regexp.MustCompile("Check: one line, `default-days: (\\d+)`"), 0},
	{installerFile, "the installer's first auto-update",
		regexp.MustCompile(`proposes a release once it is (\d+) days old`), 0},
	{installerFile, "the installer's first auto-update report",
		regexp.MustCompile(`None (\d+) days after the release: report it`), 1},
	{upgraderFile, "the upgrader's update-wait default",
		regexp.MustCompile("When `dependabot\\.yml` is missing, the default is `(\\d+)`"), 0},
	{upgraderFile, "the upgrader's next release",
		regexp.MustCompile("as old as the update wait \\(`default-days`, (\\d+) for a new installation\\)"), 0},
	{"docs/updating-and-releases.md", "the template's Dependabot setup",
		regexp.MustCompile(`and waits (\d+) days after a release before it proposes it`), 0},
	{"docs/configuration.md", "the Update line's cooldown",
		regexp.MustCompile("forsgren-template writes `default-days: (\\d+)`"), 0},
}

// waitDrift returns, for each mention of texts (keyed by file, as one line),
// why it does not name want plus its own plus: missing, or another number.
func waitDrift(texts map[repoFile]string, want int) []string {
	var drift []string
	for _, m := range waitMentions {
		found := m.pattern.FindStringSubmatch(texts[m.file])
		if found == nil {
			drift = append(drift, fmt.Sprintf("%s: %s names no update wait (%s)", m.file, m.where, m.pattern))
			continue
		}
		if got, err := strconv.Atoi(found[1]); err != nil || got != want+m.plus {
			drift = append(drift, fmt.Sprintf("%s: %s says %s, want %d", m.file, m.where, found[1], want+m.plus))
		}
	}
	return drift
}

// waitTexts are the files waitMentions reads, each as one line.
func waitTexts(t *testing.T) map[repoFile]string {
	t.Helper()
	texts := map[repoFile]string{}
	for _, m := range waitMentions {
		texts[m.file] = readRepoFileAsOneLine(t, m.file)
	}
	return texts
}

// TestEveryPlaceNamesTheTemplatesUpdateWait (forsgren#678): the installer, the
// upgrader and the docs name the 7-day update wait forsgren-template gives a
// new installation, everywhere they name it.
func TestEveryPlaceNamesTheTemplatesUpdateWait(t *testing.T) {
	for _, d := range waitDrift(waitTexts(t), templateUpdateWait) {
		t.Error(d)
	}
}

// TestAThreeDayTemplateIsCaught (forsgren#678): a mutation proof. The same
// texts with the installer's step 11 check, or the template description of
// the docs, put back to 3 days are refused, naming the place.
func TestAThreeDayTemplateIsCaught(t *testing.T) {
	mutations := []struct {
		file     repoFile
		from, to string
		wantIn   string
	}{
		{installerFile, "Check: one line, `default-days: 7`", "Check: one line, `default-days: 3`", "step 11 check says 3"},
		{"docs/updating-and-releases.md", "and waits 7 days after", "and waits 3 days after", "Dependabot setup says 3"},
	}
	for _, mu := range mutations {
		texts := waitTexts(t)
		if !strings.Contains(texts[mu.file], mu.from) {
			t.Fatalf("%s does not contain %q to mutate", mu.file, mu.from)
		}
		texts[mu.file] = strings.Replace(texts[mu.file], mu.from, mu.to, 1)
		drift := strings.Join(waitDrift(texts, templateUpdateWait), "\n")
		if !strings.Contains(drift, mu.wantIn) {
			t.Errorf("a %s at 3 days is not refused with %q; drift: %q", mu.file, mu.wantIn, drift)
		}
	}
}

// TestTheUpgraderProposesSevenAndAcceptsMore (forsgren#678): the upgrader
// takes an update wait of 7 or more as it is, proposes moving the old
// template's 3 to 7 (a question, never a stop), keeps another number below 7
// as the person's own choice, and gives the reason.
func TestTheUpgraderProposesSevenAndAcceptsMore(t *testing.T) {
	wantAll(t, "the upgrader's step 5", upgraderSection(t, "Step 5."),
		"7 or more is good: its default is what `default-days` says now",
		"`3`, the wait every installation got before forsgren#678, is a proposal: its default is `7`",
		"Another number below 7 is the person's own choice: its default is what it is now",
		"both Shai-Hulud npm waves of 2025 were found about 1 to 3 days after they started",
		"security updates skip the wait")
}

// TestTheInstallerGivesTheReason (forsgren#678): the installer's update-wait
// question and the docs' template description say why 7 days.
func TestTheInstallerGivesTheReason(t *testing.T) {
	const reason = "both Shai-Hulud npm waves of 2025 were found about 1 to 3 days after they started"
	wantAll(t, "the installer", readRepoFileAsOneLine(t, installerFile), reason, "security updates skip the wait")
	wantAll(t, "docs/updating-and-releases.md", readRepoFileAsOneLine(t, "docs/updating-and-releases.md"), reason,
		"security updates skip the cooldown")
}
