import 'package:flutter_app/features/farms/soil_card_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a typical Soil Health Card block', () {
    const sample = '''
Soil Health Card
Farmer Name: Ramasamy
Soil Type: Clay Loam
Available Nitrogen (N) 245 kg/ha
Available Phosphorus (P) 17.0 kg/ha
Available Potassium (K) 205 kg/ha
Organic Carbon (OC) 0.58 %
pH 6.7
EC (dS/m) 0.5
''';
    final r = parseSoilCardText(sample);
    expect(r.nKgHa, 245);
    expect(r.pKgHa, 17);
    expect(r.kKgHa, 205);
    expect(r.ph, 6.7);
    expect(r.ocPct, 0.58);
    expect(r.ecDsM, 0.5);
    expect(r.soilType, 'clay_loam');
    expect(r.farmName, 'Ramasamy');
    expect(r.hasRequired, isTrue);
  });

  test('prefers clay loam over clay', () {
    final r = parseSoilCardText('Soil type: Clay loam\npH: 7.1\nN: 300\nP: 22\nK: 260');
    expect(r.soilType, 'clay_loam');
    expect(r.ph, 7.1);
  });

  test('returns empty match when text has no nutrients', () {
    final r = parseSoilCardText('hello from a blurry photo');
    expect(r.hasRequired, isFalse);
    expect(r.fieldCount, 0);
  });
}
