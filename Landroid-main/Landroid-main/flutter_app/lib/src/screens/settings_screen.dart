import 'package:flutter/material.dart';

import '../api/client.dart';
import '../cache/landroid_disk_cache.dart';
import '../i18n/translations.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/staggered_entrance.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.locale,
    required this.session,
    required this.apiClient,
    required this.onApiBaseUrlSaved,
    required this.onParcelChanged,
    required this.onSignOut,
  });

  final LocaleCode locale;
  final Session session;
  final ApiClient apiClient;
  final VoidCallback onApiBaseUrlSaved;
  final VoidCallback onParcelChanged;
  final Future<void> Function() onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _apiCtrl;
  bool _testing = false;
  List<Map<String, dynamic>> _parcels = [];
  bool _loadingParcels = true;

  @override
  void initState() {
    super.initState();
    _apiCtrl = TextEditingController(text: widget.apiClient.resolvedApiBaseUrl);
    if (widget.session.isConsultant) {
      _loadParcels();
    } else {
      _loadingParcels = false;
    }
  }

  Future<void> _loadParcels() async {
    setState(() => _loadingParcels = true);
    await widget.apiClient.refreshParcels(widget.session);
    final list = await widget.apiClient.fetchParcelsList(widget.session);
    if (!mounted) return;
    setState(() {
      _parcels = list;
      _loadingParcels = false;
    });
  }

  @override
  void dispose() {
    _apiCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.apiClient.setApiBaseUrl(_apiCtrl.text);
    if (!mounted) return;
    _apiCtrl.text = widget.apiClient.resolvedApiBaseUrl;
    widget.onApiBaseUrlSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t(widget.locale, 'apiUrlSaved'))),
    );
  }

  Future<void> _reset() async {
    await widget.apiClient.setApiBaseUrl(null);
    _apiCtrl.text = widget.apiClient.resolvedApiBaseUrl;
    if (!mounted) return;
    setState(() {});
    widget.onApiBaseUrlSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t(widget.locale, 'apiUrlReset'))),
    );
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final ok = await widget.apiClient.pingHealth();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? t(widget.locale, 'apiTestOk') : t(widget.locale, 'apiTestFail'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isConsultant = widget.session.isConsultant;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      children: [
        StaggeredEntrance(
          index: 0,
          child: Text(
            t(widget.locale, 'settings'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Profile card (both roles) ──
        StaggeredEntrance(
          index: 1,
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isConsultant
                      ? const Color(0xFFE3F2FD)
                      : const Color(0xFFE8F5E9),
                  child: Icon(
                    isConsultant
                        ? Icons.engineering_rounded
                        : Icons.cottage_outlined,
                    color: isConsultant
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.session.displayName ?? t(widget.locale, 'profile'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.session.email != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.session.email!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isConsultant
                              ? const Color(0xFFE3F2FD)
                              : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isConsultant
                              ? t(widget.locale, 'roleConsultant')
                              : t(widget.locale, 'roleLandowner'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isConsultant
                                ? const Color(0xFF1565C0)
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Parcel selector (consultant only, when > 1 parcel) ──
        if (isConsultant && (_loadingParcels || _parcels.length > 1))
          StaggeredEntrance(
            index: 2,
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t(widget.locale, 'selectParcel'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_loadingParcels)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_parcels.length > 1)
                    DropdownButton<String>(
                      isExpanded: true,
                      value: widget.apiClient.parcelId.isNotEmpty &&
                              _parcels.any(
                                (e) => e['id'] == widget.apiClient.parcelId,
                              )
                          ? widget.apiClient.parcelId
                          : (_parcels.isNotEmpty
                              ? _parcels.first['id'] as String
                              : null),
                      items: _parcels
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e['id'] as String,
                              child: Text(
                                '${e['name'] ?? e['id']} (${e['id']})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        await widget.apiClient.selectParcel(v);
                        widget.onParcelChanged();
                        if (mounted) setState(() {});
                      },
                    )
                  else
                    Text(
                      _parcels.isEmpty
                          ? '—'
                          : '${_parcels.first['name'] ?? _parcels.first['id']} (${_parcels.first['id']})',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ),
        if (isConsultant && (_loadingParcels || _parcels.length > 1))
          const SizedBox(height: 12),

        // ── API server config (consultant only) ──
        if (isConsultant)
          StaggeredEntrance(
            index: 3,
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t(widget.locale, 'apiBaseUrlTitle'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t(widget.locale, 'apiBaseUrlHint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiCtrl,
                    decoration: InputDecoration(
                      labelText: t(widget.locale, 'apiBaseUrlLabel'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _save,
                        child: Text(t(widget.locale, 'apiSave')),
                      ),
                      OutlinedButton(
                        onPressed: _testing ? null : _test,
                        child: _testing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(t(widget.locale, 'apiTest')),
                      ),
                      TextButton(
                        onPressed: _reset,
                        child: Text(t(widget.locale, 'apiReset')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (isConsultant) const SizedBox(height: 12),

        // ── Clear cache (consultant only) ──
        if (isConsultant)
          StaggeredEntrance(
            index: 4,
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                ),
                onPressed: () async {
                  await clearAllDiskCacheForApi(
                    widget.apiClient.resolvedApiBaseUrl,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t(widget.locale, 'cacheCleared')),
                    ),
                  );
                  widget.onApiBaseUrlSaved();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.delete_sweep_rounded),
                    const SizedBox(width: 10),
                    Text(t(widget.locale, 'clearCache')),
                  ],
                ),
              ),
            ),
          ),

        // ── Sign out (both roles) ──
        const SizedBox(height: 20),
        StaggeredEntrance(
          index: 5,
          child: FilledButton.icon(
            onPressed: () async {
              await widget.onSignOut();
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(t(widget.locale, 'signOut')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
