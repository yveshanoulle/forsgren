package config

import (
	"slices"
	"strconv"
	"strings"
	"testing"
)

// The key week_commits (forsgren#548, decision #549 A): whether the Week page
// shows its Commits columns. Unlike the switches of forsgren#482 it is false
// unless the file says true.

// TestWeekCommitsIsOffUnlessTheFileTurnsItOn: false when the key is left out
// or has no value, and for false; true only for true; only an accepted value
// counts as written.
func TestWeekCommitsIsOffUnlessTheFileTurnsItOn(t *testing.T) {
	for _, c := range []struct {
		name, line string
		want, set  bool
	}{
		{"absent", "", false, false}, {"no value", "week_commits:\n", false, false},
		{"true", "week_commits: true\n", true, true}, {"false", "week_commits: false\n", false, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			got, err := parse([]byte(c.line + valid))
			if err != nil || len(got.Rejected) != 0 {
				t.Fatalf("want nothing rejected and no error, got %v, %v", got.Rejected, err)
			}
			if got.WeekCommits != c.want || got.written["week_commits"] != c.set {
				t.Errorf("want %v and written %v, got %v and %v", c.want, c.set, got.WeekCommits, got.written)
			}
		})
	}
}

// TestAWeekCommitsValueThatIsNotABooleanIsRejectedAndStaysOff: any other
// value is rejected naming the key, the value as written and `use true or
// false`, with the default false in force.
func TestAWeekCommitsValueThatIsNotABooleanIsRejectedAndStaysOff(t *testing.T) {
	for _, written := range []string{"yes", "True", "1", "off", "true "} {
		t.Run(written, func(t *testing.T) {
			got, err := parse([]byte("week_commits: " + strconv.Quote(written) + "\n" + valid))
			if err != nil {
				t.Fatal(err)
			}
			if got.WeekCommits || got.written["week_commits"] {
				t.Errorf("want week_commits off and not written, got %v and %v", got.WeekCommits, got.written)
			}
			wantRejection(t, got.Rejected, ErrWeekCommits, [4]string{"week_commits", written, "use true or false", "false"})
		})
	}
}

// weekCommitsSetting is the settings row of week_commits of a Config.
func weekCommitsSetting(t *testing.T, c Config) Setting {
	t.Helper()
	for _, s := range c.Settings() {
		if s.Key == "week_commits" {
			return s
		}
	}
	t.Fatal("want a week_commits row in the settings")
	return Setting{}
}

// TestWeekCommitsIsListedRightAfterWeekPage: the settings order.
func TestWeekCommitsIsListedRightAfterWeekPage(t *testing.T) {
	var keys []string
	for _, s := range (Config{}).Settings() {
		keys = append(keys, s.Key)
	}
	if at := slices.Index(keys, "week_page"); at < 0 || keys[at+1] != "week_commits" {
		t.Errorf("want week_commits right after week_page, got %v", keys)
	}
}

// TestWeekCommitsDefaultsToFalseAndAcceptsFalseAndTrue: the default false, not
// set, the values false and true, and the sentinel naming the key.
func TestWeekCommitsDefaultsToFalseAndAcceptsFalseAndTrue(t *testing.T) {
	if got := weekCommitsSetting(t, Config{}); got != (Setting{Key: "week_commits", Value: "false", Default: "false"}) {
		t.Errorf("want false by default and not set, got %+v", got)
	}
	if got := Accepted("week_commits"); !slices.Equal(got, []string{"false", "true"}) {
		t.Errorf("want false and true accepted, got %v", got)
	}
	if ErrWeekCommits.Error() != "invalid week_commits" {
		t.Errorf("want the sentinel to say invalid week_commits, got %q", ErrWeekCommits)
	}
}

// TestASettingsRowShowsWeekCommitsTrueWhenWritten: the written value is the
// Config's.
func TestASettingsRowShowsWeekCommitsTrueWhenWritten(t *testing.T) {
	got, err := parse([]byte("week_commits: true\n" + valid))
	if err != nil {
		t.Fatal(err)
	}
	want := Setting{Key: "week_commits", Value: "true", Default: "false", Set: true}
	if row := weekCommitsSetting(t, got); row != want {
		t.Errorf("want %+v, got %+v", want, row)
	}
}

// TestTheStarterOffersWeekCommitsCommentedOut: the starter names the key,
// false by default, on a commented line only.
func TestTheStarterOffersWeekCommitsCommentedOut(t *testing.T) {
	const line = "\n# week_commits: false  # the Week page's Commits columns: false (default) or true\n"
	if !strings.Contains(Starter, line) {
		t.Error("want the commented line # week_commits: false in the starter")
	}
	for _, line := range strings.Split(Starter, "\n") {
		if strings.HasPrefix(line, "week_commits:") {
			t.Errorf("want week_commits only commented out in the starter, got %q", line)
		}
	}
}
