import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/codex_diff_viewer.dart';
import 'package:ui/services/codex_diff_parser.dart';

void main() {
  const diffText = '''
diff --git a/lib/main.dart b/lib/main.dart
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1,2 +1,2 @@
-old line
+new line
 same line
''';

  test('parseCodexDiffText groups file hunks and counts changes', () {
    final summary = parseCodexDiffText(diffText);

    expect(summary.files, hasLength(1));
    expect(summary.additions, 1);
    expect(summary.deletions, 1);
    expect(summary.primaryPath, 'lib/main.dart');
    expect(
      summary.files.single.lines.any(
        (line) => line.kind == CodexDiffLineKind.add,
      ),
      isTrue,
    );
    expect(
      summary.files.single.lines.any(
        (line) => line.kind == CodexDiffLineKind.remove,
      ),
      isTrue,
    );
    expect(summarizeCodexDiff(summary), '1 file · +1 -1');
  });

  test('extractCodexDiffText finds nested diff payloads', () {
    final extracted = extractCodexDiffText({
      'result': {'patch': diffText},
    });

    expect(extracted, isNotNull);
    expect(extracted, contains('diff --git'));
  });

  testWidgets('CodexDiffViewer renders diff summary and file body', (
    tester,
  ) async {
    final summary = parseCodexDiffText(diffText);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexDiffViewer(
            summary: summary,
            padding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );

    expect(find.text('lib/main.dart'), findsNWidgets(2));
    expect(find.text('1 个文件 · +1 -1'), findsOneWidget);
    expect(
      find.textContaining('-old line', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('+new line', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('same line', findRichText: true),
      findsOneWidget,
    );
  });
}
