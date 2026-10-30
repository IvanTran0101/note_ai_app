import 'package:flutter/material.dart';

/// Asks before downloading a missing model; dismissing is a refusal.
Future<bool> confirmModelDownload(
  BuildContext context, {
  required String modelName,
  required int sizeBytes,
}) async {
  final bool vi = Localizations.localeOf(context).languageCode == 'vi';
  final String size = (sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
  final bool? approved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(vi ? 'Tải mô hình AI?' : 'Download AI model?'),
      content: Text(
        vi
            ? '$modelName\nDung lượng dự kiến: $size GiB. Bạn có thể tiếp tục dùng ứng dụng nếu chọn để sau.'
            : '$modelName\nEstimated size: $size GiB. You can keep using the app if you choose later.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(vi ? 'Để sau' : 'Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(vi ? 'Tải mô hình' : 'Download model'),
        ),
      ],
    ),
  );
  return approved == true;
}
