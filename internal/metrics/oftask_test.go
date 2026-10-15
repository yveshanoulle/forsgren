package metrics

import (
	"reflect"
	"testing"

	"github.com/yveshanoulle/forsgren/internal/history"
)

// serviceRow is the row of the service API of tableProjects over data.
func serviceRow(t *testing.T, data Data) Row {
	t.Helper()
	return rowNamed(t, Rows(tableProjects, data, now), "API")
}

// TestAServiceRowFollowsTheDoraWindow (forsgren#178): a service's row counts
// its task's deployment 45 days ago over a window of 90 days, not over 30.
func TestAServiceRowFollowsTheDoraWindow(t *testing.T) {
	records := []history.Record{
		appDeployment(1, "deploy-api", history.StateSuccess, 250*day),
		appDeployment(2, "deploy-api", history.StateSuccess, 45*day),
	}
	for days, want := range map[int]string{0: "0", 30: "0", 90: "1"} {
		got := serviceRow(t, Data{Records: records, DoraDays: days}).Frequency.NumberCell()
		if got != want {
			t.Errorf("DoraDays %d: want %s deployments in the service row, got %s", days, want, got)
		}
	}
}

// TestAServiceRowFollowsTheWorkingDay (forsgren#71, #178): 400 deployments of
// a service in 30 days are on demand at 8 hours (from 241) but only between
// once per hour and once per day at 24 hours (on demand from 721).
func TestAServiceRowFollowsTheWorkingDay(t *testing.T) {
	records := []history.Record{appDeployment(1, "deploy-api", history.StateSuccess, 40*day)}
	for id := int64(2); id < 402; id++ {
		records = append(records, appDeployment(id, "deploy-api", history.StateSuccess, day))
	}
	for hours, want := range map[int]Band{0: OnDemand, 8: OnDemand, 24: HourlyToDaily} {
		if got := serviceRow(t, Data{Records: records, WorkingHours: hours}).Frequency.Band; got != want {
			t.Errorf("WorkingHours %d: want the service row %v, got %v", hours, want, got)
		}
	}
}

// TestAServiceDataKeepsEverySettingOfItsParent (forsgren#178): ofTask narrows
// the deployments, the commits and the failure issues and nothing else, so
// every other field of Data, a setting added later too, is the parent's.
func TestAServiceDataKeepsEverySettingOfItsParent(t *testing.T) {
	parent := Data{}
	fields := reflect.ValueOf(&parent).Elem()
	for i := range fields.NumField() {
		if fields.Field(i).Kind() == reflect.Int {
			fields.Field(i).SetInt(int64(7 + i))
		}
	}
	child := reflect.ValueOf(parent.ofTask("acme/app", "deploy-api"))
	for i := range fields.NumField() {
		name := fields.Type().Field(i).Name
		switch name {
		case "Records", "Commits", "Failures":
			continue
		}
		if !reflect.DeepEqual(child.Field(i).Interface(), fields.Field(i).Interface()) {
			t.Errorf("want ofTask to keep %s as %v, got %v", name, fields.Field(i), child.Field(i))
		}
	}
}
