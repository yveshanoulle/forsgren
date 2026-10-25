package main

import (
	"fmt"
	"io"

	"github.com/yveshanoulle/forsgren/internal/history"
	"github.com/yveshanoulle/forsgren/internal/needs"
)

// defaultPullsDenied is where collect writes the refused pull request reads,
// beside the history the metrics workflow collects into (forsgren#337), and
// defaultPushesDenied the refused push reads (forsgren#414).
const (
	defaultPullsDenied  = "data/pulls_denied.csv"
	defaultPushesDenied = "data/pushes_denied.csv"
)

// refusedNeeds are the setup issue's items for the reads the files at the two
// paths note as refused (forsgren#321, step 2, and forsgren#414): the pull
// request reads first, then the push reads. A missing file notes none; one in
// no known format is a note on stderr and none, never a failure (collect
// refuses such a file before it reads anything).
func refusedNeeds(pullsPath, pushesPath string, stderr io.Writer) []needs.Need {
	items := refusedItems(pullsPath, "pull request", history.LoadPullsDenied, needs.Refused, stderr)
	return append(items, refusedItems(pushesPath, "push", history.LoadPushesDenied, needs.RefusedPushes, stderr)...)
}

// refusedItems are the items of the file at path, which load reads and items
// turn into setup issue items; noun names the read in the stderr note.
func refusedItems(path, noun string, load func(string) (history.Denied, error),
	items func(history.Denied) []needs.Need, stderr io.Writer) []needs.Need {
	denied, err := load(path)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "check-needs: the refused %s reads are unknown: %v\n", noun, err)
		return nil
	}
	return items(denied)
}
