import 'package:bizplan_java_agent/src/format/report_format.dart';
import 'package:bizplan_java_agent/src/theme.dart';
import 'package:bizplan_java_agent/src/widgets/report_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Size size = const Size(400, 900)}) => MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: child),
      ),
    );

ReportPeriodRow _row({
  required String name,
  required String code,
  required num growth,
}) =>
    ReportPeriodRow(
      name: name,
      code: code,
      cells: {
        'llmtd': const ReportPeriodCell('100'),
        'lmtd': const ReportPeriodCell('110'),
        'mtd': const ReportPeriodCell('120'),
        'growthMom': ReportPeriodCell(
          reportPercent(growth, signed: true),
          secondaryText: reportVariance(growth),
          raw: growth,
        ),
        'lytd': const ReportPeriodCell('900'),
        'ytd': const ReportPeriodCell('980'),
        'growthYoy': ReportPeriodCell(
          reportPercent(growth, signed: true),
          raw: growth,
        ),
      },
    );

Color _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).style!.color!;

void main() {
  testWidgets('period table renders every period column once', (tester) async {
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: [_row(name: 'Revenue Prepaid', code: 'rev_prepaid', growth: 4.2)],
      band: Brands.ioh,
      storageKey: 'test-periods',
    )));

    expect(find.text('LLMTD'), findsOneWidget);
    expect(find.text('LMTD'), findsOneWidget);
    expect(find.text('MTD'), findsOneWidget);
    expect(find.text('LYTD'), findsOneWidget);
    expect(find.text('YTD'), findsOneWidget);
    // Two Growth headers: one for MoM, one for YoY.
    expect(find.text('Growth'), findsNWidgets(2));
    expect(find.text('Revenue Prepaid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('growth is green when a higher-is-better metric rises',
      (tester) async {
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: [_row(name: 'Revenue Prepaid', code: 'rev_prepaid', growth: 4.2)],
      band: Brands.ioh,
      storageKey: 'test-up',
    )));

    expect(_colorOf(tester, '+4,2%'), IOH.teal600);
  });

  testWidgets('growth is red when a higher-is-better metric falls',
      (tester) async {
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: [_row(name: 'Revenue Prepaid', code: 'rev_prepaid', growth: -3.1)],
      band: Brands.ioh,
      storageKey: 'test-down',
    )));

    expect(_colorOf(tester, '-3,1%'), IOH.danger);
  });

  testWidgets('churn rising is red even though the number is positive',
      (tester) async {
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: [_row(name: 'Gross Churn 90D', code: 'gross_churn_90d', growth: 6.5)],
      band: Brands.ioh,
      storageKey: 'test-churn',
    )));

    // Polarity, not sign: churn up is bad news.
    expect(_colorOf(tester, '+6,5%'), IOH.danger);
  });

  testWidgets('extra column carries its own header label', (tester) async {
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: [
        ReportPeriodRow(
          name: 'Digital',
          code: 'rev_channel',
          cells: const {
            'mtd': ReportPeriodCell('120'),
            'extra': ReportPeriodCell('42,0%'),
          },
        ),
      ],
      band: Brands.im3,
      storageKey: 'test-extra',
      columns: const [ReportPeriodColumn.mtd, ReportPeriodColumn.extra],
      extraLabel: 'Contrib %',
    )));

    expect(find.text('Contrib %'), findsOneWidget);
    expect(find.text('42,0%'), findsOneWidget);
  });

  testWidgets('missing cells stay N/A instead of blank', (tester) async {
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: const [
        ReportPeriodRow(name: 'Sparse', code: 'rev_x', cells: {}),
      ],
      band: Brands.ioh,
      storageKey: 'test-sparse',
      columns: const [ReportPeriodColumn.mtd],
    )));

    expect(find.text(kReportNotAvailable), findsOneWidget);
  });

  testWidgets('expandable row reports its key when tapped', (tester) async {
    String? tapped;
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: const [
        ReportPeriodRow(
          name: 'Modern Channel',
          code: 'rev_channel',
          expandKey: 'chunk|modern',
          cells: {'mtd': ReportPeriodCell('120')},
        ),
      ],
      band: Brands.ioh,
      storageKey: 'test-expand',
      columns: const [ReportPeriodColumn.mtd],
      onToggleRow: (key) => tapped = key,
    )));

    await tester.tap(find.textContaining('Modern Channel'));
    await tester.pump();
    expect(tapped, 'chunk|modern');
  });

  testWidgets('a headline row reads bold across every column', (tester) async {
    await tester.pumpWidget(_host(ReportPeriodTable(
      rows: const [
        ReportPeriodRow(
          name: 'TOTAL',
          code: 'rev_channel',
          headline: true,
          cells: {'llmtd': ReportPeriodCell('120')},
        ),
        ReportPeriodRow(
          name: 'Digital',
          code: 'rev_channel',
          cells: {'llmtd': ReportPeriodCell('45')},
        ),
      ],
      band: Brands.ioh,
      storageKey: 'test-headline',
      // LLMTD is not emphasized by default, so any bold here comes from the
      // headline flag alone.
      columns: const [ReportPeriodColumn.llmtd],
    )));

    final total = tester.widget<Text>(find.text('120').first);
    final detail = tester.widget<Text>(find.text('45').first);
    expect(total.style!.fontWeight, FontWeight.w700);
    expect(detail.style!.fontWeight, FontWeight.w400);
  });
}
