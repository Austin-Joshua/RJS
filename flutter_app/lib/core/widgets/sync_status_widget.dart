import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_status_provider.dart';
import '../theme.dart';

/// Persistent AppBar offline/sync indicator — driven by Drift sync queue.
enum SyncState { savedLocally, syncing, synced }

class SyncStatusWidget extends ConsumerWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncStatusProvider);
    final state = async.asData?.value ?? SyncState.savedLocally;

    final (icon, label, accent) = switch (state) {
      SyncState.savedLocally => (Icons.save_outlined, 'Saved locally', AppColors.soilBrown),
      SyncState.syncing => (Icons.sync, 'Syncing…', AppColors.terracotta),
      SyncState.synced => (Icons.cloud_done_outlined, 'Synced', AppColors.deepGreen),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Chip(
        avatar: Icon(icon, size: 18, color: accent),
        label: Text(label, style: TextStyle(fontSize: 14, color: accent)),
        backgroundColor: AppColors.cream,
        side: BorderSide(color: accent.withValues(alpha: 0.4)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
