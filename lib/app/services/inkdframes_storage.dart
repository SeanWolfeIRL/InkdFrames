import 'dart:io';

class InkdFramesStorage {
  static Directory get rootDirectory {
    if (Platform.isAndroid) {
      return Directory('/data/user/0/com.inkdframes.app/files/inkdframes_data');
    }

    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';

    return Directory('$home/.inkdframes');
  }

  static Directory get projectsDirectory {
    return Directory('${rootDirectory.path}/projects');
  }

  static Directory get bagItemsDirectory {
    return Directory('${rootDirectory.path}/bag_items');
  }

  static Future<void> ensureDirectories() async {
    await projectsDirectory.create(recursive: true);
    await bagItemsDirectory.create(recursive: true);
  }

  static String safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
