import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/plan_view.dart';
import '../core/notes.dart';
import '../core/planner.dart';
import '../i18n/app_texts.dart';
import '../i18n/feature_texts.dart';
import '../i18n/i18n.dart';
import '../i18n/native_texts.dart';
import '../services/files.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

/// The note of the current unit on the Today screen, or a button to write one.
class NotePreview extends StatelessWidget {
  const NotePreview({super.key, required this.c, required this.note, required this.onEdit});
  final AppController c;
  final ReadingNote? note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final x = featureText(c.lang);
    final palette = context.palette;
    if (note == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: onEdit,
          icon: const Icon(Icons.edit_note, size: 20),
          label: Text(x['note']),
        ),
      );
    }
    return Material(
      color: palette.muted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.format_quote, color: palette.ring),
            const SizedBox(width: 10),
            Expanded(child: Text(note!.text, maxLines: 4, overflow: TextOverflow.ellipsis)),
            Icon(Icons.edit_outlined, size: 18, color: palette.mutedForeground),
          ]),
        ),
      ),
    );
  }
}

/// Opens the note of [day]. A reflection [prompt] is added to the text, so the
/// question stays next to the answer.
Future<void> showNoteEditor(BuildContext context, AppController c,
        {required int day, required String date, required String passage, String? prompt}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteEditor(c: c, day: day, date: date, passage: passage, prompt: prompt),
    );

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.c, required this.day, required this.date, required this.passage, this.prompt});
  final AppController c;
  final int day;
  final String date, passage;
  final String? prompt;
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final existing = widget.c.noteFor(widget.day);
  late final controller = () {
    final before = existing?.text ?? '';
    final prompt = widget.prompt;
    final value = prompt == null || before.contains(prompt) ? before : '${before.isEmpty ? '' : '$before\n\n'}$prompt\n';
    return TextEditingController(text: value)..selection = TextSelection.collapsed(offset: value.length);
  }();
  bool saving = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.c.lang;
    final x = featureText(lang), t = text(lang);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SafeArea(
        child: Gap(children: [
          Heading(existing == null ? x['note'] : x['editNote'], size: 19),
          Muted('${Fmt(lang).date(widget.date, long: true)} · ${widget.passage}'),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            maxLength: maxNoteLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: x['notePlaceholder'], counterText: ''),
          ),
          Row(children: [
            if (existing != null)
              TextButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        await widget.c.deleteNote(existing!.id);
                        navigator.pop();
                      },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(x['delete']),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      final navigator = Navigator.of(context);
                      await widget.c.saveNote(
                          day: widget.day, date: widget.date, passage: widget.passage, text: controller.text);
                      navigator.pop();
                    },
              child: Text(t.save),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// All notes, searchable and exportable.
class NotesTab extends StatefulWidget {
  const NotesTab({super.key, required this.c});
  final AppController c;
  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final lang = c.lang;
    final x = featureText(lang), t = text(lang);
    final fmt = Fmt(lang);
    final palette = context.palette;
    final q = query.trim().toLowerCase();
    final visible = c.notes
        .where((n) => q.isEmpty || n.text.toLowerCase().contains(q) || n.passage.toLowerCase().contains(q))
        .toList();
    final v = PlanView.of(c);
    final u = ui(lang);
    final todayNote = v == null ? null : c.noteFor(v.dateIndex);
    return Gap(space: 14, children: [
      Heading(x['notes'], size: 26),
      Muted(x['notesSub']),
      if (v != null)
        FilledButton.icon(
          onPressed: () => showNoteEditor(context, c,
              day: v.dateIndex,
              date: v.currentDate,
              passage: v.fixed ? bible52Units[v.dateIndex].label : v.readLabel(v.sessionItemsFor(v.dateIndex))),
          icon: Icon(todayNote == null ? Icons.add : Icons.edit_outlined, size: 18),
          label: Text(todayNote == null ? u['newNote'] : u['editTodayNote']),
        ),
      if (c.notes.isNotEmpty) ...[
        TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: x['searchNotes']),
          onChanged: (value) => setState(() => query = value),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await shareFile(notesText(c.notes, 'Leseweg · ${x['notes']}'),
                'leseweg-notizen.txt', 'text/plain');
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(nativeText(lang).shareFailed)));
            }
          },
          icon: const Icon(Icons.ios_share, size: 17),
          label: Text(x['exportNotes']),
        ),
      ],
      if (c.notes.isEmpty)
        Panel(child: Muted(u['noNotes']))
      else if (visible.isEmpty)
        Panel(child: Muted(x['noMatches']))
      else
        for (final n in visible)
          Panel(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: InkWell(
                  onTap: n.planId == c.state?.id
                      ? () => showNoteEditor(context, c, day: n.day, date: n.date, passage: n.passage)
                      : null,
                  child: Gap(space: 6, children: [
                    Text(n.passage, style: TextStyle(fontWeight: FontWeight.w700, color: palette.foreground)),
                    Muted(fmt.date(n.date, long: true), size: 12.5),
                    Text(n.text),
                  ]),
                ),
              ),
              IconButton(
                tooltip: x['deleteNote'],
                icon: Icon(Icons.delete_outline, color: palette.mutedForeground),
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: x['deleteNote'], body: x['deleteNoteText'], confirm: x['delete'], cancel: t.cancel);
                  if (ok) await c.deleteNote(n.id);
                },
              ),
            ]),
          ),
    ]);
  }
}
