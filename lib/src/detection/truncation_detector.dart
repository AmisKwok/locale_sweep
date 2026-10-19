import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'truncation_issue.dart';

export 'truncation_issue.dart';

/// Walks the render tree after layout to find silently truncated text.
class TruncationDetector {
  /// Detects text truncation in the current widget tree.
  ///
  /// Call after [WidgetTester.pumpAndSettle] to inspect the laid-out tree.
  static List<TruncationIssue> detect(WidgetTester tester, String locale) {
    final issues = <TruncationIssue>[];
    final root = tester.binding.rootElement;
    if (root == null) return issues;

    void visit(RenderObject object) {
      if (object is RenderParagraph) {
        _checkParagraph(object, locale, issues);
      }
      object.visitChildren(visit);
    }

    root.renderObject?.visitChildren(visit);
    return issues;
  }

  static void _checkParagraph(
    RenderParagraph paragraph,
    String locale,
    List<TruncationIssue> issues,
  ) {
    if (!paragraph.hasSize) return;

    final overflow = paragraph.overflow;
    if (overflow == TextOverflow.visible) return;

    final text = paragraph.text.toPlainText();
    if (text.isEmpty) return;

    if (paragraph.didExceedMaxLines) {
      final maxWidth = paragraph.constraints.maxWidth;
      final intrinsic = paragraph.getMinIntrinsicWidth(double.infinity);
      issues.add(
        TruncationIssue(
          text: text,
          locale: locale,
          overflowMode: overflow.name,
          availableWidth: maxWidth,
          desiredWidth: intrinsic > maxWidth ? intrinsic : maxWidth + 1,
          maxLines: paragraph.maxLines,
        ),
      );
      return;
    }

    // When `maxLines` is null, Flutter wraps the text instead of truncating
    // it, so comparing intrinsic width with the available width produces
    // false positives for every long-but-wrappable paragraph.
    if (paragraph.maxLines == null) return;

    // `didExceedMaxLines` only covers line-count overflow. A fixed number of
    // lines can still be truncated horizontally (e.g. `softWrap: false`).
    if (overflow == TextOverflow.visible) return;
    final maxWidth = paragraph.constraints.maxWidth;
    final intrinsic = paragraph.getMinIntrinsicWidth(double.infinity);
    if (intrinsic > maxWidth) {
      issues.add(
        TruncationIssue(
          text: text,
          locale: locale,
          overflowMode: overflow.name,
          availableWidth: maxWidth,
          desiredWidth: intrinsic,
          maxLines: paragraph.maxLines,
        ),
      );
    }
  }
}
