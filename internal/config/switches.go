package config

// The boolean switches of forsgren#482 (decisions #480 A, #481 B, #488 A): the
// three TBD columns that can be turned off and the sub rows of every table,
// and week_page (forsgren#531, decision #533 A): whether the Week page is in
// the menu. Each is true unless the file says false; a value that is not true or
// false is a Rejection with true in force, as for auto_update. week_commits
// (forsgren#548, decision #549 A) is the one switch that is false unless the
// file says true, a refused value keeping false: whether the Week page shows
// its Commits columns.

var (
	tbdTimeToMain    = booleanKey{ErrTbdTimeToMain, "tbd_time_to_main", true}
	tbdPRLeadTime    = booleanKey{ErrTbdPRLeadTime, "tbd_pr_lead_time", true}
	tbdBotPRLeadTime = booleanKey{ErrTbdBotPRLeadTime, "tbd_bot_pr_lead_time", true}
	subRows          = booleanKey{ErrSubRows, "sub_rows", true}
	weekPage         = booleanKey{ErrWeekPage, "week_page", true}
	weekCommits      = booleanKey{ErrWeekCommits, "week_commits", false}
)

// switches are the switches in force.
type switches struct {
	tbdTimeToMain, tbdPRLeadTime, tbdBotPRLeadTime, subRows, weekPage, weekCommits bool
}

// switches is the switches the file writes, the default for each it leaves out
// or does not accept, and the rejections of those it does not accept.
func (f fileConfig) switches() (switches, []*Rejection) {
	var s switches
	var rejected [6]*Rejection
	s.tbdTimeToMain, rejected[0] = tbdTimeToMain.value(f.TbdTimeToMain)
	s.tbdPRLeadTime, rejected[1] = tbdPRLeadTime.value(f.TbdPRLeadTime)
	s.tbdBotPRLeadTime, rejected[2] = tbdBotPRLeadTime.value(f.TbdBotPRLeadTime)
	s.subRows, rejected[3] = subRows.value(f.SubRows)
	s.weekPage, rejected[4] = weekPage.value(f.WeekPage)
	s.weekCommits, rejected[5] = weekCommits.value(f.WeekCommits)
	return s, rejected[:]
}
