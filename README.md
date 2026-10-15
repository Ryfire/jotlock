# JotLock

**Capture notes from the Android lock screen — jot it, lock it.**

JotLock is a lightweight note app for Android whose superpower is capture speed: a
persistent *Quick note* notification puts capture wherever you are — a **Write note**
button on the lock screen, an inline **Jot** field in the shade while the phone is
unlocked — so a thought can be captured in seconds, and after a lock-screen save the
phone can **re-lock itself**.
No accounts, no cloud, no internet permission: notes live entirely on the device.

---

## Features

| Feature | What it does |
|---|---|
| **Lock screen capture** | A persistent *Quick note* notification lives in the shade; on the lock screen its **Write note** button opens a native note-entry screen. Survives reboots. |
| **Inline capture ("Jot")** | While the device is unlocked, the notification's **Jot** action expands a text field *directly in the shade* — type and send without opening any screen, even while you're inside another app. The card adapts automatically: **Write note** on the lock screen, **Jot + Save note** in the unlocked shade. |
| **Auto re-lock after saving** | Three user-selectable behaviors: **Lock the phone** (instant re-lock + screen off, via device admin — see [*Why device admin?*](#why-device-admin)), **Show the home screen**, or **Stay on the confirmation**. Per-save override buttons on the confirmation screen. |
| **Pin notes** | Long-press a note → Pin. Pinned notes float to the top of the list with a pin badge. |
| **Search** | Case-insensitive text search from the app bar, layered on pinned-first ordering. |
| **Copy to clipboard** | Copy icon on every note (and in the action sheet) with a "Copied" confirmation. Tap a note to edit. |
| **Share in** | JotLock appears in the Android **share sheet** and the **text-selection menu** anywhere — incoming text opens the editor pre-filled. |
| **Share out** | Long-press a note → Share to send its text anywhere. |
| **Export / import backup** | JSON export (via the share sheet) and merge-import that skips duplicates — doubles as a device-migration backup. Plus a human-readable **text export** (timestamps, pinned flags). |
| **Notification toggle** | Don't want the persistent notification? Turn it off in the app; it comes back on the next launch or reboot if re-enabled. |
| **Polish** | Material 3 light/dark, adaptive launcher icon + Android 13 themed icon, edit dialog for every note. |

---

## How to use

### From the lock screen (the whole point)

1. JotLock keeps a persistent **Quick note** notification in the shade.
2. On the lock screen, tap the notification or its **Write note** button
   (same destination).
3. The note-entry screen appears. On some devices it renders directly over the
   lock screen; on others Android asks for a quick unlock first (its security
   rule for third-party apps) — either way, type your note.
4. Tap **Save note**. Depending on your *After saving* setting the phone either
   locks instantly, shows the home screen, or waits for the screen to time out.
   The next wake-up is always the lock screen — the app never pops open.

### While browsing (inline "Jot")

1. With the phone unlocked, pull down the notification shade (from the home
   screen or inside any app).
2. Tap **Jot** on the Quick note notification — a text field expands in place.
3. Type and hit send. The note is saved with a "Note saved ✓" toast; you stay
   exactly where you were. The *After saving* setting does not apply here
   (no screen was opened, so nothing needs to be dismissed or re-locked).

The card is kept in sync with the lock state: **Write note** while locked,
**Jot + Save note** while unlocked.

### In the app

- **Tap a note** — open it in the editor (edit, Save).
- **Copy icon** — copy the note's text to the clipboard.
- **Delete icon** — remove a note (with confirmation).
- **Long-press a note** — action sheet: *Edit · Pin/Unpin · Copy · Share · Delete*.
- **Magnifier** — search notes.
- **＋ New note** — add a note normally.

### Settings (gear icon)

| Setting | Options |
|---|---|
| After saving a note from the lock screen | **Lock the phone** — requires one-time device-admin activation · **Show the home screen** · **Stay on the confirmation** |
| Export notes (JSON) | Writes the full note store to a `.json` file and hands it to the share sheet |
| Export notes (text) | Writes all notes as a readable `.txt` (timestamps, pinned flags, display order) |
| Import notes (JSON) | Picks a `.json` backup and merges it in (existing note ids are skipped) |
| Clear all notes | Permanently deletes every note after a confirmation dialog |

---

## How it works

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
| `lib/main.dart` | Notes list UI: search, pin, copy, share, editor, settings |
| `lib/note.dart` | Note model + `filterAndSort` (pinned first, newest first) |
| `lib/notes_repository.dart` | MethodChannel wrapper (`jotlock/notes`) |
| `MainActivity.kt` | Channel bridge, share-intent capture, admin activation |
| `QuickNoteActivity.kt` | The lock-screen capture screen (`showWhenLocked`, insets-safe) |
| `NotificationHelper.kt` | Persistent notification, channel, enabled toggle, lock-state-aware card variants (Write note ↔ Jot), screen-state listener |
| `QuickNoteReceiver.kt` | Saves inline notes typed in the notification and re-posts it |
| `NoteStore.kt` | JSON CRUD, pin, merge-import |
| `BootReceiver.kt` | Re-posts the notification after reboot |
| `LockAdminReceiver.kt` | Device admin — only policy used: `force-lock` (for lock-after-save) |
| `AppSettings.kt` | After-save behavior setting |

---

## Building

**Requirements:** Flutter SDK (developed on 3.47.x) with Android tooling,
compile SDK 37, min SDK 24 (Android 7.0+), Java 17.

```bash
flutter pub get
flutter run                      # debug on a connected device
flutter test                     # unit + widget tests
flutter analyze
flutter build apk --debug        # quick side-load
flutter build apk --release      # signed release (47.9 MB at v1.0.0)
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

---

## Why device admin?

Device admin is Android's official mechanism for granting "control the device"
privileges — normally the territory of corporate MDM software — so it's fair to ask
what a notes app is doing with it. The honest answer: **exactly one thing, by design,
and the OS itself enforces the limit.**

### The one thing: locking the screen

After you save a note from the lock screen, the *Lock the phone* mode calls
`DevicePolicyManager.lockNow()` — the programmatic equivalent of pressing the power
button — so the phone is back on the lock screen the instant you're done. Android
provides **no ordinary API** for a third-party app to lock the screen; declaring the
`force-lock` device-admin policy is the only sanctioned way to get it. (The workarounds
you'll see in "screen off" apps — AccessibilityService hooks — are far more invasive:
they can read screen content. Device admin with `force-lock` is the *least* privileged
option, not the most.)

### Why one policy means one policy

Admin capabilities must be **declared in the app's manifest**. JotLock's
`android/app/src/main/res/xml/device_admin.xml` contains exactly this:

```xml
<uses-policies>
    <force-lock />
</uses-policies>
```

That's it — the whole file. Android enforces this list itself: a device admin cannot
exercise a policy it hasn't declared. So the things device admins are *famous for* are
out of reach for JotLock, structurally:

- ✗ Factory-reset or wipe your data
- ✗ Read, set, or change your screen-lock password
- ✗ Enforce password rules or force a password change
- ✗ Disable the camera or monitor it
- ✗ Restrict lock-screen features, apps, or anything else

And two independent safeguards on top:

1. **No `INTERNET` permission** — JotLock cannot talk to the network at all. There is
   nowhere for any data to go, whatever happened. Notes never leave the device.
2. **Activation is opt-in and visible** — the admin is only requested when you pick
   *Lock the phone* in settings, and Android shows its own system screen listing the
   policies being granted before you confirm.

### It's optional, and easy to revoke

- Only the *Lock the phone* after-save mode needs it. **Show the home screen** and
  **Stay on the confirmation** work with no admin at all.
- To revoke: **Settings → Security → Device admin apps → JotLock → Deactivate**.
- One side effect worth knowing, because it's a *feature*: Android refuses to uninstall
  an app while it's an active device admin. A hostile app (or a curious toddler)
  can't silently remove your re-lock setup — you must deactivate first, then uninstall
  normally. JotLock adds no extra lock-in beyond that Android rule.

---

## Permissions (and why)

| Permission | Purpose |
|---|---|
| `POST_NOTIFICATIONS` | Shows the persistent Quick note notification (Android 13+ runtime prompt). |
| `RECEIVE_BOOT_COMPLETED` | Re-posts the notification after a reboot. |
| Device admin (`force-lock`) | Lets the app call `lockNow()` to re-lock the phone after a lock-screen save — nothing else. Optional; see [*Why device admin?*](#why-device-admin) for exactly what is (not) granted. |
| `ACTION_SEND` / `ACTION_PROCESS_TEXT` filters | Make JotLock a share-sheet and text-selection target (no data leaves the device). |

---

## Caveats worth knowing

- **Secure lock screens:** Android may require a quick unlock before showing the
  capture screen over a PIN/fingerprint keyguard. That's enforced by the OS for
  third-party apps; devices that allow over-keyguard rendering get the
  no-auth flow automatically.
- **OEM skins:** a few launchers render inline reply inconsistently on ongoing
  notifications — the plain button (**Write note** / **Save note**) remains as the
  reliable fallback everywhere.
- **Inline Jot availability:** the swap between the locked and unlocked card
  variants happens while the app's process is alive. If Android has killed
  the process in the background, the last posted variant stays — e.g. the
  shade may briefly lack **Jot** after a long lock until you open the app
  (or a note is saved) again. **Write note / Save note** are always present.
- **Uninstalling while device admin is active:** Android blocks uninstall until
  you deactivate it (Settings → Security → Device admin apps → JotLock). That's
  an Android safety rule, not a JotLock lock-in — see
  [*Why device admin?*](#why-device-admin).
- **Lock screen visibility:** the phone's *Lock screen → Notifications* setting
  must be "Show" (the default) for the capture action to appear while locked.
- Notes are capped at **500** (oldest auto-trimmed) and 4,000 characters each.
- OEM skins (Motorola, Samsung, Xiaomi…) vary in how they treat lock screen
  notifications — test on your device.

---

## Testing

```bash
flutter test
```

Covers the display-ordering/filtering logic (`filterAndSort`) and a widget smoke
test that mocks the native channel.
