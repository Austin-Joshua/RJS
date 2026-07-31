import 'package:flutter_app/features/farms/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rupees use Indian digit grouping', () {
    // A farmer reads these; ₹1,42,000 parses faster than ₹142,000.
    expect(formatRs(142000), '₹1,42,000');
    expect(formatRs(9840), '₹9,840');
    expect(formatRs(500), '₹500');
    expect(formatRs(12142000), '₹1,21,42,000');
    expect(formatRs(-6307), '-₹6,307');
    expect(formatRs(null), '—');
  });

  test('crop and season codes render as words', () {
    expect(cropLabel('black_gram'), 'Black gram');
    expect(cropLabel('paddy'), 'Paddy');
    expect(seasonLabel('kharif'), 'Kharif');
    // An unknown code degrades to something readable rather than crashing.
    expect(cropLabel('finger_millet'), 'finger millet');
  });

  test('nutrient keys shorten to their symbols', () {
    expect(nutrientLabel('n_kg_ha'), 'N');
    expect(nutrientLabel('p_kg_ha'), 'P');
    expect(nutrientLabel('k_kg_ha'), 'K');
  });
}
