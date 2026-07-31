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

/// Pure parser — no camera, no ML Kit. Unit-tested against SHC-style text.
SoilCardOcrResult parseSoilCardText(String text) {
  final normalized = text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[|]+'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ');
  final lower = normalized.toLowerCase();
  final matched = <String>[];

  double? pick(List<RegExp> patterns, String label, {double? min, double? max}) {
    for (final re in patterns) {
      final m = re.firstMatch(lower) ?? re.firstMatch(normalized);
      if (m == null) continue;
      final raw = m.group(1) ?? m.group(2);
      if (raw == null) continue;
      final v = double.tryParse(raw.replaceAll(',', '.'));
      if (v == null) continue;
      if (min != null && v < min) continue;
      if (max != null && v > max) continue;
      matched.add(label);
      return v;
    }
    return null;
  }

  // Nitrogen — SHC often prints "Available Nitrogen (N)" then kg/ha value.
  final n = pick([
    RegExp(r'available\s*nitrogen[^0-9]{0,40}?(\d+(?:[.,]\d+)?)', caseSensitive: false),
    RegExp(r'\bn\s*[:=\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:kg/?ha)?', caseSensitive: false),
    RegExp(r'nitrogen\s*\(?\s*n\s*\)?[^0-9]{0,24}(\d+(?:[.,]\d+)?)', caseSensitive: false),
  ], 'N', min: 0, max: 2000);

  final p = pick([
    RegExp(r'available\s*phosphorus[^0-9]{0,40}?(\d+(?:[.,]\d+)?)', caseSensitive: false),
    RegExp(r'\bp\s*[:=\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:kg/?ha)?', caseSensitive: false),
    RegExp(r'phosphorus\s*\(?\s*p\s*\)?[^0-9]{0,24}(\d+(?:[.,]\d+)?)', caseSensitive: false),
  ], 'P', min: 0, max: 500);

  final k = pick([
    RegExp(r'available\s*potassium[^0-9]{0,40}?(\d+(?:[.,]\d+)?)', caseSensitive: false),
    RegExp(r'\bk\s*[:=\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:kg/?ha)?', caseSensitive: false),
    RegExp(r'potassium\s*\(?\s*k\s*\)?[^0-9]{0,24}(\d+(?:[.,]\d+)?)', caseSensitive: false),
  ], 'K', min: 0, max: 2000);

  final ph = pick([
    RegExp(r'\bp\s*h\s*[:=\-]?\s*(\d+(?:[.,]\d+)?)', caseSensitive: false),
    RegExp(r'soil\s*p\s*h[^0-9]{0,16}(\d+(?:[.,]\d+)?)', caseSensitive: false),
  ], 'pH', min: 0, max: 14);

  final oc = pick([
    RegExp(r'organic\s*carbon[^0-9]{0,32}?(\d+(?:[.,]\d+)?)', caseSensitive: false),
    RegExp(r'\boc\s*[:=\-]?\s*(\d+(?:[.,]\d+)?)\s*%?', caseSensitive: false),
  ], 'OC', min: 0, max: 10);

  final ec = pick([
    RegExp(r'electrical\s*conductivity[^0-9]{0,24}(\d+(?:[.,]\d+)?)', caseSensitive: false),
    RegExp(r'\bec\s*(?:\(?\s*d\s*s\s*/?\s*m\s*\)?)?\s*[:=\-]?\s*(\d+(?:[.,]\d+)?)',
        caseSensitive: false),
    RegExp(r'salinity[^0-9]{0,24}(\d+(?:[.,]\d+)?)', caseSensitive: false),
  ], 'EC', min: 0, max: 50);

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
    nKgHa: n,
    pKgHa: p,
    kKgHa: k,
    ph: ph,
    ocPct: oc,
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
    final input = InputImage.fromFile(file);
    final recognized = await _recognizer.processImage(input);
    return parseSoilCardText(recognized.text);
  }

  void dispose() {
    // Fire-and-forget; TextRecognizer.close is async but dispose cannot await.
    _recognizer.close();
  }
}
