package com.ryfire.jotlock

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /** Text arriving via ACTION_SEND / ACTION_PROCESS_TEXT, waiting for Dart. */
    private var pendingIncomingText: String? = null

    private val adminComponent by lazy {
        ComponentName(this, LockAdminReceiver::class.java)
    }

    private val devicePolicyManager by lazy {
        getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingIncomingText = extractIncomingText(intent)
        // Keep the notification card in sync with lock state while we run.
        NotificationHelper.ensureScreenListener(this)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val incoming = extractIncomingText(intent)
        if (!incoming.isNullOrEmpty()) pendingIncomingText = incoming
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
                        NotificationHelper.post(this)
                        result.success(added)
                    }
                    "clearNotes" ->
                        result.success(NoteStore.clearAll(this))
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
