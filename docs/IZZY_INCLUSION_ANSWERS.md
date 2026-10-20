# IzzyOnDroid App Inclusion Request (pre-answered)

Status: DRAFT — ready to paste into a new issue at
`codeberg.org/IzzyOnDroid/repodata` whenever we decide to submit. No age gate
(policy verified 2026-10-20): the only time criterion is that apps *stale for
12+ months* get dropped — fresh, maintained apps are welcome.

Reference: the official template lives in that repo at
`.forgejo/issue_template/app-inclusion-request.yaml` (fetched verbatim
2026-10-20); the policy is at
`izzyondroid.org/docs/general/AppInclusionPolicy`. Submission is an **issue**
(not an MR): create it at `codeberg.org/IzzyOnDroid/repodata/issues/new` with
title exactly: **[AppRequest] JotLock**

HOW TO USE: fill in the **AI Tools Usage** section honestly first — it is a
*required* dropdown in the template — then paste the sections below into the
matching fields and submit. A reviewer VirusTotal-scans the APK, installs it
on a test device with network monitoring, checks it generally works, and adds
the `approved` label. We pass the network check by construction: the app has
no INTERNET permission at all.

---

## Guidelines

- I am the developer of the app. — **Yes** (single maintainer).
- The app complies with the App Inclusion Policy. — **Yes** (verified
  requirement-by-requirement 2026-10-20; see the checklist at the bottom).
- The app is not already listed in the repo or issue tracker. — **Yes**
  (verified 2026-10-20: no `jotlock` issues exist in their tracker; re-check at
  submission).
- The Fastlane folder is available in the app's repo. — **Yes**:
  `fastlane/metadata/android/en-US/` (title, short/full descriptions, changelogs
  for versionCodes 6–8, icon, 8 phone screenshots).

## App meta-data

- **Link to the source code:** `https://github.com/Ryfire/jotlock`
- **Link to app in another app store:** none — GitHub Releases is the only
  distribution channel today (F-Droid submission planned ~mid-January 2027;
  note that would be a *separate signing lineage*, not install-compatible).
- **License used:** MIT
- **Categories:** Writing (matches the F-Droid category; `Time` or `Office` are
  optional secondaries — at least 1, max 5 allowed)
- **Summary:** Lock-screen-first notes app: capture a thought straight from
  the lock screen, with reminders that sound but never clutter it.
- **Description:**

  JotLock is a fast, no-nonsense notes app built around one idea: all the
  magic starts from the lock screen. A persistent Quick note notification
  puts a Write note button there, an inline Jot field waits in the
  notification shade, and per-note reminders always play your sound but never
  clutter your lock screen.

  Features:

  - Quick note from the lock screen — capture a thought in seconds
  - Inline Jot reply straight from the notification shade
  - Reminders with exact alarms: once, daily, weekly, or custom repeat
  - Checklists with `[ ]` / `[x]` syntax and progress counts
  - Priority colors, pinning, copy and share
  - Optional App PIN to keep notes private
  - Search as you type
  - JSON and text export, JSON import — your data stays yours
  - Choose what happens after saving: lock the phone, go home, or stay on the
    confirmation

  Free, open source (MIT), and ad-free. No accounts, no cloud, no INTERNET
  permission: notes physically have nowhere to go but the device.

## Technical instructions

**Build instructions** (CLI, from a fresh clone):

```
# Requirements: Flutter SDK 3.47.6 (matches the repo .metadata revision
# 5fc34683), JDK 17, Android SDK (compileSdk 37, minSdk 24)
flutter pub get
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Release builds sign with the release keystore when `android/key.properties`
exists (never committed — keystore lives outside the repo) and fall back to
the debug key otherwise, so a fresh clone always builds. Per-ABI APKs come
from `flutter build apk --release --split-per-abi` — the APKs on GitHub
Releases are exactly these, signed with the same key, and IzzyOnDroid mirrors
them as-is (their signature-continuity check pins every update to the
inclusion-time key).

## AI Tools Usage — FILL IN HONESTLY AT SUBMISSION

The template makes this a **required** declaration (dropdown), and the policy
is explicit: "vibe-coded apps will be rejected"; README/changelog/docs may
contain LLM text, but "the code itself should be free of it"; LLM use for
research/debugging/look-ups is acceptable "provided their output is not
included in the app's code"; and "any lack of transparency discovered by us
can lead to the project being degraded to rejected state". Pick the *true*
Assistance Level, name the tool(s), describe what they helped with, and tick
the accountability boxes only if they are true:

- **Assistance Level:** (None / Minimal / Moderate / Substantial / Dominant)
- **"AI" Tool(s):** (e.g. OpenCode)
- **What did the tools help with, and how?** (e.g. debugging, research,
  documentation)
- **AI Accountability:**
  - The human developer(s) reviewed and edited all "AI"-generated outputs
  - The human developer(s) ran manual tests and manually verified all changes

## Further Notices

- **Sensitive-permission screening answers:** exactly one device-admin policy
  (`force-lock`, opt-in, only for the lock-after-saving feature); exact alarms
  (`SCHEDULE_EXACT_ALARM` on ≤32, `USE_EXACT_ALARM` on 33+ — alarm-clock use
  case); a `specialUse` foreground service hosting the lock-state listener;
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` used only via the system dialog.
  Full rationale in `docs/DEVELOPMENT.md` ("Why device admin", architecture
  sections).
- **No INTERNET permission at all** — no ads, no trackers, no self-updater;
  the reviewer network-monitoring step passes by construction.
- **APK sizes** (v1.4.0, measured 2026-10-19): universal 50.6 MB, arm64-v8a
  17.6 MB, armeabi-v7a 15.2 MB, x86_64 19.1 MB. The Izzy-compatible form is
  the arm64 split — under the ~30 MB per-app rule-of-thumb.

## Pre-submission checklist

1. Re-verify no existing request in the IzzyOnDroid tracker (done 2026-10-20:
   none).
2. Fill the AI Tools Usage section honestly — it is required.
3. Confirm the latest GitHub release still attaches all four APKs (the splits
   must always ship: split users depend on them for versionCode progression).
4. Create the issue at `codeberg.org/IzzyOnDroid/repodata/issues/new`, title
   **[AppRequest] JotLock**, pasting this document's answers into the template
   fields.
5. After `approved`: updates flow automatically from tagged GitHub Releases —
   keep releasing, keep the keystore safe.
