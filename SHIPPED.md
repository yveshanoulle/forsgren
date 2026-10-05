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
