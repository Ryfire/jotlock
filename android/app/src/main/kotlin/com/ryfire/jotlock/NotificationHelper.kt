package com.ryfire.jotlock

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat

/**
 * Builds and posts the persistent "Quick note" notification. The card is
 * re-rendered to match the device lock state, because Android shows the
 * same card on every surface and the two states want different things:
 *
 * - device locked (lock screen card): a single **Write note** action that
 *   opens QuickNoteActivity, which renders on top of the keyguard so notes
 *   can be typed and saved without unlocking. The inline reply field is
 *   deliberately not offered there: inline replies over a keyguard behave
 *   inconsistently across OEM skins (some dismiss the lock screen).
 * - device unlocked (shade while browsing): **Jot** — an inline RemoteInput
 *   reply field that saves via QuickNoteReceiver without opening any screen
 *   — next to a **Write note** action for the full capture screen.
 *
 * post() picks the variant from KeyguardManager at post time. To keep the
 * card current as the user locks/unlocks — and to guarantee a stale
 * unlocked card (with Jot) can never linger onto the lock screen —
 * LockStateService hosts this helper's screen listener at foreground
 * priority so the process is never killed between re-posts. The service's
 * foreground notification IS this card, so nothing extra is shown.
 *
 * The card must stay VISIBILITY_PUBLIC: on Moto's lock screen, expanding
 * a collapsed notification icon for a non-public card is treated as
 * "unlock to view" (the keyguard drops straight to the launcher instead
 * of showing the card), which breaks the Write-note-from-lock-screen flow.
 */
object NotificationHelper {
    const val CHANNEL_ID = "quick_notes"
    const val NOTIFICATION_ID = 1001

    private const val PREFS_FILE = "jotlock"
    private const val KEY_NOTIFICATION_ENABLED = "notification_enabled"

    // Same value as Notification.CATEGORY_NOTE (framework constant).
    private const val CATEGORY_NOTE = "note"

    private var screenListenerRegistered = false

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getBoolean(KEY_NOTIFICATION_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_NOTIFICATION_ENABLED, enabled)
            .apply()
    }

    /**
     * Builds the card matching the current lock state. Unlike [buildCard],
     * returns null when the notification is disabled in settings.
     */
    fun build(context: Context): Notification? =
        if (isEnabled(context)) buildCard(context) else null

    /** Posts the variant matching the current lock state. */
    fun post(context: Context) {
        val notification = build(context) ?: return
        notificationManager(context).notify(NOTIFICATION_ID, notification)
    }

    /** Builds the card regardless of the enabled setting (used by LockStateService). */
    fun buildCard(context: Context): Notification {
        ensureChannel(context)
        Log.d(TAG, "build: locked=${isDeviceLocked(context)}")

        // One PendingIntent, two tap paths: the notification body and the
        // Write note action both open QuickNoteActivity.
        val openPending = PendingIntent.getActivity(
            context,
            0,
            Intent(context, QuickNoteActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val writeAction = NotificationCompat.Action.Builder(
            R.drawable.ic_note,
            "Write note",
            openPending
        ).build()

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_note)
            .setContentTitle("Quick note")
            .setOngoing(true)
            .setCategory(CATEGORY_NOTE)
            // PUBLIC keeps the card visible (with its actions) on the lock
            // screen — see the class comment for why PRIVATE breaks it.
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openPending)
            .setOnlyAlertOnce(true)

        if (isDeviceLocked(context)) {
            // Lock screen card: Write note only.
            builder.addAction(writeAction)
        } else {
            // Inline capture: expands a text field right in the shade.
            // Android 12+ requires MUTABLE for PendingIntents backing remote
            // inputs — the system fills the typed text into the intent.
            val replyPending = PendingIntent.getBroadcast(
                context,
                1,
                Intent(context, QuickNoteReceiver::class.java)
                    .setAction(QuickNoteReceiver.ACTION_INLINE_SAVE),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            val jotAction = NotificationCompat.Action.Builder(
                R.drawable.ic_note,
                "Jot",
                replyPending
            )
                .addRemoteInput(
                    RemoteInput.Builder(QuickNoteReceiver.EXTRA_INLINE_TEXT)
                        .setLabel("Note")
                        .build()
                )
                .setAllowGeneratedReplies(false)
                .build()
            builder.addAction(jotAction).addAction(writeAction)
        }

        return builder.build()
    }

    /**
     * Registers the lock-state listener (idempotent) so the posted card
     * swaps between the locked and unlocked variants as the device locks
     * and unlocks. Process-scoped: no service, no wake-ups, no cost while
     * the process is dead — which is exactly why LockStateService keeps
     * the process alive at foreground priority.
     */
    fun ensureScreenListener(context: Context) {
        if (screenListenerRegistered) return
        screenListenerRegistered = true
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                Log.d(TAG, "screen event: ${intent.action}")
                post(ctx.applicationContext)
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        // All three actions are protected system broadcasts (only the OS can
        // send them), so an exported receiver is safe here. RECEIVER_NOT_
        // EXPORTED silently drops USER_PRESENT on Android 14+ (stickiness +
        // export-policy interaction observed on device) — exported restores
        // delivery while keeping the actions spoof-proof.
        ContextCompat.registerReceiver(
            context.applicationContext,
            receiver,
            filter,
            ContextCompat.RECEIVER_EXPORTED
        )
        Log.d(TAG, "screen listener registered")
    }

    fun cancel(context: Context) {
        notificationManager(context).cancel(NOTIFICATION_ID)
    }

    private fun isDeviceLocked(context: Context): Boolean {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return km.isKeyguardLocked
    }

    private fun ensureChannel(context: Context) {
        // NotificationChannel requires API 26; NotificationCompat falls back on 24/25.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Quick notes",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Capture quick notes from the lock screen or shade"
            setShowBadge(false)
        }
        notificationManager(context).createNotificationChannel(channel)
    }

    /**
     * Reminder channels. Two exist: the sounded one carries the user's
     * picked notification sound (versioned id — channel sound is immutable
     * after creation, so changing it requires delete + recreate), the
     * silent one posts a banner without sound or vibration for reminders
     * the user marked quiet. Both are IMPORTANCE_HIGH (heads-up + lock
     * screen alert) but lockscreenVisibility SECRET: reminder cards must
     * never clutter the lock screen — the jot "Write note" card stands
     * alone there — while sounded reminders still ring while locked.
     */
    fun currentReminderChannelId(context: Context): String {
        ensureReminderChannels(context)
        return "note_reminders_v$reminderChannelVersion"
    }

    const val REMINDER_SILENT_CHANNEL_ID = "note_reminders_silent"

    private var reminderChannelVersion = 1

    fun ensureReminderChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = notificationManager(context)

        // Legacy unversioned channel from before the sound feature —
        // no longer used; remove it from user-facing channel lists.
        nm.deleteNotificationChannel("note_reminders")

        val silent = NotificationChannel(
            REMINDER_SILENT_CHANNEL_ID,
            "Note reminders (silent)",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Reminders on individual notes, without sound"
            setShowBadge(true)
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = NotificationCompat.VISIBILITY_SECRET
        }
        nm.createNotificationChannel(silent)

        val sounded = NotificationChannel(
            "note_reminders_v$reminderChannelVersion",
            "Note reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Reminders you set on individual notes"
            setShowBadge(true)
            setSound(
                resolveReminderSoundUri(context),
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            enableVibration(true)
            lockscreenVisibility = NotificationCompat.VISIBILITY_SECRET
        }
        nm.createNotificationChannel(sounded)
    }

    /** Stored URI, or the system default notification sound when unset. */
    fun resolveReminderSoundUri(context: Context): android.net.Uri? {
        val stored = AppSettings.reminderSoundUri(context)
        if (stored != null) {
            return if (stored.isEmpty()) null else android.net.Uri.parse(stored)
        }
        return android.provider.Settings.System.DEFAULT_NOTIFICATION_URI
    }

    /**
     * Applies a newly picked sound: bumps the version, deletes the old
     * sounded channel, recreates it with the new URI (the documented
     * workaround for immutable channel sound). Silent channel is untouched.
     */
    fun applyReminderSound(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = notificationManager(context)
        nm.deleteNotificationChannel("note_reminders_v$reminderChannelVersion")
        reminderChannelVersion++
        ensureReminderChannels(context)
        Log.d(TAG, "reminder sound applied, channel v$reminderChannelVersion")
    }

    /** Human-readable name of the current reminder sound ("Silent" etc). */
    fun reminderSoundTitle(context: Context): String {
        val stored = AppSettings.reminderSoundUri(context)
        if (stored != null && stored.isEmpty()) return "Silent"
        val uri = resolveReminderSoundUri(context) ?: return "Silent"
        if (uri == android.provider.Settings.System.DEFAULT_NOTIFICATION_URI) {
            return "System default"
        }
        return try {
            val ringtone = android.media.RingtoneManager.getRingtone(context, uri)
            ringtone?.getTitle(context) ?: "Unknown sound"
        } catch (_: Exception) {
            "Unknown sound"
        }
    }

    private fun notificationManager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private const val TAG = "JotLockNotif"
}