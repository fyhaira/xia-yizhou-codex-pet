# Xia Yizhou Codex Pet

> A tiny fan-made Codex companion for anyone who wished Xia Yizhou (Caleb) could hang out on their desktop too. 🍎

I spend a lot of time watching Codex work, and at some point I started wondering: could Caleb sit there with me while it does?

That small idea slowly turned into this desktop pet. He follows your pointer with his eyes, reacts while Codex is working or waiting for you to review something, lets you drag him around, and eventually falls asleep when things have been quiet for a while. 💤

I wanted him to feel cute and fun, but I also wanted installing him to be something other fans could feel comfortable with. The result is an unofficial, non-commercial fan project with a deliberately cautious installer.

[中文说明](README.zh-CN.md)

## What Caleb does

- 👀 Looks around the full 360° as you move the physical pointer.
- Shows a continuing working animation while Codex is busy.
- Stays in his review animation while an unread result is waiting.
- Can be picked up and dragged around.
- Falls asleep after a period of real inactivity, then wakes when you interact or work resumes.

The generic runtime work comes from the separately maintained [Codex Pet Interaction Enhancer](https://github.com/fyhaira/codex-pet-interaction-enhancer), pinned to one exact validated revision.

## A small heads-up ⚠️

This is still a **Developer Preview / Experimental** fan project. It supports only the exact builds below. If your version does not match, the installer stops before changing anything instead of trying to guess.

## Compatibility

| Codex/ChatGPT version | Build | Platform | Status |
|---|---:|---|---|
| 26.908.40834 | 8881 | macOS arm64 | Supported |
| 26.915.31945 | 9922 | macOS arm64 | Supported |
| 26.917.62051 | 10789 | macOS arm64 | Supported |
| 26.924.20706 | 11431 | macOS arm64 | Supported |

Only these exact macOS arm64 combinations are currently supported. Every other version, build, platform, or architecture fails closed.

## Installation 🛠️

1. Download the versioned ZIP and `checksums.txt` from the matching GitHub Release.
2. Verify the ZIP checksum.
3. Quit ChatGPT/Codex, Codex Pet Toolkit, QA copies, and their remaining helpers.
4. Open `Xia Yizhou Codex Pet.app`.
5. Run **Dry Run** first and check the detected build. If everything looks right, choose **Install**.
6. The installer creates and launches a private managed runtime copy. It never patches `/Applications/ChatGPT.app` in place.

This project is **not currently Apple-notarized**, so macOS may show its standard warning for downloaded software. Please do not disable Gatekeeper globally. See [Installation](docs/installation.md) for the current safe opening guidance and release-status checks.

## Uninstall

Quit the relevant Codex processes, reopen the same installer, and choose **Uninstall**. The installer removes only state it can prove it installed. If an identical Xia package was already there before installation, it is preserved. See [Uninstall](docs/uninstall.md).

## How installation protects your setup

- The official ChatGPT/Codex app stays read-only and is never patched in place.
- Runtime changes are prepared in temporary staging, checked, and only then promoted as a private managed copy.
- Exact build manifests, source hashes, ASAR integrity, signatures, pet hashes, and identity associations are all verified fail-closed.
- Process guards stop installation while the official app, managed copies, QA copies, or another process using protected Codex state is still active.
- Install and uninstall use bounded backups, an operation lock, rollback, and ownership checks.
- Your tasks, projects, authentication, profile, unrelated pets, and daily-use Toolkit remain outside the installer's ownership.

## What is and is not in this repository

The Git repository contains the installer source, the three final pet payload files, documentation, and release tooling.

It does **not** contain Codex binaries, managed runtimes, Node binaries, app bundles, build caches, profiles, backups, diagnostics, official reference images, or private source-art material.

Release construction downloads and verifies the exact official Node.js archive and the exact pinned Interaction Enhancer commit. A Release ZIP may carry those verified dependencies inside the installer app, but they are never committed to Git.

## Current limitations

- macOS arm64 only.
- Exact listed Codex builds only.
- Not currently Apple-notarized.
- A Codex update will normally need a newly validated compatibility manifest and installer release.
- This is unofficial and depends on Codex internals, so a future update may temporarily break it.

See [Compatibility](docs/compatibility.md) and [Troubleshooting](docs/troubleshooting.md).

## Legal

Installer code is source-available under the [Personal Use License](LICENSE). The Xia payload has separate [asset terms](ASSET-TERMS.md). Please also read the [licensing structure](docs/licensing.md), [disclaimer](DISCLAIMER.md), and [third-party notices](THIRD-PARTY-NOTICES.txt).
