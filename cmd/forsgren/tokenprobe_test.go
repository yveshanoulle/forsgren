package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// probeRun runs token-probe on an expiry file holding expiry (no file for
// ""), with the token state, and returns its outcome and the line it wrote.
func probeRun(t *testing.T, expiry, state string) (outcome, string) {
	t.Helper()
	dir := t.TempDir()
	file := filepath.Join(dir, "token-expiry")
	if expiry != "" {
		if err := os.WriteFile(file, []byte(expiry), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	out := filepath.Join(dir, "token-probed.tsv")
	code, stdout, stderr := runCommand("token-probe", "--token-expiry", file, "--token-state", state, "--out", out)
	written, err := os.ReadFile(filepath.Clean(out))
	if err != nil {
		written = nil
	}
	return outcome{code, stdout, stderr}, string(written)
}

// TestTokenProbeWritesOneLineForTheToken (forsgren#276): the line of the
// token-expiry-probe artifact, FORSGREN_TOKEN, a tab and the expiry date, or
// never, or error: <word>, from the file collect wrote and whether the
// secret was set; exit 0 for every one of them, an error line included.
func TestTokenProbeWritesOneLineForTheToken(t *testing.T) {
	for _, c := range []struct{ name, expiry, state, want string }{
		{"a date", "2027-01-12T08:35:47Z\n", "set", "2027-01-12"},
		{"no expiry", "no-expiry\n", "set", "never"},
		{"the run's own token", "no-expiry run-token\n", "set", "never"},
		{"an unreadable header", "unreadable\n", "set", "error: unreadable"},
		{"no file, the token set", "", "set", "error: unknown"},
		{"a file of anything else", "soon\n", "set", "error: unknown"},
		{"no file, no token", "", "missing", "error: missing"},
	} {
		t.Run(c.name, func(t *testing.T) {
			got, line := probeRun(t, c.expiry, c.state)
			if got.code != 0 {
				t.Fatalf("want exit 0, got %+v", got)
			}
			if want := "FORSGREN_TOKEN\t" + c.want + "\n"; line != want {
				t.Errorf("want the line %q, got %q", want, line)
			}
			if !strings.Contains(got.stdout, "FORSGREN_TOKEN "+c.want) {
				t.Errorf("want stdout to say FORSGREN_TOKEN %s, got %q", c.want, got.stdout)
			}
		})
	}
}

// TestTokenProbeNeverShowsTheToken: with the token in the environment, as a
// step that had it would, the token is in neither the file nor the output.
func TestTokenProbeNeverShowsTheToken(t *testing.T) {
	t.Setenv("FORSGREN_TOKEN", testToken)
	for _, state := range []string{"set", "missing"} {
		got, line := probeRun(t, "", state)
		if line == "" {
			t.Fatalf("%s: want a line, got none (%+v)", state, got)
		}
		for name, text := range map[string]string{"file": line, "stdout": got.stdout, "stderr": got.stderr} {
			if strings.Contains(text, testToken) {
				t.Errorf("%s: the token is in the %s: %q", state, name, text)
			}
		}
	}
}

// TestTokenProbeRefusesAnUnknownTokenState: a state other than set or missing
// is a usage error, exit 2, and no file: the step that passes it turns red.
func TestTokenProbeRefusesAnUnknownTokenState(t *testing.T) {
	got, line := probeRun(t, "no-expiry\n", "maybe")
	if got.code != 2 {
		t.Errorf("want exit 2, got %+v", got)
	}
	if line != "" {
		t.Errorf("want no file, got %q", line)
	}
	if !strings.Contains(got.stderr, "--token-state") {
		t.Errorf("want stderr to name --token-state, got %q", got.stderr)
	}
}

// TestTokenProbeFailsWhenTheFileCannotBeWritten: a file it cannot write is
// exit 1 with the path named, never a silent pass.
func TestTokenProbeFailsWhenTheFileCannotBeWritten(t *testing.T) {
	out := filepath.Join(t.TempDir(), "missing", "token-probed.tsv")
	code, _, stderr := runCommand("token-probe", "--token-expiry", expiryFile(t), "--token-state", "set", "--out", out)
	if code != 1 || !strings.Contains(stderr, out) {
		t.Errorf("want exit 1 naming %s, got %d and %q", out, code, stderr)
	}
}
