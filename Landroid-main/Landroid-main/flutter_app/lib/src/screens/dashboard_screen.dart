import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../api/client.dart';
import '../cache/landroid_disk_cache.dart';
import '../i18n/translations.dart';
import '../models/session.dart' show Session;
import '../widgets/app_card.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/why_score_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.locale,
    required this.session,
    required this.apiClient,
  });

  final LocaleCode locale;
  final Session session;
  final ApiClient apiClient;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _futureData;

  @override
  void initState() {
    super.initState();
    _futureData = _loadData();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.token != widget.session.token ||
        oldWidget.apiClient.resolvedApiBaseUrl !=
            widget.apiClient.resolvedApiBaseUrl) {
      _futureData = _loadData();
    }
  }

  Future<_DashboardData> _loadData({bool forceNetwork = false}) async {
    final api = widget.apiClient.resolvedApiBaseUrl;
    try {
      await widget.apiClient.refreshParcels(widget.session);
    } catch (_) {
      // If we can't even list parcels, show noParcel state rather than crash.
    }
    if (!widget.apiClient.hasSelectedParcel) {
      return _DashboardData.noParcel();
    }
    final pid = widget.apiClient.parcelId;

    if (!forceNetwork) {
      final cached = await DashboardDiskCache.read(api, pid);
      if (cached != null) {
        final lh = cached['landHealth'] as Map<String, dynamic>?;
        final inner = lh?['land_health'] as Map<String, dynamic>?;
        final mode = inner?['data_mode'] as String?;
        // Do not reuse cached demo rows if Earth Engine may now be online.
        if (mode != 'synthetic_demo') {
          Map<String, dynamic>? docs;
          try {
            docs = await widget.apiClient.listDocuments(widget.session);
          } catch (_) {}
          return _DashboardData(
            landHealth: cached['landHealth']! as Map<String, dynamic>,
            plantZones: cached['plantZones']! as Map<String, dynamic>,
            valuation: cached['valuation']! as Map<String, dynamic>,
            fromCache: true,
            documentsResponse: docs,
            landHealthError: null,
          );
        }
      }
    }

    String? landHealthError;
    Map<String, dynamic> landHealth = {};
    try {
      landHealth = await widget.apiClient.landHealth(widget.session);
    } catch (e) {
      landHealthError = e.toString();
    }

    final futures = await Future.wait([
      widget.apiClient.plantZones(widget.session).catchError((_) => <String, dynamic>{}),
      widget.apiClient.valuation(widget.session).catchError((_) => <String, dynamic>{}),
      widget.apiClient.listDocuments(widget.session).catchError((_) => <String, dynamic>{}),
    ]);

    final plantZones = futures[0];
    final valuation = futures[1];
    final documentsResponse = futures[2];

    // Only write to cache if we got at least some data
    if (landHealth.isNotEmpty || plantZones.isNotEmpty || valuation.isNotEmpty) {
      try {
        await DashboardDiskCache.write(
          api,
          widget.apiClient.parcelId,
          landHealth: landHealth,
          plantZones: plantZones,
          valuation: valuation,
        );
      } catch (_) {}
    }

    return _DashboardData(
      landHealth: landHealth,
      plantZones: plantZones,
      valuation: valuation,
      fromCache: false,
      documentsResponse: documentsResponse,
      landHealthError: landHealthError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return FutureBuilder<_DashboardData>(
      future: _futureData,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: AppCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t(widget.locale, 'loading'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fetching land intelligence…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          final errMsg = snapshot.hasError
              ? snapshot.error.toString()
              : t(widget.locale, 'apiError');
          return Center(
            child: AppCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t(widget.locale, 'apiError'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    errMsg,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _futureData = _loadData(forceNetwork: true);
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(t(widget.locale, 'retry')),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data!;
        if (data.noParcel) {
          return _buildNoParcelPlaceholder(theme, muted);
        }

        return widget.session.isLandowner
            ? _buildLandownerDashboard(data, theme, muted)
            : _buildConsultantDashboard(data, theme, muted);
      },
    );
  }

  // ─── No parcel placeholder ───

  Widget _buildNoParcelPlaceholder(ThemeData theme, Color muted) {
    final isConsultant = widget.session.isConsultant;
    final accent =
        isConsultant ? const Color(0xFF1565C0) : const Color(0xFF2E7D32);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    isConsultant
                        ? Icons.engineering_rounded
                        : Icons.cottage_outlined,
                    size: 52,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isConsultant
                      ? t(widget.locale, 'dashboardRoleStripConsultant')
                      : t(widget.locale, 'dashboardRoleStripLandowner'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isConsultant
                    ? t(widget.locale, 'noParcelsAssigned')
                    : t(widget.locale, 'noParcelForLandowner'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── LANDOWNER: read-only intelligence dashboard ───

  Widget _buildLandownerDashboard(
    _DashboardData data,
    ThemeData theme,
    Color muted,
  ) {
    final landHealth = data.landHealth['land_health'] as Map<String, dynamic>?;
    final plantZones = data.plantZones['plant_zones'] as Map<String, dynamic>?;
    final valuation = data.valuation['valuation'] as Map<String, dynamic>?;
    final score = landHealth?['score'];
    final label = landHealth?['label'] as String?;
    final signalCards = landHealth?['signal_cards'] as List<dynamic>?;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _futureData = _loadData(forceNetwork: true));
        await _futureData;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        children: [
          StaggeredEntrance(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(widget.locale, 'landownerDashboardTitle'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                // Read-only badge
                Material(
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
                          size: 20,
                          color: Color(0xFF2E7D32),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(widget.locale, 'dashboardRoleStripLandowner'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (data.landHealthError != null) ...[
            StaggeredEntrance(
              index: 15,
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  '${t(widget.locale, 'landHealthLoadFailed')}\n\n${data.landHealthError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Overall Health Score — prominent card ──
          StaggeredEntrance(
            index: 1,
            child: AppCard(
              liquidGlass: true,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _healthColor(label).withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${score ?? '-'}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _healthColor(label),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t(widget.locale, 'overallHealth'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _healthColor(label).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            label ?? '—',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _healthColor(label),
                            ),
                          ),
                        ),
                        if (landHealth != null && landHealth.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                showWhyScoreDialog(
                                  context,
                                  locale: widget.locale,
                                  landHealth: landHealth,
                                );
                              },
                              icon: const Icon(Icons.insights_rounded, size: 18),
                              label: Text(t(widget.locale, 'whyThisScoreTitle')),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── API-backed NDVI, rainfall, temperature, soil (same payload as /ai/.../land-health) ──
          if (landHealth != null && landHealth.isNotEmpty) ...[
            StaggeredEntrance(
              index: 2,
              child: _KeyMetricsSection(
                locale: widget.locale,
                landHealth: landHealth,
                theme: theme,
                muted: muted,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── FR-24 charts (NDVI monthly, rainfall, etc.) — backend signal_cards ──
          if (signalCards != null && signalCards.isNotEmpty) ...[
            StaggeredEntrance(
              index: 3,
              child: Text(
                t(widget.locale, 'chartsTitle'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...signalCards.asMap().entries.map((e) {
              final card = e.value as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StaggeredEntrance(
                  index: 4 + e.key,
                  child: _SignalCardChart(
                    locale: widget.locale,
                    card: card,
                    theme: theme,
                    muted: muted,
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],

          // ── Plant Zones ──
          StaggeredEntrance(
            index: 14,
            child: _MetricCard(
              title: t(widget.locale, 'plantZones'),
              children: [
                if (plantZones?['zones'] is Map<String, dynamic>) ...[
                  Text(
                    'Bare ${(plantZones!['zones'] as Map)['bare_stressed_pct']}% · '
                    'Sparse ${(plantZones['zones'] as Map)['sparse_pct']}% · '
                    'Healthy ${(plantZones['zones'] as Map)['healthy_pct']}% · '
                    'Dense ${(plantZones['zones'] as Map)['dense_pct']}%',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  '${t(widget.locale, 'confidence')}: ${plantZones?['confidence'] ?? '-'}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Tree Count (placeholder) ──
          StaggeredEntrance(
            index: 3,
            child: _MetricCard(
              title: t(widget.locale, 'treeCount'),
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.park_rounded,
                      color: Colors.green.shade700,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(widget.locale, 'treeCountPlaceholder'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Land Valuation ──
          StaggeredEntrance(
            index: 4,
            child: _MetricCard(
              title: t(widget.locale, 'landValuation'),
              children: [
                Text(
                  '${t(widget.locale, 'band')}: ${valuation?['low_per_acre_inr'] ?? '-'} – ${valuation?['high_per_acre_inr'] ?? '-'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${t(widget.locale, 'confidence')}: ${valuation?['confidence'] ?? '-'}%',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Advisory Notes (read-only) ──
          StaggeredEntrance(
            index: 5,
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.rate_review_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        t(widget.locale, 'consultantAdvisory'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t(widget.locale, 'advisoryPlaceholder'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CONSULTANT: full workspace dashboard ───

  Widget _buildConsultantDashboard(
    _DashboardData data,
    ThemeData theme,
    Color muted,
  ) {
    final landHealth = data.landHealth['land_health'] as Map<String, dynamic>?;
    final plantZones = data.plantZones['plant_zones'] as Map<String, dynamic>?;
    final valuation = data.valuation['valuation'] as Map<String, dynamic>?;
    final signalCards = landHealth?['signal_cards'] as List<dynamic>?;
    final dataMode = landHealth?['data_mode'] as String?;
    final methodology =
        landHealth?['methodology'] as Map<String, dynamic>?;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _futureData = _loadData(forceNetwork: true));
        await _futureData;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        children: [
          StaggeredEntrance(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(widget.locale, 'dashboard'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Material(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.engineering_rounded,
                          size: 20,
                          color: Color(0xFF1565C0),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(widget.locale, 'dashboardRoleStripConsultant'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Document vault (compact, inline for consultant)
          StaggeredEntrance(
            index: 1,
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(widget.locale, 'documentVault'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._documentTiles(data.documentsResponse),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      try {
                        final bytes = await widget.apiClient
                            .downloadGisSnapshotReport(widget.session);
                        final dir = await getTemporaryDirectory();
                        final name =
                            'gis-snapshot-${widget.apiClient.parcelId}.txt';
                        final f = File('${dir.path}/$name');
                        await f.writeAsBytes(bytes, flush: true);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${t(widget.locale, 'gisReportSaved')}: $name',
                            ),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(t(widget.locale, 'downloadGisReport')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (data.fromCache)
            StaggeredEntrance(
              index: 2,
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.storage_rounded,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(widget.locale, 'dashboardCachedHint'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (data.fromCache) const SizedBox(height: 12),

          if (dataMode == 'synthetic_demo')
            StaggeredEntrance(
              index: 3,
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: theme.colorScheme.tertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(widget.locale, 'syntheticDataWarning'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (dataMode == 'synthetic_demo') const SizedBox(height: 12),

          if (data.landHealthError != null)
            StaggeredEntrance(
              index: 35,
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  '${t(widget.locale, 'landHealthLoadFailed')}\n\n${data.landHealthError}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          if (data.landHealthError != null) const SizedBox(height: 12),

          StaggeredEntrance(
            index: 4,
            child: _MetricCard(
              title: t(widget.locale, 'landHealth'),
              liquidGlass: true,
              children: [
                Text(
                  '${t(widget.locale, 'score')}: ${landHealth?['score'] ?? '-'} · ${landHealth?['label'] ?? ''}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${t(widget.locale, 'confidence')}: ${landHealth?['confidence'] ?? '-'}%',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                if (methodology?['composite_fr22'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${methodology!['composite_fr22']}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                ],
                if (landHealth != null && landHealth.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        showWhyScoreDialog(
                          context,
                          locale: widget.locale,
                          landHealth: landHealth,
                        );
                      },
                      icon: const Icon(Icons.insights_rounded, size: 18),
                      label: Text(t(widget.locale, 'whyThisScoreTitle')),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (landHealth != null && landHealth.isNotEmpty)
            StaggeredEntrance(
              index: 5,
              child: _KeyMetricsSection(
                locale: widget.locale,
                landHealth: landHealth,
                theme: theme,
                muted: muted,
              ),
            ),
          if (landHealth != null && landHealth.isNotEmpty) const SizedBox(height: 12),
          const SizedBox(height: 4),
          Text(
            t(widget.locale, 'chartsTitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (signalCards != null)
            ...signalCards.asMap().entries.map((e) {
              final card = e.value as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StaggeredEntrance(
                  index: 6 + e.key,
                  child: _SignalCardChart(
                    locale: widget.locale,
                    card: card,
                    theme: theme,
                    muted: muted,
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          StaggeredEntrance(
            index: 20,
            child: _MetricCard(
              title: t(widget.locale, 'plantZones'),
              children: [
                if (plantZones?['zones'] is Map<String, dynamic>) ...[
                  Text(
                    'Bare ${(plantZones!['zones'] as Map)['bare_stressed_pct']}% · '
                    'Sparse ${(plantZones['zones'] as Map)['sparse_pct']}% · '
                    'Healthy ${(plantZones['zones'] as Map)['healthy_pct']}% · '
                    'Dense ${(plantZones['zones'] as Map)['dense_pct']}%',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  '${t(widget.locale, 'confidence')}: ${plantZones?['confidence'] ?? '-'}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StaggeredEntrance(
            index: 21,
            child: _MetricCard(
              title: t(widget.locale, 'valuation'),
              children: [
                Text(
                  '${t(widget.locale, 'band')}: ${valuation?['low_per_acre_inr'] ?? '-'} – ${valuation?['high_per_acre_inr'] ?? '-'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${t(widget.locale, 'confidence')}: ${valuation?['confidence'] ?? '-'}%',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _healthColor(String? label) {
    switch (label) {
      case 'Healthy':
        return Colors.green.shade700;
      case 'Moderate':
        return Colors.orange.shade800;
      case 'At Risk':
        return Colors.red.shade800;
      default:
        return Colors.blueGrey;
    }
  }

  List<Widget> _documentTiles(Map<String, dynamic>? documentsResponse) {
    final docs = documentsResponse?['documents'] as List<dynamic>?;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (docs == null || docs.isEmpty) {
      return [
        Text(
          '—',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
      ];
    }
    return docs.map((raw) {
      final m = raw as Map<String, dynamic>;
      final id = m['id'] as String? ?? '';
      final title = m['title'] as String? ?? id;
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.download_rounded),
          onPressed: () async {
            try {
              final bytes = await widget.apiClient.downloadDocument(
                widget.session,
                id,
              );
              final dir = await getTemporaryDirectory();
              final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
              final f = File('${dir.path}/landroid-$safe');
              await f.writeAsBytes(bytes);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(f.path)),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$e')),
              );
            }
          },
        ),
      );
    }).toList();
  }
}

/// Renders ``ndvi``, ``rainfall``, ``temperature``, ``soil`` from
/// ``GET /api/v1/ai/{parcel}/land-health`` → ``land_health``.
class _KeyMetricsSection extends StatelessWidget {
  const _KeyMetricsSection({
    required this.locale,
    required this.landHealth,
    required this.theme,
    required this.muted,
  });

  final LocaleCode locale;
  final Map<String, dynamic> landHealth;
  final ThemeData theme;
  final Color muted;

  String _fmt(dynamic v) {
    if (v == null) {
      return '—';
    }
    if (v is num) {
      return v.toString();
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final mode = landHealth['data_mode'] as String?;
    final ndvi = landHealth['ndvi'] as Map<String, dynamic>?;
    final rain = landHealth['rainfall'] as Map<String, dynamic>?;
    final temp = landHealth['temperature'] as Map<String, dynamic>?;
    final soil = landHealth['soil'] as Map<String, dynamic>?;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  t(locale, 'keyMetricsTitle'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (mode != null)
                Chip(
                  label: Text(
                    mode == 'earth_engine'
                        ? t(locale, 'dataModeEarthEngine')
                        : t(locale, 'dataModeSynthetic'),
                    style: theme.textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (ndvi != null) ...[
            Row(
              children: [
                Icon(Icons.grass_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  t(locale, 'metricNdvi'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${t(locale, 'ndviCurrentShort')}: ${_fmt(ndvi['current'])} · '
              '${t(locale, 'ndviTwoYearShort')}: ${_fmt(ndvi['two_year_mean'])} · '
              '${t(locale, 'ndviStatus')}: ${_fmt(ndvi['status'])} · '
              '${t(locale, 'confidence')}: ${_fmt(ndvi['confidence'])}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (rain != null) ...[
            Row(
              children: [
                Icon(Icons.water_drop_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  t(locale, 'metricRainfall'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${t(locale, 'rainfallAnnualMm')}: ${_fmt(rain['annual_mm'])} mm · '
              '${t(locale, 'rainfallVsNormal')}: ${_fmt(rain['deviation_pct_from_normal'])}% · '
              '${t(locale, 'rainfallFlag')}: ${_fmt(rain['flag'])} · '
              '${t(locale, 'confidence')}: ${_fmt(rain['confidence'])}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (temp != null) ...[
            Row(
              children: [
                Icon(Icons.thermostat_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  t(locale, 'metricTemperature'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${t(locale, 'heatStressDays')}: ${_fmt(temp['heat_stress_event_count'])} · '
              '${t(locale, 'confidence')}: ${_fmt(temp['confidence'])}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (soil != null) ...[
            Row(
              children: [
                Icon(Icons.landscape_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  t(locale, 'metricSoil'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${t(locale, 'soilPh')}: ${_fmt(soil['ph'])} · '
              '${t(locale, 'soilSoc')}: ${_fmt(soil['organic_carbon_g_kg'])} g/kg · '
              '${t(locale, 'soilTexture')}: ${_fmt(soil['texture'])} · '
              '${t(locale, 'confidence')}: ${_fmt(soil['confidence'])}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: muted,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignalCardChart extends StatelessWidget {
  const _SignalCardChart({
    required this.locale,
    required this.card,
    required this.theme,
    required this.muted,
  });

  final LocaleCode locale;
  final Map<String, dynamic> card;
  final ThemeData theme;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final title = card['title'] as String? ?? '';
    final value = card['current_value'];
    final valueLabel = card['value_label'] as String? ?? '';
    final trend = card['trend_indicator'] as String? ?? '';
    final conf = card['confidence'];
    final chart = card['historical_chart'] as List<dynamic>?;
    final ctx = card['context'] as String?;
    final hasChart = chart != null && chart.length > 1;

    final spots = <FlSpot>[];
    if (chart != null) {
      for (var i = 0; i < chart.length; i++) {
        final y = chart[i];
        final yn = y is num ? y.toDouble() : double.tryParse('$y') ?? 0.0;
        spots.add(FlSpot(i.toDouble(), yn));
      }
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$value',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (trend.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(trend, style: theme.textTheme.titleLarge),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            valueLabel,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, height: 1.3),
          ),
          if (ctx != null) ...[
            const SizedBox(height: 4),
            Text(
              ctx,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, height: 1.3),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '${t(locale, 'confidence')}: $conf%',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasChart) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: null,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: theme.colorScheme.outline
                          .withValues(alpha: 0.2),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, m) => Text(
                          v.toStringAsFixed(
                            v.truncateToDouble() == v ? 0 : 1,
                          ),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: muted),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, m) => Text(
                          '${v.toInt() + 1}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: muted),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.children,
    this.liquidGlass = false,
  });

  final String title;
  final List<Widget> children;
  final bool liquidGlass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      liquidGlass: liquidGlass,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...children,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.landHealth,
    required this.plantZones,
    required this.valuation,
    this.fromCache = false,
    this.noParcel = false,
    this.documentsResponse,
    this.landHealthError,
  });

  final Map<String, dynamic> landHealth;
  final Map<String, dynamic> plantZones;
  final Map<String, dynamic> valuation;
  final bool fromCache;
  final bool noParcel;
  final Map<String, dynamic>? documentsResponse;
  final String? landHealthError;

  factory _DashboardData.noParcel() => const _DashboardData(
        landHealth: {},
        plantZones: {},
        valuation: {},
        noParcel: true,
      );
}
