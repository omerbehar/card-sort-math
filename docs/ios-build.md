# Building CardSortMath for iPhone (iOS)

> **TL;DR:** iOS builds require a **Mac with Xcode** and an **Apple Developer
> account** — there is no way around Apple's toolchain. The repo is already
> iOS-export-*configured* (`export_presets.cfg`, app icon, mobile/portrait
> renderer); the steps below finish the job on a Mac.

## No Mac? Build on a cloud Mac (GitHub Actions)

`.github/workflows/mobile-build.yml` runs an **iOS job on a macOS cloud runner** —
no Mac of your own required. From the **Actions** tab → *Mobile Build* → *Run
workflow* (or push a `v*` tag). It always:

- generates the Xcode project with Godot, and
- compiles an **unsigned Simulator build** (proves it builds), uploading the
  Xcode project as an artifact.

To get an **installable signed `.ipa`** (TestFlight / device), enrol in the Apple
Developer Program and add these repo **secrets** (Settings → Secrets → Actions):

| Secret | What |
|---|---|
| `IOS_CERTIFICATE_BASE64` | base64 of your distribution cert `.p12` |
| `IOS_CERTIFICATE_PASSWORD` | the `.p12` password |
| `IOS_PROVISION_PROFILE_BASE64` | base64 of your `.mobileprovision` |
| `IOS_TEAM_ID` | your 10-char Apple Team ID |
| `IOS_EXPORT_METHOD` | `development` / `ad-hoc` / `app-store` |
| `KEYCHAIN_PASSWORD` | any string (unlocks the CI keychain) |

With those set, the job archives + exports a signed `.ipa` and uploads it as an
artifact. (Codemagic is an alternative that manages the certs/profiles for you in
its UI — see the comparison the team discussed.)

## What's already set up (committed)

- `export_presets.cfg` — an **iOS** export preset:
  - Bundle id `com.omerbehar.cardsortmath` *(change to your own reverse-DNS id)*
  - Portrait-only, iPhone device family, **min iOS 14.0** (Godot 4.6 uses Metal,
    which requires iOS 14+)
  - App Store icon → `ios/icon_1024.png`
  - **Placeholder** Team ID `XXXXXXXXXX` and empty signing fields — you fill these
    with your Apple credentials on the Mac.
- `ios/icon_1024.png` — a 1024×1024 **opaque** app icon (placeholder art derived
  from `icon.svg`; replace with final branding). Regenerate with
  `godot --headless -s res://tools/gen_ios_icon.gd`.
- `project.godot` — already `rendering_method="mobile"`, `orientation="portrait"`.

## What you need on the Mac

1. **macOS + Xcode** (latest stable), with the iOS SDK and command-line tools
   (`xcode-select --install`).
2. **Godot 4.6** (same version as the project) + the **iOS export templates**
   (Editor → *Manage Export Templates* → *Download and Install*).
3. An **Apple Developer account** ($99/yr) and, in Xcode, a signing **Team** plus
   an automatically-managed provisioning profile.

## Steps

1. **Open the project** in Godot 4.6 on the Mac.
2. **Project → Export → iOS** preset:
   - Set **App Store Team ID** to your real 10-character team id (Apple Developer
     → Membership), replacing `XXXXXXXXXX`.
   - Set the **Bundle Identifier** to an id you own.
   - Leave code-signing to Xcode (automatic signing) unless you manage profiles
     manually.
3. **Export** (gives you an Xcode project):
   - GUI: *Export Project…* → choose a folder (e.g. `build/ios/`).
   - or CLI on the Mac:
     ```sh
     godot --headless --export-debug "iOS" build/ios/CardSortMath
     ```
   Godot generates a `*.xcodeproj` (it does **not** build the `.ipa` itself —
   Xcode does).
4. **Open the generated `.xcodeproj` in Xcode.**
   - Select your **Team** under *Signing & Capabilities* (enables automatic
     signing).
   - Pick your connected iPhone (or a Simulator) as the run target.
5. **Run / Archive:**
   - **Run** (▶) installs and launches on a connected device (the device must be
     registered to your developer account; free accounts allow 7-day local
     installs).
   - **Product → Archive** → *Distribute App* to produce a signed `.ipa` for
     TestFlight / the App Store.

## App Store submission checklist (later)

- Replace `ios/icon_1024.png` with final 1024×1024 **opaque** artwork (no alpha,
  no rounded corners — Apple rejects transparency on the store icon).
- Bump `application/short_version` (marketing version) per release. The **build
  number** (`application/version` / `CFBundleVersion`) is **auto-set from the CI
  run number** by `mobile-build.yml`, so TestFlight uploads never collide — no
  manual bump needed for builds.
- Fill the privacy usage strings in the preset only for capabilities you actually
  use (none today — no camera/mic/photos).
- Provide a launch screen / storyboard (the preset uses Godot's default launch
  screen; customise via the `storyboard/*` options if desired).

## Why this can't be built in CI / on Linux

This repo's CI (and the Claude Code web sandbox) run on **Linux**. Godot's iOS
exporter validates against the macOS signing toolchain and refuses a headless
Linux export (it returns a configuration error with no usable message). Even if
it produced the Xcode project, **compiling and signing an iOS app is macOS-only**
(Apple ships `xcodebuild`, the iOS SDK, and the signing stack only for macOS). So
iOS packaging is a **manual, Mac-side step** — everything that *can* be prepared
cross-platform (the preset, icon, and engine config) is committed here.
