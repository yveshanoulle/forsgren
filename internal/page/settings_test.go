package page

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

// TestPossibleValuesAreExactlyWhatCheckConfigAccepts (forsgren#141): for every
// optional key, each value the settings page lists is accepted by the config
// loader, which check-config runs, and the values just outside the list are
// refused, so the page cannot drift from what the loader accepts. Proven by
// mutation: a limit of the page that drifted by one.
func TestPossibleValuesAreExactlyWhatCheckConfigAccepts(t *testing.T) {
	for _, setting := range (config.Config{}).Settings() {
		possible := possibleListOf(setting.Key)
		if possible == "" {
			t.Fatalf("want possible values for %s on the settings page, got none", setting.Key)
		}
		accepted, refused := probesOf(t, possible)
		for _, value := range accepted {
			wantLoads(t, setting.Key, value, true)
		}
		for _, value := range refused {
			wantLoads(t, setting.Key, value, false)
		}
	}
}

// probesOf are the values a column of possible values promises are accepted
// and the ones next to it that must be refused: "a, b, c" promises each name
// and refuses a name it does not list; "1 to 9" promises 1 and 9 and refuses 0
// and 10.
func probesOf(t *testing.T, possible string) (accepted, refused []string) {
	t.Helper()
	low, high, isRange := strings.Cut(possible, " to ")
	if !isRange {
		return strings.Split(possible, ", "), []string{"not-listed"}
	}
	first, errFirst := strconv.Atoi(low)
	last, errLast := strconv.Atoi(high)
	if errFirst != nil || errLast != nil {
		t.Fatalf("want a range like 1 to 9, got %q", possible)
	}
	return []string{low, high}, []string{strconv.Itoa(first - 1), strconv.Itoa(last + 1)}
}

// companions are the line a key needs beside it for the file to be valid:
// auto_update needs its level, and a level needs auto_update on.
var companions = map[string]string{
	"auto_update":       "auto_update_level: patch\n",
	"auto_update_level": "auto_update: true\n",
}

// wantLoads fails t unless a config file that sets key to value loads exactly
// when ok says it should.
func wantLoads(t *testing.T, key, value string, ok bool) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "forsgren.config.yml")
	content := fmt.Sprintf("version: 1\n%s: %s\n%sprojects: []\n", key, value, companions[key])
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := config.Load(path); (err == nil) != ok {
		t.Errorf("%s: %s: want the config loader to accept it: %v, got %v", key, value, ok, err)
	}
}
