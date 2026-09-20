# AtomZero CI Tooling

This directory contains the helper scripts and configuration used by the
GitHub Actions workflow defined in
[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml).

The workflow runs the functional test suite with a 100% coverage gate on
every push and pull request, and builds the AtomZero game shell (the `core/`
directory and `icon.svg` only — see the
[Technical Design](../../doc/AtomZero_Technical_Design.md))
for five platforms, publishing the artifacts to a GitHub Release.

| Platform | Minimum target | Artifact |
|----------|----------------|----------|
| macOS    | macOS 11 (arm64) / 10.12 (x86_64) | `AtomZero-<version>-macos.zip` (contains `.app`) |
| Linux    | glibc 2.35+ (Ubuntu 22.04)        | `AtomZero-<version>-linux.deb` and `.rpm` |
| Windows  | Windows 10                        | `AtomZero-<version>-windows.zip` (contains `.exe`) |
| Android  | Android 9 (API 28)                | `AtomZero-<version>-android.apk` |
| iOS      | iOS 14                            | `AtomZero-<version>-ios.ipa` (unsigned unless secrets set) |

---

## Scripts

### `generate_export_presets.py`

Generates a complete `export_presets.cfg` containing five presets
(macOS, Linux, Windows Desktop, Android, iOS) from the contents of `core/`
and `icon.svg`. The script scans `core/` for files with exportable
extensions (`.gd`, `.tscn`, `.tres`, `.json`, `.svg`, `.png`, …) and emits
them as the `export_files` PackedStringArray, mirroring the behaviour of
the hand-tuned macOS preset that previously lived in the repository.

```bash
python3 tools/ci/generate_export_presets.py [--version VERSION] [--output PATH]
```

- `--version`  Override the game version (default: read from `project.godot`).
- `--output`   Output path (default: `export_presets.cfg` in the project root).

The `prepare` job of the workflow runs this script and uploads the resulting
file as the `export-presets` artifact, which every build job downloads.

### `package_linux.sh`

Wraps a Linux binary into a `.deb` and/or `.rpm` package. Installs the
binary to `/usr/lib/atomzero/`, creates a desktop entry and icon, and
creates writable directories (`mods/`, `saves/`, `.cache/`, `logs/`) that
the AtomZero Bootstrap expects as siblings of the executable (see
[Bootstrap.gd](../../core/bootstrap/Bootstrap.gd), `get_writable_root()`).

```bash
bash tools/ci/package_linux.sh <deb|rpm> <version> <binary_path> [project_root]
```

- `<deb|rpm>`    Package format to produce.
- `<version>`    Game version, embedded in the package metadata.
- `<binary_path>` Path to the Godot-exported Linux binary.
- `[project_root]` Optional project root (defaults to the script's `../../`).

Dependencies: `dpkg-deb` (for `.deb`), `rpmbuild` (for `.rpm`). Both are
installed in the `build-linux` job.

### `notify.py`

Build-failure notifier. Creates a GitHub issue summarising the failure and
optionally posts to a Slack/Discord webhook. Invoked by the
`notify-failure` job whenever any build job fails.

```bash
python3 tools/ci/notify.py \
  --version <version> \
  --tag <git-tag> \
  --failed-jobs macos,linux \
  [--labels build-failure,ci] \
  [--dry-run]
```

Reads the following environment variables (set automatically by the
workflow):

| Variable | Purpose |
|----------|---------|
| `GITHUB_REPOSITORY`  | `owner/repo` for the Issues API |
| `GITHUB_RUN_ID`      | Links to the failed workflow run |
| `GITHUB_TOKEN`       | Token with `issues:write` scope |
| `GITHUB_EVENT_NAME`  | Included in the issue body |
| `GITHUB_REF`         | Included in the issue body |
| `NOTIFY_WEBHOOK_URL` | Optional Slack/Discord webhook (if set, a message is posted) |

Use `--dry-run` locally to preview the issue body without making any API
calls.

---

## Workflow overview

The workflow in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)
contains nine jobs:

1. **`test`** — installs a headless Godot 4.6.3 Linux editor and runs
   `tools/run_tests.py -n 8 --cov-fail-under 100`. Runs on every push,
   pull request, and manual dispatch. A test failure blocks the release
   job (on tag pushes) and triggers the failure notifier.
2. **`prepare`** — resolves the version (from the pushed tag or manual
   input), runs `generate_export_presets.py`, and uploads the generated
   `export_presets.cfg` as an artifact. Only runs for tag pushes and manual
   dispatch; on branch pushes/pull requests it is skipped, which skips the
   whole build chain below.
3. **`build-macos`** — installs Godot 4.6.3 + export templates on macOS,
   exports an `.app` bundle, and zips it.
4. **`build-linux`** — exports the Linux binary, then packages it as both
   `.deb` and `.rpm` via `package_linux.sh`.
5. **`build-windows`** — cross-exports a Windows `.exe` from the Linux
   editor and zips it with its `.pck`/`.dll` siblings.
6. **`build-android`** — sets up Java 17, the Android SDK (API 34) and NDK
   r23c, configures signing, and exports a signed `.apk`.
7. **`build-ios`** — exports an Xcode project (unsigned by default) and
   builds a `.ipa` via `xcodebuild`, or directly exports a signed `.ipa`
   when signing secrets are provided.
8. **`release`** — downloads all build artifacts, stages them, and creates
   a GitHub Release with `softprops/action-gh-release`. Runs only when all
   builds *and* the test job succeeded.
9. **`notify-failure`** — runs `if: always()` after every job; if any job
   (including `test`) failed, it creates a GitHub issue (and posts to the
   webhook).

The macOS and iOS jobs run on `macos-latest`; all others run on
`ubuntu-22.04`. Each build job reuses the same Godot-installation steps
and pipes the editor's `--headless --export-release` output through
GitHub Actions log groups for easy scanning.

---

## Triggers

The workflow runs on:

- **Push or pull request on any branch** — runs the `test` job only
  (functional suite + 100% coverage gate). The build chain is skipped.
- **Push of a version tag** matching `v*` (e.g. `v2026.9.0`). The version
  is derived by stripping the leading `v`, and a Release is created only if
  the tests pass.
- **Manual dispatch** (`workflow_dispatch`) with two inputs:
  - `version` — the version string to build (default `2026.9.0`).
  - `create_release` — whether to create a GitHub Release after the builds
    succeed (default `true`).

```bash
# Tag-triggered release (recommended for releases)
git tag v2026.9.0
git push origin v2026.9.0

# Manual build without a release
gh workflow run ci.yml -f version=2026.9.0 -f create_release=false
```

A `concurrency` group keyed on `github.ref` cancels any superseded run on
the same ref.

---

## Version management

The single source of truth for the game version is the `config/version`
field in [`project.godot`](../../project.godot) (currently `2026.9.0`),
mirrored by the `GAME_VERSION` constant in
[`Bootstrap.gd`](../../core/bootstrap/Bootstrap.gd).

The `prepare` job resolves the effective build version as follows:

| Trigger | Version source | Tag |
|---------|----------------|-----|
| `push: tags: v*` | Tag with the leading `v` stripped | The pushed tag |
| `workflow_dispatch` | The `version` input | `v<version>` |

The resolved version is passed to `generate_export_presets.py` (so every
preset's `application/version` field matches) and is baked into every
artifact filename (e.g. `AtomZero-2026.9.0-macos.zip`). The `release` job
uses the same version for the release name and body.

---

## Required GitHub Secrets

All secrets are **optional** — the workflow produces working artifacts
without any configuration, but signing requires the secrets below.

### Android signing

| Secret | Required? | Description |
|--------|-----------|-------------|
| `ANDROID_KEYSTORE_BASE64` | Optional | Base64-encoded release keystore. If absent, a debug keystore is generated automatically (the resulting APK is installable but not Play-Store-ready). |
| `ANDROID_KEYSTORE_USER`   | With the keystore | Keystore alias. |
| `ANDROID_KEYSTORE_PASS`   | With the keystore | Keystore password. |
| `ANDROID_KEY_PASS`        | With the keystore | Key password. |

To produce a base64-encoded keystore from a `.jks`/`.keystore` file:

```bash
base64 -i release.keystore | tr -d '\n'
```

### iOS signing

| Secret | Required? | Description |
|--------|-----------|-------------|
| `IOS_CERTIFICATE_BASE64` | Optional | Base64-encoded developer `.p12` certificate. If absent, the workflow exports an unsigned Xcode project and builds an unsigned `.ipa` (installable via Xcode/AltStore with a development device). |
| `IOS_CERTIFICATE_PASS`   | With the certificate | Password for the `.p12`. |
| `IOS_PROVISIONING_PROFILE` | With the certificate | Base64-encoded `.mobileprovision` file. |
| `IOS_TEAM_ID`              | With the certificate | Apple Developer Team ID (10 chars). Required for signed builds; a placeholder is used for unsigned builds so Godot's validation passes. |

When none of these are set, the iOS job patches the preset to set
`application/export_project_only=true`, exports the Xcode project, and
builds it with `CODE_SIGNING_ALLOWED=NO`. The resulting `.ipa` is named
`AtomZero-<version>-ios-unsigned.ipa`.

### Failure notifications

| Secret | Required? | Description |
|--------|-----------|-------------|
| `NOTIFY_WEBHOOK_URL` | Optional | Slack/Discord incoming-webhook URL. If set, `notify.py` posts a summary message in addition to creating a GitHub issue. |

When any build job fails, the `notify-failure` job always creates a
GitHub issue (using the built-in `GITHUB_TOKEN`, which has `issues:write`
via the workflow's `permissions:` block) listing the failed jobs and a
link to the run.

### Permissions

The workflow declares:

```yaml
permissions:
  contents: write   # softprops/action-gh-release creates the release
  issues: write     # notify-failure creates issues
```

No additional token configuration is required for these — the default
`GITHUB_TOKEN` is sufficient.

---

## Local testing

The helper scripts can be run locally without GitHub Actions.

```bash
# Generate export_presets.cfg without touching the committed file
python3 tools/ci/generate_export_presets.py --output /tmp/export_presets.cfg
# Spot-check that the committed presets carry the current version
# (the committed file is hand-tuned and may differ from the generated
# output in formatting/ordering, so compare version fields, not bytes)
grep '"2026.9.0"' /tmp/export_presets.cfg | head
grep -n '"2026.9.0"' export_presets.cfg | head

# Preview the failure-notification issue body
python3 tools/ci/notify.py --dry-run --version 2026.9.0 --failed-jobs macos,linux

# Build a .deb from a local Linux binary
bash tools/ci/package_linux.sh deb 2026.9.0 dist/AtomZero.x86_64

# Full local release: tests + coverage gate + local-platform packaging
python3 tools/release.py --dry-run
```

---

## Log output

Every build step wraps Godot's output in a GitHub Actions log group
(`::group::` / `::endgroup::`) so the editor's import and export logs are
collapsible in the Actions UI. Each step also prints `::notice::`
annotations at key milestones (Godot installed, package produced, release
published) and `::error::` annotations when an expected artifact is
missing, so failures surface immediately in the run summary.

For full log retention, build artifacts are kept for 14 days
(`retention-days: 14`) and the `export-presets` artifact for 1 day.
