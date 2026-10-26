package config

import (
	"slices"
	"strconv"
	"testing"
)

// switchCase is one of the four boolean switches of forsgren#482 (decisions
// #480 A, #481 B, #488 A): its key, its sentinel and the Config field that
// holds it.
type switchCase struct {
	key      string
	sentinel error
	field    func(Config) bool
}

var switchKeys = []switchCase{
	{"tbd_time_to_main", ErrTbdTimeToMain, func(c Config) bool { return !c.HideTbdTimeToMain }},
	{"tbd_pr_lead_time", ErrTbdPRLeadTime, func(c Config) bool { return !c.HideTbdPRLeadTime }},
	{"tbd_bot_pr_lead_time", ErrTbdBotPRLeadTime, func(c Config) bool { return !c.HideTbdBotPRLeadTime }},
	{"sub_rows", ErrSubRows, func(c Config) bool { return !c.HideSubRows }},
}

// switchLoad is a way a switch is written in the file: the line after its key,
// the value it takes, and whether the key counts as written.
type switchLoad struct {
	name, line string
	want, set  bool
}

var switchLoads = []switchLoad{
	{"absent", "", true, false}, {"no value", ":\n", true, false},
	{"true", ": true\n", true, true}, {"false", ": false\n", false, true},
}

// TestSwitchesAreOnUnlessTheFileTurnsThemOff (forsgren#482): each key is true
// when the file leaves it out or gives it no value, false only for false, and
// only a key with an accepted value counts as written.
func TestSwitchesAreOnUnlessTheFileTurnsThemOff(t *testing.T) {
	for _, k := range switchKeys {
		for _, c := range switchLoads {
			t.Run(k.key+" "+c.name, func(t *testing.T) {
				file := valid
				if c.line != "" {
					file = k.key + c.line + valid
				}
				wantSwitch(t, file, k, c)
			})
		}
	}
}

// wantSwitch fails t unless the file loads with nothing rejected and the
// switch k is as c says.
func wantSwitch(t *testing.T, file string, k switchCase, c switchLoad) {
	t.Helper()
	got, err := parse([]byte(file))
	if err != nil || len(got.Rejected) != 0 {
		t.Fatalf("want nothing rejected and no error, got %v, %v", got.Rejected, err)
	}
	if k.field(got) != c.want || got.written[k.key] != c.set {
		t.Errorf("want %s %v and written %v, got %v and %v", k.key, c.want, c.set, k.field(got), got.written)
	}
}

// TestASwitchThatIsNotABooleanIsRejectedAndStaysOn (forsgren#482, #183): any
// other value, a quoted one and yes included, is rejected naming the key, the
// value as written and `use true or false`, with true in force.
func TestASwitchThatIsNotABooleanIsRejectedAndStaysOn(t *testing.T) {
	for _, k := range switchKeys {
		for _, written := range []string{"yes", "True", "1", "off", "false "} {
			t.Run(k.key+" "+written, func(t *testing.T) {
				got, err := parse([]byte(k.key + ": " + strconv.Quote(written) + "\n" + valid))
				if err != nil {
					t.Fatal(err)
				}
				wantStillOn(t, got, k)
				wantRejection(t, got.Rejected, k.sentinel, [4]string{k.key, written, "use true or false", "true"})
			})
		}
	}
}

// wantStillOn fails t unless the switch k is on in got and not written.
func wantStillOn(t *testing.T, got Config, k switchCase) {
	t.Helper()
	if !k.field(got) {
		t.Errorf("want %s on, got off", k.key)
	}
	if got.written[k.key] {
		t.Errorf("want %s not written, got %v", k.key, got.written)
	}
}

// TestAcceptedSwitchValues (forsgren#482, #79): the values Accepted names for
// each switch, sorted as for auto_update.
func TestAcceptedSwitchValues(t *testing.T) {
	for _, k := range switchKeys {
		if got := Accepted(k.key); !slices.Equal(got, []string{"false", "true"}) {
			t.Errorf("%s: want false and true, got %v", k.key, got)
		}
	}
}

// TestSwitchesAreListedWhereTheSettingsPageWantsThem (forsgren#482): the three
// tbd_ switches follow tbd_figures, sub_rows follows view.
func TestSwitchesAreListedWhereTheSettingsPageWantsThem(t *testing.T) {
	var keys []string
	for _, s := range (Config{}).Settings() {
		keys = append(keys, s.Key)
	}
	at := slices.Index(keys, "tbd_figures")
	if !slices.Equal(keys[:2], []string{"view", "sub_rows"}) {
		t.Errorf("want sub_rows after view, got %v", keys)
	}
	want := []string{"tbd_time_to_main", "tbd_pr_lead_time", "tbd_bot_pr_lead_time"}
	if !slices.Equal(keys[at+1:at+4], want) {
		t.Errorf("want the tbd_ switches after tbd_figures, got %v", keys)
	}
}

// TestSwitchesDefaultToTrue (forsgren#482): each switch lists the default true.
func TestSwitchesDefaultToTrue(t *testing.T) {
	for _, s := range (Config{}).Settings() {
		isSwitch := slices.ContainsFunc(switchKeys, func(k switchCase) bool { return k.key == s.Key })
		if isSwitch && s.Default != "true" {
			t.Errorf("%s: want the default true, got %q", s.Key, s.Default)
		}
	}
}

// TestSwitchSentinelsNameTheirKey (forsgren#482): each Err says invalid and
// the key.
func TestSwitchSentinelsNameTheirKey(t *testing.T) {
	for _, k := range switchKeys {
		want := "invalid " + k.key
		if k.sentinel == nil {
			t.Fatalf("%s: want a sentinel", k.key)
		}
		if k.sentinel.Error() != want {
			t.Errorf("want the sentinel %q, got %q", want, k.sentinel)
		}
	}
}

// TestAConfigNotLoadedFromAFileHidesNothing (forsgren#482): the zero value of a
// Config is the default, every switch on, so a Config built by hand shows
// everything.
func TestAConfigNotLoadedFromAFileHidesNothing(t *testing.T) {
	for _, k := range switchKeys {
		if !k.field(Config{}) {
			t.Errorf("%s: want it on in a Config not loaded from a file", k.key)
		}
	}
}
