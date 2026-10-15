package com.ryfire.jotlock

import android.content.Context

/**
 * App-level settings (SharedPreferences, shared between Dart and Kotlin).
 *
 * After a note is saved from the lock screen, the capture screen either
 * locks the phone, shows the home screen, or waits for the screen to turn
 * off — chosen by the user in the app settings.
 */
object AppSettings {
    private const val PREFS_FILE = "jotlock"
    private const val KEY_AFTER_SAVE = "after_save_action"

    const val AFTER_SAVE_WAIT = "wait"
    const val AFTER_SAVE_LOCK = "lock"
    const val AFTER_SAVE_HOME = "home"

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
