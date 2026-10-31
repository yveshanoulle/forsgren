package page

import (
	"strings"
	"testing"
)

// legendFailedText are the sentences of the legend's paragraph on the Failed
// and Fail rate columns (forsgren#545, decision #546, forsgren#547, forsgren#601).
var legendFailedText = []string{
	"Failed and Fail rate count the failed deployments of the window: those with the state failure.",
	"A deployment that finished in another way is not failed.",
	"Under each weekday, Failed is the share of the row's failed deployments that fall on that weekday, " +
		"and Fail rate is the failed deployments of that weekday out of its successful plus failed deployments.",
	"Deployments that finished in another way are left out of Fail rate, in the failed deployments and in the total, " +
		"as in the change fail rate.",
	"In Total, Deployments is the count of the successful plus failed deployments, " +
		"so it is the denominator of Fail rate.",
	"In Total, Failed is a count and Fail rate is the failed deployments " +
		"out of the successful plus failed deployments of the window.",
	"A dash means there is nothing to divide: a row with no failed deployments has a dash in its Failed cells, " +
		"and a weekday without successful or failed deployments has a dash in its Fail rate cell.",
	"In each row the weekday with the highest Failed and the weekday with the highest Fail rate are shown in red, " +
		"every tied weekday, and none when the row has no failed deployments; " +
		"a screen reader hears the word highest in these cells.",
}

// TestLegendExplainsFailedAndFailRateInOneParagraph (forsgren#545): one
// paragraph starts with Failed and Fail rate and holds every sentence.
func TestLegendExplainsFailedAndFailRateInOneParagraph(t *testing.T) {
	_, section, _ := weekSection(t, calculated())
	if got := strings.Count(section, "<p>Failed and Fail rate "); got != 1 {
		t.Fatalf("want one paragraph starting with Failed and Fail rate, got %d", got)
	}
	_, paragraph, _ := strings.Cut(section, "<p>Failed and Fail rate ")
	paragraph, _, _ = strings.Cut(paragraph, "</p>")
	for _, want := range legendFailedText {
		if !strings.Contains("Failed and Fail rate "+paragraph, want) {
			t.Errorf("want %q in the Failed and Fail rate paragraph", want)
		}
	}
}
