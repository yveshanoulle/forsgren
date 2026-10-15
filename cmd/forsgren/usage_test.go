package main

import (
	"bytes"
	"regexp"
	"slices"
	"sort"
	"strings"
	"testing"
)

var (
	// helpFlagLine is a flag in the output of `<command> -h`, which Go's flag
	// package prints for every flag its FlagSet defines: "  -name type".
	helpFlagLine = regexp.MustCompile(`(?m)^\s+-([A-Za-z][A-Za-z0-9-]*)`)
	// usageFlag is a flag named in the usage text: "--name".
	usageFlag = regexp.MustCompile(`--([A-Za-z][A-Za-z0-9-]*)`)
	// usageCommandStart begins a command's block of the usage text.
	usageCommandStart = regexp.MustCompile(`^(?:usage: |       )forsgren (\S+)`)
)

// definedFlags are the flags a command's FlagSet defines, read from what the
// command prints for -h, so a new flag is found without being listed here.
func definedFlags(t *testing.T, command string) []string {
	t.Helper()
	var stderr bytes.Buffer
	run([]string{command, "-h"}, &bytes.Buffer{}, &stderr)
	var names []string
	for _, m := range helpFlagLine.FindAllStringSubmatch(stderr.String(), -1) {
		if m[1] != "h" && m[1] != "help" {
			names = append(names, m[1])
		}
	}
	sort.Strings(names)
	return names
}

// usageBlocks splits the usage text into its commands: the flags each names.
func usageBlocks() map[string][]string {
	blocks := map[string][]string{}
	current := ""
	for _, line := range strings.Split(usage, "\n") {
		if m := usageCommandStart.FindStringSubmatch(line); m != nil {
			current = m[1]
			blocks[current] = []string{}
		}
		for _, f := range usageFlag.FindAllStringSubmatch(line, -1) {
			blocks[current] = append(blocks[current], f[1])
		}
	}
	for _, flags := range blocks {
		sort.Strings(flags)
	}
	return blocks
}

// TestUsageNamesEveryCommandAndEveryFlag keeps the printed usage equal to the
// commands and the flags they define, so a new flag cannot be left out of it
// again (forsgren#180).
func TestUsageNamesEveryCommandAndEveryFlag(t *testing.T) {
	blocks := usageBlocks()
	flagged := 0
	for command := range commands {
		defined := definedFlags(t, command)
		if len(defined) > 0 {
			flagged++
		}
		named, listed := blocks[command]
		if !listed {
			t.Errorf("the usage text does not list the command %s", command)
			continue
		}
		if !slices.Equal(defined, named) {
			t.Errorf("%s: the usage names flags %v, the command defines %v", command, named, defined)
		}
	}
	// A reader of -h that found no flag anywhere would make every comparison
	// above pass on empty sets.
	if flagged < len(commands)-1 {
		t.Errorf("only %d of %d commands printed any flag for -h, want all but latest-release: the reader of -h is broken",
			flagged, len(commands))
	}
}
