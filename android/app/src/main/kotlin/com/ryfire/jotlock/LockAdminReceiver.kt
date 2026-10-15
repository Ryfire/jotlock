package com.ryfire.jotlock

import android.app.admin.DeviceAdminReceiver

/**
 * Device admin receiver. Only exists so the app can call
 * DevicePolicyManager.lockNow() (force-lock policy) after a note is saved
 * from the lock screen, returning the user to the lock screen immediately.
 */
class LockAdminReceiver : DeviceAdminReceiver()
