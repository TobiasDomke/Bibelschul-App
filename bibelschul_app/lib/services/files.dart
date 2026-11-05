import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/backup.dart';
import '../core/notes.dart';

/// Hands a generated file (backup, CSV, calendar) to the system share sheet,
/// where the user can save it to Files, send it or open it in another app.
/// This replaces the browser download of the web app.
Future<bool> shareFile(String content, String filename, String mimeType) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content, encoding: utf8, flush: true);
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: mimeType, name: filename)],
    subject: filename,
  ));
  return result.status != ShareResultStatus.unavailable;
}

/// Shares binary data such as a generated statistics image.
Future<bool> shareBytes(List<int> bytes, String filename, String mimeType, {String? text}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: mimeType, name: filename)],
    text: text,
  ));
  return result.status != ShareResultStatus.unavailable;
}

/// Lets the user pick a backup file (web app or app format) and validates it.
/// Returns null when cancelled.
Future<AppBackup?> pickBackup() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json']);
  if (file == null) return null;
  final size = file.lengthSync() ?? await file.length();
  if (size == null || size > maxBackupBytes) throw const FormatException('backup');
  return parseAppBackup(utf8.decode(await file.readAsBytes()));
}

/// Shares a short text (for example a plan code) through the system share sheet.
Future<bool> shareText(String text) async {
  final result = await SharePlus.instance.share(ShareParams(text: text));
  return result.status != ShareResultStatus.unavailable;
}
