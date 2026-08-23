import 'package:flutter/material.dart';
import 'package:bizplan_java_agent/src/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brand lookup normalizes every spelling seen in payloads', () {
    expect(Brands.of('IOH'), Brands.ioh);
    expect(Brands.of('Indosat'), Brands.ioh);
    expect(Brands.of('im3'), Brands.im3);
    expect(Brands.of('3ID'), Brands.tri);
    expect(Brands.of('tri'), Brands.tri);
    expect(Brands.of('TSEL'), Brands.tsel);
    expect(Brands.of('Telkomsel'), Brands.tsel);
    // XL and SF are one commercial operator.
    expect(Brands.of('xl'), Brands.xlsmart);
    expect(Brands.of('SF'), Brands.xlsmart);
    expect(Brands.of('Smartfren'), Brands.xlsmart);
    expect(Brands.of('XLSMART'), Brands.xlsmart);
    expect(Brands.of('Industry'), Brands.industry);
  });

  test('brand colours follow the agreed identity', () {
    expect(Brands.ioh.color, const Color(0xFF15A697)); // teal
    expect(Brands.im3.color, const Color(0xFFF5A623)); // orange
    expect(Brands.tri.color, const Color(0xFFEB008B)); // magenta
    expect(Brands.tsel.color, const Color(0xFFE13838)); // red
    expect(Brands.xlsmart.color, const Color(0xFF1B6FD4)); // blue
  });

  test('unknown brand degrades to a neutral identity without throwing', () {
    final unknown = Brands.of('SOMEONE ELSE');
    expect(unknown.label, 'SOMEONE ELSE');
    expect(Brands.all.contains(unknown), isFalse);
    expect(Brands.of(null).label, '');
  });
}
