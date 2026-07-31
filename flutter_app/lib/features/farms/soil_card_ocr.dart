import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/models/farm_models.dart';

/// Values pulled from a Soil Health Card / lab-report photo.
class SoilCardOcrResult {
  const SoilCardOcrResult({
    this.nKgHa,
    this.pKgHa,
    this.kKgHa,
    this.ph,
    this.ocPct,
    this.ecDsM,
    this.soilType,
    this.farmName,
    this.rawText = '',
    this.matchedLabels = const [],
  });

  final double? nKgHa;
  final double? pKgHa;
  final double? kKgHa;
  final double? ph;
  final double? ocPct;
  final double? ecDsM;
  final String? soilType;
  final String? farmName;
  final String rawText;
  final List<String> matchedLabels;

  bool get hasRequired => nKgHa != null && pKgHa != null && kKgHa != null && ph != null;

  int get fieldCount => [
        nKgHa,
        pKgHa,
        kKgHa,
        ph,
        ocPct,
        ecDsM,
        soilType,
      ].where((v) => v != null).length;
}

String _normalizeOcrText(String text) {
  return text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[|]+'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}')
      .replaceAll(RegExp(r'(?<=\d)O(?=\d)'), '0')
      .replaceAll(RegExp(r'(?<=\d)l(?=\d)'), '1');
}

double? _parseNum(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return double.tryParse(raw.replaceAll(',', '.').trim());
}

/// Pure parser — no camera, no ML Kit. Unit-tested against SHC-style text.
SoilCardOcrResult parseSoilCardText(String text) {
  final normalized = _normalizeOcrText(text);
  final lower = normalized.toLowerCase();
  final matched = <String>[];

  double? pick(List<RegExp> patterns, String label, {double? min, double? max}) {
    for (final re in patterns) {
      final m = re.firstMatch(lower) ?? re.firstMatch(normalized);
      if (m == null) continue;
      final raw = m.group(1) ?? m.group(2);
      final v = _parseNum(raw);
      if (v == null) continue;
      if (min != null && v < min) continue;
      if (max != null && v > max) continue;
      matched.add(label);
      return v;
    }
    return null;
  }

  // pH before P — avoids "P" patterns stealing from nearby lines.
  final ph = pick([
    RegExp(r'\bp\s*h\s*[:=\-]?\s*(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'soil\s*p\s*h[^0-9]{0,16}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'ph\s*value[^0-9]{0,12}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'reaction\s*\(?\s*ph\s*\)?[^0-9]{0,12}(\d+(?:\.\d+)?)', caseSensitive: false),
  ], 'pH', min: 0, max: 14);

  final n = pick([
    RegExp(r'available\s*nitrogen[^0-9]{0,40}?(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'avail\.?\s*n(?:itrogen)?[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'\bn\s*\(?\s*kg/?ha\s*\)?[^0-9]{0,16}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'nitrogen\s*\(?\s*n\s*\)?[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'(?<![a-z])\bn\s*[:=\-]\s*(\d+(?:\.\d+)?)\s*(?:kg/?ha)?', caseSensitive: false),
  ], 'N', min: 0, max: 2000);

  final p = pick([
    RegExp(r'available\s*phosphorus[^0-9]{0,40}?(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'avail\.?\s*p(?:hosphorus)?[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'\bp\s*\(?\s*kg/?ha\s*\)?[^0-9]{0,16}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'phosphorus\s*\(?\s*p\s*\)?[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'(?<![a-z])\bp\s*[:=\-]\s*(\d+(?:\.\d+)?)\s*(?:kg/?ha)?', caseSensitive: false),
  ], 'P', min: 0, max: 500);

  final k = pick([
    RegExp(r'available\s*potassium[^0-9]{0,40}?(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'avail\.?\s*k(?:potassium)?[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'\bk\s*\(?\s*kg/?ha\s*\)?[^0-9]{0,16}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'potassium\s*\(?\s*k\s*\)?[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'(?<![a-z])\bk\s*[:=\-]\s*(\d+(?:\.\d+)?)\s*(?:kg/?ha)?', caseSensitive: false),
  ], 'K', min: 0, max: 2000);

  final oc = pick([
    RegExp(r'organic\s*carbon[^0-9]{0,32}?(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'\boc\s*[:=\-]?\s*(\d+(?:\.\d+)?)\s*%?', caseSensitive: false),
    RegExp(r'carbon\s*\(?\s*oc\s*\)?[^0-9]{0,16}(\d+(?:\.\d+)?)', caseSensitive: false),
  ], 'OC', min: 0, max: 10);

  final ec = pick([
    RegExp(r'electrical\s*conductivity[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'\bec\s*(?:\(?\s*d\s*s\s*/?\s*m\s*\)?)?\s*[:=\-]?\s*(\d+(?:\.\d+)?)',
        caseSensitive: false),
    RegExp(r'salinity[^0-9]{0,24}(\d+(?:\.\d+)?)', caseSensitive: false),
  ], 'EC', min: 0, max: 50);

  // Table row: N P K OC pH on one line (common on printed SHC).
  var nOut = n;
  var pOut = p;
  var kOut = k;
  var phOut = ph;
  var ocOut = oc;
  for (final line in normalized.split(RegExp(r'[\r\n]+'))) {
    final row = RegExp(
      r'^\s*(\d{2,4})\s+(\d{1,3}(?:\.\d+)?)\s+(\d{2,4})\s+(\d(?:\.\d+)?)\s+(\d(?:\.\d+)?)\s*$',
    ).firstMatch(line.trim());
    if (row != null) {
      nOut ??= _parseNum(row.group(1));
      pOut ??= _parseNum(row.group(2));
      kOut ??= _parseNum(row.group(3));
      ocOut ??= _parseNum(row.group(4));
      phOut ??= _parseNum(row.group(5));
      if (nOut != null && !matched.contains('N')) matched.add('N');
      if (pOut != null && !matched.contains('P')) matched.add('P');
      if (kOut != null && !matched.contains('K')) matched.add('K');
      if (ocOut != null && !matched.contains('OC')) matched.add('OC');
      if (phOut != null && !matched.contains('pH')) matched.add('pH');
      break;
    }
  }

  // Longest label first so "clay loam" wins over "clay".
  String? soilType;
  final types = soilTypeOptions.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final e in types) {
    final name = e.value.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim();
    final key = e.key.replaceAll('_', ' ');
    if (lower.contains(name) || lower.contains(key)) {
      soilType = e.key;
      break;
    }
  }
  if (soilType != null) matched.add('soil type');

  String? farmName;
  final nameMatch = RegExp(
    r'(?:farmer|farm|field|plot)\s*name\s*[:=\-]?\s*([A-Za-z0-9 ._-]{3,40})',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (nameMatch != null) {
    farmName = nameMatch.group(1)?.trim();
    if (farmName != null && farmName.isNotEmpty) matched.add('name');
  }

  return SoilCardOcrResult(
    nKgHa: nOut,
    pKgHa: pOut,
    kKgHa: kOut,
    ph: phOut,
    ocPct: ocOut,
    ecDsM: ec,
    soilType: soilType,
    farmName: farmName,
    rawText: text.trim(),
    matchedLabels: matched,
  );
}

/// Runs on-device OCR (Google ML Kit) then [parseSoilCardText].
class SoilCardOcrScanner {
  SoilCardOcrScanner({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<SoilCardOcrResult> scanFile(File file) async {
    if (!file.existsSync()) {
      throw StateError('Image file not found — try picking the photo again.');
    }
    final input = InputImage.fromFile(file);
    final recognized = await _recognizer.processImage(input);
    final text = recognized.text.trim();
    if (text.isEmpty) {
      throw StateError('No text detected. Use a sharper, well-lit photo of the Soil Health Card.');
    }
    return parseSoilCardText(text);
  }

  void dispose() {
    _recognizer.close();
  }
}
