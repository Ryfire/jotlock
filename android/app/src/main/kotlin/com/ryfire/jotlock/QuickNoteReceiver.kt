package com.ryfire.jotlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.core.app.RemoteInput

/**
 * Saves a note typed directly into the persistent notification's inline
 * reply field ("Jot", offered while the device is unlocked). No activity is
 * launched: the jot lands in NoteStore from wherever the user happens to be.
 *
 * Direct-reply protocol: after consuming the reply the notification must be
 * re-posted, otherwise the shade keeps showing the "replying…" state. The
 * after-save lock/home behavior intentionally does not apply here — no
 * capture screen was shown, so there is nothing to dismiss and nothing to
 * interrupt with a forced lock.
 */
class QuickNoteReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_INLINE_SAVE) return

        val text = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(EXTRA_INLINE_TEXT)
            ?.toString()
            ?.trim()
            .orEmpty()
        if (text.isNotEmpty()) {
            NoteStore.addNote(context, text.take(MAX_NOTE_LENGTH))
            Toast.makeText(context, "Note saved ✓", Toast.LENGTH_SHORT).show()
        }

        // Required by the direct-reply contract, even for an empty reply.
        NotificationHelper.post(context)
    }

    companion object {
        const val ACTION_INLINE_SAVE = "com.ryfire.jotlock.ACTION_INLINE_SAVE"
        const val EXTRA_INLINE_TEXT = "inline_note_text"

        // Matches the Flutter editor's maxLength; keeps the documented
        // 4,000-character cap true for every capture path.
        const val MAX_NOTE_LENGTH = 4000
    }
}
