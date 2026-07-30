import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

final ttsProvider = Provider<FlutterTts>((ref) {
  final tts = FlutterTts();
  tts.setLanguage('en-IN');
  tts.setSpeechRate(0.45);
  ref.onDispose(tts.stop);
  return tts;
});

/// Demo advisory text until Drift/backend advisory is wired.
const demoAdvisoryText =
    'Apply 2 bags urea, 1 bag DAP, and 1 bag MOP per hectare. '
    'Soil pH is slightly acidic — apply 0.5 tonnes lime per hectare. '
    'Net irrigation need is 45 millimetres after rainfall.';
