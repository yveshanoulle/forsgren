package dictionary

import (
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// averageWords are the words that would call a figure an arithmetic average.
var averageWords = regexp.MustCompile(`(?i)\b(mean|average)\b`)

// ruled holds what Yves's ruling on #563 asks of each definition: the
// phrases the definition must say (lower case) and, where it says so, the
// words it must not use.
var ruled = []struct {
	name   string
	says   []string
	forbid *regexp.Regexp
}{
	{"Overall Performance", []string{"quick check score", "same weight", "no data", "not a dora band"}, averageWords},
	{"final deployment", []string{"success or a failure", "not the last deployment", "running"}, nil},
	{"stream", []string{"repository", "kind", "environment", "workflow", "task", "all releases"}, nil},
	{"lower bound", []string{"known:", "unknown:", "at least"}, nil},
	{"bot", []string{"[bot]", "account type", "never guessed"}, nil},
	{"lead time", []string{"deployment lead time", "issue lead time", "pr lead time"}, nil},
	{"trunk", []string{"default branch", "whatever", "not necessarily"}, nil},
	{"mainline", []string{"default branch", "not necessarily"}, nil},
	{"Quick Check", []string{"questionnaire", "does not run", "no repository"}, nil},
	{"Total", []string{"issues", "week page", "total row"}, nil},
	{"Fail rate", []string{"total", "weekday", "change fail rate"}, nil},
}

func TestRuledDefinitionsSayWhatTheRulingAsks(t *testing.T) {
	byName := map[string]Entry{}
	for _, e := range entries(t) {
		byName[strings.ToLower(e.Name)] = e
	}
	for _, r := range ruled {
		e, ok := byName[strings.ToLower(r.name)]
		if !ok {
			t.Errorf("the dictionary has no entry %q", r.name)
			continue
		}
		for _, problem := range problemsOf(e.Definition, r.says, r.forbid) {
			t.Errorf("%q: the definition %s: %s", r.name, problem, e.Definition)
		}
	}
}

// problemsOf are what is wrong with a definition: each phrase it does not say
// and, when forbid matches, the word it uses.
func problemsOf(definition string, says []string, forbid *regexp.Regexp) []string {
	var problems []string
	for _, phrase := range unsaid(definition, says) {
		problems = append(problems, "does not say "+strconv.Quote(phrase))
	}
	if forbid != nil && forbid.MatchString(definition) {
		problems = append(problems, "uses a word it must not")
	}
	return problems
}

// unsaid are the phrases (lower case) the definition does not contain,
// ignoring case.
func unsaid(definition string, phrases []string) []string {
	var missing []string
	for _, phrase := range phrases {
		if !strings.Contains(strings.ToLower(definition), phrase) {
			missing = append(missing, phrase)
		}
	}
	return missing
}
