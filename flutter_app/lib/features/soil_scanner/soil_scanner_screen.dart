import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/database/database_provider.dart';
import '../../core/database/tables.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/repos/field_repo.dart';
import '../../data/repos/sync_worker.dart';

/// Camera viewfinder placeholder — queues soil SHC values and flushes to
/// `POST /fields/{id}/soil-override` when the API is reachable.
class SoilScannerScreen extends ConsumerStatefulWidget {
  const SoilScannerScreen({super.key});

  @override
  ConsumerState<SoilScannerScreen> createState() => _SoilScannerScreenState();
}

class _SoilScannerScreenState extends ConsumerState<SoilScannerScreen> {
  bool _capturing = false;
  String? _lastMessage;

  Future<void> _capture() async {
    setState(() {
      _capturing = true;
      _lastMessage = null;
    });

    final field = await ref.read(activeFieldProvider.future);
    final db = ref.read(appDatabaseProvider);
    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            kind: 'soil_card_ocr',
            payloadJson: jsonEncode({
              'field_id': field?.id,
              'n_kg_ha': 180,
              'p_kg_ha': 45,
              'k_kg_ha': 90,
              'ph': 6.4,
              'oc_pct': 0.62,
              'source': 'camera_placeholder',
            }),
            status: SyncOpStatus.pending,
          ),
        );

    if (Env.isApiConfigured) {
      await ref.read(syncWorkerProvider).flush();
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _capturing = false;
      _lastMessage = Env.isApiConfigured
          ? (field == null
              ? 'Queued locally — waiting for field bootstrap'
              : 'Soil override synced to backend')
          : 'Card saved locally — will sync N/P/K/pH when API_BASE_URL is set';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Soil Health Card', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Align the government card in the frame, then capture.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.soilBrown,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.terracotta, width: 3),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.document_scanner_outlined, size: 96, color: AppColors.cream.withValues(alpha: 0.35)),
                    Positioned(
                      top: 24,
                      left: 24,
                      right: 24,
                      bottom: 24,
                      child: CustomPaint(painter: _ViewfinderPainter()),
                    ),
                    if (_capturing) const CircularProgressIndicator(color: AppColors.cream),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _capturing ? null : _capture,
              icon: const Icon(Icons.camera_alt, size: 28),
              label: Text(_capturing ? 'Capturing…' : 'Capture card'),
            ),
          ),
          if (_lastMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _lastMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.deepGreen),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.cream
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const len = 28.0;
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, len), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - len), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - len, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - len), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
