package com.ryfire.jotlock

import android.content.Context
import java.security.MessageDigest
import java.security.SecureRandom

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
 *
 * App PIN: optional gate on the Flutter management UI. Only a salted
 * SHA-256 hash is stored — never the plaintext digits.
 */
object AppSettings {
    private const val PREFS_FILE = "jotlock"
    private const val KEY_AFTER_SAVE = "after_save_action"
    private const val KEY_REMINDER_SOUND = "reminder_sound_uri"
    private const val KEY_REMINDER_CHANNEL_VERSION = "reminder_channel_version"
    private const val KEY_PIN_HASH = "pin_hash"
    private const val KEY_PIN_SALT = "pin_salt"
    private const val KEY_RELOCK_ON_RESUME = "relock_on_resume"

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

    /** Version suffix of the active sounded reminder channel. */
    fun reminderChannelVersion(context: Context): Int =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getInt(KEY_REMINDER_CHANNEL_VERSION, 1)

    fun setReminderChannelVersion(context: Context, version: Int) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_REMINDER_CHANNEL_VERSION, version)
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

    /** Whether an app PIN has been set (only a hash exists in prefs). */
    fun isPinSet(context: Context): Boolean =
        pinHash(context).isNotEmpty() && pinSalt(context).isNotEmpty()

    /**
     * Stores a new PIN: generates a fresh 16-byte salt, saves the SHA-256
     * of "jotlock:salt:pin" as hex. The plaintext never leaves this call.
     */
    fun setPin(context: Context, pin: String) {
        val saltBytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val salt = hex(saltBytes)
        val prefs = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_PIN_SALT, salt)
            .putString(KEY_PIN_HASH, hex(sha256(salt, pin)))
            .apply()
    }

    /** Constant-time comparison of the entered PIN against the stored hash. */
    fun verifyPin(context: Context, pin: String): Boolean {
        val salt = pinSalt(context)
        val stored = pinHash(context)
        if (salt.isEmpty() || stored.isEmpty()) return false
        return MessageDigest.isEqual(
            stored.toByteArray(Charsets.UTF_8),
            hex(sha256(salt, pin)).toByteArray(Charsets.UTF_8)
        )
    }

    /** Removes the PIN (caller must have verified it first). */
    fun clearPin(context: Context) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_PIN_HASH)
            .remove(KEY_PIN_SALT)
            .apply()
    }

    /**
     * Whether returning to the app from the background should re-lock the
     * PIN gate (default true). When off, the gate only engages on a cold
     * app start. Read fresh by the gate on every resume.
     */
    fun relockOnResume(context: Context): Boolean =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_RELOCK_ON_RESUME, true)

    fun setRelockOnResume(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RELOCK_ON_RESUME, value)
            .apply()
    }

    private fun pinHash(context: Context): String =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(KEY_PIN_HASH, "") ?: ""

    private fun pinSalt(context: Context): String =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(KEY_PIN_SALT, "") ?: ""

    private fun sha256(salt: String, pin: String): ByteArray =
        MessageDigest.getInstance("SHA-256")
            .digest("jotlock:$salt:$pin".toByteArray(Charsets.UTF_8))

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }
}
