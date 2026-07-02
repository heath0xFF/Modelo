# AGENTS.md

## Feature work

Reviewability is the constraint. A diff over ~1500 lines means decompose, not polish.

1. First pass: attempt the whole feature loosely; expect a rough, oversized cut.
2. Under ~1500 lines → clean up and merge. Over → stop, propose an atomic, incremental, independently-reviewable decomposition before writing more.
3. Define sub-tasks by general capability, not the shape of the throwaway pass. Same ceiling applies to each; recurse.
4. Re-attempt the full feature once foundations exist — it'll come in under threshold.

Pause for human review on UI/API/schema/contract changes and any new architectural invariant.

## Build, test, validate & install

The app is a native macOS SwiftUI target. The Xcode project is **generated** by
XcodeGen from `project.yml` and is never committed (`.gitignore`d), so regenerate
it before building if `project.yml` changed or the project is missing.

- **Project:** `Modelo.xcodeproj` · **Scheme:** `Modelo` · **Product:** `Modelo.app`
  (Swift module is named `Modelo`, so tests `@testable import Modelo`).
- **Tooling:** `xcodegen` (Homebrew) + `xcodebuild` (Xcode 26+). Deps (MarkdownUI,
  Highlightr) resolve via SPM on first build.

```bash
# Regenerate the project from project.yml (run after editing project.yml or adding files)
xcodegen generate
```

**Validate a change compiles** (CI-style; no signing needed, output to gitignored `build/`):

```bash
xcodebuild -project Modelo.xcodeproj -scheme Modelo -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

A green build ends in `** BUILD SUCCEEDED **`. Treat any `error:` line as a hard
failure — a text/grep "verification" that only checks for the presence of strings
(e.g. `verify_implementation.py`) does **not** prove the code compiles and must not
be trusted as validation.

**Run the test suite** (`ModeloTests`, in-memory SwiftData):

```bash
xcodebuild -project Modelo.xcodeproj -scheme Modelo \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO test
```

**Build a signed Release and install to /Applications.** Use *automatic* signing
with the local team (derived from the machine's "Apple Development" certificate).
Do **not** sign manually with `CODE_SIGN_STYLE=Manual` and no profile: that strips
the `com.apple.application-identifier` entitlement, which the data-protection
keychain requires (`Modelo.entitlements` + `CODE_SIGN_ENTITLEMENTS` in `project.yml`
exist precisely to make Xcode embed a Mac Team Provisioning Profile granting it).
Without it, `KeychainStore` falls back to the legacy login keychain and macOS
prompts for the keychain password after installs.

```bash
xcodegen generate   # only needed if files were added/removed
# Local team ID from the dev certificate (OU field):
TEAM_ID=$(security find-certificate -c "Apple Development" -p \
  | openssl x509 -noout -subject | sed -n 's/.*OU=\([^\/]*\).*/\1/p')
xcodebuild -project Modelo.xcodeproj -scheme Modelo -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build-release build \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID"
osascript -e 'tell application "Modelo" to quit' 2>/dev/null   # free the running copy
rm -rf /Applications/Modelo.app
cp -R build-release/Build/Products/Release/Modelo.app /Applications/
open /Applications/Modelo.app
```

After the build, `codesign -d --entitlements - /Applications/Modelo.app` must list
`com.apple.application-identifier` and `keychain-access-groups`, and
`Contents/embedded.provisionprofile` must exist — if either is missing, secrets
regress to the prompt-per-install legacy keychain. `codesign --verify --verbose
/Applications/Modelo.app` should report it valid. Keep `build/` and
`build-release/` gitignored.

The keychain must be unlocked for codesign to use the signing key, so run this in
an interactive shell (the `!` prefix in Claude Code works). If macOS asks for a
password so *codesign* can access the signing key, run this once (it prompts for
the login password) to whitelist Apple's tools for that key:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  ~/Library/Keychains/login.keychain-db
```
