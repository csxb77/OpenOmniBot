import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ui/services/codex_diff_parser.dart';

class CodexDiffViewer extends StatelessWidget {
  const CodexDiffViewer({
    super.key,
    required this.summary,
    required this.padding,
  });

  final CodexDiffSummary summary;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (summary.files.isEmpty) {
      return Padding(
        padding: padding,
        child: const Text(
          '暂无 diff',
          style: TextStyle(color: Color(0xFF8FA4C2), fontSize: 12, height: 1.4),
        ),
      );
    }

    final theme = Theme.of(context);
    final maxLineCount = summary.files.fold<int>(
      0,
      (maxLines, file) => math.max(maxLines, file.lines.length),
    );
    final lineNumberWidth = math
        .max(36.0, math.max(1, maxLineCount.toString().length) * 7.5 + 6)
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = math.max(320.0, constraints.maxWidth).toDouble();
        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiffOverviewBar(summary: summary),
              const SizedBox(height: 14),
              for (var index = 0; index < summary.files.length; index += 1) ...[
                _DiffFileSection(
                  file: summary.files[index],
                  minWidth: minWidth,
                  lineNumberWidth: lineNumberWidth,
                ),
                if (index < summary.files.length - 1)
                  const SizedBox(height: 14),
              ],
              SizedBox(
                height: math
                    .max(12.0, theme.visualDensity.baseSizeAdjustment.dy + 12.0)
                    .toDouble(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiffOverviewBar extends StatelessWidget {
  const _DiffOverviewBar({required this.summary});

  final CodexDiffSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = summary.primaryPath;
    final title = summary.files.length == 1
        ? (path.isEmpty ? 'Diff' : path)
        : '${summary.files.length} 个文件';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111B2B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF223047)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.compare_arrows_rounded,
            size: 18,
            color: Color(0xFF9FB1C8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFF1F5FB),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildOverviewText(summary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8FA4C2),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _DiffStatPill(
            additions: summary.additions,
            deletions: summary.deletions,
          ),
        ],
      ),
    );
  }
}

String _buildOverviewText(CodexDiffSummary summary) {
  final fileLabel = summary.files.length == 1
      ? '1 个文件'
      : '${summary.files.length} 个文件';
  return '$fileLabel · ${formatCodexDiffStat(additions: summary.additions, deletions: summary.deletions)}';
}

class _DiffFileSection extends StatelessWidget {
  const _DiffFileSection({
    required this.file,
    required this.minWidth,
    required this.lineNumberWidth,
  });

  final CodexDiffFile file;
  final double minWidth;
  final double lineNumberWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateLabel = file.isNewFile
        ? '新'
        : file.isDeletedFile
        ? '删'
        : '改';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1724),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF223047)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Icon(
                  file.isNewFile
                      ? Icons.add_circle_outline_rounded
                      : file.isDeletedFile
                      ? Icons.remove_circle_outline_rounded
                      : Icons.description_outlined,
                  size: 17,
                  color: const Color(0xFF9FB1C8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.displayPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFF1F5FB),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _StateChip(label: stateLabel),
                const SizedBox(width: 8),
                _DiffStatPill(
                  additions: file.additions,
                  deletions: file.deletions,
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF223047)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in file.lines)
                      _DiffLineRow(
                        line: line,
                        lineNumberWidth: lineNumberWidth,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({required this.line, required this.lineNumberWidth});

  final CodexDiffLine line;
  final double lineNumberWidth;

  @override
  Widget build(BuildContext context) {
    final (background, textColor, gutterColor) = switch (line.kind) {
      CodexDiffLineKind.add => (
        const Color(0xFF13291D),
        const Color(0xFFD6FFE2),
        const Color(0xFF6CD68F),
      ),
      CodexDiffLineKind.remove => (
        const Color(0xFF2B1720),
        const Color(0xFFFFD6DD),
        const Color(0xFFE27C8B),
      ),
      CodexDiffLineKind.header => (
        const Color(0xFF162033),
        const Color(0xFFBFD0E8),
        const Color(0xFF8FA4C2),
      ),
      CodexDiffLineKind.meta => (
        const Color(0xFF111B2B),
        const Color(0xFF8FA4C2),
        const Color(0xFF6F809A),
      ),
      CodexDiffLineKind.context => (
        const Color(0xFF0F1724),
        const Color(0xFFF1F5FB),
        const Color(0xFF6F809A),
      ),
    };

    final oldNumber = _lineNumberText(line.oldLineNumber);
    final newNumber = _lineNumberText(line.newLineNumber);
    final contentText =
        line.kind == CodexDiffLineKind.header ||
            line.kind == CodexDiffLineKind.meta
        ? line.content
        : '${line.prefix}${line.content}';

    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              oldNumber,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: gutterColor,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              newNumber,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: gutterColor,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SelectableText(
            contentText,
            maxLines: 1,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              height: 1.45,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  String _lineNumberText(int? value) => value == null ? ' ' : value.toString();
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF162033),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2A3A53)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9FB1C8),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _DiffStatPill extends StatelessWidget {
  const _DiffStatPill({required this.additions, required this.deletions});

  final int additions;
  final int deletions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF162033),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2A3A53)),
      ),
      child: Text(
        formatCodexDiffStat(additions: additions, deletions: deletions),
        style: TextStyle(
          color: additions >= deletions
              ? const Color(0xFF79D29A)
              : const Color(0xFFFFA8B5),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
