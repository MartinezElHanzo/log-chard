import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'core/notes_io.dart';

/// App-side notes persistence: `notes.yaml` next to `log_chard.yaml` in the
/// OS app-support dir. Same layering as [ConfigStore] — pure IO lives in
/// core/ so CLI/MCP could share it later.
class NotesStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}notes.yaml');
  }

  Future<List<LogNote>> load() async => loadNotesFile((await _file()).path);

  Future<void> save(List<LogNote> notes) async =>
      saveNotesFile((await _file()).path, notes);
}
