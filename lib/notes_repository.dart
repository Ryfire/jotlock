import 'package:flutter/services.dart';

import 'note.dart';

/// Dart side of the `jotlock/notes` MethodChannel.
///
/// All note state lives in native SharedPreferences (see NoteStore.kt) so it
/// is shared with the lock screen capture screen, which runs without a
/// Flutter engine. Every mutation also re-posts the lock screen notification.
class NotesRepository {
  static const MethodChannel _channel = MethodChannel('jotlock/notes');

  Future<List<Note>> getNotes() async {
    final result = await _channel.invokeMethod<List<dynamic>>('getNotes');
    return (result ?? const []).whereType<Map>().map(Note.fromMap).toList();
  }

  Future<void> saveNote(String text) =>
      _channel.invokeMethod('saveNote', {'text': text});

  Future<void> updateNote(String id, String text) => _channel
      .invokeMethod('updateNote', {'id': id, 'text': text});

  /// Deletes a note (also cancels its pending alarm and reminder card
/// natively). Resolves false when the id was not found.
Future<bool> deleteNote(String id) async =>
    await _channel.invokeMethod<bool>('deleteNote', {'id': id}) ?? false;

  Future<void> setPinned(String id, bool pinned) =>
      _channel.invokeMethod('setPinned', {'id': id, 'pinned': pinned});

  /// Sets the priority color on a note. `0` removes the color.
  Future<void> setNoteColor(String id, int colorIndex) =>
      _channel.invokeMethod('setNoteColor', {'id': id, 'color': colorIndex});

  /// Marks a note done (or clears it). Reminder clearing is handled by the
  /// caller so it can show a user-visible confirmation.
  Future<void> setDone(String id, bool done) =>
      _channel.invokeMethod('setDone', {'id': id, 'done': done});

  /// Sets (or replaces) the reminder on a note. Native side schedules an
  /// exact AlarmManager alarm that posts a notification; when [silent] it
  /// fires without sound (banner only). [repeatDays] > 0 makes the reminder
  /// recurring — the native receiver advances and re-arms it on every fire
  /// (1 = daily, 7 = weekly, N = every N days).
  Future<void> setReminder(
    String id,
    DateTime at, {
    bool silent = false,
    int repeatDays = 0,
  }) =>
      _channel.invokeMethod(
        'setReminder',
        {
          'id': id,
          'atMillis': at.millisecondsSinceEpoch,
          'silent': silent,
          'repeatDays': repeatDays,
        },
      );

  /// Removes the reminder from a note, cancels its pending alarm and any
  /// visible reminder card.
  Future<void> cancelReminder(String id) =>
      _channel.invokeMethod('cancelReminder', {'id': id});

  /// Opens the system notification-sound picker (with a Silent option).
  /// Resolves with the newly chosen sound's display name; also resolves
  /// with the unchanged title if the picker was dismissed.
  Future<String> pickReminderSound() async =>
      await _channel.invokeMethod<String>('pickReminderSound') ?? '';

  /// Human-readable name of the current reminder sound.
  Future<String> getReminderSoundTitle() async =>
      await _channel.invokeMethod<String>('getReminderSoundTitle') ?? '';

  /// Whether the app is already exempt from battery optimizations
  /// (doze / App Standby), keeping the process and its lock-screen
  /// service alive in the background.
  Future<bool> isBatteryExempt() async {
    return await _channel.invokeMethod<bool>('isBatteryExempt') ?? false;
  }

  /// Opens the system dialog asking to exempt the app from battery
  /// optimizations. No-op when already exempt.
  Future<void> requestBatteryExempt() =>
      _channel.invokeMethod('requestBatteryExempt');

  /// Opens [url] in the system browser (https/http only — enforced
  /// natively). The app itself stays offline; the browser handles the link.
  Future<void> openUrl(String url) =>
      _channel.invokeMethod('openUrl', {'url': url});

  /// Installed app version name (PackageManager.versionName), or ''.
  Future<String> getVersionName() async =>
      await _channel.invokeMethod<String>('getVersionName') ?? '';

  /// Note id from a tapped reminder notification, or null. Consuming the
  /// value clears it.
  Future<String?> takePendingOpenNoteId() =>
      _channel.invokeMethod<String>('takePendingOpenNoteId');

  /// Text sent into the app from the share sheet (ACTION_SEND) or the
  /// text-selection menu (ACTION_PROCESS_TEXT), or null if there is none.
  /// Consuming the value clears it.
  Future<String?> takePendingIncomingText() =>
      _channel.invokeMethod<String>('takePendingIncomingText');

  /// Full notes store as a JSON array string (matches the native format).
  Future<String> getExportJson() async {
    return await _channel.invokeMethod<String>('getExportJson') ?? '[]';
  }

  /// Merges a JSON array of notes; notes with an already-present id are
  /// skipped. Returns the number of notes added.
  Future<int> importNotes(String json) async {
    return await _channel.invokeMethod<int>('importNotes', {'json': json}) ?? 0;
  }

  /// Permanently deletes every note.
  Future<void> clearNotes() => _channel.invokeMethod('clearNotes');

  Future<void> refreshNotification() =>
      _channel.invokeMethod('refreshNotification');

  Future<void> dismissNotification() =>
      _channel.invokeMethod('dismissNotification');

  Future<bool> isNotificationEnabled() async {
    return await _channel.invokeMethod<bool>('isNotificationEnabled') ?? true;
  }

  /// What the lock screen capture screen does after a note is saved:
  /// `lock` (device admin), `home`, or `wait` (stay until screen off).
  Future<String> getAfterSaveAction() async {
    return await _channel.invokeMethod<String>('getAfterSaveAction') ?? 'wait';
  }

  Future<void> setAfterSaveAction(String action) =>
      _channel.invokeMethod('setAfterSaveAction', {'action': action});

  /// Whether an app PIN gates the management UI. Only a salted hash is
  /// stored natively; the plaintext digits never persist.
  Future<bool> isPinSet() async {
    return await _channel.invokeMethod<bool>('isPinSet') ?? false;
  }

  /// Whether returning from the background re-locks the PIN gate
  /// (default true). When off, the gate only engages on a cold start.
  Future<bool> getRelockOnResume() async {
    return await _channel.invokeMethod<bool>('getRelockOnResume') ?? true;
  }

  Future<void> setRelockOnResume(bool value) =>
      _channel.invokeMethod('setRelockOnResume', {'value': value});

  /// Stores a new PIN (4-8 digits) natively as a salted hash.
  Future<void> setPin(String pin) =>
      _channel.invokeMethod('setPin', {'pin': pin});

  /// Checks a PIN against the stored hash.
  Future<bool> verifyPin(String pin) async {
    return await _channel.invokeMethod<bool>('verifyPin', {'pin': pin}) ?? false;
  }

  /// Removes the PIN; only succeeds when [pin] matches the current one.
  Future<bool> clearPin(String pin) async {
    return await _channel.invokeMethod<bool>('clearPin', {'pin': pin}) ?? false;
  }

  Future<bool> isDeviceAdminActive() async {
    return await _channel.invokeMethod<bool>('isDeviceAdminActive') ?? false;
  }

  Future<void> requestDeviceAdmin() =>
      _channel.invokeMethod('requestDeviceAdmin');
}
