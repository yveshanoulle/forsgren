package main

import (
	"io"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/page"
)

// hidesOf are the four hide flags of the page data, in the order of the
// settings page.
func hidesOf(d page.Data) [4]bool {
	return [4]bool{d.HideSubRows, d.HideTbdTimeToMain, d.HideTbdPRLeadTime, d.HideTbdBotPRLeadTime}
}

// hidesFrom is the switches of the page data a render makes from the
// config file with the keys, or with no config for none.
func hidesFrom(t *testing.T, keys string) [4]bool {
	t.Helper()
	o := renderOptions{}
	if keys != "" {
		o.config = writeConfig(t, keys+validConfig)
	}
	data, err := pageData(o, time.Unix(0, 0), io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	return hidesOf(data)
}

// TestRenderPassesTheSwitchesToThePageData (forsgren#482): the four switches
// are on in the data of a render without a config and of one that leaves them
// out, and each is off exactly when the config says false; the page does not
// use them yet.
func TestRenderPassesTheSwitchesToThePageData(t *testing.T) {
	none := [4]bool{}
	if got := hidesFrom(t, ""); got != none {
		t.Errorf("no config: want nothing hidden, got %v", got)
	}
	if got := hidesFrom(t, "\n"); got != none {
		t.Errorf("left out: want nothing hidden, got %v", got)
	}
	off := "tbd_time_to_main: false\ntbd_pr_lead_time: false\ntbd_bot_pr_lead_time: false\nsub_rows: false\n"
	if got := hidesFrom(t, off); got != ([4]bool{true, true, true, true}) {
		t.Errorf("want all four hidden, got %v", got)
	}
	if got := hidesFrom(t, "sub_rows: false\n"); got != ([4]bool{true}) {
		t.Errorf("want only the sub rows hidden, got %v", got)
	}
}

// TestCheckConfigCountsARejectedSwitch (forsgren#482, #183): the four switches
// with a value that is not accepted are four settings not accepted, each with
// its warning on stderr, and the exit is 0.
func TestCheckConfigCountsARejectedSwitch(t *testing.T) {
	keys := "tbd_time_to_main: yes\ntbd_pr_lead_time: 0\ntbd_bot_pr_lead_time: off\nsub_rows: \"false\"\n"
	code, stdout, stderr := runCommand("check-config", "--config", writeConfig(t, keys+validConfig))
	if code != 0 || !strings.HasSuffix(stdout, "settings not accepted: 4\n") {
		t.Errorf("want exit 0 and four settings not accepted, got %d, %q", code, stdout)
	}
	for _, want := range []string{`invalid tbd_time_to_main "yes": use true or false; using the default true`,
		`invalid tbd_pr_lead_time "0": use true or false; using the default true`,
		`invalid tbd_bot_pr_lead_time "off": use true or false; using the default true`,
		`invalid sub_rows "false": use true or false; using the default true`} {
		if !strings.Contains(stderr, want) {
			t.Errorf("want stderr to hold %q, got %q", want, stderr)
		}
	}
}
