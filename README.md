# Edith

Edith is a macOS app built from extensions: coding agents, terminals, remote
machines, music, clipboard, downloads and more, in one window. It needs macOS 14
or later on Apple silicon.

This repository is home to Edith's signed releases and its community. The source
code is private, so this is where you download Edith and where you tell us what
is broken or what you want next.

## Download

- Latest release: [Edith.dmg](https://github.com/pulkitxm/edith-releases/releases/latest/download/Edith.dmg)
- Homebrew: `brew install --cask pulkitxm/tap/edith`
- Website: [edith.pulkit.page](https://edith.pulkit.page)

Edith updates itself. Extensions install and update from the Extensions page in
the app.

## Report a bug

[Open a bug report](https://github.com/pulkitxm/edith-releases/issues/new?template=bug_report.yml).
Include your Edith version (Edith menu, About Edith, or `ed version`), your
macOS version and the steps that make it happen. Search the
[open issues](https://github.com/pulkitxm/edith-releases/issues) first and add
to an existing one when it is the same problem.

## Request a feature

[Open a feature request](https://github.com/pulkitxm/edith-releases/issues/new?template=feature_request.yml)
for a new extension, a change to an existing one, or anything in the app.
Describe the problem you want solved before the solution you have in mind.

## Ask a question

Use [Discussions](https://github.com/pulkitxm/edith-releases/discussions) for
questions, setups and ideas that are not ready to be a request.

## Security

Do not open a public issue for a vulnerability. Report it privately as described
in [SECURITY.md](SECURITY.md).

## Pull requests

This repository holds release files only, so code changes cannot be merged
here. Describe the fix in an issue instead and it will be made in the source.

## What is in a release

| Release | Holds |
| --- | --- |
| `vX.Y.Z` | `Edith.dmg` and the signed Sparkle appcast for that version |
| `extensions/<id>/<version>-<fingerprint>` | One signed extension package |
| `extension-catalog-v1` | The signed extension catalog the app reads |

Made by Pulkit.
