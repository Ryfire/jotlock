package com.ryfire.jotlock

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Extra: note id to open, sent by fired reminder notifications. */
        const val EXTRA_OPEN_NOTE_ID = "open_note_id"

        private const val REQUEST_PICK_SOUND = 4001
    }

    /** Text arriving via ACTION_SEND / ACTION_PROCESS_TEXT, waiting for Dart. */
    private var pendingIncomingText: String? = null

    /** Note id to open after tapping a fired reminder notification. */
    private var pendingOpenNoteId: String? = null

    /** Parked Dart result while the system sound picker is open. */
    private var pendingSoundResult: MethodChannel.Result? = null

    private val adminComponent by lazy {
        ComponentName(this, LockAdminReceiver::class.java)
    }

    private val devicePolicyManager by lazy {
        getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }

    private val powerManager by lazy {
        getSystemService(POWER_SERVICE) as PowerManager
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingIncomingText = extractIncomingText(intent)
        pendingOpenNoteId = intent?.getStringExtra(EXTRA_OPEN_NOTE_ID)
        // Keep the notification card in sync with lock state while we run.
        NotificationHelper.ensureScreenListener(this)
        // Restore the reminder channels this build expects — older builds
        // could leave them without the SECRET lock-screen visibility.
        NotificationHelper.healReminderChannels(this)
        ensureLockStateService()
    }

    /** Starts the foreground service that hosts the lock-state listener. */
    private fun ensureLockStateService() {
        if (NotificationHelper.isEnabled(this)) {
            ContextCompat.startForegroundService(
                this,
                Intent(this, LockStateService::class.java)
            )
        }
    }

    private fun notificationManagerCompat() = NotificationManagerCompat.from(this)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val incoming = extractIncomingText(intent)
        if (!incoming.isNullOrEmpty()) pendingIncomingText = incoming
        intent?.getStringExtra(EXTRA_OPEN_NOTE_ID)?.let { pendingOpenNoteId = it }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_SOUND) return
        val dartResult = pendingSoundResult
        pendingSoundResult = null
        if (dartResult == null) return

        // null URI (and not "Silent" stored) = picker dismissed or Silent
        // chosen. EXTRA_RINGTONE_PICKED_URI is absent when Silent is picked.
        val picked = data
            ?.getParcelableExtra<android.net.Uri>(
                android.media.RingtoneManager.EXTRA_RINGTONE_PICKED_URI
            )
        val toStore = when {
            resultCode != RESULT_OK -> null // dismissed: keep current sound
            picked != null -> picked.toString()
            else -> "" // Silent picked
        }
        if (toStore != null) {
            AppSettings.setReminderSoundUri(this, toStore)
            NotificationHelper.applyReminderSound(this)
        }
        dartResult.success(NotificationHelper.reminderSoundTitle(this))
    }

    private fun extractIncomingText(intent: Intent?): String? {
        if (intent == null) return null
        val text = when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_PROCESS_TEXT -> intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)
            else -> null
        }
        return text?.trim()?.ifEmpty { null }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jotlock/notes")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNotes" -> result.success(NoteStore.notesAsMaps(this))
                    "saveNote" -> {
                        val text = call.argument<String>("text")?.trim().orEmpty()
                        if (text.isEmpty()) {
                            result.error("INVALID", "Note text is empty", null)
                        } else {
                            NoteStore.addNote(this, text)
                            NotificationHelper.post(this)
                            result.success(true)
                        }
                    }
                    "updateNote" -> {
                        val id = call.argument<String>("id").orEmpty()
                        val text = call.argument<String>("text")?.trim().orEmpty()
                        val ok = id.isNotEmpty() && NoteStore.updateNote(this, id, text)
                        if (ok) NotificationHelper.post(this)
                        result.success(ok)
                    }
                    "deleteNote" -> {
                        val id = call.argument<String>("id").orEmpty()
                        val ok = id.isNotEmpty() && NoteStore.deleteNote(this, id)
                        if (ok) {
                            // Dead alarm + visible reminder card must go too.
                            ReminderScheduler.cancel(this, id)
                            ReminderReceiver.cancelCard(this, id)
                        }
                        NotificationHelper.post(this)
                        result.success(ok)
                    }
                    "setPinned" -> {
                        val id = call.argument<String>("id").orEmpty()
                        val pinned = call.argument<Boolean>("pinned") == true
                        result.success(
                            id.isNotEmpty() && NoteStore.setPinned(this, id, pinned)
                        )
                    }
                    "takePendingIncomingText" -> {
                        val text = pendingIncomingText
                        pendingIncomingText = null
                        result.success(text)
                    }
                    "getExportJson" ->
                        result.success(NoteStore.getNotes(this).toString())
                    "importNotes" -> {
                        val json = call.argument<String>("json").orEmpty()
                        val added = NoteStore.importNotes(this, json)
                        // Imported notes may carry future reminders; arm them.
                        ReminderScheduler.rescheduleAll(this)
                        NotificationHelper.post(this)
                        result.success(added)
                    }
                    "clearNotes" -> {
                        // Cancel every pending alarm and visible reminder
                        // card before wiping the store.
                        val notes = NoteStore.getNotes(this)
                        for (i in 0 until notes.length()) {
                            val note = notes.optJSONObject(i) ?: continue
                            val id = note.optString("id")
                            ReminderScheduler.cancel(this, id)
                            ReminderReceiver.cancelCard(this, id)
                        }
                        notificationManagerCompat().cancel(ReminderReceiver.SUMMARY_ID)
                        result.success(NoteStore.clearAll(this))
                    }
                    "setReminder" -> {
                        val id = call.argument<String>("id").orEmpty()
                        val at = call.argument<Number>("atMillis")?.toLong() ?: 0L
                        val silent = call.argument<Boolean>("silent") == true
                        if (id.isEmpty() || at <= System.currentTimeMillis()) {
                            result.error("INVALID", "Bad reminder request", null)
                        } else if (NoteStore.getNote(this, id) == null) {
                            result.error("INVALID", "Note not found", null)
                        } else {
                            NoteStore.setReminderAt(this, id, at, silent)
                            ReminderScheduler.schedule(this, id, at)
                            result.success(true)
                        }
                    }
                    "cancelReminder" -> {
                        val id = call.argument<String>("id").orEmpty()
                        NoteStore.setReminderAt(this, id, 0L)
                        ReminderScheduler.cancel(this, id)
                        ReminderReceiver.cancelCard(this, id)
                        result.success(true)
                    }
                    "takePendingOpenNoteId" -> {
                        val id = pendingOpenNoteId
                        pendingOpenNoteId = null
                        result.success(id)
                    }
                    "getReminderSoundTitle" ->
                        result.success(NotificationHelper.reminderSoundTitle(this))
                    "pickReminderSound" -> {
                        if (pendingSoundResult != null) {
                            result.error("BUSY", "Sound picker already open", null)
                        } else {
                            pendingSoundResult = result
                            val picker = Intent(
                                android.media.RingtoneManager.ACTION_RINGTONE_PICKER
                            ).apply {
                                // Resolve straight to the platform sound
                                // picker: a plain ACTION_RINGTONE_PICKER
                                // start went through the app chooser on
                                // this device because other apps also
                                // match the action.
                                setPackage("com.android.soundpicker")
                                setClassName(
                                    "com.android.soundpicker",
                                    "com.android.soundpicker.RingtonePickerActivity"
                                )
                                putExtra(
                                    android.media.RingtoneManager.EXTRA_RINGTONE_TYPE,
                                    android.media.RingtoneManager.TYPE_NOTIFICATION
                                )
                                putExtra(
                                    android.media.RingtoneManager.EXTRA_RINGTONE_TITLE,
                                    "Reminder sound"
                                )
                                putExtra(
                                    android.media.RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,
                                    true
                                )
                                // Preselect the current choice, including
                                // the Silent radio when "" was stored.
                                val stored = AppSettings.reminderSoundUri(this@MainActivity)
                                if (stored != null && stored.isEmpty()) {
                                    putExtra(
                                        android.media.RingtoneManager
                                            .EXTRA_RINGTONE_SHOW_DEFAULT,
                                        false
                                    )
                                    putExtra(
                                        android.media.RingtoneManager
                                            .EXTRA_RINGTONE_EXISTING_URI,
                                        null as android.net.Uri?
                                    )
                                } else {
                                    putExtra(
                                        android.media.RingtoneManager
                                            .EXTRA_RINGTONE_EXISTING_URI,
                                        NotificationHelper
                                            .resolveReminderSoundUri(
                                            this@MainActivity
                                        )
                                    )
                                }
                            }
                            startActivityForResult(picker, REQUEST_PICK_SOUND)
                        }
                    }
                    "refreshNotification" -> {
                        NotificationHelper.setEnabled(this, true)
                        NotificationHelper.post(this)
                        ensureLockStateService()
                        result.success(true)
                    }
                    "dismissNotification" -> {
                        NotificationHelper.setEnabled(this, false)
                        stopService(Intent(this, LockStateService::class.java))
                        NotificationHelper.cancel(this)
                        result.success(true)
                    }
                    "isNotificationEnabled" ->
                        result.success(NotificationHelper.isEnabled(this))
                    "getAfterSaveAction" ->
                        result.success(AppSettings.afterSaveAction(this))
                    "setAfterSaveAction" -> {
                        val action = call.argument<String>("action").orEmpty()
                        if (action in setOf(
                                AppSettings.AFTER_SAVE_WAIT,
                                AppSettings.AFTER_SAVE_LOCK,
                                AppSettings.AFTER_SAVE_HOME
                            )
                        ) {
                            AppSettings.setAfterSaveAction(this, action)
                            result.success(true)
                        } else {
                            result.error("INVALID", "Unknown action", null)
                        }
                    }
                    "isBatteryExempt" ->
                        result.success(
                            powerManager.isIgnoringBatteryOptimizations(packageName)
                        )
                    "requestBatteryExempt" -> {
                        if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                                ).setData(Uri.parse("package:$packageName"))
                            )
                        }
                        result.success(true)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url").orEmpty()
                        val opened = if (url.startsWith("https://") ||
                            url.startsWith("http://")
                        ) {
                            try {
                                startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                )
                                true
                            } catch (e: Exception) {
                                false
                            }
                        } else {
                            false
                        }
                        result.success(opened)
                    }
                    "getVersionName" -> result.success(
                        try {
                            packageManager.getPackageInfo(packageName, 0).versionName
                        } catch (e: Exception) {
                            ""
                        }
                    )
                    "isDeviceAdminActive" ->
                        result.success(devicePolicyManager.isAdminActive(adminComponent))
                    "requestDeviceAdmin" -> {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Allows JotLock to lock the screen immediately after a note is saved from the lock screen."
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
