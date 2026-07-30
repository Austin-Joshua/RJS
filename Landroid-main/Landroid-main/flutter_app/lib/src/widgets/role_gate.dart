import 'package:flutter/material.dart';

import '../i18n/translations.dart';
import '../models/session.dart';
import 'app_card.dart';

/// Hides [child] behind a lock card when the user's role is not in
/// [allowedRoles]. An optional [fallback] widget replaces the default
/// lock icon + message.
class RoleGate extends StatelessWidget {
  const RoleGate({
    super.key,
    required this.allowedRoles,
    required this.current,
    required this.locale,
    required this.child,
    this.fallback,
  });

  final List<Role> allowedRoles;
  final Role current;
  final LocaleCode locale;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (!allowedRoles.contains(current)) {
      if (fallback != null) {
        return fallback!;
      }
      final theme = Theme.of(context);
      return Center(
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  t(locale, 'roleBlocked'),
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return child;
  }
}
