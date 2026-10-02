# Contributing to forsgren

## Proposing a change

Open an issue first for anything larger than a typo, so the change can be
agreed before it is built. Then send a pull request against `main`. Every
change keeps the gates green: run `./FBP.sh --no-commit` (see README,
"Working on forsgren") before you push.

A pull request from outside the repository gets CI only after the
maintainer has approved its workflow run.

## Reporting a vulnerability

Never in a public issue or pull request: report it privately, as
[SECURITY.md](SECURITY.md) describes.

## Licence of contributions

forsgren is licensed under the European Union Public Licence v. 1.2
(EUPL-1.2), see [LICENSE](LICENSE). Contributions are accepted under the
same licence: inbound = outbound. There is no Contributor Licence Agreement
(CLA).

## Developer Certificate of Origin

Instead of a CLA, every contribution is made under the Developer
Certificate of Origin (DCO) 1.1, from <https://developercertificate.org>:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

You certify this by adding a `Signed-off-by` line to every commit, with
your real name and an email address you can be reached at:

```
Signed-off-by: Name <email>
```

`git commit -s` adds that line for you, from your `user.name` and
`user.email`. `./FBP.sh` signs off for you: every commit it makes, the
`*** RED ****` one included, is a `git commit --signoff`. A pull request with a commit that is not signed off is not
merged until it is.

### What the DCO check enforces

Every pull request runs the **DCO** workflow (`.github/workflows/dco.yml`).
It is red, naming the commit, when any commit of the pull request:

- has no `Signed-off-by: Name <email>` line as a trailer: the line must
  stand whole, in the last paragraph of the commit message (where
  `git commit -s` puts it). A `Signed-off-by` in the body text, in the
  middle of a line, or as the subject line does not count;
- is signed off with an email that is not the commit's author email
  (compared without case). Each author signs off their own commits;
- has no author email at all.

Merge commits are held to the same rule (`git merge --signoff`). To fix a red check, sign the
commits off and force-push the branch: `git commit --amend -s` for the
last commit, `git rebase --signoff main` for all of them.
