import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/notes/model_download_confirmation.dart';

void main() {
  for (final approved in [false, true]) {
    testWidgets('download confirmation returns $approved', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await confirmModelDownload(
                    context,
                    modelName: 'model.gguf',
                    sizeBytes: 1073741824,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('model.gguf'), findsOneWidget);
      expect(find.textContaining('1.00 GiB'), findsOneWidget);
      await tester.tap(find.text(approved ? 'Download model' : 'Later'));
      await tester.pumpAndSettle();
      expect(result, approved);
    });
  }
}
