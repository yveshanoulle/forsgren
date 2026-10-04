# Security policy

## Supported versions

Security fixes go to `main`, and to the latest release once releases exist.
Older releases are not patched: update to the latest one.

## Reporting a vulnerability

Report it privately, through GitHub's private vulnerability reporting: on
the repository's Security tab, choose "Report a vulnerability", or go
straight to
<https://github.com/yveshanoulle/forsgren/security/advisories/new>.

Never report a vulnerability in a public issue, a pull request or a
discussion: that publishes it before there is a fix.

## What to include

The affected version, steps to reproduce, the impact, and a proof of concept
if you have one.

## What to expect

forsgren is a one-maintainer project. Your report is acknowledged, and
looked at and fixed, as soon as possible. You get a reply within 7 days,
telling you what was decided and why. The conversation stays in the private
advisory until a fix is out, and the advisory credits you if you want it.

## Scope

forsgren reads GitHub data (workflow runs, deployments, issues) with the
token an installation gives it. Reports about how forsgren handles that
token, for example leaking it into output, logs or the published page, or
using it for more than reading, are in scope, as are reports about the
static page publishing anything beyond numbers and dates (see README,
Privacy).
