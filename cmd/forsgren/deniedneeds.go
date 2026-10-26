package main

import (
	"fmt"

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
// request reads first, then the push reads. A missing file notes none. A
// file that cannot be read, or is in no known format, is an error naming the
// read and the file: the refusal may still stand, so the caller must not
// write or close the setup issue (forsgren#395).
func refusedNeeds(pullsPath, pushesPath string) ([]needs.Need, error) {
	items, err := refusedItems(pullsPath, "pull request", history.LoadPullsDenied, needs.Refused)
	if err != nil {
		return nil, err
	}
	pushes, err := refusedItems(pushesPath, "push", history.LoadPushesDenied, needs.RefusedPushes)
	if err != nil {
		return nil, err
	}
	return append(items, pushes...), nil
}

// refusedItems are the items of the file at path, which load reads and items
// turn into setup issue items; noun names the read in the error.
func refusedItems(path, noun string, load func(string) (history.Denied, error),
	items func(history.Denied) []needs.Need) ([]needs.Need, error) {
	denied, err := load(path)
	if err != nil {
		return nil, fmt.Errorf("the refused %s reads are unknown (%s): %w", noun, path, err)
	}
	return items(denied), nil
}
