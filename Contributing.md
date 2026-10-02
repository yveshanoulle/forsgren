# Contributing to Forsgren

Thank you for considering a contribution to Forsgren.

Forsgren exists to make DORA metrics easier to calculate, understand, and publish in a transparent and reproducible way. Contributions are welcome from people with different backgrounds: software engineers, researchers, DevOps practitioners, technical writers, users of DORA metrics, and anyone who can help improve the project.

This document explains how to contribute effectively.

## Ways to contribute

There are many useful ways to contribute, including:

- reporting bugs;
- improving documentation;
- improving examples;
- adding or improving tests;
- fixing defects;
- improving portability across platforms and CI/CD systems;
- improving installation or configuration;
- improving metric calculation or presentation;
- proposing new integrations;
- improving security, reliability, or maintainability;
- providing references or evidence that improve how DORA concepts are represented.

A contribution does not need to involve code.

## Before you start

Small, self-contained changes can usually go directly to a pull request.

Examples include:

- typo fixes;
- documentation corrections;
- small test improvements;
- straightforward bug fixes with an obvious expected result.

For larger or potentially disruptive changes, please open an issue or discussion before investing significant effort.

This is especially important for changes involving:

- DORA metric definitions or interpretation;
- public interfaces;
- stored data formats;
- compatibility;
- security;
- architecture;
- new dependencies;
- GitHub Actions or release infrastructure;
- behaviour that existing users may rely on.

Early discussion helps avoid two contributors solving the same problem differently and gives maintainers an opportunity to explain constraints that may not yet be obvious from the code.

## Principles

### Prefer evidence over convention

Forsgren deals with measurements that people may use to understand software delivery performance.

When proposing a behavioural change, metric interpretation, or technical rule, explain the reasoning behind it.

Where appropriate, support the proposal with:

- tests;
- references;
- data;
- reproducible examples;
- relevant DORA research or documentation.

"Other projects do it this way" can be useful context, but it is not by itself a reason for Forsgren to do the same.

### Make important assumptions executable where practical

If a rule is important enough for the project to depend on, prefer expressing it in an automated test, validation script, invariant, or quality gate rather than documenting it only in prose.

Documentation remains important, but important project behaviour should be difficult to change accidentally.

### Prefer explicit behaviour

Avoid relying on hidden assumptions, undocumented defaults, or behaviour that only works because of the current environment.

A future contributor should be able to understand why something works and what guarantees it depends on.

### Keep Forsgren portable

Forsgren should avoid unnecessary coupling to a specific:

- CI/CD provider;
- hosting platform;
- operating system;
- repository structure;
- deployment system.

Platform-specific integrations are welcome, but the underlying concepts and metric definitions should remain as portable as reasonably possible.

### Challenge ideas, not people

Technical disagreement is expected and useful.

Challenge assumptions, implementations, evidence, and trade-offs directly. Do not attack or diminish the person presenting them.

All contributors must follow the project's `CODE_OF_CONDUCT.md`.

## Setting up the project

Start by cloning or forking the repository and following the setup instructions in the project README.

Before making changes, make sure the existing quality checks pass in your local environment where practical.

If the project provides scripts for running tests or quality gates, prefer those scripts over recreating the commands manually. This reduces the chance that local testing differs from what CI will run.

## Making a change

Keep changes focused.

A pull request should ideally solve one problem or introduce one coherent improvement.

Avoid mixing unrelated refactoring, formatting, dependency upgrades, and behavioural changes into the same pull request unless they genuinely need to be changed together.

When modifying existing behaviour:

1. understand the current behaviour;
2. identify what should change;
3. add or update tests where appropriate;
4. make the smallest change that satisfies the requirement;
5. run the relevant quality gates;
6. update documentation when the observable behaviour changes.

If you discover an unrelated issue while working on a contribution, prefer opening a separate issue or pull request.

## Tests and quality gates

Changes should leave the repository in a passing state.

Where appropriate:

- bug fixes should include a regression test;
- new behaviour should include tests;
- important invariants should be pinned by tests;
- existing tests should not be weakened merely to make a change pass.

If a test must be changed because the expected behaviour itself has changed, explain that explicitly in the pull request.

Do not silently remove, bypass, or weaken a quality gate.

If a quality rule genuinely needs an exception, make the exception narrow and explain why it exists.

## Changes to DORA metric behaviour

Changes affecting how Forsgren calculates or interprets DORA metrics require particular care.

A change must not silently redefine a metric.

If your contribution changes the meaning, inputs, classification, aggregation, or interpretation of a DORA metric, the pull request should explain:

- which metric is affected;
- what behaviour exists today;
- what behaviour is proposed;
- why the change is needed;
- which source or evidence supports the interpretation;
- whether existing results may change;
- whether the change affects backwards compatibility;
- how the behaviour is tested.

Where authoritative DORA material exists, prefer it over secondary interpretations.

If multiple reasonable interpretations exist, make the ambiguity explicit rather than presenting one interpretation as undisputed fact.

## Dependencies

New dependencies have a long-term maintenance and security cost.

Before adding one, consider whether the same result can reasonably be achieved using:

- existing project dependencies;
- standard platform tools;
- a small amount of maintainable project code.

A new dependency may still be the right choice, but the pull request should make that trade-off visible when it is significant.

## Pull requests

A useful pull request description explains:

- what changed;
- why the change is needed;
- how it was tested;
- any important design decisions;
- known limitations;
- compatibility implications;
- remaining follow-up work, if any.

For non-trivial changes, include enough context that a reviewer does not have to reconstruct the reasoning from the code alone.

Small pull requests are generally easier to review and safer to merge than large ones.

## Review

Review is intended to improve the change and protect the long-term quality of the project.

Review comments may question:

- assumptions;
- implementation choices;
- missing tests;
- failure modes;
- security consequences;
- maintainability;
- portability;
- compatibility;
- unnecessary complexity.

Contributors are encouraged to question reviewer assumptions as well.

The goal is not consensus for its own sake. The goal is a change whose reasoning, risks, and consequences are understood.

A requested change should ideally explain the concern it is addressing rather than merely prescribe a different implementation.

## Decision making

Not every technical question has an objectively correct answer.

When alternatives exist, decisions should consider factors such as:

- correctness;
- evidence;
- simplicity;
- testability;
- maintainability;
- security;
- portability;
- backwards compatibility;
- operational risk.

Important decisions should be recorded where future contributors can discover the reasoning behind them.

## Documentation

Update documentation when your contribution changes something users or contributors need to know.

Documentation should describe the behaviour that actually exists.

Avoid documenting planned behaviour as though it has already been implemented.

Examples and commands should be realistic and, where practical, executable.

## Security issues

Do not publicly disclose a vulnerability that could put users or infrastructure at risk.

Follow the process described in `SECURITY.md`.

If the project does not yet contain a `SECURITY.md`, contact the maintainers privately rather than opening a public issue with exploit details.

## Code of Conduct

Participation in Forsgren is governed by the project's `CODE_OF_CONDUCT.md`, based on Contributor Covenant 3.0.

By participating in the project, you agree to follow that Code of Conduct.

## Licensing

By submitting a contribution, you agree that your contribution may be distributed under the license used by the Forsgren project.

Make sure you have the right to contribute any code, documentation, data, or other material you submit.

Do not copy material from another project unless its license allows that use and any required attribution is preserved.

## Questions

If you are unsure whether an idea fits Forsgren, open an issue or discussion.

A short conversation before implementation is often cheaper than rewriting a contribution after review.
