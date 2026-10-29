package page

// The legend's band edges over the DORA window and the working day
// (forsgren#71, forsgren#178): the counts each deployment frequency band
// spans, as the legend page states them.

import (
	"github.com/yveshanoulle/forsgren/internal/config"
	"github.com/yveshanoulle/forsgren/internal/metrics"
)

// WorkingDay is the hours of a working day, 8 when Data holds none.
func (d Data) WorkingDay() int { return metrics.WorkingDay(d.WorkingHours) }

// Window is the DORA window in days, 30 when Data holds none (forsgren#178).
func (d Data) Window() int { return config.DoraWindow(d.DoraDays) }

// edges are the band edges over the window.
func (d Data) edges() metrics.Edges { return metrics.EdgesOf(d.Window()) }

// OnDemandFrom is the lowest count over the window that is on demand for the
// working day.
func (d Data) OnDemandFrom() int { return metrics.OnDemandFrom(d.WorkingHours, d.Window()) }

// HourlyToDailyFrom is the lowest count over the window between once per hour
// and once per day.
func (d Data) HourlyToDailyFrom() int { return d.edges().HourlyToDaily }

// HourlyToDailyTo is the highest count over the window between once per hour
// and once per day, one below OnDemandFrom.
func (d Data) HourlyToDailyTo() int { return d.OnDemandFrom() - 1 }

// DailyToWeeklyFrom is the lowest count over the window between once per day
// and once per week.
func (d Data) DailyToWeeklyFrom() int { return d.edges().DailyToWeekly }

// DailyToWeeklyTo is the highest count between once per day and once per
// week, one below HourlyToDailyFrom.
func (d Data) DailyToWeeklyTo() int { return d.HourlyToDailyFrom() - 1 }

// WeeklyToMonthlyFrom is the lowest count over the window between once per
// week and once per month.
func (d Data) WeeklyToMonthlyFrom() int { return d.edges().WeeklyToMonthly }

// WeeklyToMonthlyTo is the highest count between once per week and once per
// month, one below DailyToWeeklyFrom.
func (d Data) WeeklyToMonthlyTo() int { return d.DailyToWeeklyFrom() - 1 }
