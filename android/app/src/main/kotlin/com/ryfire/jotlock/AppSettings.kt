package com.ryfire.jotlock

import android.content.Context

/**
 * App-level settings (SharedPreferences, shared between Dart and Kotlin).
 *
 * After a note is saved from the lock screen, the capture screen either
 * locks the phone, shows the home screen, or waits for the screen to turn
 * off — chosen by the user in the app settings.
 *
 * Reminder sound: the notification-sound URI played by sounded reminder
 * notifications, chosen via the system ringtone picker. An empty string
 * means "Silent" was picked; null (unset) means the system default sound.
 */
object AppSettings {
    private const val PREFS_FILE = "jotlock"
    private const val KEY_AFTER_SAVE = "after_save_action"
    private const val KEY_REMINDER_SOUND = "reminder_sound_uri"

    const val AFTER_SAVE_WAIT = "wait"
    const val AFTER_SAVE_LOCK = "lock"
    const val AFTER_SAVE_HOME = "home"

    /** "" = Silent picked; null = never picked (system default). */
    fun reminderSoundUri(context: Context): String? =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(KEY_REMINDER_SOUND, null)

    fun setReminderSoundUri(context: Context, uri: String?) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_REMINDER_SOUND, uri)
            .apply()
    }

    fun afterSaveAction(context: Context): String =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(KEY_AFTER_SAVE, AFTER_SAVE_WAIT) ?: AFTER_SAVE_WAIT

    fun setAfterSaveAction(context: Context, action: String) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_AFTER_SAVE, action)
            .apply()
    }
}
