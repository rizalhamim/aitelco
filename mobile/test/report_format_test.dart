import 'package:bizplan_java_agent/src/format/report_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero decimals never emits a dangling separator', () {
    expect(reportPattern(0), '#,##0');
    expect(reportPattern(1), '#,##0.0');
    expect(reportNumber(3), '3');
    expect(reportNumber(3, decimals: 0), '3');
    expect(reportNumber(1234567), '1.234.567');
    expect(reportNumber(1234.5, decimals: 1), '1.234,5');
  });

  test('null stays N/A and observed zero stays zero', () {
    expect(reportNumber(null), kReportNotAvailable);
    expect(reportMagnitude(null), kReportNotAvailable);
    expect(reportPercent(null), kReportNotAvailable);
    expect(reportVariance(null), kReportNotAvailable);
    expect(reportNumber(0), '0');
    expect(reportMagnitude(0), '0');
    expect(reportPercent(0), '0,0%');
  });

  test('magnitude adapts between plain, thousand, million and billion', () {
    expect(reportMagnitude(742), '742');
    expect(reportMagnitude(12300), '12,3 Thousand');
    expect(reportMagnitude(850400000), '850,4 Mn');
    expect(reportMagnitude(1200000000), '1,2 Bn');
    expect(reportMagnitude(1250000, unit: 'IDR'), '1,3 Mn IDR');
    // Small revenue must not be forced into Bn.
    expect(reportMagnitude(4500000, unit: 'IDR'), '4,5 Mn IDR');
  });

  test('useThousand false keeps counts ungrouped below one million', () {
    expect(reportMagnitude(450, useThousand: false), '450');
    expect(reportMagnitude(12300, useThousand: false), '12.300');
    expect(reportMagnitude(2500000, useThousand: false), '2,5 Mn');
  });

  test('tier picks one scale for a whole column', () {
    final tier = reportMagnitudeTier(9.2e9, unit: 'IDR');
    expect(tier.divisor, 1e9);
    expect(tier.label, 'Bn IDR');
    expect(reportScaled(9200000000, tier.divisor), '9,2');
  });

  test('percent and variance use canonical glyphs', () {
    expect(reportPercent(12.34), '12,3%');
    expect(reportPercent(12.34, signed: true), '+12,3%');
    expect(reportPercent(-2.5, signed: true), '-2,5%');
    expect(reportVariance(-1234.5), '▼ 1.234,5');
    expect(reportVarianceMagnitude(2500000), '▲ 2,5 Mn');
  });

  test('polarity treats churn as lower is better and share as neutral', () {
    expect(reportPolarityFor('rev_prepaid'), ReportPolarity.higherIsBetter);
    expect(reportPolarityFor('fb_churn_im3'), ReportPolarity.lowerIsBetter);
    expect(reportPolarityFor('latency_im3_4g'), ReportPolarity.lowerIsBetter);
    expect(reportPolarityFor('fb_ms'), ReportPolarity.neutral);
    expect(reportPolarityFor('atl_contribution'), ReportPolarity.neutral);
  });

  test('key aware values keep identifiers ungrouped', () {
    expect(reportValueForKey('month_id', 202608), '202608');
    expect(reportValueForKey('site_id', 12345678), '12345678');
    expect(reportValueForKey('kec_id', 3578010), '3578010');
    // Coordinates keep dot decimals. They are geo notation, not a locale number.
    expect(reportValueForKey('lat', -7.2504512), '-7.25045');
    expect(reportValueForKey('rev_prepaid', 1250000), '1,3 Mn IDR');
    expect(reportValueForKey('vlr_daily', 450), '450');
    expect(reportValueForKey('growth_pct', -2.5), '-2,5%');
    expect(reportValueForKey('usg_data_gb', 1234.56), '1.234,6 GB');
    expect(reportValueForKey('latency_im3_4g', 38.42), '38,4 ms');
    expect(reportValueForKey('dl_speed_im3_4g', 21.7), '21,7 Mbps');
    expect(reportValueForKey('note', 12.3456), '12,3');
    expect(reportValueForKey('is_5g', true), 'Ya');
    expect(reportValueForKey('anything', null), kReportNotAvailable);
  });
}
