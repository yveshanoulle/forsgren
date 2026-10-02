# TODO — forsgren

**OPEN items only.** Completed work moves to
[/Users/yveshanoulle/Sources/forsgren/SHIPPED.md](/Users/yveshanoulle/Sources/forsgren/SHIPPED.md)
in the same commit — see
[/Users/yveshanoulle/Sources/forsgren/CONVENTIONS.md](/Users/yveshanoulle/Sources/forsgren/CONVENTIONS.md).

## Open

- npm: keep `node_modules` in sync with the lockfile (reinstall on a lockfile change) and pin node — [#2](https://github.com/yveshanoulle/forsgren/issues/2)

## After the bootstrap (no issue yet; Yves's ruling of 2026-10-01 on [#1](https://github.com/yveshanoulle/forsgren/issues/1))

- A template repository for installations: one config file, a data folder, and a scheduled workflow on GitHub-hosted runners.
- That template's workflow: install a pinned forsgren, run `collect` and `render`, commit `history.csv`, publish the page.
- A getting-started doc written for strangers, from "Use this template" to a published page.
