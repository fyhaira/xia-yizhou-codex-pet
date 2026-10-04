# Compatibility

The installer uses exact, fail-closed compatibility manifests. It does not select a nearby version or assume that a later Codex build is compatible.

| Version | Build | Architecture | Accepted features |
|---|---:|---|---|
| 26.908.40834 | 8881 | macOS arm64 | gaze, durable running/review, sleep |
| 26.915.31945 | 9922 | macOS arm64 | gaze, durable running/review, sleep |
| 26.917.62051 | 10789 | macOS arm64 | gaze, durable running/review, sleep |
| 26.924.20706 | 11431 | macOS arm64 | gaze, durable running/review, sleep |

The packaged engine is pinned to Codex Pet Interaction Enhancer commit `69818621da1c850a28ef9aa023126338d65ffc1b` and `@electron/asar` 4.1.0.

When Codex updates, keep using the official app until an exact compatibility update is validated. Do not force the installer to accept an unknown build.
