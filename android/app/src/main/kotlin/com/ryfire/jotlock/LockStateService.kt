package com.ryfire.jotlock

import android.app.Notification
import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Keeps the jotlock process alive at foreground priority so the
 * SCREEN_ON / SCREEN_OFF / USER_PRESENT listener registered by
 * NotificationHelper.ensureScreenListener() always runs. Without it the
 * process can be killed while the unlocked card (with the Jot inline
 * action) is posted, and that stale card would then render on the lock
 * screen — the "Jot" action must never appear there.
 *
 * The persistent Quick note notification doubles as this service's
 * foreground notification, so nothing new appears for the user: the card
 * they already have is simply guaranteed to stay in sync with the lock
 * state.
 */
class LockStateService : Service() {

    override fun onCreate() {
        super.onCreate()
        // startForeground must always run when started via
        // startForegroundService(); buildCard() never returns null.
        val notification: Notification = NotificationHelper.buildCard(this)
        startForeground(NotificationHelper.NOTIFICATION_ID, notification)
        // Re-post so the variant matches the lock state at this exact
        // moment, then keep it in sync from here on.
        NotificationHelper.post(this)
        NotificationHelper.ensureScreenListener(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!NotificationHelper.isEnabled(this)) {
            // Notification turned off in settings — the toggle stops this
            // service too; a sticky restart after that is a no-op here.
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}