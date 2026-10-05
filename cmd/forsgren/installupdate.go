package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"regexp"

	"github.com/yveshanoulle/forsgren/internal/github"
	"github.com/yveshanoulle/forsgren/internal/update"
)

// errNoCaller is an installation whose branch has none of the caller files.
var errNoCaller = errors.New("no caller file of forsgren at the head of the branch")

// versionFlag and shaFlag are what --version and --sha are: a release version
// of forsgren and a full commit sha.
var (
	versionFlag = regexp.MustCompile(`^v\d+\.\d+\.\d+$`)
	shaFlag     = regexp.MustCompile(`^[0-9a-f]{40}$`)
)

// installUpdate is the subcommand the update workflow runs when check-update
// found a release within the level: `forsgren install-update --repo
// <owner/name> --branch <branch> --version <vX.Y.Z> --sha <sha>` moves the
// pins of the caller files of the branch's head to that release in one commit
// and says `installed <version> on <branch> as <commit>`. Exit 0 is done, 2 a
// usage or GitHub error, or no caller file at the head (forsgren#62). It
// writes with GITHUB_TOKEN, which needs contents: write.
func installUpdate(args []string, stdout, stderr io.Writer) int {
	in, ok := installInput(args, stderr)
	if !ok {
		return 2
	}
	commit, err := install(context.Background(), in)
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "install-update: %v\n", err)
		return 2
	}
	_, _ = fmt.Fprintf(stdout, "installed %s on %s as %s\n", in.version, in.branch, commit)
	return 0
}

// installation is what install-update is asked: the repository, its branch
// and the release, with the commit its tag points at.
type installation struct {
	repo    string
	branch  string
	version string
	sha     string
}

// flagCheck is one flag's value, whether it is a valid one, and what it must
// be.
type flagCheck struct {
	ok   bool
	got  string
	want string
}

// installInput parses install-update's four required flags and checks them.
// It returns false once the error is on stderr.
func installInput(args []string, stderr io.Writer) (installation, bool) {
	values, ok := requiredFlags(stderr, args, "install-update",
		flagSpec{"repo", "<owner/name>", "the data repository"},
		flagSpec{"branch", "<branch>", "its branch the pins are moved on"},
		flagSpec{"version", "<vX.Y.Z>", "the release to install"},
		flagSpec{"sha", "<40-hex>", "the commit of that release's tag"})
	if !ok {
		return installation{}, false
	}
	for _, c := range []flagCheck{
		{github.IsRepositoryName(values[0]), values[0], "--repo <owner/name> must be one owner/name"},
		{versionFlag.MatchString(values[2]), values[2], "--version <vX.Y.Z> must be a release version"},
		{shaFlag.MatchString(values[3]), values[3], "--sha <40-hex> must be a full commit sha"},
	} {
		if !c.ok {
			_, _ = fmt.Fprintf(stderr, "install-update: %s, got %q\n", c.want, c.got)
			return installation{}, false
		}
	}
	return installation{repo: values[0], branch: values[1], version: values[2], sha: values[3]}, true
}

// install moves the pins of the caller files at the branch's tip to the
// release, in one commit that follows that tip, and returns the commit.
func install(ctx context.Context, in installation) (string, error) {
	client, err := jobClient(github.DefaultMaxPages)
	if err != nil {
		return "", err
	}
	tip, err := client.BranchTip(ctx, in.repo, in.branch)
	if err != nil {
		return "", err
	}
	files, err := repinnedCallers(ctx, client, in, tip)
	if err != nil {
		return "", err
	}
	if len(files) == 0 {
		return "", fmt.Errorf("%w %s of %s", errNoCaller, in.branch, in.repo)
	}
	message := fmt.Sprintf("forsgren: install %s within auto_update_level (forsgren#62)", in.version)
	commit := github.BranchCommit{Branch: in.branch, Base: tip, Message: message, Files: files}
	return client.CommitFiles(ctx, in.repo, commit)
}

// repinnedCallers are the caller files that exist at tip, each with its pin
// moved to the release, by repository path. A file that is not there is
// skipped; any other failure to read or move one is an error.
func repinnedCallers(
	ctx context.Context, client *github.Client, in installation, tip string,
) (map[string]string, error) {
	files := map[string]string{}
	workflows := update.CallerWorkflows()
	for _, path := range update.Callers() {
		content, found, err := client.FileAt(ctx, in.repo, github.FileRef{Ref: tip, Path: path})
		if err != nil {
			return nil, err
		}
		if !found {
			continue
		}
		pin := update.Target{Workflow: workflows[path], Version: in.version, SHA: in.sha}
		if files[path], err = update.Repin(content, pin); err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
	}
	return files, nil
}
