package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/yveshanoulle/forsgren/internal/needs"
)

// atFirstOfOctober fixes the clock of check-needs at 2026-10-01 for the test.
func atFirstOfOctober(t *testing.T) {
	t.Helper()
	old := now
	now = func() time.Time { return time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC) }
	t.Cleanup(func() { now = old })
}

// writeExpiry writes the expiry line collect would write into the checkout
// and returns the file's path.
func writeExpiry(t *testing.T, line string) string {
	t.Helper()
	if err := os.WriteFile("token-expiry", []byte(line), 0o600); err != nil {
		t.Fatal(err)
	}
	return "token-expiry"
}

// checkNeedsWithTokenExpiry runs check-needs for acme/data at 2026-10-01 in
// a checkout where every need of 0.4.0 is in place, --token-expiry naming the
// file expiry gives there.
func checkNeedsWithTokenExpiry(t *testing.T, expiry func(*testing.T) string) (int, string, string) {
	t.Helper()
	setVersion(t, "0.4.0")
	atFirstOfOctober(t)
	t.Setenv("GITHUB_TOKEN", testToken)
	installationWithIssuesWrite(t)
	return runCommand("check-needs", "--config", "forsgren.config.yml",
		"--repository", "acme/data", "--token-expiry", expiry(t))
}

// TestCheckNeedsMakesAnItemOfATokenThatExpiresSoon (forsgren#177): every
// need of 0.4.0 is in place, and the token expires within 14 days: the setup
// issue is created, its item naming the date and the command to set a new
// token.
func TestCheckNeedsMakesAnItemOfATokenThatExpiresSoon(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	fake := newSetupServer(t, 201)
	code, stdout, stderr := checkNeedsWithTokenExpiry(t,
		func(t *testing.T) string { return writeExpiry(t, "2026-10-10T08:35:47Z\n") })
	const item = "FORSGREN_TOKEN expires on 2026-10-10. Make a new fine-grained token and set it " +
		"with `gh secret set FORSGREN_TOKEN -R acme/data` in a separate terminal."
	if code != 0 || !strings.Contains(stdout, item) || len(fake.posts) != 1 || !strings.Contains(fake.posts[0], item) ||
		!strings.Contains(fake.posts[0], "forsgren:token_expiry 2026-10-10T08:35:47Z") {
		t.Errorf("want exit 0 and the item %q, with its mark, in stdout and the issue, got %d, %q, %q, %q",
			item, code, stdout, stderr, fake.posts)
	}
}

// TestCheckNeedsHasNoItemForATokenThatIsFarOrUnknown (forsgren#177): a far
// date, no file, a directory and a file that is no date are nothing missing,
// so the open setup issue is closed again (the fake refuses that write,
// which the note on stderr shows).
func TestCheckNeedsHasNoItemForATokenThatIsFarOrUnknown(t *testing.T) {
	cases := map[string]func(t *testing.T) string{
		"far":        func(t *testing.T) string { return writeExpiry(t, "2026-10-15T00:00:01Z\n") },
		"no file":    func(*testing.T) string { return "no-such-file" },
		"directory":  func(*testing.T) string { return "." },
		"not a date": func(t *testing.T) string { return writeExpiry(t, "soon\n") },
	}
	for name, file := range cases {
		t.Run(name, func(t *testing.T) {
			newOpenIssueServer(t)
			code, _, stderr := checkNeedsWithTokenExpiry(t, file)
			if code != 0 || !strings.Contains(stderr, "the setup issue could not be closed") {
				t.Errorf("want exit 0 and an attempt to close the issue, got %d, %q", code, stderr)
			}
		})
	}
}

// recordingIssueServer answers the setup issue lookup with one marked issue
// in state whose body is body (none for an empty state), counts those
// lookups, and answers every write with 200; it keeps each write as
// `METHOD path body`, the body being the JSON body's "body" text, if any.
type recordingIssueServer struct {
	writes  []string
	lookups int
}

func newRecordingIssueServer(t *testing.T, state, body string) *recordingIssueServer {
	t.Helper()
	fake := &recordingIssueServer{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			raw, _ := io.ReadAll(r.Body)
			var sent struct{ Body string }
			_ = json.Unmarshal(raw, &sent)
			fake.writes = append(fake.writes, r.Method+" "+r.URL.Path+" "+sent.Body)
			_, _ = io.WriteString(w, `{"number": 7}`)
			return
		}
		fake.lookups++
		if state == "" {
			_, _ = io.WriteString(w, "[]")
			return
		}
		issue, _ := json.Marshal(map[string]any{"number": 7, "state": state, "title": "Setup",
			"created_at": "2026-10-01T00:00:00Z", "body": body})
		_, _ = io.WriteString(w, "["+string(issue)+"]")
	}))
	t.Cleanup(srv.Close)
	setGithubAPI(t, srv.URL)
	return fake
}

// carriedItem is the renewal item as the setup issue's body holds it: the
// steps and the hidden mark with the date, the way a run with a known date
// wrote it.
const carriedItem = needs.Marker + "\n\nforsgren 0.4.0 needs more configuration in this repository.\n" +
	"\n- [ ] FORSGREN_TOKEN expires on 2026-10-10. Make a new fine-grained token and set it " +
	"with `gh secret set FORSGREN_TOKEN -R acme/data` in a separate terminal. " +
	"<!-- forsgren:token_expiry 2026-10-10T08:35:47Z -->\n"

// unknownExpiry are the ways the run does not know the token's expiry: no
// readable date for check-needs, whatever the cause (a collect that failed
// leaves no file either).
var unknownExpiry = map[string]func(t *testing.T) string{
	"no file":    func(*testing.T) string { return "no-such-file" },
	"directory":  func(*testing.T) string { return "." },
	"not a date": func(t *testing.T) string { return writeExpiry(t, "soon\n") },
}

// TestCheckNeedsKeepsTheRenewalItemTheOpenIssueCarriesWhenTheExpiryIsUnknown
// (forsgren#177): without a readable date the open setup issue that carries
// the item (by its mark) is not closed; it is written again with the item
// and the same date.
func TestCheckNeedsKeepsTheRenewalItemTheOpenIssueCarriesWhenTheExpiryIsUnknown(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	for name, file := range unknownExpiry {
		t.Run(name, func(t *testing.T) {
			fake := newRecordingIssueServer(t, "open", carriedItem)
			code, _, stderr := checkNeedsWithTokenExpiry(t, file)
			const item = "FORSGREN_TOKEN expires on 2026-10-10. Make a new fine-grained token and set it " +
				"with `gh secret set FORSGREN_TOKEN -R acme/data` in a separate terminal. " +
				"<!-- forsgren:token_expiry 2026-10-10T08:35:47Z -->"
			wantKept(t, fake, code, stderr, item)
		})
	}
}

// wantKept fails t unless the run exited 0 quietly and wrote exactly one
// update of issue 7 whose body keeps item.
func wantKept(t *testing.T, fake *recordingIssueServer, code int, stderr, item string) {
	t.Helper()
	if code != 0 || stderr != "" || len(fake.writes) != 1 ||
		!strings.HasPrefix(fake.writes[0], "PATCH /repos/acme/data/issues/7 ") ||
		!strings.Contains(fake.writes[0], item) {
		t.Errorf("want exit 0 and one update of issue 7 that keeps %q, got %d, %q, %q",
			item, code, stderr, fake.writes)
	}
}

// TestCheckNeedsAddsNoRenewalItemFromAnUnknownExpiry (forsgren#177): with no
// readable date nothing is created, and a closed issue that carries the item
// is carrying nothing: no write at all.
func TestCheckNeedsAddsNoRenewalItemFromAnUnknownExpiry(t *testing.T) {
	t.Run("no issue", func(t *testing.T) {
		fake := newSetupServer(t, 201)
		checkNeedsWithTokenExpiry(t, unknownExpiry["no file"])
		if len(fake.posts) != 0 {
			t.Errorf("want nothing created, got %q", fake.posts)
		}
	})
	t.Run("closed issue", func(t *testing.T) {
		fake := newRecordingIssueServer(t, "closed", carriedItem)
		checkNeedsWithTokenExpiry(t, unknownExpiry["no file"])
		if len(fake.writes) != 0 {
			t.Errorf("want no write, got %q", fake.writes)
		}
	})
}

// failingLookupServer answers every request with a 500 and returns the
// methods it was asked with.
func failingLookupServer(t *testing.T) *[]string {
	t.Helper()
	requests := &[]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*requests = append(*requests, r.Method)
		http.Error(w, `{"message": "boom"}`, http.StatusInternalServerError)
	}))
	t.Cleanup(srv.Close)
	setGithubAPI(t, srv.URL)
	return requests
}

// TestCheckNeedsKeepsNothingWhenTheLookupFailsAndTheExpiryIsUnknown
// (forsgren#181): the setup issue lookup answers an error while the expiry is
// unknown. A failed lookup is not proof of a renewal: no item is kept, the
// issue is neither written nor closed (no write at all), and the run says
// what it says today: the note that the issue could not be closed on stderr,
// status ok on stdout.
func TestCheckNeedsKeepsNothingWhenTheLookupFailsAndTheExpiryIsUnknown(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	for name, file := range unknownExpiry {
		t.Run(name, func(t *testing.T) {
			requests := failingLookupServer(t)
			code, stdout, stderr := checkNeedsWithTokenExpiry(t, file)
			if code != 0 || stdout != "check-needs: ok\n" ||
				!strings.HasPrefix(stderr, "check-needs: the setup issue could not be closed: ") {
				t.Errorf("want exit 0, the note that the issue could not be closed and status ok, got %d, %q, %q",
					code, stdout, stderr)
			}
			if got := strings.Join(*requests, " "); got != http.MethodGet {
				t.Errorf("want one lookup and no write, got requests %q", got)
			}
		})
	}
}

// TestCheckNeedsLooksTheSetupIssueUpOncePerRun (forsgren#181): whatever the
// expiry and the issue, a run looks the setup issue up once and writes what
// it wrote before: the lookup is shared by keeping the renewal item and by
// reporting.
func TestCheckNeedsLooksTheSetupIssueUpOncePerRun(t *testing.T) {
	t.Setenv("GITHUB_REPOSITORY", "acme/data")
	near := func(t *testing.T) string { return writeExpiry(t, "2026-10-10T08:35:47Z\n") }
	far := func(t *testing.T) string { return writeExpiry(t, "2026-10-15T00:00:01Z\n") }
	cases := []struct {
		name, state string
		expiry      func(*testing.T) string
		writes      int
	}{
		{"unknown, open issue", "open", unknownExpiry["no file"], 1},
		{"unknown, closed issue", "closed", unknownExpiry["no file"], 0},
		{"unknown, no issue", "", unknownExpiry["no file"], 0},
		{"near, open issue", "open", near, 1},
		{"near, closed issue", "closed", near, 1},
		{"far, open issue", "open", far, 2},
		{"far, closed issue", "closed", far, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fake := newRecordingIssueServer(t, c.state, carriedItem)
			code, _, _ := checkNeedsWithTokenExpiry(t, c.expiry)
			if code != 0 || fake.lookups != 1 || len(fake.writes) != c.writes {
				t.Errorf("want exit 0, one lookup and %d writes, got %d, %d, %q", c.writes, code, fake.lookups, fake.writes)
			}
		})
	}
}
