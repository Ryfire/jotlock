# JotLock — development guide

Developer reference: architecture, build/release workflow, and the reasoning
behind the permission choices. For user-facing documentation see the
[README](../README.md).

## Requirements

- Flutter SDK (developed on 3.47.x) with Android tooling, Java 17
- compile SDK 37, min SDK 24 (Android 7.0+)

```bash
flutter pub get
flutter run                      # debug on a connected device
flutter test                     # unit + widget tests
flutter analyze
flutter build apk --release      # release-key signed (debug key if no key.properties)
```

### Signing

Release builds are signed with the real release keystore when
`android/key.properties` exists, and fall back to the standard Android
**debug key** (`~/.android/debug.keystore`) when it doesn't — so a fresh
clone always builds, and locally built APKs still install over another
locally built one until real signing is set up.

**Release keystore** (never commit it, never lose it):

| | |
|---|---|
| File | `C:\Users\Ryfire\keystores\jotlock-release.jks` — deliberately **outside the repo** |
| Alias | `jotlock` |
| Subject | `CN=Jamey R, OU=dev, O=RyfireApps, C=US` |
| Valid until | 2054 (10,000 days) |
| SHA-256 | `66:D4:5C:E1:4E:E8:3A:10:AC:8B:26:99:EE:86:CC:CA:00:1C:60:EC:2C:47:A3:BC:B6:3E:5A:A3:CC:F1:CF:DA` |

Credentials live in `android/key.properties` (gitignored): `storePath`,
`storePassword`, `keyAlias`, `keyPassword`. `android/app/build.gradle.kts`
loads that file and defines the `release` signing config from it.

**Backup is critical.** For GitHub-Releases distribution this keystore is
the app's permanent identity — losing the `.jks` and its password means no
update can ever be installed over the current one. Keep a copy of the
keystore file *and* the password in a second location (cloud + password
manager). Google Play is **out of scope for now** (never shipped — see
[PLAY_MIGRATION.md](PLAY_MIGRATION.md) for the parked plan). If ever
pursued, Play App Signing holds a separate Google-managed install key, so
Play would be another incompatible channel and this keystore would merely
become the (replaceable) upload key.

**First signed release migration:** installs of debug-signed builds can't
accept an update signed with the release key — Android requires
uninstalling first, which wipes app data. Announce it in the release notes
and tell users to export notes via the in-app JSON backup before upgrading.

### Distribution channels

Android refuses to install an update whose signing key differs from the
installed app's — switching to a differently-signed channel means
uninstalling first (data wipe). Each key therefore creates a channel
lineage:

| Channel | Signed by | Install-compatible with |
|---|---|---|
| GitHub Releases (primary) | `jotlock-release.jks` | Obtainium, IzzyOnDroid |
| Obtainium | — (reads GitHub Releases directly) | GitHub, IzzyOnDroid |
| IzzyOnDroid | — (mirrors our release APKs as-is, signature kept) | GitHub, Obtainium |
| F-Droid main | F-Droid's own key | nothing — separate lineage |
| Google Play | Google-managed key (out of scope for now) | nothing — separate lineage |

Consequences:

- GitHub / Obtainium / IzzyOnDroid are **one compatible channel** — users
  switch freely between them without data loss. This keystore is that
  channel's identity; losing it breaks all three at once.
- F-Droid and (if ever) Play are separate lineages.

**Obtainium** — nothing to submit; it tracks the GitHub Releases feed
directly. Updates flow automatically as long as every release follows the
convention established with v1.4.0: **attach all four APKs** (arm64-v8a,
armeabi-v7a, x86_64, universal). The per-ABI splits carry Flutter's ABI
versionCode offsets (1.4.0: universal 8, arm-v7a 1008, arm64 2008,
x86_64 4008) — all higher than the universal, so a split installs cleanly
over a universal install, but the reverse (split user → later
universal-only release) is a versionCode downgrade Android blocks.
Never publish a release without the splits, and split users stay on a
clean update path forever. README should advertise it as an install path.

**IzzyOnDroid** (`https://apt.izzysoft.de/fdroid/repo`) — an
F-Droid-client-compatible store that mirrors developer-signed release
APKs from GitHub, adding discoverability with zero build work. To request:
open an issue at `codeberg.org/IzzyOnDroid/repodata` using the
app-inclusion template, subject to the App Inclusion Policy
(`izzyondroid.org/docs/general/AppInclusionPolicy`). **No minimum-age or
months-maintained gate** (unlike F-Droid's 3-month rule — verified from
the policy text 2026-10-19); the only time criterion is that apps *stale
for 12+ months* get dropped, which doesn't apply here. Mechanics we
already meet: FOSS (MIT), APKs on properly tagged GitHub releases (their
update script polls those automatically), no ads/trackers/proprietary
deps, no self-updater (no INTERNET permission at all), fastlane
metadata, developer-signed release builds. **One real constraint:** the
policy reserves ~30 MB per app (rule-of-thumb) — the 50.6 MB universal
APK busts it. Measured `--split-per-abi` sizes (2026-10-19):
armeabi-v7a 15.2 MB, arm64-v8a 17.6 MB, x86_64 19.1 MB — per-ABI splits
on GitHub Releases are the Izzy-compatible form (arm64 alone fits
comfortably; arm64+v7a ≈ 33 MB is exception territory). Expect screening
questions about sensitive permissions — device admin (`force-lock`),
exact alarms (`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`), the specialUse
foreground service, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — the
rationale sections in this document are the answers. Their
signature-continuity check pins every update to the same key recorded at
inclusion, so the keystore-backup rule above is doubly binding here.

**F-Droid main** — builds apps **from source** and signs with **their own
key**, so F-Droid builds won't install over a GitHub-signed APK
(uninstall + data wipe). The reproducible-builds route would let F-Droid
publish with the developer's own signature (the fingerprint above; the
`Binaries:` flow), but the 2026-10-19 local double-build test showed
non-deterministic output, so the first accepted build will use F-Droid
signing. Resubmission is planned for ~mid-January 2027 once the 3-month
maintenance policy is satisfied.

## Architecture

Flutter can't render UI on the lock screen, so the capture path is fully native
Kotlin while the management UI is Flutter. Both sides talk to **one source of
truth**: a JSON array in `SharedPreferences`.

```
Lock screen ── tap notification ──► QuickNoteActivity (showWhenLocked)
Unlocked shade ── inline reply ──► QuickNoteReceiver
                                        │ saves
                                        ▼
                              NoteStore (SharedPreferences)
                                        ▲            ▲
BootReceiver ── re-posts ─► NotificationHelper      Flutter app
                                           (MainActivity MethodChannel)
```

| File | Role |
|---|---|
| `lib/main.dart` | Notes list UI: search, pin, copy, share, editor, reminders, settings, optional PIN gate |
| `lib/note.dart` | Note model + `filterAndSort` (pinned first, newest first) |
| `lib/notes_repository.dart` | MethodChannel wrapper (`jotlock/notes`) |
| `MainActivity.kt` | Channel bridge, share-intent capture, sound picker, admin activation, app-PIN endpoints |
| `QuickNoteActivity.kt` | The lock-screen capture screen (`showWhenLocked`, insets-safe) |
| `NotificationHelper.kt` | Persistent notification, channels, lock-state-aware card variants (Write note ↔ Jot), screen-state listener, reminder sound channels |
| `QuickNoteReceiver.kt` | Saves inline notes typed in the notification and re-posts it |
| `ReminderScheduler.kt` | Exact AlarmManager scheduling, re-arm on boot |
| `ReminderReceiver.kt` | Fires reminder cards (grouped, SECRET on lock screen), clears the one-shot |
| `NoteStore.kt` | JSON CRUD, pin, reminders (`reminderAt`/`reminderSilent`), merge-import |
| `BootReceiver.kt` | Re-posts the notification and re-arms reminders after reboot |
| `LockAdminReceiver.kt` | Device admin — only policy used: `force-lock` (for lock-after-save) |
| `AppSettings.kt` | After-save behavior, reminder sound URI, app-PIN hash, channel version |
| `LockStateService.kt` | Foreground service (specialUse) hosting the screen-state listener |

### Lock-state-aware notification card

The Quick note card is re-rendered to match the device lock state:

- **Locked**: single **Write note** action → `QuickNoteActivity`
  (`showWhenLocked`) — type and save over the keyguard.
- **Unlocked**: inline **Jot** RemoteInput (saved by `QuickNoteReceiver`) +
  **Write note**.

`LockStateService` keeps the process at foreground priority so the
SCREEN_ON/OFF/USER_PRESENT listener can never die between re-posts — a stale
unlocked card with the Jot action must never linger onto the lock screen.

The card must stay `VISIBILITY_PUBLIC`: on Moto's lock screen, expanding a
collapsed icon for a non-public card is treated as "unlock to view", which
breaks the capture flow.

### Reminder cards vs the lock screen

Reminder notifications use the opposite rule: they set
`setVisibility(SECRET)` **per notification** (children and summary). Channel-level
`lockscreenVisibility` alone is not reliable on all OEM builds — this device
persisted channels with visibility `-1000` (unspecified) even when the app set
`SECRET` at creation. Per-notification visibility overrides and wins; result:
reminders sound while locked but never render on the lock screen.

Channel plumbing: the sounded reminder channel id is versioned
(`note_reminders_v<N>`, version persisted in prefs via `AppSettings`) because a
channel's sound is immutable — changing the picked sound deletes and recreates
the channel. `healReminderChannels()` runs on app launch: recreates the sounded
channel if missing or missing SECRET visibility, deletes stale versions, and
removes the legacy unversioned channel. Silent reminders post to a separate
`note_reminders_silent` channel (no sound, no vibration).

Reminder notification ids: `100000 + (noteId.hashCode() and 0x7FFFFFFF) % 800000`,
summary id 99999, group key `com.ryfire.jotlock.REMINDERS`.

### Why device admin (long-form rationale)

After a lock-screen save, *Lock the phone* mode calls
`DevicePolicyManager.lockNow()` — the programmatic equivalent of pressing the
power button. Android provides no ordinary API for a third-party app to lock the
screen; declaring the `force-lock` device-admin policy is the only sanctioned
way. The workarounds seen in "screen off" apps (AccessibilityService hooks) are
far more invasive — they can read screen content. Device admin with `force-lock`
is the *least* privileged option, not the most.

Admin capabilities must be declared in the manifest;
`android/app/src/main/res/xml/device_admin.xml` contains only:

```xml
<uses-policies>
    <force-lock />
</uses-policies>
```

Android enforces this list itself: an admin cannot exercise an undeclared
policy. Factory reset, password access, camera control and so on are
structurally out of reach. Two safeguards on top: no `INTERNET` permission, and
activation is opt-in + visible (system screen lists granted policies).

### App PIN gate

The optional PIN guards the Flutter management UI only — the lock-screen
capture path (`QuickNoteActivity`, inline Jot) is deliberately untouched:
gating it would defeat the app's purpose, and the keyguard already protects
whatever sits behind it. It is a privacy screen, not encryption — notes stay
plain JSON in SharedPreferences.

Storage: `AppSettings` keeps a random 16-byte salt (hex) and the SHA-256 of
`"jotlock:<salt>:<pin>"` — the plaintext digits are never persisted.
Verification recomputes the hash and compares via `MessageDigest.isEqual`
(constant time). Channel methods: `isPinSet`, `setPin` (validated 4-8
digits), `verifyPin`, and `clearPin` (only clears after verification).

The gate (`_PinGate` in `lib/main.dart`) wraps `NotesPage` under
`MaterialApp.home`. On start it checks `isPinSet()` — while that check is
pending it shows a splash instead of the note list, so a gated app never
flashes its contents. It re-arms on every `resumed` lifecycle event,
re-querying the setting rather than trusting a cached value, so a PIN set
or removed in settings mid-session is always honored. In-app dialogs and
bottom sheets only reach `inactive` and don't re-lock; full-screen system
activities (file picker, ringtone picker, device-admin screen) do.

## Testing

```bash
flutter test
```

Covers the display-ordering/filtering logic (`filterAndSort`) and widget
smoke tests that mock the native channel, including the PIN gate (shown
when set, wrong-PIN rejection, unlock, re-lock on resume).

## adb device workflow (helpful bits)

```powershell
adb connect 192.168.12.221:5555            # wireless adb
adb install -r build\app\outputs\flutter-apk\app-release.apk
adb shell dumpsys notification --noredact  # channel/card state
adb shell dumpsys alarm | findstr jotlock  # scheduled reminders
adb shell uiautomator dump                 # Flutter widgets via content-desc
```
