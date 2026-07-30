import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'api/client.dart';
import 'auth/auth_repository.dart';
import 'i18n/translations.dart';
import 'models/session.dart' show Role, Session;
import 'screens/auth_screen.dart';
import 'screens/create_parcel_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/document_vault_screen.dart';
import 'screens/map_screen.dart';
import 'screens/parcels_list_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/app_header_bar.dart';

/// ──── Tab definitions per role ────
///
/// Consultant:  Map  │  Dashboard  │  Parcels  │  Settings
/// Landowner:   Dashboard  │  Map  │  Documents  │  Settings
///
enum ConsultantTab { map, dashboard, parcels, settings }

enum LandownerTab { dashboard, map, documents, settings }

class LandroidApp extends StatefulWidget {
  const LandroidApp({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<LandroidApp> createState() => _LandroidAppState();
}

class _LandroidAppState extends State<LandroidApp> {
  static const _kThemeKey = 'theme_mode';
  final AuthRepository _authRepo = AuthRepository();

  LocaleCode _locale = english;
  Session? _session;
  StreamSubscription<AuthState>? _authStateSub;

  /// Index into the current role's tab list.
  int _tabIndex = 0;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _listenSupabaseAuthRefresh();
    unawaited(_restoreSupabaseSession());
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }

  void _listenSupabaseAuthRefresh() {
    if (!AuthRepository.isSupabaseConfigured) {
      return;
    }
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final sess = data.session;
      final u = sess?.user;
      final tok = sess?.accessToken;
      if (u == null || tok == null || tok.isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        final cur = _session;
        if (cur != null && cur.uid == u.id) {
          _session = cur.copyWith(token: tok);
        }
      });
    });
  }

  Future<void> _restoreSupabaseSession() async {
    final restored = await _authRepo.restoreSessionIfSignedIn(_locale);
    if (restored != null && mounted) {
      setState(() {
        _session = restored;
        _tabIndex = 0;
      });
    }
  }

  // ─── Theme persistence ───

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeKey);
    if (!mounted) return;
    setState(() {
      _themeMode = switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kThemeKey,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }

  // ─── Auth helpers ───

  void _onAuthenticated(Session session) {
    setState(() {
      _session = session;
      _tabIndex = 0;
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(t(_locale, 'signOut')),
        content: Text(t(_locale, 'signOutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t(_locale, 'signOutCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t(_locale, 'signOut')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _authRepo.signOut();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _session = null;
      _tabIndex = 0;
    });
  }

  // ─── Consultant: create parcel ───

  Future<void> _openCreateParcel() async {
    final session = _session;
    if (session == null || !session.isConsultant) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CreateParcelScreen(
          locale: _locale,
          session: session,
          apiClient: widget.apiClient,
        ),
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  // ─── Locale ───

  void _setLocale(LocaleCode code) {
    setState(() => _locale = code);
    final s = _session;
    if (s != null) _authRepo.syncProfileForSession(s, _locale);
  }

  String _roleLabel(Role role) {
    return role == Role.consultant
        ? t(_locale, 'roleConsultant')
        : t(_locale, 'roleLandowner');
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: t(_locale, 'title'),
      debugShowCheckedModeBanner: false,
      locale: Locale(_locale),
      supportedLocales: const [Locale('en'), Locale('ta')],
      themeMode: _themeMode,
      theme: AppTheme.light(_locale),
      darkTheme: AppTheme.dark(_locale),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.25,
          child: child,
        );
      },
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: AppHeaderBar(
                  locale: _locale,
                  session: _session,
                  themeMode: _themeMode,
                  onThemeModeChanged: _setThemeMode,
                  roleLabel:
                      _session != null ? _roleLabel(_session!.role) : null,
                  onLocaleChanged: _setLocale,
                  onCreateParcel:
                      _session?.isConsultant == true ? _openCreateParcel : null,
                  onSignOut: _session != null ? _signOut : null,
                ),
              ),
              Expanded(
                child: _session == null
                    ? AuthScreen(
                        locale: _locale,
                        onAuthenticated: _onAuthenticated,
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.02, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(
                            '${_session!.role}_${_tabIndex}_${widget.apiClient.resolvedApiBaseUrl}',
                          ),
                          child: _buildTabBody(),
                        ),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _session == null ? null : _buildNavBar(context),
      ),
    );
  }

  // ─── Tab body ───

  Widget _buildTabBody() {
    final session = _session!;
    if (session.isConsultant) {
      final tab = ConsultantTab.values[_tabIndex];
      return switch (tab) {
        ConsultantTab.map => MapScreen(
            key: ValueKey(widget.apiClient.resolvedApiBaseUrl),
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
          ),
        ConsultantTab.dashboard => DashboardScreen(
            key: ValueKey(widget.apiClient.resolvedApiBaseUrl),
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
          ),
        ConsultantTab.parcels => ParcelsListScreen(
            key: ValueKey(widget.apiClient.resolvedApiBaseUrl),
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
            onParcelSelected: () => setState(() {}),
          ),
        ConsultantTab.settings => SettingsScreen(
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
            onApiBaseUrlSaved: () => setState(() {}),
            onParcelChanged: () => setState(() {}),
            onSignOut: _signOut,
          ),
      };
    } else {
      final tab = LandownerTab.values[_tabIndex];
      return switch (tab) {
        LandownerTab.dashboard => DashboardScreen(
            key: ValueKey(widget.apiClient.resolvedApiBaseUrl),
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
          ),
        LandownerTab.map => MapScreen(
            key: ValueKey(widget.apiClient.resolvedApiBaseUrl),
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
          ),
        LandownerTab.documents => DocumentVaultScreen(
            key: ValueKey(widget.apiClient.resolvedApiBaseUrl),
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
          ),
        LandownerTab.settings => SettingsScreen(
            locale: _locale,
            session: session,
            apiClient: widget.apiClient,
            onApiBaseUrlSaved: () => setState(() {}),
            onParcelChanged: () => setState(() {}),
            onSignOut: _signOut,
          ),
      };
    }
  }

  // ─── Navigation bar ───

  Widget _buildNavBar(BuildContext context) {
    final session = _session!;
    final consultant = session.isConsultant;

    final navTheme = consultant
        ? NavigationBarThemeData(
            backgroundColor: const Color(0xFFF0F7FF),
            indicatorColor: const Color(0xFF90CAF9),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (s) => TextStyle(
                fontWeight: s.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: const Color(0xFF0D47A1),
              ),
            ),
          )
        : NavigationBarThemeData(
            backgroundColor: const Color(0xFFF1F8F4),
            indicatorColor: const Color(0xFFA5D6A7),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (s) => TextStyle(
                fontWeight: s.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: const Color(0xFF1B5E20),
              ),
            ),
          );

    final destinations = consultant
        ? [
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map_rounded),
              label: t(_locale, 'map'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard_rounded),
              label: t(_locale, 'dashboard'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.landscape_outlined),
              selectedIcon: const Icon(Icons.landscape_rounded),
              label: t(_locale, 'parcels'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: t(_locale, 'settings'),
            ),
          ]
        : [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard_rounded),
              label: t(_locale, 'dashboard'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map_rounded),
              label: t(_locale, 'map'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder_rounded),
              label: t(_locale, 'documents'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: t(_locale, 'settings'),
            ),
          ];

    return Theme(
      data: Theme.of(context).copyWith(navigationBarTheme: navTheme),
      child: NavigationBar(
        selectedIndex: _tabIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          setState(() => _tabIndex = index);
        },
        destinations: destinations,
      ),
    );
  }
}
