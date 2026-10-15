package com.ryfire.jotlock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Schedules one-shot note reminders with AlarmManager so they fire even
 * with the app process dead. Exact alarms are used when the platform
 * allows them (USE_EXACT_ALARM is declared in the manifest), falling back
 * to a setWindow inexact alarm — a few minutes of drift beats not firing.
 *
 * Request codes are derived from the note id's hash, so re-scheduling the
 * same note replaces its previous alarm and canceling is a plain
 * AlarmManager.cancel with an identical PendingIntent.
 */
object ReminderScheduler {
    const val EXTRA_NOTE_ID = "reminder_note_id"

    // Fallback window when exact alarms are not permitted.
    private const val INEXACT_WINDOW_MS = 10 * 60 * 1000L

    private fun alarmManager(context: Context): AlarmManager =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pendingIntent(context: Context, id: String): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction(ReminderReceiver.ACTION_FIRE)
            .putExtra(EXTRA_NOTE_ID, id)
        return PendingIntent.getBroadcast(
            context,
            id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun schedule(context: Context, id: String, atMillis: Long) {
        val am = alarmManager(context)
        val pi = pendingIntent(context, id)
        val exactAllowed =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (exactAllowed) {
            am.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                atMillis,
                pi
            )
            Log.d(TAG, "scheduled exact reminder for $id at $atMillis")
        } else {
            am.setWindow(
                AlarmManager.RTC_WAKEUP,
                atMillis,
                INEXACT_WINDOW_MS,
                pi
            )
            Log.d(TAG, "scheduled inexact reminder for $id at ~$atMillis")
        }
    }

    fun cancel(context: Context, id: String) {
        alarmManager(context).cancel(pendingIntent(context, id))
        Log.d(TAG, "canceled reminder alarm for $id")
    }

    /**
     * Re-arms every future reminder (idempotent — identical PendingIntents
     * overwrite). Used after imports and on boot.
     */
    fun rescheduleAll(context: Context) {
        val now = System.currentTimeMillis()
        val notes = NoteStore.getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            val at = note.optLong("reminderAt", 0L)
            if (at > now) schedule(context, note.optString("id"), at)
        }
    }

    /**
     * Boot path: re-arm future reminders; fire past-due ones immediately so
     * a reminder that elapsed while the device was off is not lost.
     */
    fun onBoot(context: Context) {
        val now = System.currentTimeMillis()
        val notes = NoteStore.getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            val at = note.optLong("reminderAt", 0L)
            if (at == 0L) continue
            val id = note.optString("id")
            if (at > now) {
                schedule(context, id, at)
            } else {
                ReminderReceiver.showReminder(context, id)
            }
        }
    }

    private const val TAG = "JotLockReminder"
}