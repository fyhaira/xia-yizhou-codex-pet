# Installation

## Requirements

- Apple-silicon Mac running macOS 14 or later.
- One exact supported ChatGPT/Codex build listed in [compatibility](compatibility.md).
- Enough free space for a private managed copy of the installed application.

## Procedure

1. Download the ZIP and checksum file from the same GitHub Release.
2. Verify the archive:

   ```sh
   shasum -a 256 -c checksums.txt
   ```

3. Extract the ZIP in Finder.
4. Quit the official app, Codex Pet Toolkit, other managed/QA copies, and wait for their helpers to exit.
5. Open the installer. Run **Dry Run** before **Install**.
6. Confirm that the detected version, build, and architecture exactly match a supported manifest.

The current project is not Apple-notarized. If macOS blocks the app, confirm that the archive checksum matches the published value, then use Finder's standard control-click **Open** flow. Do not disable Gatekeeper globally and do not run copied Terminal bypass commands.

The installer does not patch the official app. It installs the pet payload and builds a separately managed runtime under the user's Application Support directory.
