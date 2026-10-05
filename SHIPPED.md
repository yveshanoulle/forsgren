# Shipped — forsgren

History of completed work on forsgren. Append-only.

Conventions:
[CONVENTIONS.md](CONVENTIONS.md).
Active work lives in
[TODO.md](TODO.md).

---

## 2026-10-02 — bootstrap: the estate's build, gates, CI and conventions for forsgren ([#1](https://github.com/yveshanoulle/forsgren/issues/1))

Twenty-five steps, `da7bf40` … this review (step 25), each landed through
`FBP.sh`. forsgren now builds like the sites and checks like
another estate repository's PRE → BUILD → POST sfl and FBP, driven from one
order file that CI runs phase by phase on forsgren's own runner, plus
another estate repository's Go gates, around a Go module that renders one placeholder page
through `html/template`.

**What landed, by step:** 1–2 sfl/FBP with the guarded commit block and
page-count fixtures, the Go module, the placeholder page, the site build,
Go tests and gofmt; 3 the secret scan; 4 the tool installer and the exact Go
pin (`toolchain` line exported as `GOTOOLCHAIN`); 5 the commit-message
fixture must reach PRE; 6 the data guard; 7 npm (exact pins, lockfile,
`npm ci`, manifest policy, audit); 8 HTMLHint, Stylelint, lint coverage on
the generated page; 9 required pages; 10 privacy posture and repository
links; 11 HTML duplication on templates and generated page; 12 shellcheck,
yamllint, stray tracked files (12.1 no inherited suppression; 12.2 the data
guard made secret-class, its patterns as case arms); 13 script references;
14 CI (`quality.yml`, `run_ci_phase.sh`, gate wiring, trigger scope, report);
15 the flat-folder guard (15.1 go.mod ignores node_modules); 16 the
workflow-trigger gate; 17 action pins; 18 actionlint; 19 zizmor; 20 Go lint
and Go test duplication; 21 Go file length; 22 Go coverage ratchet; 23 go
mod tidy, govulncheck, deadcode; 24 refactor (one self-test harness); 25
review (docs checked against the code, comment truth, open points listed on
the issue).

**Yves's rulings on the way (all on #1):** Go, not Python; konenki's phases
and template layout too; the script is `FBP.sh`; steps 1–2 in one FBP; Go
tools through go.mod `tool` lines; gofmt auto-fix in FBP, check-only in CI;
no gosec G101 exclusion; HTML duplication ported, not n/a; the
script-reference guard and the no-pull-request-trigger gate in the
bootstrap; code only in this repository, an installation's config and data
in a data repository made from a template forsgren will provide; install
and update designed in; docs from the start; an exclusion needs Yves's yes
on an issue, inherited suppressions are removed; the data guard is
secret-class with no suppression; the climb ban is n/a while the script
folder stays flat; the gate workflow keeps the name Quality.

Open points the steps left are in the step comments on #1; the template repository, its
workflow and the getting-started doc are in TODO.md.

---

## 2026-10-05 — the /scoring/ view, released as 0.1.3 ([#47](https://github.com/yveshanoulle/forsgren/issues/47))

`0e4d7e1` … the 0.1.3 version step, each step a red and its green through
`FBP.sh`. /scoring/ is a fourth page beside /standard/ and /numbers/, named
in every view's switch and selectable as `view: scoring`: each metric's DORA
Quick Check score alone (categorical bands (6 - band) x 2, percents
(100 - whole percent) / 10), `-` where a metric has no data, and an Overall
Performance column, the exact mean of the scored metrics in whole tenths,
half up, `-` when none is scored. Deployment frequency has data once a
successful deployment is recorded; an old last success scores 0, the
lowest band. The legend credits the Quick Check (dora.dev, © Google LLC,
CC BY 4.0). The page has its golden.

**Yves's rulings (all on #47):** whole percents rounded down; `-` for a
metric without data, Overall over the scored ones; the legend credit; the
scoring page shows scores only (numbers and scores side by side is #55);
`-` means not enough evidence, 0 means observed performance in the lowest
band, and "ever deployed" is the evidence for deployment frequency. A
longer first collect run is #57.

---

## 2026-10-05 — auto-update for Dependabot's forsgren bumps, released as 0.2.0 ([#58](https://github.com/yveshanoulle/forsgren/issues/58))

`f4c761a` … the 0.2.0 version step, each step a red and its green through
`FBP.sh`. Two config keys, `auto_update` (off when absent) and
`auto_update_level`, say whether and how far an installation lets a
Dependabot pull request that bumps forsgren's pin merge itself. The command
`forsgren check-update --config <path> --repo <owner/name> --pull <n>` decides:
exit 0 merges (printing `merge <old> to <new>`), exit 1 leaves the pull
request for a human with one reason line, exit 2 is a usage, configuration or
network error. The reusable `auto_update.yml` (workflow_call only, no
permissions of its own: the caller grants contents, pull-requests and actions
write) installs forsgren from its own commit, checks out the caller at the
pull request's base commit, runs the guard, merges (squash, branch deleted)
and then starts the installation's `forsgren.yml` on the default branch; a
failed merge fails the run and starts nothing. The docs, the refactor and the
review continue in [#60](https://github.com/yveshanoulle/forsgren/issues/60)
and [#59](https://github.com/yveshanoulle/forsgren/issues/59).

## 2026-10-05 — Dependabot's forsgren pull request comes as one, released as 0.2.1 ([#61](https://github.com/yveshanoulle/forsgren/issues/61))

An installation has two caller workflows that pin forsgren, `forsgren.yml`
and `forsgren-update.yml`. The guard now takes the caller files that exist in
the repository at the pull request's base commit (`Pull.Present`, filled by
`forsgren check-update` from the directory of `--config` and the guard's own
list of callers, `update.Callers`), and leaves a pull request for a human with
the reason `moves <file> but not <file>` when it moves one of two existing
callers and not the other. A repository with one caller, or none, behaves as
before. The starter config names the possible values of `auto_update_level`
in a comment.

## 2026-10-05 — auto-update fails closed on a caller lookup error, released as 0.2.2 ([#59](https://github.com/yveshanoulle/forsgren/issues/59))

`forsgren check-update` now exits 2 when looking up a caller file fails with
anything other than does-not-exist, instead of treating the file as absent and
letting the guard decide on a partial picture; the update stays unmerged until
the lookup works. A caller file that exists but has no pin change now gets a
readable reason in the guard's output. The level tests cover `auto_update_level`
with v0.2.1 to v0.2.2, the review pins were seen failing before they went
green, and the tests share their helpers instead of each building its own.

## 2026-10-05 — the newest release within the level installs by itself, released as 0.2.3 ([#62](https://github.com/yveshanoulle/forsgren/issues/62))

Dependabot proposes only the newest release, so a pull request beyond
`auto_update_level` used to leave a safe release within the level uninstalled.
`forsgren check-update` now exits 3 with `install <old> to <new> at <sha>` when
only the level leaves a pull request and forsgren has a published release
within it; `auto_update.yml` then runs the new `forsgren install-update`, which
moves both pins on the default branch in one commit through the API, based on
the branch head it read the files at and without force, and starts
`forsgren.yml`. The bigger pull request stays open for a human. The release
list (`PublishedReleases`), the newest-within-level pick, the pin rewrite and
the commit through the git data API are each tested, and the workflow's new
steps are pinned by `Scripts/test_auto_update_workflow.sh`.
