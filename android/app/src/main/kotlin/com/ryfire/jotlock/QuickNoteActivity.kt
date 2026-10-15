package com.ryfire.jotlock

import android.app.Activity
import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * Lightweight native note-entry screen that renders on top of the lock
 * screen (showWhenLocked) so a note can be typed and saved without
 * unlocking the device — same mechanism alarm clocks use.
 *
 * After saving, the app setting decides what happens next: lock the phone
 * (device admin), show the home screen, or stay on a confirmation until
 * the screen turns off. The Lock / Go home buttons let the user override
 * per save.
 */
class QuickNoteActivity : Activity() {

    private var screenOffRegistered = false

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_SCREEN_OFF) finish()
        }
    }

    private val devicePolicyManager: DevicePolicyManager
        get() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private val adminComponent: ComponentName
        get() = ComponentName(this, LockAdminReceiver::class.java)

    private fun isAdminActive(): Boolean = devicePolicyManager.isAdminActive(adminComponent)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                    or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        setContentView(R.layout.activity_quick_note)

        val input = findViewById<EditText>(R.id.note_input)
        input.requestFocus()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // SOFT_INPUT_ADJUST_RESIZE is ignored on R+; keep the card above
            // the keyboard by padding for IME + system bar insets instead.
            window.setDecorFitsSystemWindows(false)
            val root = findViewById<View>(R.id.quick_note_root)
            ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
                val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
                val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
                view.setPadding(0, bars.top, 0, maxOf(ime.bottom, bars.bottom))
                insets
            }
            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
        } else {
            window.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
                    or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            )
        }

        findViewById<Button>(R.id.save_button).setOnClickListener {
            val text = input.text.toString().trim()
            if (text.isEmpty()) {
                Toast.makeText(this, "Nothing to save", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            NoteStore.addNote(this, text)
            onNoteSaved()
        }
        findViewById<Button>(R.id.cancel_button).setOnClickListener { finish() }
        findViewById<Button>(R.id.lock_button).setOnClickListener {
            if (isAdminActive()) {
                devicePolicyManager.lockNow()
                finish()
            } else {
                showSavedState()
            }
        }
        findViewById<Button>(R.id.home_button).setOnClickListener { goHome() }
    }

    private fun onNoteSaved() {
        when (AppSettings.afterSaveAction(this)) {
            AppSettings.AFTER_SAVE_LOCK ->
                if (isAdminActive()) {
                    // Lock + sleep immediately; the keyguard covers whatever
                    // is behind us, so the next wake-up is the lock screen.
                    devicePolicyManager.lockNow()
                    finish()
                    return
                }
            AppSettings.AFTER_SAVE_HOME -> {
                goHome()
                return
            }
        }
        showSavedState()
    }

    private fun showSavedState() {
        findViewById<EditText>(R.id.note_input).visibility = View.GONE
        findViewById<View>(R.id.button_row).visibility = View.GONE
        findViewById<View>(R.id.saved_group).visibility = View.VISIBLE

        val adminActive = isAdminActive()
        findViewById<Button>(R.id.lock_button).visibility =
            if (adminActive) View.VISIBLE else View.GONE
        findViewById<View>(R.id.lock_disabled_hint).visibility =
            if (adminActive) View.GONE else View.VISIBLE

        // Insecure keyguard: exiting would surface whatever is behind us, so
        // fall back to exiting when the screen turns off.
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!km.isKeyguardSecure && !screenOffRegistered) {
            ContextCompat.registerReceiver(
                this,
                screenOffReceiver,
                IntentFilter(Intent.ACTION_SCREEN_OFF),
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            screenOffRegistered = true
        }
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    override fun onDestroy() {
        if (screenOffRegistered) unregisterReceiver(screenOffReceiver)
        super.onDestroy()
    }
}
