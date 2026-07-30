import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../api/client.dart';
import '../i18n/translations.dart';
import '../models/session.dart';
import '../widgets/app_card.dart';
import '../widgets/staggered_entrance.dart';

/// Standalone Document Vault screen — shows parcel documents and GIS report
/// download. Read-only for landowners; identical view for consultants when
/// accessed from the Parcels tab.
class DocumentVaultScreen extends StatefulWidget {
  const DocumentVaultScreen({
    super.key,
    required this.locale,
    required this.session,
    required this.apiClient,
  });

  final LocaleCode locale;
  final Session session;
  final ApiClient apiClient;

  @override
  State<DocumentVaultScreen> createState() => _DocumentVaultScreenState();
}

class _DocumentVaultScreenState extends State<DocumentVaultScreen> {
  late Future<_VaultData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant DocumentVaultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.apiClient.resolvedApiBaseUrl !=
            widget.apiClient.resolvedApiBaseUrl) {
      _future = _load();
    }
  }

  Future<_VaultData> _load() async {
    await widget.apiClient.refreshParcels(widget.session);
    if (!widget.apiClient.hasSelectedParcel) {
      return _VaultData.noParcel();
    }
    try {
      final docs = await widget.apiClient.listDocuments(widget.session);
      return _VaultData(documentsResponse: docs);
    } catch (_) {
      return _VaultData(documentsResponse: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return FutureBuilder<_VaultData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: AppCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t(widget.locale, 'loading'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final data =
            snapshot.hasData ? snapshot.data! : _VaultData.noParcel();

        if (data.noParcel) {
          return Center(
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_off_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(widget.locale, 'noParcelsAssigned'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          );
        }

        final docs =
            data.documentsResponse?['documents'] as List<dynamic>? ?? [];

        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = _load());
            await _future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            children: [
              StaggeredEntrance(
                index: 0,
                child: Text(
                  t(widget.locale, 'documentVault'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              StaggeredEntrance(
                index: 1,
                child: widget.session.isLandowner
                    ? Material(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.visibility_rounded,
                                size: 18,
                                color: Color(0xFF2E7D32),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                t(widget.locale, 'readOnly'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              // GIS Report
              StaggeredEntrance(
                index: 2,
                child: AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t(widget.locale, 'downloadGisReport'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _downloadGisReport(context),
                        child: const Icon(Icons.download_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Document listing
              if (docs.isEmpty)
                StaggeredEntrance(
                  index: 3,
                  child: AppCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          size: 40,
                          color: muted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t(widget.locale, 'noDocuments'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...docs.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value as Map<String, dynamic>;
                  final id = m['id'] as String? ?? '';
                  final title = m['title'] as String? ?? id;
                  final mime = m['mime_type'] as String? ?? '';

                  IconData docIcon;
                  if (mime.contains('pdf')) {
                    docIcon = Icons.picture_as_pdf_rounded;
                  } else if (mime.contains('image')) {
                    docIcon = Icons.image_rounded;
                  } else {
                    docIcon = Icons.description_rounded;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: StaggeredEntrance(
                      index: 3 + i,
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(docIcon, color: theme.colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.download_rounded),
                              onPressed: () =>
                                  _downloadDocument(context, id, title),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadGisReport(BuildContext ctx) async {
    try {
      final bytes =
          await widget.apiClient.downloadGisSnapshotReport(widget.session);
      final dir = await getTemporaryDirectory();
      final name = 'gis-snapshot-${widget.apiClient.parcelId}.txt';
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('${t(widget.locale, 'gisReportSaved')}: $name'),
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _downloadDocument(
    BuildContext ctx,
    String docId,
    String docTitle,
  ) async {
    try {
      final bytes =
          await widget.apiClient.downloadDocument(widget.session, docId);
      final dir = await getTemporaryDirectory();
      final safe = docId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final f = File('${dir.path}/landroid-$safe');
      await f.writeAsBytes(bytes);
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(f.path)),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

class _VaultData {
  const _VaultData({this.documentsResponse, this.noParcel = false});
  final Map<String, dynamic>? documentsResponse;
  final bool noParcel;

  factory _VaultData.noParcel() => const _VaultData(noParcel: true);
}
