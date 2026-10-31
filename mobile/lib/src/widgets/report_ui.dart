import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format/report_format.dart';
import '../theme.dart';

typedef ReportValueGetter<T> = Object? Function(T row);
typedef ReportValueFormatter = String Function(Object? value);

@immutable
class ReportUiDensity {
  final double pageInset;
  final double panelPadding;
  final double sectionGap;
  final double radius;
  final double visualControlHeight;
  final double interactiveExtent;
  final double tableRowHeight;
  final bool largeText;

  const ReportUiDensity({
    required this.pageInset,
    required this.panelPadding,
    required this.sectionGap,
    required this.radius,
    required this.visualControlHeight,
    required this.interactiveExtent,
    required this.tableRowHeight,
    required this.largeText,
  });

  factory ReportUiDensity.of(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final largeText = scale >= 1.6;
    return ReportUiDensity(
      pageInset: largeText ? 14 : 12,
      panelPadding: largeText ? 14 : 12,
      sectionGap: largeText ? 10 : 8,
      radius: largeText ? 14 : 12,
      visualControlHeight: largeText ? 44 : 36,
      interactiveExtent: 48,
      tableRowHeight: largeText ? 48 : 40,
      largeText: largeText,
    );
  }

  static Duration motionDuration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180);
}

enum ReportSegmentStyle { primary, flat }

@immutable
class ReportSegmentItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final Color? selectedColor;
  final Color? selectedForeground;

  const ReportSegmentItem({
    required this.value,
    required this.label,
    this.icon,
    this.selectedColor,
    this.selectedForeground,
  });
}

class ReportSegmentedControl<T> extends StatelessWidget {
  final List<ReportSegmentItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final String semanticLabel;
  final ReportSegmentStyle style;
  final bool equalWidth;
  final bool scrollable;

  const ReportSegmentedControl({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.semanticLabel = 'Pilihan laporan',
    this.style = ReportSegmentStyle.primary,
    this.equalWidth = false,
    this.scrollable = true,
  }) : assert(items.length > 0);

  @override
  Widget build(BuildContext context) {
    final density = ReportUiDensity.of(context);
    final children = [
      for (final item in items)
        _ReportSegment<T>(
          item: item,
          selected: item.value == value,
          style: style,
          density: density,
          onTap: () {
            if (item.value != value) onChanged(item.value);
          },
        ),
    ];
    final segments = Row(
      mainAxisSize: equalWidth ? MainAxisSize.max : MainAxisSize.min,
      children: equalWidth
          ? [for (final child in children) Expanded(child: child)]
          : children,
    );
    final content = equalWidth
        ? segments
        : scrollable
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: segments,
              )
            : segments;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        decoration: style == ReportSegmentStyle.primary
            ? BoxDecoration(
                color: context.vSubtle,
                borderRadius: BorderRadius.circular(density.radius),
                border: Border.all(color: context.vRule),
              )
            : null,
        child: content,
      ),
    );
  }
}

class _ReportSegment<T> extends StatelessWidget {
  final ReportSegmentItem<T> item;
  final bool selected;
  final ReportSegmentStyle style;
  final ReportUiDensity density;
  final VoidCallback onTap;

  const _ReportSegment({
    required this.item,
    required this.selected,
    required this.style,
    required this.density,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = item.selectedColor ?? IOH.teal500;
    final activeForeground = item.selectedForeground ??
        (style == ReportSegmentStyle.primary ? Colors.white : activeColor);
    final selectedBackground = style == ReportSegmentStyle.primary
        ? activeColor
        : activeColor.withValues(alpha: 0.1);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: density.interactiveExtent),
            child: Center(
              child: AnimatedContainer(
                duration: ReportUiDensity.motionDuration(context),
                constraints: BoxConstraints(
                  minHeight: density.visualControlHeight,
                ),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? selectedBackground : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    style == ReportSegmentStyle.primary ? 9 : 4,
                  ),
                  border: style == ReportSegmentStyle.flat && selected
                      ? Border(
                          bottom: BorderSide(color: activeColor, width: 2.5))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 16,
                        color: selected ? activeForeground : context.vMute,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: TextStyle(
                          color: selected ? activeForeground : context.vMute,
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReportTabRail<T> extends StatefulWidget {
  final List<ReportSegmentItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final String semanticLabel;

  const ReportTabRail({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.semanticLabel = 'Jenis laporan',
  }) : assert(items.length > 0);

  @override
  State<ReportTabRail<T>> createState() => _ReportTabRailState<T>();
}

class _ReportTabRailState<T> extends State<ReportTabRail<T>> {
  final _keys = <T, GlobalKey>{};

  @override
  void didUpdateWidget(covariant ReportTabRail<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedContext = _keys[widget.value]?.currentContext;
      if (!mounted || selectedContext == null) return;
      Scrollable.ensureVisible(
        selectedContext,
        duration: ReportUiDensity.motionDuration(context),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in widget.items)
              KeyedSubtree(
                key: _keys.putIfAbsent(item.value, GlobalKey.new),
                child: _ReportTabItem<T>(
                  item: item,
                  selected: item.value == widget.value,
                  onTap: () {
                    if (item.value != widget.value) {
                      widget.onChanged(item.value);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportTabItem<T> extends StatelessWidget {
  final ReportSegmentItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  const _ReportTabItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.selectedColor ?? IOH.teal600;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: AnimatedContainer(
            duration: ReportUiDensity.motionDuration(context),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.07) : null,
              border: Border(
                bottom: BorderSide(
                  color: selected ? color : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Center(
              child: Text(
                item.label,
                softWrap: true,
                style: TextStyle(
                  color: selected ? color : context.vMute,
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String reportCellText(Object? value) {
  if (value == null) return 'Tidak tersedia';
  final text = value.toString();
  return text.isEmpty ? 'Tidak tersedia' : text;
}

/// Secondary line formatter. A missing sub value means there is nothing extra
/// to say about the cell, which is not the same as a missing measurement, so
/// it renders as no line at all rather than as `Tidak tersedia`.
String reportOptionalCellText(Object? value) => value?.toString() ?? '';

@immutable
class ReportContextValue {
  final String label;
  final String value;
  final IconData? icon;

  const ReportContextValue({
    required this.label,
    required this.value,
    this.icon,
  });
}

/// A responsive context summary for scope, period, metric, brand, or site.
///
/// Place this widget in a pinned sliver owned by the screen when sticky
/// behavior is needed. The widget itself has no navigation or fetch behavior.
class ReportContextBar extends StatelessWidget {
  final List<ReportContextValue> values;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? actionLabel;
  final EdgeInsetsGeometry padding;

  const ReportContextBar({
    super.key,
    required this.values,
    this.semanticLabel = 'Konteks laporan aktif',
    this.onTap,
    this.actionLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      container: true,
      label: semanticLabel,
      button: onTap != null,
      hint: onTap == null ? null : actionLabel,
      child: Material(
        color: context.vWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: context.vRule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: padding,
              child: scale >= 1.6
                  ? Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final value in values) _ContextValue(value: value),
                        if (onTap != null)
                          _ContextAction(label: actionLabel ?? 'Ubah konteks'),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var index = 0;
                                    index < values.length;
                                    index++) ...[
                                  if (index > 0) const SizedBox(width: 14),
                                  _ContextValue(value: values[index]),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (onTap != null) ...[
                          const SizedBox(width: 8),
                          _ContextAction(label: actionLabel ?? 'Ubah konteks'),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextValue extends StatelessWidget {
  final ReportContextValue value;

  const _ContextValue({required this.value});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${value.label}: ${value.value}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (value.icon != null) ...[
            Icon(value.icon, size: 16, color: IOH.teal600),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.label.toUpperCase(),
                    style: const TextStyle(
                      color: IOH.teal600,
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value.value,
                    softWrap: true,
                    style: TextStyle(
                      color: context.vInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextAction extends StatelessWidget {
  final String label;

  const _ContextAction({required this.label});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 17, color: IOH.teal600),
          const SizedBox(width: 5),
          Text(
            label,
            softWrap: true,
            style: TextStyle(
              color: context.vInk,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

@immutable
class ReportChapterLink {
  final String id;
  final String label;
  final IconData? icon;

  const ReportChapterLink({
    required this.id,
    required this.label,
    this.icon,
  });
}

/// Accessible chapter navigation with optional expand and collapse actions.
class ReportChapterNavigator extends StatefulWidget {
  final List<ReportChapterLink> chapters;
  final String? activeId;
  final ValueChanged<String> onSelected;
  final VoidCallback? onExpandAll;
  final VoidCallback? onCollapseAll;
  final String semanticLabel;

  const ReportChapterNavigator({
    super.key,
    required this.chapters,
    required this.onSelected,
    this.activeId,
    this.onExpandAll,
    this.onCollapseAll,
    this.semanticLabel = 'Navigasi bagian laporan',
  });

  @override
  State<ReportChapterNavigator> createState() => _ReportChapterNavigatorState();
}

class _ReportChapterNavigatorState extends State<ReportChapterNavigator> {
  final _chapterKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant ReportChapterNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeId != widget.activeId) _revealActive();
  }

  void _revealActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeContext = _chapterKeys[widget.activeId]?.currentContext;
      if (!mounted || activeContext == null) return;
      Scrollable.ensureVisible(
        activeContext,
        duration: ReportUiDensity.motionDuration(context),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: context.vWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.vRule),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chapter in widget.chapters)
                      KeyedSubtree(
                        key: _chapterKeys.putIfAbsent(
                          chapter.id,
                          GlobalKey.new,
                        ),
                        child: _ChapterNavButton(
                          chapter: chapter,
                          selected: widget.activeId == chapter.id,
                          onTap: () => widget.onSelected(chapter.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.onExpandAll != null || widget.onCollapseAll != null)
              SizedBox(
                width: 48,
                height: 48,
                child: PopupMenuButton<String>(
                  tooltip: 'Aksi semua bagian',
                  icon: Icon(Icons.more_horiz, color: context.vMute),
                  onSelected: (action) {
                    if (action == 'expand') widget.onExpandAll?.call();
                    if (action == 'collapse') widget.onCollapseAll?.call();
                  },
                  itemBuilder: (context) => [
                    if (widget.onExpandAll != null)
                      const PopupMenuItem(
                        value: 'expand',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.unfold_more),
                          title: Text('Buka semua'),
                        ),
                      ),
                    if (widget.onCollapseAll != null)
                      const PopupMenuItem(
                        value: 'collapse',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.unfold_less),
                          title: Text('Tutup semua'),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChapterNavButton extends StatelessWidget {
  final ReportChapterLink chapter;
  final bool selected;
  final VoidCallback onTap;

  const _ChapterNavButton({
    required this.chapter,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: chapter.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: AnimatedContainer(
              duration: ReportUiDensity.motionDuration(context),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? IOH.teal500.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: selected ? IOH.teal500 : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chapter.icon != null) ...[
                    Icon(
                      chapter.icon,
                      size: 18,
                      color: selected ? IOH.teal600 : context.vMute,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      chapter.label,
                      softWrap: true,
                      style: TextStyle(
                        color: selected ? IOH.teal600 : context.vInk,
                        fontFamily: 'Poppins',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Summary-first chapter card that is expanded by default.
///
/// Supply [expanded] to control all chapter states from the parent. When it is
/// null, this widget owns its expansion state locally.
class ReportChapter extends StatefulWidget {
  final String title;
  final String summary;
  final Widget? child;
  final WidgetBuilder? contentBuilder;
  final IconData? icon;
  final Color? accent;
  final String? badge;
  final bool initiallyExpanded;
  final bool? expanded;
  final ValueChanged<bool>? onExpansionChanged;
  final String? semanticLabel;

  const ReportChapter({
    super.key,
    required this.title,
    required this.summary,
    this.child,
    this.contentBuilder,
    this.icon,
    this.accent,
    this.badge,
    this.initiallyExpanded = true,
    this.expanded,
    this.onExpansionChanged,
    this.semanticLabel,
  }) : assert((child == null) != (contentBuilder == null));

  @override
  State<ReportChapter> createState() => _ReportChapterState();
}

class _ReportChapterState extends State<ReportChapter> {
  late bool _expanded = widget.initiallyExpanded;

  bool get _isExpanded => widget.expanded ?? _expanded;

  void _toggle() {
    final next = !_isExpanded;
    if (widget.expanded == null) setState(() => _expanded = next);
    widget.onExpansionChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final density = ReportUiDensity.of(context);
    final accent = widget.accent ?? IOH.teal500;
    final expanded = _isExpanded;
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? widget.title,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: context.vWhite,
          borderRadius: BorderRadius.circular(density.radius),
          border: Border.all(color: context.vRule),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: widget.title,
              value: expanded ? 'Terbuka' : 'Tertutup',
              hint: expanded ? 'Ketuk untuk menutup' : 'Ketuk untuk membuka',
              child: Material(
                color: context.vWhite,
                child: InkWell(
                  onTap: _toggle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.icon != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(widget.icon, color: accent, size: 20),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  softWrap: true,
                                  style: TextStyle(
                                    color: context.vInk,
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.summary,
                                  softWrap: true,
                                  style: TextStyle(
                                    color: context.vMute,
                                    fontSize: 11,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                widget.badge!,
                                softWrap: true,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: ReportUiDensity.motionDuration(context),
                            child: Icon(
                              Icons.expand_more,
                              size: 24,
                              color: context.vMute,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: widget.contentBuilder?.call(context) ?? widget.child!,
              ),
          ],
        ),
      ),
    );
  }
}

@immutable
class ReportTableColumn<T> {
  final String label;
  final ReportValueGetter<T> value;
  final ReportValueGetter<T>? secondaryValue;
  final ReportValueFormatter formatter;
  final ReportValueFormatter secondaryFormatter;
  final bool numeric;
  final bool emphasized;
  final bool comparison;
  final double width;
  final String? semanticLabel;

  /// Raw numeric that decides the growth colour. Falls back to [value], which
  /// only helps when [value] already returns a number rather than a string.
  final ReportValueGetter<T>? signal;

  /// Neutral by default so every existing column keeps its current rendering.
  /// Opt in per column to get green for improvement and red for decline.
  final ReportPolarity polarity;

  /// Per row override. A period table holds many metrics in one column, and
  /// churn growing is not the same news as revenue growing.
  final ReportPolarity Function(T row)? polarityOf;

  /// Per row text colour, for identity rather than direction. Used to paint an
  /// aggregate or brand row in its own colour. Growth colour wins when both
  /// apply, because direction is the more urgent signal.
  final Color? Function(T row)? textColorOf;

  /// Per row bold, for totals and aggregate rows.
  final bool Function(T row)? emphasizedOf;

  const ReportTableColumn({
    required this.label,
    required this.value,
    this.secondaryValue,
    this.formatter = reportCellText,
    this.secondaryFormatter = reportCellText,
    this.numeric = false,
    this.emphasized = false,
    this.comparison = false,
    this.width = 132,
    this.semanticLabel,
    this.signal,
    this.polarity = ReportPolarity.neutral,
    this.polarityOf,
    this.textColorOf,
    this.emphasizedOf,
  }) : assert(width >= 72);

  String text(T row) => formatter(value(row));

  String? secondaryText(T row) {
    final getter = secondaryValue;
    if (getter == null) return null;
    final text = secondaryFormatter(getter(row));
    return text.isEmpty ? null : text;
  }

  /// Effective polarity for [row]: the per row override, else the column one.
  ReportPolarity polarityFor(T row) => polarityOf?.call(row) ?? polarity;

  /// The numeric behind the growth colour, or null when there is none.
  Object? signalOf(T row) => (signal ?? value)(row);

  /// Text colour for [row]: growth direction first, then row identity.
  Color? growthColor(BuildContext context, T row) {
    final resolved = polarityFor(row);
    if (resolved != ReportPolarity.neutral) {
      final growth =
          reportGrowthColor(context, signalOf(row), polarity: resolved);
      if (growth != null) return growth;
    }
    return textColorOf?.call(row);
  }

  /// Whether [row] renders bold in this column.
  bool emphasizedFor(T row) => emphasized || (emphasizedOf?.call(row) ?? false);

  /// Spoken direction so colour is never the only carrier of meaning.
  String growthSemantics(T row) {
    final resolved = polarityFor(row);
    if (resolved == ReportPolarity.neutral) return '';
    return reportGrowthSemantics(signalOf(row), polarity: resolved);
  }
}

enum ReportTableDensity { compact, comfortable }

enum ReportTableLayoutPolicy { adaptive, horizontal, stacked }

/// A table that always renders every row and every column.
///
/// At large text scale or narrow width it switches to stacked row cards. At
/// normal scale it provides an always-visible horizontal scrollbar and scroll
/// instruction. It never applies row limits or text ellipsis.
class ReportAllDataTable<T> extends StatefulWidget {
  final List<T> rows;
  final List<ReportTableColumn<T>> columns;
  final String semanticLabel;
  final String emptyLabel;
  final double stackedBreakpoint;
  final double stackedTextScale;
  final Color? headerBackground;
  final bool zebra;
  final ReportTableDensity density;
  final ReportTableLayoutPolicy layoutPolicy;
  final String? storageKey;
  final bool freezeFirstColumn;
  final ValueChanged<T>? onFirstColumnTap;

  const ReportAllDataTable({
    super.key,
    required this.rows,
    required this.columns,
    this.semanticLabel = 'Tabel data lengkap',
    this.emptyLabel = 'Tidak ada data',
    this.stackedBreakpoint = 360,
    this.stackedTextScale = 1.6,
    this.headerBackground,
    this.zebra = true,
    this.density = ReportTableDensity.compact,
    this.layoutPolicy = ReportTableLayoutPolicy.adaptive,
    this.storageKey,
    this.freezeFirstColumn = false,
    this.onFirstColumnTap,
  })  : assert(stackedBreakpoint > 0),
        assert(stackedTextScale >= 1),
        assert(columns.length > 0);

  @override
  State<ReportAllDataTable<T>> createState() => _ReportAllDataTableState<T>();
}

class _ReportAllDataTableState<T> extends State<ReportAllDataTable<T>> {
  final ScrollController _horizontal = ScrollController();
  bool _hasHorizontalOverflow = false;
  bool _atHorizontalStart = true;
  bool _atHorizontalEnd = true;

  @override
  void initState() {
    super.initState();
    _horizontal.addListener(_updateOverflow);
  }

  @override
  void dispose() {
    _horizontal
      ..removeListener(_updateOverflow)
      ..dispose();
    super.dispose();
  }

  void _queueOverflowCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverflow());
  }

  void _updateOverflow() {
    if (!mounted || !_horizontal.hasClients) return;
    final next = _horizontal.position.maxScrollExtent > 0.5;
    final atStart = _horizontal.position.pixels <= 0.5;
    final atEnd = _horizontal.position.pixels >=
        _horizontal.position.maxScrollExtent - 0.5;
    if (next != _hasHorizontalOverflow ||
        atStart != _atHorizontalStart ||
        atEnd != _atHorizontalEnd) {
      setState(() {
        _hasHorizontalOverflow = next;
        _atHorizontalStart = atStart;
        _atHorizontalEnd = atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Semantics(
        container: true,
        label: widget.emptyLabel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.emptyLabel,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.vMute, fontSize: 12),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = switch (widget.layoutPolicy) {
          ReportTableLayoutPolicy.horizontal => false,
          ReportTableLayoutPolicy.stacked => true,
          ReportTableLayoutPolicy.adaptive =>
            constraints.maxWidth < widget.stackedBreakpoint ||
                scale >= widget.stackedTextScale,
        };
        return Semantics(
          container: true,
          label: widget.semanticLabel,
          child: stacked
              ? _buildStacked(context)
              : _buildWide(context, constraints.maxWidth),
        );
      },
    );
  }

  Widget _buildWide(BuildContext context, double viewportWidth) {
    if (widget.freezeFirstColumn && widget.columns.length > 1) {
      return _buildFrozenWide(context, viewportWidth);
    }
    _queueOverflowCheck();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final widthScale = (1 + (textScale - 1) * 0.25).clamp(1.0, 1.3);
    final totalWidth = widget.columns.fold<double>(
      0,
      (sum, column) => sum + column.width * widthScale,
    );
    final widths = <int, TableColumnWidth>{
      for (var i = 0; i < widget.columns.length; i++)
        i: FixedColumnWidth(widget.columns[i].width * widthScale),
    };
    final compact = widget.density == ReportTableDensity.compact;
    final headerHeight = compact ? 36.0 : 48.0;
    final rowHeight = compact ? 40.0 : 48.0;

    return Container(
      decoration: BoxDecoration(
        color: context.vWhite,
        border: Border.all(color: context.vRule),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                trackVisibility: _hasHorizontalOverflow,
                interactive: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  key: widget.storageKey == null
                      ? null
                      : PageStorageKey<String>(
                          'report-table-${widget.storageKey}'),
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: totalWidth,
                    child: Table(
                      columnWidths: widths,
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: context.vRule,
                          width: 0.7,
                        ),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: widget.headerBackground ?? context.vPanel,
                            border: Border(
                              bottom: BorderSide(color: context.vInk, width: 2),
                            ),
                          ),
                          children: [
                            for (final column in widget.columns)
                              _TableCell(
                                text: column.label,
                                numeric: column.numeric,
                                header: true,
                                minHeight: headerHeight,
                                semanticLabel:
                                    column.semanticLabel ?? column.label,
                              ),
                          ],
                        ),
                        for (var rowIndex = 0;
                            rowIndex < widget.rows.length;
                            rowIndex++)
                          TableRow(
                            decoration: BoxDecoration(
                              color: widget.zebra && rowIndex.isOdd
                                  ? context.vZebra
                                  : context.vWhite,
                            ),
                            children: [
                              for (final column in widget.columns)
                                _TableCell(
                                  text: column.text(widget.rows[rowIndex]),
                                  secondaryText: column.secondaryText(
                                    widget.rows[rowIndex],
                                  ),
                                  numeric: column.numeric,
                                  emphasized:
                                      column.emphasizedFor(widget.rows[rowIndex]),
                                  comparison: column.comparison,
                                  textColor: column.growthColor(
                                    context,
                                    widget.rows[rowIndex],
                                  ),
                                  minHeight: rowHeight,
                                  semanticLabel:
                                      '${column.semanticLabel ?? column.label}: ${column.text(widget.rows[rowIndex])}${column.growthSemantics(widget.rows[rowIndex])}',
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_hasHorizontalOverflow && !_atHorizontalStart)
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 10,
                  child: IgnorePointer(child: _TableEdgeFade(left: true)),
                ),
              if (_hasHorizontalOverflow && !_atHorizontalEnd)
                const Positioned(
                  right: 0,
                  top: 0,
                  bottom: 10,
                  child: IgnorePointer(child: _TableEdgeFade(left: false)),
                ),
            ],
          ),
          if (_hasHorizontalOverflow)
            Semantics(
              label: 'Tabel dapat digeser horizontal',
              child: Container(
                color: context.vPanel,
                constraints: const BoxConstraints(minHeight: 28),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.swipe_left, size: 16, color: context.vMute),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Geser horizontal untuk melihat semua kolom',
                        softWrap: true,
                        style: TextStyle(color: context.vMute, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFrozenWide(BuildContext context, double viewportWidth) {
    _queueOverflowCheck();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final widthScale = (1 + (textScale - 1) * 0.2).clamp(1.0, 1.25).toDouble();
    final frozenColumn = widget.columns.first;
    final scrollColumns = widget.columns.skip(1).toList(growable: false);
    final maxFrozenWidth =
        (viewportWidth * 0.46).clamp(112.0, 190.0).toDouble();
    final frozenWidth = (frozenColumn.width * widthScale)
        .clamp(112.0, maxFrozenWidth)
        .toDouble();
    final scrollWidths = <double>[
      for (final column in scrollColumns) column.width * widthScale,
    ];
    final scrollWidth =
        scrollWidths.fold<double>(0, (sum, value) => sum + value);
    final compact = widget.density == ReportTableDensity.compact;
    final minHeaderHeight = compact ? 32.0 : 48.0;
    // Tappable rows keep the 48 dp touch target; read-only rows stay dense.
    final minRowHeight =
        widget.onFirstColumnTap == null ? (compact ? 32.0 : 48.0) : 48.0;
    final headerHeight = _measuredRowHeight(
      context,
      [frozenColumn.label, ...scrollColumns.map((column) => column.label)],
      [frozenWidth, ...scrollWidths],
      header: true,
      minimum: minHeaderHeight,
    );
    final rowHeights = <double>[
      for (final row in widget.rows)
        _measuredRowHeight(
          context,
          [
            frozenColumn.text(row),
            for (final column in scrollColumns) column.text(row),
          ],
          [frozenWidth, ...scrollWidths],
          secondaryTexts: [
            frozenColumn.secondaryText(row),
            for (final column in scrollColumns) column.secondaryText(row),
          ],
          boldFlags: [
            frozenColumn.emphasizedFor(row),
            for (final column in scrollColumns)
              column.emphasizedFor(row) ||
                  column.comparison ||
                  column.growthColor(context, row) != null,
          ],
          minimum: minRowHeight,
        ),
    ];
    final scrollHeaderColor = widget.headerBackground ?? IOH.teal500;
    final scrollHeaderForeground =
        ThemeData.estimateBrightnessForColor(scrollHeaderColor) ==
                Brightness.dark
            ? Colors.white
            : const Color(0xFF322100);

    Widget renderedDataCell({
      required ReportTableColumn<T> column,
      required T row,
      required int rowIndex,
      required double width,
    }) {
      final background =
          widget.zebra && rowIndex.isOdd ? context.vZebra : context.vWhite;
      final resolvedBackground = column.comparison
          ? Color.alphaBlend(IOH.yellow.withValues(alpha: 0.09), background)
          : background;
      return Container(
        width: width,
        height: rowHeights[rowIndex],
        decoration: BoxDecoration(
          color: resolvedBackground,
          border: Border(bottom: BorderSide(color: context.vRule, width: 0.7)),
        ),
        child: _TableCell(
          text: column.text(row),
          secondaryText: column.secondaryText(row),
          numeric: column.numeric,
          emphasized: column.emphasizedFor(row),
          comparison: column.comparison,
          textColor: column.growthColor(context, row),
          minHeight: rowHeights[rowIndex],
          exactHeight: rowHeights[rowIndex],
          semanticLabel:
              '${column.semanticLabel ?? column.label}: ${column.text(row)}${column.secondaryText(row) == null ? '' : ', ${column.secondaryText(row)}'}${column.growthSemantics(row)}',
        ),
      );
    }

    final frozenPane = SizedBox(
      width: frozenWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: headerHeight,
            decoration: BoxDecoration(
              color: context.vPanel,
              border: Border(
                right: BorderSide(color: context.vRule),
                bottom: BorderSide(color: context.vInk, width: 2),
              ),
            ),
            child: _TableCell(
              text: frozenColumn.label,
              numeric: frozenColumn.numeric,
              header: true,
              minHeight: headerHeight,
              exactHeight: headerHeight,
              semanticLabel: frozenColumn.semanticLabel ?? frozenColumn.label,
            ),
          ),
          for (var rowIndex = 0; rowIndex < widget.rows.length; rowIndex++)
            Material(
              color: widget.zebra && rowIndex.isOdd
                  ? context.vZebra
                  : context.vWhite,
              child: InkWell(
                onTap: widget.onFirstColumnTap == null
                    ? null
                    : () => widget.onFirstColumnTap!(widget.rows[rowIndex]),
                child: Container(
                  height: rowHeights[rowIndex],
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: context.vRule),
                      bottom: BorderSide(color: context.vRule, width: 0.7),
                    ),
                  ),
                  child: _TableCell(
                    text: frozenColumn.text(widget.rows[rowIndex]),
                    secondaryText:
                        frozenColumn.secondaryText(widget.rows[rowIndex]),
                    numeric: frozenColumn.numeric,
                    emphasized:
                        frozenColumn.emphasizedFor(widget.rows[rowIndex]),
                    textColor:
                        frozenColumn.growthColor(context, widget.rows[rowIndex]),
                    minHeight: rowHeights[rowIndex],
                    exactHeight: rowHeights[rowIndex],
                    semanticLabel:
                        '${frozenColumn.semanticLabel ?? frozenColumn.label}: ${frozenColumn.text(widget.rows[rowIndex])}${widget.onFirstColumnTap == null ? '' : '. Ketuk untuk detail'}',
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final scrollPane = Stack(
      children: [
        Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          trackVisibility: _hasHorizontalOverflow,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            key: widget.storageKey == null
                ? null
                : PageStorageKey<String>('report-table-${widget.storageKey}'),
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: scrollWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: headerHeight,
                    color: scrollHeaderColor,
                    child: Row(
                      children: [
                        for (var index = 0;
                            index < scrollColumns.length;
                            index++)
                          SizedBox(
                            width: scrollWidths[index],
                            height: headerHeight,
                            child: _TableCell(
                              text: scrollColumns[index].label,
                              numeric: scrollColumns[index].numeric,
                              header: true,
                              textColor: scrollHeaderForeground,
                              minHeight: headerHeight,
                              exactHeight: headerHeight,
                              semanticLabel:
                                  scrollColumns[index].semanticLabel ??
                                      scrollColumns[index].label,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var rowIndex = 0;
                      rowIndex < widget.rows.length;
                      rowIndex++)
                    Row(
                      children: [
                        for (var columnIndex = 0;
                            columnIndex < scrollColumns.length;
                            columnIndex++)
                          renderedDataCell(
                            column: scrollColumns[columnIndex],
                            row: widget.rows[rowIndex],
                            rowIndex: rowIndex,
                            width: scrollWidths[columnIndex],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_hasHorizontalOverflow && !_atHorizontalStart)
          const Positioned(
            left: 0,
            top: 0,
            bottom: 10,
            child: IgnorePointer(child: _TableEdgeFade(left: true)),
          ),
        if (_hasHorizontalOverflow && !_atHorizontalEnd)
          const Positioned(
            right: 0,
            top: 0,
            bottom: 10,
            child: IgnorePointer(child: _TableEdgeFade(left: false)),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: context.vWhite,
        border: Border.all(color: context.vRule),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              frozenPane,
              Expanded(child: scrollPane),
            ],
          ),
          if (_hasHorizontalOverflow)
            Semantics(
              label:
                  'Kolom metrik tetap terlihat. Data dapat digeser horizontal',
              child: Container(
                color: context.vPanel,
                constraints: const BoxConstraints(minHeight: 28),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.swipe_left, size: 16, color: context.vMute),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Metric tetap, geser periode ke kiri atau kanan',
                        softWrap: true,
                        style: TextStyle(color: context.vMute, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _measuredRowHeight(
    BuildContext context,
    List<String> primaryTexts,
    List<double> widths, {
    List<String?>? secondaryTexts,
    List<bool>? boldFlags,
    required double minimum,
    bool header = false,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    // A small additive margin absorbs rounding between measured and painted
    // lines. Multiplying instead inflated every row, up to 2.4x at large text.
    final measurementSafety = scaler.scale(1) > 1 ? 6.0 : 3.0;
    // The rendered cell inherits the ambient text style, which carries the app
    // font and its line height. Measuring against a bare TextStyle reports a
    // shorter line than the one actually painted, and the cell overflows.
    final inherited = DefaultTextStyle.of(context).style;
    var height = minimum;
    for (var index = 0; index < primaryTexts.length; index++) {
      // Bold text is wider, so it wraps sooner. Measuring it as regular weight
      // under-reports the line count for the same reason.
      final bold = header ||
          (boldFlags != null && index < boldFlags.length && boldFlags[index]);
      final style = inherited.merge(TextStyle(
        fontFamily: header ? 'Poppins' : null,
        fontSize: header ? 11 : 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        height: _cellLineHeight,
      ));
      final primary = TextPainter(
        text: TextSpan(text: primaryTexts[index], style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: (widths[index] - 16).clamp(24.0, double.infinity));
      var contentHeight = primary.height;
      final secondary = secondaryTexts != null ? secondaryTexts[index] : null;
      if (secondary != null && secondary.isNotEmpty) {
        final secondaryPainter = TextPainter(
          text: TextSpan(
            text: secondary,
            style: inherited.merge(
              const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                height: _cellLineHeight,
              ),
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: (widths[index] - 16).clamp(24.0, double.infinity));
        contentHeight += 2 + secondaryPainter.height;
      }
      height = math
          .max(height, contentHeight + _cellVerticalPadding * 2 + measurementSafety)
          .toDouble();
    }
    return height.ceilToDouble();
  }

  Widget _buildStacked(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var rowIndex = 0; rowIndex < widget.rows.length; rowIndex++)
          Semantics(
            container: true,
            label: 'Baris ${rowIndex + 1} dari ${widget.rows.length}',
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: widget.zebra && rowIndex.isOdd
                    ? context.vZebra
                    : context.vWhite,
                border: Border.all(color: context.vRule),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var columnIndex = 0;
                      columnIndex < widget.columns.length;
                      columnIndex++)
                    _StackedCell<T>(
                      column: widget.columns[columnIndex],
                      row: widget.rows[rowIndex],
                      showDivider: columnIndex > 0,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TableEdgeFade extends StatelessWidget {
  final bool left;

  const _TableEdgeFade({required this.left});

  @override
  Widget build(BuildContext context) {
    final solid = context.vWhite.withValues(alpha: 0.92);
    return SizedBox(
      width: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [solid, context.vWhite.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

const double _cellVerticalPadding = 4;

// Prompt's natural line box is about 1.5 em; a fixed 1.2 keeps cells dense.
// Measurement and painting must both use it or rows clip.
const double _cellLineHeight = 1.2;

class _TableCell extends StatelessWidget {
  final String text;
  final String? secondaryText;
  final bool numeric;
  final bool header;
  final bool emphasized;
  final bool comparison;
  final String semanticLabel;
  final double minHeight;
  final double? exactHeight;
  final Color? textColor;

  const _TableCell({
    required this.text,
    required this.numeric,
    required this.semanticLabel,
    required this.minHeight,
    this.secondaryText,
    this.header = false,
    this.emphasized = false,
    this.comparison = false,
    this.exactHeight,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: exactHeight == null
            ? BoxConstraints(minHeight: minHeight)
            : BoxConstraints.tightFor(height: exactHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: _cellVerticalPadding),
          child: Align(
            alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  numeric ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  textAlign: numeric ? TextAlign.right : TextAlign.left,
                  softWrap: true,
                  style: TextStyle(
                    color: textColor ?? (header ? context.vMute : context.vInk),
                    fontFamily: header ? 'Poppins' : null,
                    fontSize: header ? 11 : 12,
                    fontWeight: header || emphasized || comparison
                        ? FontWeight.w700
                        : FontWeight.w400,
                    height: _cellLineHeight,
                    fontFeatures:
                        numeric ? const [FontFeature.tabularFigures()] : null,
                  ),
                ),
                if (secondaryText != null && secondaryText!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondaryText!,
                    textAlign: numeric ? TextAlign.right : TextAlign.left,
                    softWrap: true,
                    style: TextStyle(
                      color: context.vMute,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      height: _cellLineHeight,
                      fontFeatures:
                          numeric ? const [FontFeature.tabularFigures()] : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StackedCell<T> extends StatelessWidget {
  final ReportTableColumn<T> column;
  final T row;
  final bool showDivider;

  const _StackedCell({
    required this.column,
    required this.row,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final text = column.text(row);
    final growthColor = column.growthColor(context, row);
    return Semantics(
      label:
          '${column.semanticLabel ?? column.label}: $text${column.growthSemantics(row)}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: showDivider
            ? BoxDecoration(
                border: Border(top: BorderSide(color: context.vRule)),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                column.label,
                softWrap: true,
                style: TextStyle(
                  color: context.vMute,
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                text,
                textAlign: column.numeric ? TextAlign.right : TextAlign.left,
                softWrap: true,
                style: TextStyle(
                  color: growthColor ?? context.vInk,
                  fontSize: 12,
                  fontWeight:
                      growthColor == null ? FontWeight.w400 : FontWeight.w700,
                  fontFeatures: column.numeric
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One period cell: the number to show plus the raw value behind it.
///
/// Growth cells need both. The string is what the user reads, the number is
/// what decides whether the cell is green or red.
@immutable
class ReportPeriodCell {
  final String text;
  final String? secondaryText;
  final num? raw;

  const ReportPeriodCell(this.text, {this.secondaryText, this.raw});

  static const ReportPeriodCell empty = ReportPeriodCell(kReportNotAvailable);
}

/// One row of a period table.
///
/// [code] drives polarity, so a churn row colours the opposite way to a
/// revenue row inside the same table.
@immutable
class ReportPeriodRow {
  final String name;
  final String? subtitle;
  final String code;
  final Map<String, ReportPeriodCell> cells;

  /// Nested detail line, rendered with a leading indent.
  final bool indented;

  /// Totals or headline rows, rendered bold on a distinct surface.
  final bool headline;

  /// Set when the row can expand or collapse; null makes the row inert.
  final String? expandKey;

  final bool expanded;

  const ReportPeriodRow({
    required this.name,
    required this.cells,
    this.subtitle,
    this.code = '',
    this.indented = false,
    this.headline = false,
    this.expandKey,
    this.expanded = false,
  });

  ReportPeriodCell cell(String key) => cells[key] ?? ReportPeriodCell.empty;
}

/// Column roles a period table can show. The order here is the order on screen.
enum ReportPeriodColumn {
  llmtd,
  lmtd,
  mtd,
  growthMom,
  lytd,
  ytd,
  growthYoy,
  extra,
}

extension ReportPeriodColumnLabel on ReportPeriodColumn {
  String get key => name;

  String get label {
    switch (this) {
      case ReportPeriodColumn.llmtd:
        return 'LLMTD';
      case ReportPeriodColumn.lmtd:
        return 'LMTD';
      case ReportPeriodColumn.mtd:
        return 'MTD';
      case ReportPeriodColumn.growthMom:
        return 'Growth';
      case ReportPeriodColumn.lytd:
        return 'LYTD';
      case ReportPeriodColumn.ytd:
        return 'YTD';
      case ReportPeriodColumn.growthYoy:
        return 'Growth';
      case ReportPeriodColumn.extra:
        return '';
    }
  }

  bool get isGrowth =>
      this == ReportPeriodColumn.growthMom || this == ReportPeriodColumn.growthYoy;

  bool get isEmphasized =>
      this == ReportPeriodColumn.mtd || this == ReportPeriodColumn.ytd;

  String get semanticLabel {
    switch (this) {
      case ReportPeriodColumn.growthMom:
        return 'Growth MTD terhadap LMTD';
      case ReportPeriodColumn.growthYoy:
        return 'Growth YTD terhadap LYTD';
      default:
        return label;
    }
  }
}

/// The canonical LLMTD / LMTD / MTD / Growth / LYTD / YTD / Growth table.
///
/// Every report tab renders period data through this one widget so geometry,
/// typography, growth colouring, and the responsive fallback stay identical.
/// It is a thin wrapper over [ReportAllDataTable], which already owns frozen
/// first column, horizontal scrolling, and the stacked large text layout.
class ReportPeriodTable extends StatelessWidget {
  /// Header of the frozen first column: Metric, Name, Slab, or Channel.
  final String nameLabel;

  final List<ReportPeriodRow> rows;

  /// Columns in display order. Defaults to the full seven period roles.
  final List<ReportPeriodColumn> columns;

  /// Header label for [ReportPeriodColumn.extra], for example `Contrib %`.
  final String extraLabel;

  /// Band colour of the header, normally the active brand.
  final BrandIdentity band;

  final String storageKey;

  /// Called with [ReportPeriodRow.expandKey] when an expandable row is tapped.
  final ValueChanged<String>? onToggleRow;

  final String semanticLabel;

  /// Width of the frozen name column. Wider for channel or slab names.
  final double nameWidth;

  static const List<ReportPeriodColumn> fullPeriods = [
    ReportPeriodColumn.llmtd,
    ReportPeriodColumn.lmtd,
    ReportPeriodColumn.mtd,
    ReportPeriodColumn.growthMom,
    ReportPeriodColumn.lytd,
    ReportPeriodColumn.ytd,
    ReportPeriodColumn.growthYoy,
  ];

  static const List<ReportPeriodColumn> monthOnlyPeriods = [
    ReportPeriodColumn.llmtd,
    ReportPeriodColumn.lmtd,
    ReportPeriodColumn.mtd,
    ReportPeriodColumn.growthMom,
  ];

  /// One canonical geometry so no tab drifts again.
  static const double dataColumnWidth = 88;
  static const double growthColumnWidth = 96;

  const ReportPeriodTable({
    super.key,
    required this.rows,
    required this.band,
    required this.storageKey,
    this.nameLabel = 'Metric',
    this.columns = fullPeriods,
    this.extraLabel = '',
    this.onToggleRow,
    this.semanticLabel = 'Tabel periode lengkap',
    this.nameWidth = 158,
  });

  @override
  Widget build(BuildContext context) {
    String nameText(ReportPeriodRow row) {
      final marker = row.expandKey == null
          ? ''
          : (row.expanded ? '▾ ' : '▸ ');
      final indent = row.indented ? '   ' : '';
      return '$indent$marker${row.name}';
    }

    return ReportAllDataTable<ReportPeriodRow>(
      semanticLabel: semanticLabel,
      rows: rows,
      layoutPolicy: ReportTableLayoutPolicy.horizontal,
      freezeFirstColumn: true,
      headerBackground: band.color,
      storageKey: storageKey,
      onFirstColumnTap: onToggleRow == null
          ? null
          : (row) {
              final key = row.expandKey;
              if (key != null) onToggleRow!(key);
            },
      columns: [
        ReportTableColumn<ReportPeriodRow>(
          label: nameLabel,
          width: nameWidth,
          value: nameText,
          secondaryValue: (row) => row.subtitle,
          secondaryFormatter: reportOptionalCellText,
          emphasized: true,
        ),
        for (final column in columns)
          ReportTableColumn<ReportPeriodRow>(
            label: column == ReportPeriodColumn.extra
                ? extraLabel
                : column.label,
            semanticLabel: column == ReportPeriodColumn.extra
                ? extraLabel
                : column.semanticLabel,
            width: column.isGrowth ? growthColumnWidth : dataColumnWidth,
            numeric: true,
            emphasized: column.isEmphasized,
            comparison: column.isGrowth,
            value: (row) => row.cell(column.key).text,
            secondaryValue: (row) => row.cell(column.key).secondaryText,
            secondaryFormatter: reportOptionalCellText,
            signal: (row) => row.cell(column.key).raw,
            // Totals read bold across the whole row, not just in the name.
            emphasizedOf: (row) => row.headline,
            polarityOf: (row) => column.isGrowth
                ? reportPolarityFor(row.code)
                : ReportPolarity.neutral,
          ),
      ],
    );
  }
}

/// The standard content card: white surface, hairline border, teal caption.
///
/// This is the one panel shape used by the site screen, the reports screen,
/// and the map sheet, so a section looks the same wherever it appears.
class ReportPanel extends StatelessWidget {
  final String title;
  final Widget child;

  /// Optional line under the title, for scope or a row count.
  final String? subtitle;

  /// Optional control pinned to the right of the title, such as a toggle.
  final Widget? trailing;

  final EdgeInsetsGeometry margin;

  const ReportPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.vRule),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ReportSectionHeader(title, subtitle: subtitle)),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ]),
    );
  }
}

/// Uppercase teal caption that opens a section.
class ReportSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const ReportSectionHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: IOH.teal600,
          letterSpacing: 0.5,
        ),
      ),
      if (subtitle != null && subtitle!.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          subtitle!,
          style: TextStyle(fontSize: 9.5, color: context.vMute),
        ),
      ],
    ]);
  }
}

/// One label and value line inside a [ReportAttributeTable].
@immutable
class ReportAttribute {
  final String label;
  final String value;

  /// Small line under the label, normally the raw payload key.
  final String? sublabel;

  /// Overrides the value colour, for growth or brand identity.
  final Color? valueColor;

  /// Indent depth for nested structures.
  final int depth;

  const ReportAttribute({
    required this.label,
    required this.value,
    this.sublabel,
    this.valueColor,
    this.depth = 0,
  });
}

/// Label left, value right, zebra striped, stacking when space runs out.
///
/// This is the reference row shape for site attributes and for the map sheet
/// field list.
class ReportAttributeTable extends StatelessWidget {
  final List<ReportAttribute> attributes;
  final String emptyLabel;

  /// Width below which each row stacks label over value.
  final double stackedBreakpoint;

  const ReportAttributeTable({
    super.key,
    required this.attributes,
    this.emptyLabel = 'Tidak ada atribut.',
    this.stackedBreakpoint = 420,
  });

  @override
  Widget build(BuildContext context) {
    if (attributes.isEmpty) {
      return Text(emptyLabel, style: TextStyle(color: context.vMute));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final stacked =
          constraints.maxWidth < stackedBreakpoint || textScale > 1.35;
      return Column(
        children: [
          for (var index = 0; index < attributes.length; index++)
            ReportKeyValueRow(
              attribute: attributes[index],
              zebra: index.isOdd,
              stacked: stacked,
            ),
        ],
      );
    });
  }
}

/// A single attribute row. Values stay selectable so they can be copied.
class ReportKeyValueRow extends StatelessWidget {
  final ReportAttribute attribute;
  final bool zebra;
  final bool stacked;

  const ReportKeyValueRow({
    super.key,
    required this.attribute,
    this.zebra = false,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          attribute.label,
          softWrap: true,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: context.vMute,
          ),
        ),
        if (attribute.sublabel != null &&
            attribute.sublabel!.isNotEmpty &&
            attribute.sublabel != attribute.label) ...[
          const SizedBox(height: 1),
          Text(
            attribute.sublabel!,
            softWrap: true,
            style: TextStyle(fontSize: 9, color: context.vMute),
          ),
        ],
      ],
    );
    final valueStyle = TextStyle(
      fontSize: 12,
      fontWeight:
          attribute.valueColor == null ? FontWeight.w400 : FontWeight.w700,
      color: attribute.valueColor ?? context.vInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final content = stacked
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            labelWidget,
            const SizedBox(height: 2),
            SelectableText(attribute.value, style: valueStyle),
          ])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 4, child: labelWidget),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: SelectableText(
                attribute.value,
                textAlign: TextAlign.right,
                style: valueStyle,
              ),
            ),
          ]);

    return Semantics(
      label: '${attribute.label}, ${attribute.value}',
      child: Container(
        width: double.infinity,
        color: zebra ? context.vZebra : context.vWhite,
        padding: EdgeInsets.only(
          left: 8 + attribute.depth * 12,
          right: 8,
          top: 6,
          bottom: 6,
        ),
        child: content,
      ),
    );
  }
}

/// Growth reading with an arrow glyph and direction colour.
///
/// Replaces the several hand-rolled percent chips that used different glyphs,
/// different decimal separators, and different colour rules.
class ReportGrowthText extends StatelessWidget {
  final Object? value;
  final ReportPolarity polarity;

  /// `%` for a relative move, `pp` for a percentage point move.
  final String suffix;

  final double fontSize;

  const ReportGrowthText(
    this.value, {
    super.key,
    this.polarity = ReportPolarity.higherIsBetter,
    this.suffix = '%',
    this.fontSize = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    final color = reportGrowthColor(context, value, polarity: polarity);
    return Text(
      reportGrowth(value, suffix: suffix),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color ?? context.vMute,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      semanticsLabel:
          '${reportGrowth(value, suffix: suffix)}${reportGrowthSemantics(value, polarity: polarity)}',
    );
  }
}
