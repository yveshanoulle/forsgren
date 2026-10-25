package main

import (
	"fmt"
	"io"

	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// defaultPullsDenied is where collect writes the refused pull request reads,
// beside the history the metrics workflow collects into (forsgren#337).
const defaultPullsDenied = "data/pulls_denied.csv"

// refusedNeeds are the setup issue's items for the pull request reads the
// file at path notes as refused (forsgren#321, step 2). A missing file notes
// none; one in no known format is a note on stderr and none, never a failure
// (collect refuses such a file before it reads anything).
func refusedNeeds(path string, stderr io.Writer) []needs.Need {
	denied, err := history.LoadPullsDenied(path)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-needs: the refused pull request reads are unknown: %v\n", err)
		return nil
	}
	return needs.Refused(denied)
}
