package update

import (
	"testing"

	"github.com/yveshanoulle/forsgren/internal/config"
)

func TestNewestWithin(t *testing.T) {
	rel := func(tag string) Published { return Published{Tag: tag, SHA: "sha-" + tag} }
	draft := func(tag string) Published { p := rel(tag); p.Draft = true; return p }
	pre := func(tag string) Published { p := rel(tag); p.Prerelease = true; return p }
	tests := []struct {
		name     string
		level    string
		releases []Published
		want     string
	}{
		{"patch skips a draft and a minor", config.LevelPatch,
			[]Published{rel("v0.2.2"), draft("v0.2.3"), rel("v0.3.0")}, "v0.2.2"},
		{"minor takes the minor", config.LevelMinor,
			[]Published{rel("v0.2.2"), draft("v0.2.3"), rel("v0.3.0")}, "v0.3.0"},
		{"nothing newer within the level", config.LevelPatch,
			[]Published{rel("v0.2.1"), rel("v0.2.0"), rel("v0.3.0"), rel("v1.0.0")}, ""},
		{"a prerelease and a bad tag are skipped", config.LevelPatch,
			[]Published{pre("v0.2.4"), rel("v0.2.5-rc1"), rel("latest"), rel("v0.2.2")}, "v0.2.2"},
		{"an unordered list gives the highest, compared as numbers", config.LevelPatch,
			[]Published{rel("v0.2.3"), rel("v0.2.10"), rel("v0.2.2"), rel("v0.2.9")}, "v0.2.10"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := NewestWithin("v0.2.1", tt.level, tt.releases)
			if ok != (tt.want != "") || got.Tag != tt.want {
				t.Fatalf("NewestWithin = %q, %v; want %q", got.Tag, ok, tt.want)
			}
			if ok && got.SHA != "sha-"+tt.want {
				t.Errorf("SHA = %q, want the one of %s", got.SHA, tt.want)
			}
		})
	}
}
