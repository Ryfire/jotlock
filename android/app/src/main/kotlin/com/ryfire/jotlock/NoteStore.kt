package com.ryfire.jotlock

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Single source of truth for notes. Lives in native SharedPreferences so the
 * lock screen capture screen and receivers can read/write it without the
 * Flutter engine running. Display ordering (pinned first, then newest) is
 * applied on the Dart side.
 */
object NoteStore {
    private const val PREFS_FILE = "jotlock"
    private const val KEY_NOTES = "notes"
    private const val MAX_NOTES = 500

    fun getNotes(context: Context): JSONArray {
        val raw = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getString(KEY_NOTES, "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    fun notesAsMaps(context: Context): List<Map<String, Any?>> {
        val notes = getNotes(context)
        val out = ArrayList<Map<String, Any?>>(notes.length())
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            out.add(
                mapOf(
                    "id" to note.optString("id"),
                    "text" to note.optString("text"),
                    "createdAt" to note.optLong("createdAt"),
                    "pinned" to note.optBoolean("pinned", false),
                    "color" to note.optInt("color", 0),
                    "reminderAt" to note.optLong("reminderAt", 0L),
                    "reminderSilent" to note.optBoolean("reminderSilent", false),
                    "repeatDays" to note.optInt("repeatDays", 0),
                    "done" to note.optBoolean("done", false),
                )
            )
        }
        return out
    }

    /** Returns the note with [id], or null when it does not exist. */
    fun getNote(context: Context, id: String): JSONObject? {
        val notes = getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            if (note.optString("id") == id) return note
        }
        return null
    }

    fun addNote(context: Context, text: String): Boolean {
        val existing = getNotes(context)
        val note = JSONObject()
            .put("id", System.currentTimeMillis().toString())
            .put("text", text)
            .put("createdAt", System.currentTimeMillis())
            .put("pinned", false)
        val out = JSONArray().put(note)
        for (i in 0 until existing.length()) out.put(existing.get(i))
        return saveNotes(context, out)
    }

    fun updateNote(context: Context, id: String, text: String): Boolean {
        val notes = getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            if (note.optString("id") == id) {
                note.put("text", text)
                return saveNotes(context, notes)
            }
        }
        return false
    }

    fun deleteNote(context: Context, id: String): Boolean {
        val notes = getNotes(context)
        val out = JSONArray()
        var found = false
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            if (note.optString("id") == id) found = true else out.put(note)
        }
        return if (found) saveNotes(context, out) else false
    }

    fun setPinned(context: Context, id: String, pinned: Boolean): Boolean {
        val notes = getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            if (note.optString("id") == id) {
                note.put("pinned", pinned)
                return saveNotes(context, notes)
            }
        }
        return false
    }

    /**
     * Stores the priority color index on the note. A value <= 0 removes the
     * field (no color). The palette itself lives on the Dart side.
     */
    fun setNoteColor(context: Context, id: String, colorIndex: Int): Boolean {
        val notes = getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            if (note.optString("id") == id) {
                if (colorIndex > 0) {
                    note.put("color", colorIndex)
                } else {
                    note.remove("color")
                }
                return saveNotes(context, notes)
            }
        }
        return false
    }

    /**
     * Marks a note done (struck through in the list). A true flag saves the
     * field; false removes it — done is stored only when set, like pin/color.
     * Reminder clearing lives on the Dart side (user-visible snackbar).
     */
    fun setDone(context: Context, id: String, done: Boolean): Boolean {
        val notes = getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            if (note.optString("id") == id) {
                if (done) {
                    note.put("done", true)
                } else {
                    note.remove("done")
                }
                return saveNotes(context, notes)
            }
        }
        return false
    }

    /**
     * Stores the reminder target time on the note. A value <= 0 removes the
     * fields (no reminder). [repeatDays] > 0 marks the reminder recurring —
     * ReminderReceiver advances reminderAt on each fire and re-arms.
     * Scheduling/canceling the actual alarm lives in ReminderScheduler —
     * this only persists the state. [silent] chooses between the sounded
     * and silent reminder channels at fire time.
     */
    fun setReminderAt(
        context: Context,
        id: String,
        atMillis: Long,
        silent: Boolean = false,
        repeatDays: Int = 0,
    ): Boolean {
        val notes = getNotes(context)
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            if (note.optString("id") == id) {
                if (atMillis > 0) {
                    note.put("reminderAt", atMillis)
                    note.put("reminderSilent", silent)
                    if (repeatDays > 0) {
                        note.put("repeatDays", repeatDays)
                    } else {
                        note.remove("repeatDays")
                    }
                } else {
                    note.remove("reminderAt")
                    note.remove("reminderSilent")
                    note.remove("repeatDays")
                }
                return saveNotes(context, notes)
            }
        }
        return false
    }

    /** Deletes every note. Returns true; other settings are untouched. */
    fun clearAll(context: Context): Boolean {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_NOTES)
            .apply()
        return true
    }

    /**
     * Merges a JSON array of notes into the store, skipping notes whose id
     * already exists. Returns the number of notes added.
     */
    fun importNotes(context: Context, jsonText: String): Int {
        val incoming = try {
            JSONArray(jsonText)
        } catch (_: Exception) {
            return 0
        }
        val notes = getNotes(context)
        val ids = HashSet<String>()
        for (i in 0 until notes.length()) {
            val note = notes.optJSONObject(i) ?: continue
            ids.add(note.optString("id"))
        }
        var added = 0
        val now = System.currentTimeMillis()
        for (i in 0 until incoming.length()) {
            val item = incoming.optJSONObject(i) ?: continue
            val text = item.optString("text").trim()
            if (text.isEmpty()) continue
            var id = item.optString("id")
            if (id.isEmpty() || ids.contains(id)) id = "${now + added}"
            ids.add(id)
            val createdAt =
                if (item.has("createdAt")) item.optLong("createdAt", now) else now
            val reminder = item.optLong("reminderAt", 0L)
            val note = JSONObject()
                .put("id", id)
                .put("text", text)
                .put("createdAt", createdAt)
                .put("pinned", item.optBoolean("pinned", false))
            val color = item.optInt("color", 0)
            if (color > 0) note.put("color", color)
            if (item.optBoolean("done", false)) note.put("done", true)
            // Only carry future reminders across an import; past ones would
            // otherwise fire immediately on the importing device.
            if (reminder > now) {
                note.put("reminderAt", reminder)
                note.put("reminderSilent", item.optBoolean("reminderSilent", false))
                val repeat = item.optInt("repeatDays", 0)
                if (repeat > 0) note.put("repeatDays", repeat)
            }
            notes.put(note)
            added++
        }
        if (added > 0) saveNotes(context, notes)
        return added
    }

    private fun saveNotes(context: Context, notes: JSONArray): Boolean {
        val trimmed = JSONArray()
        for (i in 0 until minOf(notes.length(), MAX_NOTES)) trimmed.put(notes.get(i))
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_NOTES, trimmed.toString())
            .apply()
        return true
    }
}
