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
flutter build apk --release      # signed release
```

### Release signing

`app-release.apk` is signed with `android/app/jotlock.keystore`. The keystore
credentials live in `android/key.properties`:

```
storePassword=...
keyPassword=...
keyAlias=jotlock
storeFile=jotlock.keystore
```

Keep the keystore **and** `key.properties` safe — losing them means you can't
update the app with the same identity. To regenerate from scratch:

```bash
keytool -genkeypair -v -keystore android/app/jotlock.keystore \
  -storetype PKCS12 -alias jotlock -keyalg RSA -keysize 2048 \
  -validity 10950 -dname "CN=JotLock, O=Ryfire, C=US"
```

If `key.properties` is absent, release builds fall back to debug signing so
CI-style checkouts still build.

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
| `lib/main.dart` | Notes list UI: search, pin, copy, share, editor, reminders, settings |
| `lib/note.dart` | Note model + `filterAndSort` (pinned first, newest first) |
| `lib/notes_repository.dart` | MethodChannel wrapper (`jotlock/notes`) |
| `MainActivity.kt` | Channel bridge, share-intent capture, sound picker, admin activation |
| `QuickNoteActivity.kt` | The lock-screen capture screen (`showWhenLocked`, insets-safe) |
| `NotificationHelper.kt` | Persistent notification, channels, lock-state-aware card variants (Write note ↔ Jot), screen-state listener, reminder sound channels |
| `QuickNoteReceiver.kt` | Saves inline notes typed in the notification and re-posts it |
| `ReminderScheduler.kt` | Exact AlarmManager scheduling, re-arm on boot |
| `ReminderReceiver.kt` | Fires reminder cards (grouped, SECRET on lock screen), clears the one-shot |
| `NoteStore.kt` | JSON CRUD, pin, reminders (`reminderAt`/`reminderSilent`), merge-import |
| `BootReceiver.kt` | Re-posts the notification and re-arms reminders after reboot |
| `LockAdminReceiver.kt` | Device admin — only policy used: `force-lock` (for lock-after-save) |
| `AppSettings.kt` | After-save behavior, reminder sound URI, channel version |
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

## Testing

```bash
flutter test
```

Covers the display-ordering/filtering logic (`filterAndSort`) and a widget
smoke test that mocks the native channel.

## adb device workflow (helpful bits)

```powershell
adb connect 192.168.12.221:5555            # wireless adb
adb install -r build\app\outputs\flutter-apk\app-release.apk
adb shell dumpsys notification --noredact  # channel/card state
adb shell dumpsys alarm | findstr jotlock  # scheduled reminders
adb shell uiautomator dump                 # Flutter widgets via content-desc
```
