# Play Store readiness: exact-alarm permission migration

Parked plan for the day JotLock targets the Google Play Store. Nothing here is
implemented yet — GitHub and F-Droid builds keep the current behavior.

## Why it exists

Play policy restricts `USE_EXACT_ALARM` (Android 13+) to apps whose **core**
functionality is precisely-timed actions — alarm clocks and calendar apps.
JotLock is a notes app with a reminder feature, so submitting as-is risks
rejection (task/reminder apps have been rejected for exactly this). GitHub and
F-Droid enforce no such policy; the current permission is fine there.

The side effect diagnosed on-device (Android pins `USE_EXACT_ALARM` holders to
unrestricted battery with a greyed, non-user-controllable toggle — same as the
stock Clock app) is also part of the Play-risk picture.

## The swap

`USE_EXACT_ALARM` → `SCHEDULE_EXACT_ALARM` (user-granted special access).

| | Current (`USE_EXACT_ALARM`) | After migration (`SCHEDULE_EXACT_ALARM`) |
|---|---|---|
| Play Store | Rejection risk | Compliant, no declaration form needed |
| User experience | Zero prompts | One-time system grant ("Alarms & reminders → Allow") |
| Reminder punctuality | Exact always | Exact if granted; otherwise ~10-min drift window |
| Battery menu | Pinned unrestricted, greyed | Ordinary user control |

## Migration steps

1. **Manifest** (`android/app/src/main/AndroidManifest.xml`):
   - Remove `android.permission.USE_EXACT_ALARM`.
   - Remove the `maxSdkVersion="32"` attribute from
     `android.permission.SCHEDULE_EXACT_ALARM` so it applies on 33+.
   - Result:
     ```xml
     <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
     ```
2. **Grant prompt** — when setting a reminder without the grant:
   - Fire `Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM` with
     `package:<pkg>` URI (system toggle screen), once, from the reminder
     dialog; proceed with scheduling regardless of the outcome.
   - `ReminderScheduler.schedule()` already branches on
     `canScheduleExactAlarms()` → `setWindow` fallback. No logic change
     needed — the fallback path just becomes reachable on 31+.
   - Android 11 and below: nothing to do (exact alarms predate the permission).
3. **Settings tile** — reuse the "Keep running in background" tile pattern:
   "Allow exact alarms so reminders fire on time — or they'll fire within
   ~10 minutes." Hidden or inert when granted.
4. **Re-verify on device**:
   - Grant path: reminder fires exactly on time in doze (04:01-style check).
   - Deny path: reminder fires within the ~10-minute window.
   - Boot re-arm still works.
5. **Ship**: version bump + release note ("stricter permission, one-time
   Allow"). GitHub/F-Droid users updating lose the auto-grant until they tap
   Allow — a one-time settings nudge covers it.

## Known user-facing delta

- Declining the grant never loses a reminder — it only allows drift (the
  existing inexact fallback).
- One trivial extra permission tap for users coming from the alternate
  platforms; reminders otherwise behave identically.
