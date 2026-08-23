import 'package:bizplan_java_agent/src/theme.dart';
import 'package:bizplan_java_agent/src/widgets/report_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(
  Widget child, {
  double textScale = 1,
  Size size = const Size(320, 900),
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: themeMode,
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compact segmented control keeps one controlled callback',
      (tester) async {
    var selected = 'coordinate';
    var callbackCount = 0;
    await tester.pumpWidget(_app(
      StatefulBuilder(builder: (context, setState) {
        return ReportSegmentedControl<String>(
          value: selected,
          equalWidth: true,
          onChanged: (value) {
            callbackCount++;
            setState(() => selected = value);
          },
          items: const [
            ReportSegmentItem(value: 'coordinate', label: 'Coordinate'),
            ReportSegmentItem(value: 'territory', label: 'Territory Wise'),
          ],
        );
      }),
    ));

    final control = find.byWidgetPredicate(
      (widget) => widget is ReportSegmentedControl<String>,
    );
    expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
    await tester.tap(find.text('Territory Wise'));
    await tester.pumpAndSettle();
    expect(selected, 'territory');
    expect(callbackCount, 1);
    await tester.tap(find.text('Territory Wise'));
    await tester.pumpAndSettle();
    expect(callbackCount, 1);
  });

  testWidgets('lazy chapter body is built only after opening', (tester) async {
    var expanded = false;
    var buildCount = 0;
    await tester.pumpWidget(_app(
      StatefulBuilder(builder: (context, setState) {
        return ReportChapter(
          title: 'Network',
          summary: 'Complete network fields',
          expanded: expanded,
          onExpansionChanged: (value) => setState(() => expanded = value),
          contentBuilder: (context) {
            buildCount++;
            return const Text('Network table');
          },
        );
      }),
    ));

    expect(buildCount, 0);
    await tester.tap(find.text('Network'));
    await tester.pump();
    expect(find.text('Network table'), findsOneWidget);
    expect(buildCount, 1);
  });

  testWidgets('all-data table exposes every row and column on narrow screens',
      (tester) async {
    final rows =
        List.generate(6, (index) => {'name': 'Row $index', 'value': index});
    await tester.pumpWidget(_app(
      ReportAllDataTable<Map<String, Object>>(
        rows: rows,
        columns: [
          ReportTableColumn(label: 'Name', value: (row) => row['name']),
          ReportTableColumn(label: 'Value', value: (row) => row['value']),
        ],
      ),
      textScale: 2,
    ));

    expect(find.text('Name'), findsWidgets);
    expect(find.text('Value'), findsWidgets);
    for (var index = 0; index < rows.length; index++) {
      expect(find.text('Row $index'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('temporal table remains horizontal at 200 percent text scale',
      (tester) async {
    final rows = [
      {'metric': 'Revenue', 'lmtd': 10, 'mtd': 12, 'growth': 20, 'ytd': 80},
      {'metric': 'Subscriber', 'lmtd': 8, 'mtd': 9, 'growth': 12.5, 'ytd': 70},
    ];
    await tester.pumpWidget(_app(
      ReportAllDataTable<Map<String, Object>>(
        rows: rows,
        layoutPolicy: ReportTableLayoutPolicy.horizontal,
        freezeFirstColumn: true,
        storageKey: 'temporal-test',
        columns: [
          ReportTableColumn(label: 'Metric', value: (row) => row['metric']),
          ReportTableColumn(
              label: 'LMTD', numeric: true, value: (row) => row['lmtd']),
          ReportTableColumn(
              label: 'MTD', numeric: true, value: (row) => row['mtd']),
          ReportTableColumn(
              label: 'Growth', numeric: true, value: (row) => row['growth']),
          ReportTableColumn(
              label: 'YTD', numeric: true, value: (row) => row['ytd']),
        ],
      ),
      textScale: 2,
      size: const Size(320, 900),
    ));

    final horizontalScroll = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScroll, findsOneWidget);
    for (final header in ['Metric', 'LMTD', 'MTD', 'Growth', 'YTD']) {
      expect(find.text(header), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('executive matrix freezes metric and keeps two Growth columns',
      (tester) async {
    final rows = [
      {
        'metric': 'Revenue Prepaid with a long readable metric name',
        'llmtd': '90',
        'lmtd': '100',
        'mtd': '110',
        'growth_mom': '+10.0%',
        'var_mom': '▲ 10',
        'lytd': '900',
        'ytd': '990',
        'growth_yoy': '+10.0%',
        'var_yoy': '▲ 90',
      },
    ];
    await tester.pumpWidget(_app(
      ReportAllDataTable<Map<String, String>>(
        rows: rows,
        layoutPolicy: ReportTableLayoutPolicy.horizontal,
        freezeFirstColumn: true,
        storageKey: 'frozen-executive-test',
        columns: [
          ReportTableColumn(
              label: 'Metric', width: 158, value: (row) => row['metric']),
          ReportTableColumn(label: 'LLMTD', value: (row) => row['llmtd']),
          ReportTableColumn(label: 'LMTD', value: (row) => row['lmtd']),
          ReportTableColumn(label: 'MTD', value: (row) => row['mtd']),
          ReportTableColumn(
            label: 'Growth',
            semanticLabel: 'Growth MTD terhadap LMTD',
            value: (row) => row['growth_mom'],
            secondaryValue: (row) => row['var_mom'],
          ),
          ReportTableColumn(label: 'LYTD', value: (row) => row['lytd']),
          ReportTableColumn(label: 'YTD', value: (row) => row['ytd']),
          ReportTableColumn(
            label: 'Growth',
            semanticLabel: 'Growth YTD terhadap LYTD',
            value: (row) => row['growth_yoy'],
            secondaryValue: (row) => row['var_yoy'],
          ),
        ],
      ),
      textScale: 2,
      size: const Size(320, 900),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Growth'), findsNWidgets(2));
    expect(find.text('▲ 10'), findsOneWidget);
    expect(find.text('▲ 90'), findsOneWidget);
    final metricFinder =
        find.text('Revenue Prepaid with a long readable metric name');
    final lmtdFinder = find.text('100');
    final metricX = tester.getTopLeft(metricFinder).dx;
    final lmtdX = tester.getTopLeft(lmtdFinder).dx;
    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    await tester.drag(horizontal, const Offset(-420, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(metricFinder).dx, metricX);
    expect(tester.getTopLeft(lmtdFinder).dx, lessThan(lmtdX));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter controls preserve content reachability', (tester) async {
    var expanded = false;
    await tester.pumpWidget(_app(
      StatefulBuilder(builder: (context, setState) {
        return ReportChapter(
          title: 'Revenue',
          summary: '12 metrics',
          expanded: expanded,
          onExpansionChanged: (value) => setState(() => expanded = value),
          child: const Text('Full revenue table'),
        );
      }),
    ));

    expect(find.text('Full revenue table'), findsNothing);
    await tester.tap(find.text('Revenue'));
    await tester.pumpAndSettle();
    expect(find.text('Full revenue table'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('report foundations lay out across the viewport matrix',
      (tester) async {
    const sizes = [
      Size(320, 720),
      Size(360, 800),
      Size(412, 915),
      Size(600, 960),
      Size(1024, 600),
    ];
    for (final size in sizes) {
      for (final textScale in [1.0, 2.0]) {
        await tester.pumpWidget(_app(
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ReportContextBar(values: [
              ReportContextValue(
                label: 'View',
                value: 'Comprehensive',
                icon: Icons.analytics_outlined,
              ),
              ReportContextValue(
                label: 'Scope',
                value: 'Central Java',
                icon: Icons.location_on_outlined,
              ),
            ]),
            SizedBox(height: 12),
            ReportChapterNavigator(
              chapters: [
                ReportChapterLink(id: 'revenue', label: 'Revenue'),
                ReportChapterLink(id: 'network', label: 'Network'),
                ReportChapterLink(id: 'attributes', label: 'All Attributes'),
              ],
              onSelected: _ignoreChapter,
            ),
          ]),
          size: size,
          textScale: textScale,
          themeMode: size.width == 600 ? ThemeMode.dark : ThemeMode.light,
        ));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Failed at ${size.width}x${size.height}, scale $textScale',
        );
      }
    }
  });
}

void _ignoreChapter(String _) {}
