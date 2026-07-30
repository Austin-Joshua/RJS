import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../auth/auth_repository.dart';
import '../auth/demo_credentials.dart';
import '../i18n/translations.dart';
import '../models/session.dart' show Role, Session;
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/staggered_entrance.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.locale,
    required this.onAuthenticated,
  });

  final LocaleCode locale;
  final ValueChanged<Session> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthRepository _auth = AuthRepository();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _busyEmail = false;
  bool _busyGoogle = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSignIn = false;

  bool get _anyBusy => _busyEmail || _busyGoogle;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) {
      return t(widget.locale, 'fieldRequired');
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) {
      return t(widget.locale, 'fieldRequired');
    }
    final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(s);
    if (!ok) {
      return t(widget.locale, 'invalidEmail');
    }
    return null;
  }

  String? _validatePassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) {
      return t(widget.locale, 'fieldRequired');
    }
    if (s.length < 6) {
      return t(widget.locale, 'passwordTooShort');
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    final s = v ?? '';
    if (s.isEmpty) {
      return t(widget.locale, 'fieldRequired');
    }
    if (s != _passwordCtrl.text) {
      return t(widget.locale, 'passwordMismatch');
    }
    return null;
  }

  Future<void> _onSignUp() async {
    if (_anyBusy) {
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final demoRole = DemoCredentials.roleIfValid(email, password);
    if (demoRole != null) {
      if (password != _confirmCtrl.text) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(widget.locale, 'passwordMismatch'))),
        );
        return;
      }
      widget.onAuthenticated(DemoCredentials.sessionFor(demoRole));
      return;
    }

    if (!AuthRepository.isSupabaseConfigured) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(widget.locale, 'supabaseConfig'))),
      );
      return;
    }
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      return;
    }

    setState(() => _busyEmail = true);
    try {
      final session = await _auth.signUpWithEmail(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        locale: widget.locale,
      );
      if (!mounted) {
        return;
      }
      if (session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(widget.locale, 'checkEmailConfirm'))),
        );
        return;
      }
      widget.onAuthenticated(session);
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _busyEmail = false);
      }
    }
  }

  Future<void> _onSignIn() async {
    if (_anyBusy) {
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final demoRole = DemoCredentials.roleIfValid(email, password);
    if (demoRole != null) {
      widget.onAuthenticated(DemoCredentials.sessionFor(demoRole));
      return;
    }

    if (!AuthRepository.isSupabaseConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(widget.locale, 'supabaseConfig'))),
      );
      return;
    }

    // For sign-in, only email & password are required
    final emailErr = _validateEmail(_emailCtrl.text);
    final passErr = _validatePassword(_passwordCtrl.text);
    if (emailErr != null || passErr != null) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() => _busyEmail = true);
    try {
      final session = await _auth.signInWithEmail(
        email: email,
        password: password,
        locale: widget.locale,
      );
      if (!mounted) return;
      if (session == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(widget.locale, 'apiError'))),
        );
        return;
      }
      widget.onAuthenticated(session);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _busyEmail = false);
      }
    }
  }

  void _quickDemo(Role role) {
    if (_anyBusy || !DemoCredentials.kDemoLoginEnabled) {
      return;
    }
    widget.onAuthenticated(DemoCredentials.sessionFor(role));
  }

  Future<void> _onGoogle() async {
    if (_anyBusy) {
      return;
    }
    if (!AuthRepository.isSupabaseConfigured) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(widget.locale, 'supabaseConfig'))),
      );
      return;
    }
    setState(() => _busyGoogle = true);
    try {
      final session = await _auth.signInWithGoogle(locale: widget.locale);
      if (!mounted || session == null) {
        return;
      }
      widget.onAuthenticated(session);
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _busyGoogle = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    InputDecoration deco(String label) {
      return InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.clamp(0.0, 480.0);
        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StaggeredEntrance(
                    index: 0,
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.92, end: 1),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (context, scale, child) {
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: Icon(
                          Icons.eco_rounded,
                          size: 72,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StaggeredEntrance(
                    index: 1,
                    child: AppCard(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isSignIn
                                  ? t(widget.locale, 'signIn')
                                  : t(widget.locale, 'signUp'),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isSignIn
                                  ? t(widget.locale, 'signInSubtitle')
                                  : t(widget.locale, 'signUpSubtitle'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setState(() => _isSignIn = !_isSignIn);
                                _formKey.currentState?.reset();
                              },
                              child: Text(
                                _isSignIn
                                    ? t(widget.locale, 'switchToSignUp')
                                    : t(widget.locale, 'switchToSignIn'),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (!_isSignIn) ...[
                              TextFormField(
                                controller: _nameCtrl,
                                textCapitalization: TextCapitalization.words,
                                autofillHints: const [AutofillHints.name],
                                decoration: deco(t(widget.locale, 'fullName')),
                                validator: _isSignIn ? null : _validateName,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: deco(t(widget.locale, 'email')),
                              validator: _validateEmail,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscurePassword,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: deco(t(widget.locale, 'password'))
                                  .copyWith(
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Show' : 'Hide',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: _validatePassword,
                              textInputAction: TextInputAction.next,
                            ),
                            if (!_isSignIn) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirmCtrl,
                                obscureText: _obscureConfirm,
                                autofillHints: const [AutofillHints.newPassword],
                                decoration:
                                    deco(t(widget.locale, 'confirmPassword'))
                                        .copyWith(
                                  suffixIcon: IconButton(
                                    tooltip: _obscureConfirm ? 'Show' : 'Hide',
                                    onPressed: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm,
                                    ),
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: _isSignIn ? null : _validateConfirm,
                                onFieldSubmitted: (_) => _isSignIn ? _onSignIn() : _onSignUp(),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _anyBusy
                                  ? null
                                  : (_isSignIn ? _onSignIn : _onSignUp),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusSm,
                                  ),
                                ),
                              ),
                              child: _busyEmail
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    )
                                  : Text(
                                      _isSignIn
                                          ? t(widget.locale, 'signInButton')
                                          : t(widget.locale, 'signUpButton'),
                                    ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(child: Divider(color: muted.withValues(alpha: 0.35))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    t(widget.locale, 'orContinue').toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: muted,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: muted.withValues(alpha: 0.35))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              t(widget.locale, 'googleOnlyHint'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _anyBusy ? null : _onGoogle,
                              icon: _busyGoogle
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : const Icon(Icons.login_rounded),
                              label: Text(t(widget.locale, 'googleLogin')),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusSm,
                                  ),
                                ),
                              ),
                            ),
                            if (DemoCredentials.kDemoLoginEnabled) ...[
                              const SizedBox(height: 24),
                              Divider(color: muted.withValues(alpha: 0.35)),
                              const SizedBox(height: 16),
                              Text(
                                t(widget.locale, 'demoSectionTitle'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                t(widget.locale, 'demoSectionHint'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SelectableText(
                                '${t(widget.locale, 'roleConsultant')}: ${DemoCredentials.consultantEmail}\n'
                                '${t(widget.locale, 'demoPasswordLabel')}: ${DemoCredentials.sharedPassword}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: const ['monospace'],
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                '${t(widget.locale, 'roleLandowner')}: ${DemoCredentials.landownerEmail}\n'
                                '${t(widget.locale, 'demoPasswordLabel')}: ${DemoCredentials.sharedPassword}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: const ['monospace'],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _anyBusy
                                          ? null
                                          : () => _quickDemo(Role.consultant),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF1565C0),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size.fromHeight(44),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppTheme.radiusSm,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        t(widget.locale, 'demoLoginConsultant'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _anyBusy
                                          ? null
                                          : () => _quickDemo(Role.landowner),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF2E7D32),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size.fromHeight(44),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppTheme.radiusSm,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        t(widget.locale, 'demoLoginLandowner'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
