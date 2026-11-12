import 'package:appflowy_editor/src/editor/util/file_picker/file_picker_service.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:file_selector/file_selector.dart' as selector;

class FilePicker implements FilePickerService {
  @override
  Future<String?> getDirectoryPath({String? title}) {
    return fp.FilePicker.getDirectoryPath(dialogTitle: title);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    Function(fp.FilePickerStatus p1)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) async {
    if (!allowMultiple) {
      final file = await fp.FilePicker.pickFile(
        dialogTitle: dialogTitle, initialDirectory: initialDirectory, type: type,
        allowedExtensions: allowedExtensions, onFileLoading: onFileLoading,
        windowsOptions: fp.WindowsOptions(lockParentWindow: lockParentWindow),
        linuxOptions: fp.LinuxOptions(lockParentWindow: lockParentWindow),
      );
      return FilePickerResult(file == null ? [] : [file]);
    }
    final files = await fp.FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      onFileLoading: onFileLoading,
      windowsOptions: fp.WindowsOptions(lockParentWindow: lockParentWindow),
      linuxOptions: fp.LinuxOptions(lockParentWindow: lockParentWindow),
    );
    return FilePickerResult(files);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    // Preserve the existing path-selection API without creating/truncating a
    // file. file_picker13 saves bytes immediately; the host owns export writes.
    final result = await selector.getSaveLocation(
      suggestedName: fileName,
      initialDirectory: initialDirectory,
      acceptedTypeGroups: allowedExtensions == null ? const [] : [
        selector.XTypeGroup(label: 'Files', extensions: allowedExtensions),
      ],
    );
    return result?.path;
  }
}
