import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// One [AppDatabase] instance for the app's lifetime. Repositories (fields,
/// plans, sync queue) build on top of this rather than opening their own
/// connections.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
