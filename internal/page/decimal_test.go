package page

import (
	"strings"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// decimalCases are the figures every page writes with a decimal mark, in the
// default point form: the scoring view's Overall Performance, the TBD page's
// share and the count of its Commits per push, the Week page's weekend share,
// the legend's score range and the examples of its prose (forsgren#536).
func decimalCases() []struct {
	page, point string
	data        Data
} {
	return []struct {
		page, point string
		data        Data
	}{
		{"scoring/index.html", "<td>8.4</td>", viewData()},
		{"tbd.html", `<td class="num">5.0%</td>`, tbdData()},
		{"week.html", `<td class="num">0.59%</td>`, weekPageData()},
		{"legend.html", "9 to 7.1", tbdData()},
		{"legend.html", "such as 1.0 or 2.5", tbdData()},
		{"legend.html", "such as 1.3% or 3.0%", tbdData()},
	}
}

// TestDecimalSeparatorSettingDecidesTheMarkOnEveryPage (forsgren#536): the
// point by default and for point, a comma for comma, on the scores, the
// Overall Performance mean, the shares, the Week page's percentages and the
// legend; no private placeholder reaches the page.
func TestDecimalSeparatorSettingDecidesTheMarkOnEveryPage(t *testing.T) {
	for _, setting := range []string{"", "point", "comma"} {
		for _, c := range decimalCases() {
			c.data.DecimalSeparator = setting
			wantDecimalMark(t, c.page, c.point, setting, rendered(t, c.page, c.data))
		}
	}
}

// wantDecimalMark fails t unless got, the page rendered with the setting, has
// the figure point as the setting writes it (a comma for comma, and then no
// point), and no placeholder left.
func wantDecimalMark(t *testing.T, page, point, setting, got string) {
	t.Helper()
	name := page + " " + setting
	if setting != "comma" {
		wantAll(t, name, got, point)
	} else {
		wantAll(t, name, got, strings.ReplaceAll(point, ".", ","))
		wantNone(t, name, got, point)
	}
	if strings.Contains(got, metrics.DecimalMark) {
		t.Errorf("%s: want no placeholder left in the page", name)
	}
}

// TestThousandsPeriodAndDecimalCommaTogether (forsgren#536): a period between
// the groups and a comma for the decimals, both on one page: 1.282 deployments
// and a 5,0% share.
func TestThousandsPeriodAndDecimalCommaTogether(t *testing.T) {
	data := tbdData()
	data.ThousandsSeparator, data.DecimalSeparator = "period", "comma"
	data.TbdMetrics[0].Volume.Count = 1282
	got := rendered(t, "tbd.html", data)
	wantAll(t, "tbd.html", got, ">1.282</td>", `<td class="num">5,0%</td>`)
	wantNone(t, "tbd.html", got, "1,282", "5.0%", "1 282")
}

// TestThousandsSeparatorPeriod (forsgren#536): period is a thousands separator
// like comma, with the decimal comma it needs.
func TestThousandsSeparatorPeriod(t *testing.T) {
	data := tbdData()
	data.ThousandsSeparator, data.DecimalSeparator = "period", "comma"
	data.DoraDays = 180
	wantAll(t, "legend.html", rendered(t, "legend.html", data), "1.441 and more in")
}

// TestDecimalPointWithEveryThousandsSeparator (forsgren#536): the point beside
// each of the other thousands separators.
func TestDecimalPointWithEveryThousandsSeparator(t *testing.T) {
	for thousands, want := range map[string]string{"narrow_space": ">1 282</td>", "comma": ">1,282</td>",
		"none": ">1282</td>"} {
		data := tbdData()
		data.ThousandsSeparator, data.DecimalSeparator = thousands, "point"
		data.TbdMetrics[0].Volume.Count = 1282
		wantAll(t, "tbd.html "+thousands, rendered(t, "tbd.html", data), want, `<td class="num">5.0%</td>`)
	}
}
