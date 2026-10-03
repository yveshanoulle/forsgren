package metrics

// Band is a DORA performance band for deployment frequency.
//
// The bands are the deployment-frequency answers of the DORA State of
// DevOps reports (2021 to 2024): on demand (multiple deploys per day),
// between once per day and once per week, between once per week and once
// per month, and less often than once per month. The reports ask people how
// often they deploy; forsgren counts instead, so BandOf maps a count of the
// last 30 days onto them by its average rate:
//
//   - On demand: more than 30, more than one deployment a day on average.
//   - Daily to weekly: 5 to 30. Once a week is 30/7, about 4.3 in 30
//     days, so 5 is the first count at or above once a week.
//   - Weekly to monthly: 1 to 4, at least once in 30 days but less than
//     once a week.
//   - Less than monthly: 0, no deployment in the last 30 days.
type Band int

// The four bands, slowest first. The zero Band is no band.
const (
	LessThanMonthly Band = iota + 1
	WeeklyToMonthly
	DailyToWeekly
	OnDemand
)

// The lowest 30-day count of each band above LessThanMonthly.
const (
	weeklyToMonthlyFrom = 1
	dailyToWeeklyFrom   = 5
	onDemandFrom        = 31
)

// BandOf is the band of a count of successful deployments in the last 30
// days.
func BandOf(last30 int) Band {
	switch {
	case last30 >= onDemandFrom:
		return OnDemand
	case last30 >= dailyToWeeklyFrom:
		return DailyToWeekly
	case last30 >= weeklyToMonthlyFrom:
		return WeeklyToMonthly
	default:
		return LessThanMonthly
	}
}

// String is the band's name as the page shows it.
func (b Band) String() string {
	switch b {
	case OnDemand:
		return "On demand (several per day)"
	case DailyToWeekly:
		return "Daily to weekly"
	case WeeklyToMonthly:
		return "Weekly to monthly"
	case LessThanMonthly:
		return "Less than monthly"
	default:
		return "No band"
	}
}
