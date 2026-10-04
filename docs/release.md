# Release construction

The Git repository intentionally contains no Node binary, Interaction Enhancer checkout, app bundle, copied Codex application, or build output.

`installer/scripts/fetch-dependencies.sh` downloads the official Node.js 24.21.0 macOS arm64 archive and its official checksum list, verifies both pinned hashes, extracts the distribution into an ignored build-input directory, and fetches the exact Interaction Enhancer commit. The enhancer tree and lockfile dependency closure are verified before resource preparation.

`installer/scripts/build.sh` prepares the offline runtime resources, builds the native Swift installer, signs nested executables inside-out, and emits a local candidate under `dist/`. Ad-hoc signing is the default for structural QA. A future release build must provide an explicitly authorized Developer ID Application identity and complete notarization before claiming notarized status.

## GitHub Release assets

The proposed v1.1 release contains:

- `xia-yizhou-codex-pet-v1.1.zip`
- `checksums.txt`

The ZIP contains only:

- `Xia Yizhou Codex Pet.app`
- a short release README;
- `LICENSE`, `ASSET-TERMS.md`, `DISCLAIMER.md`, and `THIRD-PARTY-NOTICES.txt`.

The app internally contains the verified Xia payload, official upstream Node executable and license, pinned Interaction Enhancer engine and license, and npm dependency licenses. It does not contain the official ChatGPT/Codex app or user state.
