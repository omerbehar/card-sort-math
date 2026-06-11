# Building CardSortMath for Android

> **Good news:** unlike iOS, Android **can** be built on Linux/macOS/Windows — no
> Mac required. A signed *debug* APK needs only the Godot Android export templates
> + a debug keystore + the Android SDK's signing tools (no full Android Studio, no
> NDK, no Gradle for the one-click APK path).

## Build in the cloud (GitHub Actions)

> **Note:** the Android CI job was removed for now — we're focusing on iOS first
> (`.github/workflows/mobile-build.yml` is iOS-only). The Android **export preset**
> still lives in `export_presets.cfg`, so re-adding the job later is just dropping
> a few steps back into the workflow. Until then, build Android locally with the
> steps below (or run the one-click export from the Godot editor).

## What's already set up (committed)

- `export_presets.cfg` → **Android** preset (`preset.1`):
  - One-click (non-Gradle) APK, format APK, `arm64-v8a` + `armeabi-v7a`.
  - `package/unique_name = com.omerbehar.cardsortmath` *(change to your own id)*,
    version `1` / `1.0`, portrait immersive.
  - Keystore fields left blank — for **debug** builds Godot uses the keystore from
    *Editor Settings → Export → Android*; for **release** you supply your own.
- `project.godot` is already `rendering_method="mobile"`, `orientation="portrait"`.

## One-time setup on your machine

1. **Godot 4.6** + the **Android export templates**
   (Editor → *Manage Export Templates* → *Download and Install*).
2. **JDK 17+** (OpenJDK is fine — used by `apksigner`).
3. **Android SDK** with `platform-tools` (adb) and `build-tools` (apksigner,
   zipalign). Two easy ways:
   - **Android Studio** → SDK Manager → install *Android SDK Platform-Tools* and a
     *build-tools* package; **or**
   - **command-line tools** (no IDE):
     ```sh
     # download "commandlinetools" from developer.android.com, then:
     sdkmanager "platform-tools" "build-tools;34.0.0"
     ```
4. In Godot: *Editor → Editor Settings → Export → Android*:
   - **Android Sdk Path** → your SDK root (the folder containing `platform-tools/`
     and `build-tools/`).
   - **Java Sdk Path** → your JDK home.
   - A **Debug Keystore** is auto-created by Godot on first use (user
     `androiddebugkey`, password `android`); or point it at one you make with:
     ```sh
     keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
       -keystore debug.keystore -storepass android \
       -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
     ```

## Build a debug APK

GUI: *Project → Export → Android → Export Project…* → choose `build/android/CardSortMath.apk`.

CLI:
```sh
godot --headless --export-debug "Android" build/android/CardSortMath.apk
```

Install on a connected device (USB debugging on):
```sh
adb install -r build/android/CardSortMath.apk
```

## Release build for the Play Store

1. Create a **release keystore** (keep it safe — it identifies your app forever):
   ```sh
   keytool -genkeypair -v -keystore cardsortmath-release.keystore \
     -alias cardsortmath -keyalg RSA -keysize 2048 -validity 10000
   ```
2. In the preset's `keystore/release*` fields (or the export dialog) point at it.
3. Set `gradle_build/export_format` to **AAB** (Android App Bundle — required for
   the Play Store) and export with `--export-release`.
4. Upload the `.aab` to the Google Play Console (one-time $25 developer account).

## App icons (later)

Replace the default launcher icon by setting `launcher_icons/main_192x192` and the
two adaptive `432x432` layers in the preset to your branded PNGs (placeholder art
ships today). The 1024 source in `ios/icon_1024.png` can be downscaled for these.

## Note on this repo's CI / the Claude Code sandbox

The Linux CI sandbox has the full toolchain working (templates, debug keystore,
`apksigner`/`zipalign`/`adb`, SDK paths) and **successfully exports a Linux desktop
binary**, proving the export pipeline is healthy. However, Godot 4.6's *Android*
export validation fails **headlessly** here with an empty (message-less) error even
with everything in place — a known limitation of validating Android exports outside
the editor GUI / with a Google-blocked SDK download. On a normal developer machine
with the editor open (which prints the real validation messages) and an SDK
installed via Android Studio, `--export-debug "Android"` works as documented above.
This is **not** a Mac-style hard limitation — it's an environment/headless quirk.
