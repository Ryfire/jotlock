# F-Droid RFP draft

Paste into a new issue at <https://gitlab.com/fdroid/rfp/-/issues/new>
(GitLab account required). Suggested issue title:

> Request for packaging: JotLock

---

**App name:** JotLock

**Package name:** `com.ryfire.jotlock`

**Upstream repo:** <https://github.com/Ryfire/jotlock>

**License:** MIT

**Website:** <https://buymeacoffee.com/JameyR> (support page; the GitHub repo is canonical)

**Summary:** Capture notes from your Android lock screen in seconds — then lock the phone or head home.

**Description:**

JotLock is a fast, no-nonsense notes app built around one idea: all the magic
starts from the lock screen. A persistent **Quick note** notification puts a
**Write note** button there, an inline **Jot** field waits in the shade, and
per-note **reminders** always play your sound but never clutter your lock
screen.

Checklists, repeating reminders, priority colors, optional App PIN, JSON
backup — free, open source (MIT), and ad-free. No accounts, no cloud, **no
INTERNET permission**: notes physically have nowhere to go but the device.

**Anti-features:** none known — no ads, no tracking, no non-free network
services, no proprietary dependencies (Flutter + FOSS pub.dev packages only,
no Firebase / Google Play Services).

**Requirements:** Android 7.0+ (minSdk 24). Built with Flutter
(first-class support in fdroidserver): `flutter build apk --release`.
The Gradle config falls back to debug signing when no release keystore is
present, so upstream builds and fdroidserver signing coexist cleanly.

**Versioning:** git tags `v1.x.y` (UpdateCheckMode: Tags). Current release:
v1.4.0 (versionCode 8), tagged and released on GitHub
(<https://github.com/Ryfire/jotlock/releases>).

**Fastlane metadata:** the repo ships `fastlane/metadata/android/en-US/`
(title, short/full descriptions, changelogs for versionCodes 6–8, icon,
8 phone screenshots) plus a ready-to-adapt packaging recipe at
`metadata/com.ryfire.jotlock.yml` in the repo root.

**Developer notes for the packager:**

- Architecture and build details: [docs/DEVELOPMENT.md](DEVELOPMENT.md)
  (includes a signing section and F-Droid notes)
- The app declares exactly one device-admin policy, `force-lock`
  (used only for opt-in lock-after-saving); `INTERNET` is not requested
- Reminder scheduling uses exact alarms (`SCHEDULE_EXACT_ALARM` /
  `USE_EXACT_ALARM`), with a one-time opt-in background keep-alive for
  reliability