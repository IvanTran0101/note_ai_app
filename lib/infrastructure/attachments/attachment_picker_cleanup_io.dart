import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> releaseAttachmentSelection(String path) async {
  // Android picker plugins copy into this app's private cache. Desktop picker
  // paths are the user's originals. They are never cleanup targets.
  if (!Platform.isAndroid) return;
  await removePickerOwnedCopy(path, await getTemporaryDirectory());
}

Future<void> removePickerOwnedCopy(String path, Directory cache) async {
  final file = File(path);
  if (!await file.exists()) return;
  final root = await cache.resolveSymbolicLinks();
  final resolved = await file.resolveSymbolicLinks();
  if (!resolved.startsWith('$root${Platform.pathSeparator}')) return;
  // Delete only the resolved selected file inside the confirmed app cache;
  // never recurse, delete a folder, follow an outside symlink or clear cache.
  await File(resolved).delete();
}
