# forsgren conventions

How work is tracked in this repo: forsgren's files and the rules for them.

## Files

- [TODO.md](TODO.md) — **open** items only, one line per open GitHub issue, with its link.
- [SHIPPED.md](SHIPPED.md) — completed work, append-only history.
- GitHub issues on [yveshanoulle/forsgren](https://github.com/yveshanoulle/forsgren/issues) — the plan, the step ladder and Yves's rulings for each unit live on its issue.

## Rules

1. **`TODO.md` is for OPEN items only.** When something ships, MOVE it to `SHIPPED.md` in the same commit. No `✅` lines, no struck-through entries.
2. **One sentence plus the issue link per TODO entry.** The detail, the ladder and the acceptance criteria live on the issue, so there is one place to edit.
3. **Every entry has a verifiable done condition or an unblock condition** — on its issue.
4. **Commits link their issue** (`forsgren#N` or `#N` in the message); a commit on an issue is on `main` (no pull requests).
5. **File links are relative to the repository root** in this file, `TODO.md`, `SHIPPED.md` and `CLAUDE.md`, so they work in any checkout and on GitHub.

## Code

- Go module `github.com/yveshanoulle/forsgren`, `go 1.26.1`. `cmd/forsgren/` is the composition root and stays thin; the work lives in `internal/`.
- Go production files stay at or under 600 lines; functions stay short.
- Page templates are `html/template` files embedded with `//go:embed` (`internal/page/templates/{layout,pages}/`), never `text/template`: the page is meant to be public.
- Go tools are pinned through `go.mod` `tool` directives and `go.sum`, never installed globally.
- `gofmt`: auto-fix (`gofmt -w`) in `FBP.sh`'s local run, check-only (`gofmt -l`) in `sfl.sh` and CI.
- The generated site goes to `.build/site/` and is not committed.
- Every gate is a script named by a row of `Scripts/gate_report_order.txt`; every `Scripts/test_*.sh` is named by a row.

## Versions

What a forsgren release is, by what it asks of an installation (forsgren#78):

- **Patch:** fixes only. Nothing new for the installation to do or see.
- **Minor:** new behaviour, or anything that asks the installation for something (a permission, a secret, a file, a config key).
- **Major:** an installation that does nothing would stop working.

A release that declares a new need in `internal/needs/needs.yml` therefore cannot be a patch: every entry's version has patch number 0 (x.y.0). `TestEveryNeedIsIntroducedInAMinorOrMajor` pins that part.
