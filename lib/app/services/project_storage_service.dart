import 'dart:convert';
import 'dart:io';

import '../models/inkdframes_project.dart';
import 'inkdframes_storage.dart';

class ProjectStorageService {
  Future<File> _fileFor(String projectId) async {
    await InkdFramesStorage.ensureDirectories();

    final safeId = InkdFramesStorage.safeFileName(projectId);

    return File('${InkdFramesStorage.projectsDirectory.path}/$safeId.json');
  }

  Future<void> saveProject(InkdFramesProject project) async {
    final file = await _fileFor(project.id);
    final tempFile = File('${file.path}.tmp');

    final encoded = jsonEncode(project.toJson());

    await tempFile.writeAsString(encoded, flush: true);

    // Validate the complete temporary file before replacing the live copy.
    final verification = await tempFile.readAsString();
    final decoded = jsonDecode(verification);

    if (decoded is! Map) {
      await tempFile.delete();
      throw const FormatException('Project JSON root was not an object.');
    }

    if (await file.exists()) {
      await file.delete();
    }

    await tempFile.rename(file.path);
  }

  Future<InkdFramesProject?> loadProject(String projectId) async {
    final file = await _fileFor(projectId);

    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return null;
      }

      return InkdFramesProject.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteProject(String projectId) async {
    final file = await _fileFor(projectId);

    if (await file.exists()) {
      await file.delete();
    }

    final tempFile = File('${file.path}.tmp');

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}
