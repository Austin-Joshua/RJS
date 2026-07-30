import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/app/farmsync_app.dart';

void main() {
  runApp(const ProviderScope(child: FarmSyncApp()));
}
