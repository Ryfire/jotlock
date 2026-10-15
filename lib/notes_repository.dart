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

  Future<void> deleteNote(String id) =>
      _channel.invokeMethod('deleteNote', {'id': id});

  Future<void> setPinned(String id, bool pinned) =>
      _channel.invokeMethod('setPinned', {'id': id, 'pinned': pinned});

  /// Sets (or replaces) the one-shot reminder on a note. Native side
  /// schedules an exact AlarmManager alarm that posts a notification.
  /// [silent] fires it without sound (banner only).
  Future<void> setReminder(String id, DateTime at, {bool silent = false}) =>
      _channel.invokeMethod(
        'setReminder',
        {
          'id': id,
          'atMillis': at.millisecondsSinceEpoch,
          'silent': silent,
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

  Future<bool> isDeviceAdminActive() async {
    return await _channel.invokeMethod<bool>('isDeviceAdminActive') ?? false;
  }

  Future<void> requestDeviceAdmin() =>
      _channel.invokeMethod('requestDeviceAdmin');
}
