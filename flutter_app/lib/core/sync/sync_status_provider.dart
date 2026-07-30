import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/database_provider.dart';
import '../database/tables.dart';
import '../widgets/sync_status_widget.dart';

/// Maps Drift sync-queue rows → AppBar [SyncState].
final syncStatusProvider = StreamProvider<SyncState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.syncQueueItems)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(20))
      .watch()
      .map(syncStateFromRows);
});

SyncState syncStateFromRows(List<SyncQueueItem> rows) {
  if (rows.any((r) => r.status == SyncOpStatus.syncing)) return SyncState.syncing;
  if (rows.any((r) => r.status == SyncOpStatus.pending || r.status == SyncOpStatus.failed)) {
    return SyncState.savedLocally;
  }
  if (rows.isNotEmpty && rows.every((r) => r.status == SyncOpStatus.synced)) return SyncState.synced;
  return SyncState.savedLocally;
}
