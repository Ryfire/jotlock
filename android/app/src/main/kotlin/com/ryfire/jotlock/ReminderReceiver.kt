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
 * with its current text; a deleted note is a silent no-op).
 *
 * One-shot reminders clear their stored reminderAt here so nothing
 * re-fires. Recurring ones (repeatDays > 0) keep the card identical but
 * advance reminderAt to the next occurrence, re-arm the alarm, and let
 * missed periods collapse into this single card instead of stacking up.
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
        const val GROUP_KEY = "com.ryfire.jotlock.REMINDERS"

        // Distinct stable ids: NOTIFICATION_ID (jot card) is 1001; reminder
        // cards live above 100000, the summary just under them.
        const val SUMMARY_ID = 99999

        fun notificationIdFor(id: String): Int =
            100000 + (id.hashCode() and 0x7FFFFFFF) % 800000

        /**
         * Posts the reminder card for [id] and updates the stored reminder:
         * one-shot reminders are cleared; recurring ones advance to the
         * next occurrence and re-arm (callable from the alarm path and the
         * boot path alike). The channel depends on the note's silent flag:
         * sounded reminders use the user's picked sound, silent ones post
         * without sound — both hidden from the lock screen.
         */
        fun showReminder(context: Context, id: String) {
            val note = NoteStore.getNote(context, id)
            if (note == null) {
                // Note is gone: drop whatever reminder state remains.
                NoteStore.setReminderAt(context, id, 0L)
                return
            }
            val silent = note.optBoolean("reminderSilent", false)
            val text = note.optString("text").trim()
            if (text.isEmpty()) {
                // Nothing to remind about — don't re-arm a recurring
                // reminder into silence forever either.
                NoteStore.setReminderAt(context, id, 0L)
                return
            }
            val repeatDays = note.optInt("repeatDays", 0)
            if (repeatDays > 0) {
                // Recurring: show this occurrence's card, then advance to
                // the first future occurrence. Missed periods collapse into
                // one card rather than one notification per missed day.
                val dayMs = 24L * 60 * 60 * 1000
                val now = System.currentTimeMillis()
                var next = note.optLong("reminderAt", 0L)
                if (next <= 0L) next = now
                while (next <= now) next += repeatDays * dayMs
                NoteStore.setReminderAt(context, id, next, silent, repeatDays)
                ReminderScheduler.schedule(context, id, next)
            } else {
                // One-shot: drop the stored reminder.
                NoteStore.setReminderAt(context, id, 0L)
            }

            val channelId = if (silent) {
                NotificationHelper.ensureReminderChannels(context)
                NotificationHelper.REMINDER_SILENT_CHANNEL_ID
            } else {
                NotificationHelper.currentReminderChannelId(context)
            }
            val openNote = openNotePendingIntent(context, id)
            val child = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.ic_note)
                .setContentTitle("Note reminder")
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                // Explicit SECRET, re-asserting the channel: cards stay off
                // the lock screen even when the channel was created by an
                // older build without a lockscreenVisibility set.
                .setVisibility(NotificationCompat.VISIBILITY_SECRET)
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
                val summary = NotificationCompat.Builder(context, channelId)
                    .setSmallIcon(R.drawable.ic_note)
                    .setContentTitle("JotLock reminders")
                    .setContentText("$groupCount note reminders")
                    .setGroup(GROUP_KEY)
                    .setGroupSummary(true)
                    // Only the children alert; the summary stays silent.
                    .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
                    .setVisibility(NotificationCompat.VISIBILITY_SECRET)
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