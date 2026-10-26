package metrics

import (
	"testing"
	"time"
)

// The Mainline Lead Time of the TBD rows (forsgren#463, step 8, decisions
// #449 and #450): per repository, as the other push measures.

// TestTheTotalTbdRowCountsTheMainlineLeadTimeOfAllItsRepositories: the total
// of Acme Shop counts the commit pushed to acme/web and the one pushed to
// acme/app, each authored an hour before its push.
func TestTheTotalTbdRowCountsTheMainlineLeadTimeOfAllItsRepositories(t *testing.T) {
	total := TbdRows(tableProjects, tbdData(), now, nil)[0]
	wantLead(t, total.MainLead, 2, time.Hour)
	if total.MainLead.Project != "Acme Shop" {
		t.Errorf("want the lead time of Acme Shop, got %q", total.MainLead.Project)
	}
}

// TestARepositoryLabelTbdRowCountsItsOwnMainlineLeadTime: Website is acme/web
// alone, with the one commit pushed to it.
func TestARepositoryLabelTbdRowCountsItsOwnMainlineLeadTime(t *testing.T) {
	web := tbdRowNamed(t, TbdRows(tableProjects, tbdData(), now, nil), "Website")
	wantLead(t, web.MainLead, 1, time.Hour)
}

// TestAServiceTbdRowLeavesTheMainlineLeadTimeEmpty: it is per repository, so
// a service row (PushAbsent) has the zero value.
func TestAServiceTbdRowLeavesTheMainlineLeadTimeEmpty(t *testing.T) {
	api := tbdRowNamed(t, TbdRows(tableProjects, tbdData(), now, nil), "API")
	if api.MainLead != (MainlineLeadTime{}) || !api.PushAbsent {
		t.Errorf("want an empty lead time with PushAbsent, got %+v (absent %v)", api.MainLead, api.PushAbsent)
	}
}
