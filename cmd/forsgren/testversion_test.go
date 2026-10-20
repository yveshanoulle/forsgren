package main

import (
	"os"
	"strconv"
	"strings"
	"testing"
)

// testVersion is the forsgren version every test of this package runs as:
// fixed, so a release changes no test and no golden (forsgren#237); the
// goldens of the page package are rendered as the same version.
const testVersion = "9.9.9"

// newerRelease is the patch release after testVersion, the "newer release"
// of the examples.
var newerRelease = nextPatch(testVersion)

// nextPatch is the version one patch release after v.
func nextPatch(v string) string {
	parts := strings.Split(v, ".")
	patch, err := strconv.Atoi(parts[2])
	if err != nil {
		panic(err)
	}
	return parts[0] + "." + parts[1] + "." + strconv.Itoa(patch+1)
}

// releasedVersion is var version as built, which only the docs test, that
// reads the docs against the release, still needs.
var releasedVersion = version

func TestMain(m *testing.M) {
	version = testVersion
	os.Exit(m.Run())
}
