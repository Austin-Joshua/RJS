import 'package:flutter/material.dart';

import '../api/client.dart';
import '../i18n/translations.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/staggered_entrance.dart';
import 'create_parcel_screen.dart';

/// Consultant-only screen listing all parcels with health badges,
/// assigned landowner info, and navigation to the create-parcel flow.
class ParcelsListScreen extends StatefulWidget {
  const ParcelsListScreen({
    super.key,
    required this.locale,
    required this.session,
    required this.apiClient,
    required this.onParcelSelected,
  });

  final LocaleCode locale;
  final Session session;
  final ApiClient apiClient;
  final VoidCallback onParcelSelected;

  @override
  State<ParcelsListScreen> createState() => _ParcelsListScreenState();
}

class _ParcelsListScreenState extends State<ParcelsListScreen> {
  List<Map<String, dynamic>> _parcels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadParcels();
  }

  Future<void> _loadParcels() async {
    setState(() => _loading = true);
    await widget.apiClient.refreshParcels(widget.session);
    final list = await widget.apiClient.fetchParcelsList(widget.session);
    if (!mounted) return;
    setState(() {
      _parcels = list;
      _loading = false;
    });
  }

  Future<void> _openCreateParcel() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CreateParcelScreen(
          locale: widget.locale,
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
    if (ok == true && mounted) {
      _loadParcels();
      widget.onParcelSelected();
    }
  }

  Color _badgeColor(String? label) {
    switch (label?.toLowerCase()) {
      case 'healthy':
        return Colors.green.shade700;
      case 'moderate':
        return Colors.orange.shade800;
      case 'at risk':
        return Colors.red.shade800;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return RefreshIndicator(
      onRefresh: _loadParcels,
      child: _loading
          ? Center(
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
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              children: [
                StaggeredEntrance(
                  index: 0,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t(widget.locale, 'parcelsList'),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_parcels.length} ${t(widget.locale, 'parcelCount')}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _openCreateParcel,
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: Text(t(widget.locale, 'createParcel')),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                StaggeredEntrance(
                  index: 1,
                  child: Text(
                    t(widget.locale, 'parcelsListConsultantHint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_parcels.isEmpty)
                  StaggeredEntrance(
                    index: 2,
                    child: AppCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.landscape_rounded,
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
                  )
                else
                  ..._parcels.asMap().entries.map((entry) {
                    final i = entry.key;
                    final p = entry.value;
                    final id = p['id'] as String? ?? '';
                    final name = p['name'] as String? ?? id;
                    final badge = p['health_badge'] as String?;
                    final score = p['health_score'];
                    final ownerEmail = p['owner_email'] as String?;
                    final ownerPhone = p['owner_phone'] as String?;
                    final isSelected = widget.apiClient.parcelId == id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: StaggeredEntrance(
                        index: 2 + i,
                        child: GestureDetector(
                          onTap: () async {
                            await widget.apiClient.selectParcel(id);
                            widget.onParcelSelected();
                            if (mounted) setState(() {});
                          },
                          child: AppCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primaryContainer
                                        : theme.colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isSelected
                                        ? Border.all(
                                            color: theme.colorScheme.primary,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Icon(
                                    Icons.landscape_rounded,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : muted,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (ownerEmail != null ||
                                          ownerPhone != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.person_outline_rounded,
                                              size: 14,
                                              color: muted,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                ownerEmail ??
                                                    ownerPhone ??
                                                    '',
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(color: muted),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (score != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '${t(widget.locale, 'score')}: $score',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: muted),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (badge != null) ...[
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _badgeColor(badge)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      badge,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                        color: _badgeColor(badge),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
