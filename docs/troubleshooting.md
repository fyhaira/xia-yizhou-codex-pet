# Troubleshooting

## Unsupported build

The installed app does not match an exact compatibility manifest. No runtime should be built. Wait for a validated project update.

## Codex is still running

Quit the official app, managed runtime, Toolkit, QA copies, and relevant helpers. The installer never kills them automatically.

## Existing Xia package conflict

An existing `xia-yizhou` package differs from the published payload. The installer refuses to overwrite unknown or privately modified artwork. Preserve the package and decide manually which version you want before retrying.

## Migrated pet identity cannot be verified

The shared profile selected a cloud-style pet identity, but the installer could not uniquely prove that it corresponds to the local Xia package. The installer fails closed rather than aliasing an unrelated pet.

## macOS blocks the installer

Verify the Release checksum first. The project is not currently notarized, so use Finder's standard control-click **Open** flow if you trust the verified release. Do not disable Gatekeeper globally.

## Reporting a problem

Include the installer version, macOS version, Codex version/build, and the bounded error category. Do not upload authentication data, profiles, conversation content, account information, or private copyrighted reference material.
