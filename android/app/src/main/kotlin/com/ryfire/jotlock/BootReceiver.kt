package com.ryfire.jotlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/** Re-posts the quick note notification after a reboot. */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            if (NotificationHelper.isEnabled(context)) {
                // The service's foreground notification IS the Quick note
                // card, so starting it posts the card and keeps the
                // lock-state listener alive from boot on.
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, LockStateService::class.java)
                )
            }
            // Re-arm future note reminders; fire past-due ones immediately
            // (they elapsed while the device was off).
            ReminderScheduler.onBoot(context)
        }
    }
}
