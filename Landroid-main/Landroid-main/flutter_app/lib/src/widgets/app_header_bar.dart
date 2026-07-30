import 'package:flutter/material.dart';

import '../i18n/translations.dart';
import '../models/session.dart' show Role, Session;
import 'app_card.dart';

/// Responsive app header: avoids zero-width [Expanded] (fixes vertical letter glitch)
/// and scales down controls on narrow screens.
class AppHeaderBar extends StatelessWidget {
  const AppHeaderBar({
    super.key,
    required this.locale,
    required this.session,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.roleLabel,
    required this.onLocaleChanged,
    this.onSwitchRole,
    this.onCreateParcel,
    this.onSignOut,
  });

  final LocaleCode locale;
  final Session? session;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String? roleLabel;
  final ValueChanged<LocaleCode> onLocaleChanged;
  final Future<void> Function()? onSwitchRole;
  final Future<void> Function()? onCreateParcel;
  final Future<void> Function()? onSignOut;

  static const double _iconSize = 28;
  static const double _gap = 10;
  static double get _textInset => _iconSize + _gap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 340;
        return AppCard(
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 10 : 14,
            vertical: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleRow(theme, narrow, session),
              if (session != null) ...[
                const SizedBox(height: 10),
                _RoleBanner(locale: locale, role: session!.role),
                // ── User info + sign out (always when signed in; label falls back to uid) ──
                const SizedBox(height: 8),
                Padding(
                  padding: EdgeInsetsDirectional.only(start: _textInset),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 16,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          session!.displayName ??
                              session!.email ??
                              session!.uid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (onSignOut != null)
                        IconButton(
                          onPressed: () async {
                            await onSignOut!();
                          },
                          icon: Icon(
                            Icons.logout_rounded,
                            size: 18,
                            color: scheme.error,
                          ),
                          tooltip: t(locale, 'signOut'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: narrow ? 6 : 4),
              Padding(
                padding: EdgeInsetsDirectional.only(start: _textInset),
                child: Text(
                  t(locale, 'language'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: EdgeInsetsDirectional.only(start: _textInset),
                child: _ThemeIconRow(
                  locale: locale,
                  themeMode: themeMode,
                  onChanged: onThemeModeChanged,
                  compact: narrow,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LocaleChips(locale: locale, onChanged: onLocaleChanged),
                  if (session != null) ...[
                    if (onSwitchRole != null)
                      TextButton.icon(
                        onPressed: () async {
                          await onSwitchRole!();
                        },
                        icon: Icon(
                          Icons.swap_horiz_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        label: Text(
                          roleLabel ?? '',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          roleLabel ?? '',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: session!.isConsultant
                                ? const Color(0xFF1565C0)
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    if (session!.isConsultant)
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onCreateParcel == null
                            ? null
                            : () async {
                                await onCreateParcel!();
                              },
                        icon: const Icon(
                          Icons.add_location_alt_rounded,
                          size: 22,
                        ),
                        tooltip: t(locale, 'createParcel'),
                      ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _titleRow(ThemeData theme, bool narrow, Session? session) {
    final role = session?.role;
    final iconData = role == Role.consultant
        ? Icons.engineering_rounded
        : role == Role.landowner
            ? Icons.cottage_outlined
            : Icons.eco_rounded;
    final iconColor = role == Role.consultant
        ? const Color(0xFF1565C0)
        : role == Role.landowner
            ? const Color(0xFF2E7D32)
            : theme.colorScheme.primary;

    final title = Text(
      t(locale, 'title'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(iconData, color: iconColor, size: _iconSize),
        const SizedBox(width: _gap),
        Expanded(child: title),
      ],
    );
  }
}

class _RoleBanner extends StatelessWidget {
  const _RoleBanner({required this.locale, required this.role});

  final LocaleCode locale;
  final Role role;

  static const Color _consultantAccent = Color(0xFF1565C0);
  static const Color _landownerAccent = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final isConsultant = role == Role.consultant;
    final accent = isConsultant ? _consultantAccent : _landownerAccent;
    final bg =
        isConsultant ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9);
    final icon =
        isConsultant ? Icons.badge_rounded : Icons.visibility_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConsultant
                      ? t(locale, 'roleBannerConsultantTitle')
                      : t(locale, 'roleBannerLandownerTitle'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConsultant
                      ? t(locale, 'roleBannerConsultantSubtitle')
                      : t(locale, 'roleBannerLandownerSubtitle'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeIconRow extends StatelessWidget {
  const _ThemeIconRow({
    required this.locale,
    required this.themeMode,
    required this.onChanged,
    required this.compact,
  });

  final LocaleCode locale;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget btn(ThemeMode mode, IconData icon, String tip) {
      final sel = themeMode == mode;
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => onChanged(mode),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 8,
            ),
            child: Icon(
              icon,
              size: compact ? 20 : 22,
              color: sel ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            ThemeMode.system,
            Icons.brightness_auto_rounded,
            t(locale, 'themeSystem'),
          ),
          _divider(scheme),
          btn(
            ThemeMode.light,
            Icons.light_mode_rounded,
            t(locale, 'themeLight'),
          ),
          _divider(scheme),
          btn(
            ThemeMode.dark,
            Icons.dark_mode_rounded,
            t(locale, 'themeDark'),
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) {
    return Container(
      width: 1,
      height: 22,
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    );
  }
}

class _LocaleChips extends StatelessWidget {
  const _LocaleChips({required this.locale, required this.onChanged});

  final LocaleCode locale;
  final ValueChanged<LocaleCode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LangChip(
              label: t(locale, 'english'),
              selected: locale == english,
              onTap: () => onChanged(english),
            ),
            _LangChip(
              label: t(locale, 'tamil'),
              selected: locale == tamil,
              onTap: () => onChanged(tamil),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
