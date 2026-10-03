package history

import "testing"

// TestStreamOfARecord pins the stream collect (forsgren#16) and recovery
// time (forsgren#17) share: the repository ignoring case, the kind, the
// environment or workflow and the task; a release's tag is not part of it.
func TestStreamOfARecord(t *testing.T) {
	base := rec(1, 0)
	base.Task = "migrate"
	upper, release, other := base, base, base
	upper.Repository = "Acme/App"
	release.Kind, release.Name = KindRelease, ""
	other.Task = "seed"
	want := Stream{Repository: "acme/app", Kind: KindEnvironment, Name: "production", Task: "migrate"}
	if got := upper.Stream(); got != want {
		t.Errorf("want %+v, got %+v", want, got)
	}
	if got := release.Stream(); got.Task != "" || got.Kind != KindRelease {
		t.Errorf("want a release's stream without its tag, got %+v", got)
	}
	if base.Stream() == other.Stream() {
		t.Errorf("want two tasks to be two streams, got %+v", other.Stream())
	}
}

// TestChronologicalOrdersByCreatedAtThenID: the older deployment first, and
// by ID at the same created_at.
func TestChronologicalOrdersByCreatedAtThenID(t *testing.T) {
	cases := []struct {
		a, b Record
		want int
	}{
		{rec(9, 0), rec(1, 1), -1},
		{rec(1, 1), rec(9, 0), 1},
		{rec(1, 0), rec(2, 0), -1},
		{rec(2, 0), rec(2, 0), 0},
	}
	for _, c := range cases {
		if got := Chronological(c.a, c.b); got != c.want {
			t.Errorf("Chronological(%d at %v, %d at %v): want %d, got %d",
				c.a.ID, c.a.CreatedAt, c.b.ID, c.b.CreatedAt, c.want, got)
		}
	}
}
