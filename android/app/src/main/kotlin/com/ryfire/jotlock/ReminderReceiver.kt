package com.ryfire.jotlock

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/**
 * Fires a note's reminder notification when its alarm elapses. The note's
 * text is read fresh from NoteStore at fire time (an edited note reminds
 * with its current text; a deleted note is a silent no-op). Reminders are
 * one-shot: the stored reminderAt is cleared here so nothing re-fires.
 *
 * Cards share a group key with an auto summary so several reminders firing
 * the same day collapse into one stacked shade entry instead of filling it.
 * Tapping a card opens MainActivity with the note id; the notification is
 * auto-canceled on tap.
 */
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return
        val id = intent.getStringExtra(ReminderScheduler.EXTRA_NOTE_ID) ?: return
        showReminder(context, id)
    }

    companion object {
        const val ACTION_FIRE = "com.ryfire.jotlock.ACTION_REMINDER_FIRE"
        const val REMINDER_CHANNEL_ID = "note_reminders"
        const val GROUP_KEY = "com.ryfire.jotlock.REMINDERS"

        // Distinct stable ids: NOTIFICATION_ID (jot card) is 1001; reminder
        // cards live above 100000, the summary just under them.
        const val SUMMARY_ID = 99999

        fun notificationIdFor(id: String): Int =
            100000 + (id.hashCode() and 0x7FFFFFFF) % 800000

        /**
         * Posts the reminder card for [id] and clears the stored reminder
         * (one-shot). Also callable directly, e.g. for past-due reminders
         * found on boot.
         */
        fun showReminder(context: Context, id: String) {
            val note = NoteStore.getNote(context, id)
            // One-shot: drop the stored reminder regardless of whether the
            // note still exists.
            NoteStore.setReminderAt(context, id, 0L)
            val text = note?.optString("text")?.trim().orEmpty()
            if (note == null || text.isEmpty()) return

            NotificationHelper.ensureReminderChannel(context)
            val openNote = openNotePendingIntent(context, id)
            val child = NotificationCompat.Builder(context, REMINDER_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_note)
                .setContentTitle("Note reminder")
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(openNote)
                .setAutoCancel(true)
                .setGroup(GROUP_KEY)
                .setColor(0xFF3F51B5.toInt())
                .build()
            val nm = notificationManager(context)
            nm.notify(notificationIdFor(id), child)

            // Post a collapsed summary once two or more reminder cards
            // share the shade.
            var groupCount = 0
            for (sb in nm.activeNotifications) {
                if (sb.notification.group == GROUP_KEY) groupCount++
            }
            if (groupCount >= 2) {
                val summary = NotificationCompat.Builder(context, REMINDER_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_note)
                    .setContentTitle("JotLock reminders")
                    .setContentText("$groupCount note reminders")
                    .setGroup(GROUP_KEY)
                    .setGroupSummary(true)
                    // Only the children alert; the summary stays silent.
                    .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
                    .setColor(0xFF3F51B5.toInt())
                    .setContentIntent(openNote)
                    .setAutoCancel(true)
                    .build()
                nm.notify(SUMMARY_ID, summary)
            }
        }

        /** Removes a note's visible reminder card (used when notes are deleted). */
        fun cancelCard(context: Context, id: String) {
            notificationManager(context).cancel(notificationIdFor(id))
        }

        private fun openNotePendingIntent(context: Context, id: String): PendingIntent {
            // Tapping a reminder opens the native capture screen in edit
            // mode (pre-filled, saves back to the same note). Routing
            // through MainActivity instead proved unreliable from the
            // lock screen: the sleep/wake intent dance re-delivered the
            // stale launcher intent and dropped the note id extra.
            val intent = Intent(context, QuickNoteActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(QuickNoteActivity.EXTRA_EDIT_NOTE_ID, id)
            return PendingIntent.getActivity(
                context,
                id.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun notificationManager(context: Context): NotificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }
}