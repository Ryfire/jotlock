# JotLock

**Capture notes from the Android lock screen — jot it, lock it.**

JotLock is a fast, no-nonsense notes app built around one idea: a thought should be
captured in seconds, no matter what your phone is doing. A persistent **Quick note**
notification gives you a **Write note** button on the lock screen, an inline **Jot**
field in the shade, and per-note **reminders** that always play your sound but never
clutter your lock screen.

- **No unlocking required** — write and save notes straight from the lock screen
- **Re-locks itself** — when you're done, the phone goes back to locked, instantly
- **Private by design** — no accounts, no cloud, no internet permission. Notes never
  leave the device.
- **Free and open source** — inspect every line.

Latest release: **v1.1.2** · Requires Android 7.0+

---

## Highlights

### Capture from the lock screen
Tap the jot pencil on the lock screen and start typing — notes save without
unlocking, and the phone re-locks itself the moment you're done. Unlocking, finding
an app, waiting for it to load: gone.

### Capture from anywhere (inline Jot)
While browsing any app, pull down the shade and tap **Jot** — a text field expands
right there. Send, and you're back where you were. The note is saved; nothing on
screen changes.

### Reminders that stay out of the way
Long-press any note → **Remind me…** — pick 10 minutes, 1 hour, tomorrow 9 AM, or
any custom date and time. When it fires you get a heads-up with your sound
(your choice, or none) and tapping it opens the note ready to edit. Reminder cards
**never appear on the lock screen** — your jot button stays alone up there.

### Backup in one tap
Export all notes as JSON or readable text, import a JSON backup to merge (duplicates
skipped) — handy for moving to a new phone.

---

## Features

| Feature | What it does |
|---|---|
| **Lock screen capture** | A persistent *Quick note* notification puts a **Write note** button on the lock screen. Survives reboots. |
| **Inline capture (Jot)** | While unlocked, the notification's **Jot** action expands a text field directly in the shade — even inside other apps. |
| **Auto re-lock after saving** | Three options: **Lock the phone**, **Show the home screen**, or **Stay on the confirmation**. |
| **Reminders** | One-shot reminders per note — presets or custom date/time. Heads-up banner with your sound; opens the note pre-filled on tap. |
| **Reminder sound** | Pick any system notification sound globally, or mark individual reminders silent. |
| **Background keep-alive** | One-time "Allow" makes the capture card and reminders reliable through doze. |
| **Pin notes** | Pinned notes float to the top with a badge. |
| **Search** | Case-insensitive search over all notes. |
| **Copy / share** | Copy any note to the clipboard, or share it out. JotLock also accepts text sent **in** from the share sheet and the text-selection menu. |
| **Export / import** | JSON backup (share it anywhere) and a readable text export. |
| **Notification toggle** | Don't want the persistent card? Turn it off in settings; it returns on next launch. |
| **Polish** | Material 3, light/dark, adaptive + themed icons. |

---

## Getting started

1. **Install** the APK from [Releases](../../releases) and open JotLock.
2. **Allow notifications** when Android asks (Android 13+).
3. Optional — for *Lock the phone* mode: pick it in Settings and activate the
   device-admin prompt Android shows (see below).
4. Recommended — Settings → **Keep running in background** → **Allow**, so the
   capture card and reminders stay reliable.

## How to use

### From the lock screen

1. Tap the jot pencil (or the **Write note** button on the Quick note card).
2. Type your note, tap **Save note**.
3. Depending on your *After saving* setting the phone locks instantly, goes home,
   or stays put — the next wake is always the lock screen, never the app.

> If your phone uses a PIN/fingerprint, Android may ask for a quick unlock before
> showing the capture screen — that's an OS security rule for all apps, not a
> JotLock setting.

### From the shade (inline Jot)

1. Pull down the notification shade anywhere — home screen or inside any app.
2. Tap **Jot** on the Quick note card, type, send.
3. Done — you stay exactly where you were.

### Reminders

1. **Long-press a note** (or tap it → menu) → **Remind me…**
2. Pick a preset or *Pick date & time…*, choose whether it should play your sound,
   and tap **Set reminder**.
3. When it fires, tap the card to edit the note. One-shot: it fires once and clears.

The reminder sound itself (what "play sound" uses) is set in Settings →
**Reminder sound**.

### In the app

- **Tap a note** to edit · **Copy** / **Delete** icons on each note
- **Long-press** for the full menu: *Edit · Pin · Copy · Remind me… · Share · Delete*
- **Magnifier** to search · **＋ New note** to add

---

## Settings

| Setting | What it's for |
|---|---|
| After saving a note from the lock screen | Lock the phone · Show the home screen · Stay on the confirmation |
| Reminder sound | The sound sounded reminders play — system picker, Silent included |
| Keep running in background | One-time allow so the card + reminders survive battery doze |
| Export / Import | JSON backup round-trip, plus a readable text export |
| Clear all notes | Wipes everything (after confirmation) |

---

## Privacy & permissions

JotLock is offline-only. There is **no INTERNET permission**, so it cannot send
anything anywhere — notes physically have nowhere to go but your device.

| Permission | Why |
|---|---|
| Notifications | The Quick note card and reminder alerts. |
| Exact alarms | Reminders fire on time even after a reboot or overnight idle. |
| Background (battery) | Optional one-time allow so capture/reminders survive doze. |
| Device admin (force-lock) | Optional, only for *Lock the phone* mode — see below. |

### About device admin

*Lock the phone* after saving needs Android's only sanctioned way for an app to
re-lock the screen: the `force-lock` device-admin policy. That is the **single
policy** JotLock declares — Android itself forbids an admin from using anything it
hasn't declared, so wiping data, changing passwords, camera access and the rest are
structurally out of reach. Activation is opt-in (only when you pick that mode) and
revocable anytime via **Settings → Security → Device admin apps → JotLock**.

---

## Good to know

- The lock-screen card needs your phone's *Lock screen → Notifications* set to
  **Show** (the default).
- A few phone skins render inline reply fields inconsistently; the plain buttons
  (**Write note** / **Save note**) work everywhere.
- Notes are capped at 500 (oldest trimmed) and 4,000 characters each.
- While device admin is active, Android blocks uninstalling until you deactivate it
  (a safety rule, not JotLock lock-in).

---

## Building from source

Flutter + Android SDK; see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for setup,
architecture and release signing.

```bash
flutter pub get
flutter run
```
