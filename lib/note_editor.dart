import 'package:flutter/material.dart';

import 'package:jotlock/note.dart';

/// Full-screen note editor, replacing the old cramped AlertDialog.
///
/// The text area fills the whole page under the app bar and scrolls as it
/// grows. Save (check icon) pops with the trimmed text; the back arrow and
/// system back pop with null — asking first when the text changed, since a
/// discard here loses edits with no undo. Enter inserts a newline (this is
/// a page, not a single-field dialog); saving is the check action only.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key, this.initialText});
  final String? initialText;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _controller;
  late final String _original;

  @override
  void initState() {
    super.initState();
    // Initialized eagerly here — a lazy `_original` would snapshot on first
    // read (after the user typed) and make every edit look clean.
    _controller = TextEditingController(text: _clampedInitial());
    _original = _controller.text.trim();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Share-sheet text can exceed the cap; the editor shows it clamped so
  /// the maxLength counter starts honest.
  String _clampedInitial() {
    final text = widget.initialText ?? '';
    return text.length > maxNoteLength
        ? text.substring(0, maxNoteLength)
        : text;
  }

  bool get _canSave => _controller.text.trim().isNotEmpty;

  /// True when the user changed the text since opening (whitespace-only
  /// differences don't count — Save trims anyway).
  bool get _isDirty => _controller.text.trim() != _original;

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  /// Returns true when the page may close without losing edits.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your edits will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (!context.mounted) return;
        // Navigator.pop below is a direct pop — it bypasses canPop, so
        // this handler is not re-entered after the user confirms.
        if (discard) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.initialText == null ? 'New note' : 'Edit note'),
          actions: [
            IconButton(
              key: const Key('editor-save'),
              tooltip: 'Save',
              icon: const Icon(Icons.check),
              onPressed: _canSave ? _save : null,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _controller,
            autofocus: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            maxLength: maxNoteLength,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Note text',
            ),
            buildCounter:
                (
                  BuildContext context, {
                  required int currentLength,
                  required bool isFocused,
                  int? maxLength,
                }) {
                  // Hidden until the cap is near — the default counter
                  // would waste a row on every note.
                  final remaining = (maxLength ?? maxNoteLength) - currentLength;
                  if (remaining > 100) return null;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                    child: Text(
                      '$remaining characters left',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  );
                },
          ),
        ),
      ),
    );
  }
}
