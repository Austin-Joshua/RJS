import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../auth/demo_credentials.dart';
import '../i18n/translations.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';

/// Land Consultant flow: name, assign landowner (email or phone), optional Birdscale files.
class CreateParcelScreen extends StatefulWidget {
  const CreateParcelScreen({
    super.key,
    required this.locale,
    required this.session,
    required this.apiClient,
  });

  final LocaleCode locale;
  final Session session;
  final ApiClient apiClient;

  @override
  State<CreateParcelScreen> createState() => _CreateParcelScreenState();
}

class _CreateParcelScreenState extends State<CreateParcelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String? _boundaryGeojson;
  String? _boundaryLabel;
  PlatformFile? _ndviPick;
  PlatformFile? _demPick;

  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBoundary() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['geojson', 'json'],
    );
    if (r == null || r.files.isEmpty) {
      return;
    }
    final f = r.files.single;
    if (f.path == null && f.bytes == null) {
      return;
    }
    final raw = f.bytes ?? await File(f.path!).readAsBytes();
    _boundaryGeojson = String.fromCharCodes(raw);
    setState(() {
      _boundaryLabel = f.name;
    });
  }

  Future<void> _pickNdvi() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['tif', 'tiff'],
    );
    if (r != null && r.files.isNotEmpty) {
      setState(() => _ndviPick = r.files.single);
    }
  }

  Future<void> _pickDem() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['tif', 'tiff'],
    );
    if (r != null && r.files.isNotEmpty) {
      setState(() => _demPick = r.files.single);
    }
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (email.isEmpty && phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(widget.locale, 'ownerContactRequired'))),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.apiClient.createParcel(
        widget.session,
        name: _nameCtrl.text.trim(),
        ownerEmail: email.isNotEmpty ? email : null,
        ownerPhone: phone.isNotEmpty ? phone : null,
        boundaryGeojson: _boundaryGeojson,
      );
      final pid = widget.apiClient.parcelId;
      if (pid.isNotEmpty) {
        if (_ndviPick != null) {
          final p = _ndviPick!;
          final path = p.path;
          if (path != null) {
            await widget.apiClient.uploadParcelNdvi(
              widget.session,
              pid,
              path,
              p.name,
            );
          }
        }
        if (_demPick != null) {
          final p = _demPick!;
          final path = p.path;
          if (path != null) {
            await widget.apiClient.uploadParcelDem(
              widget.session,
              pid,
              path,
              p.name,
            );
          }
        }
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(widget.locale, 'parcelCreated'))),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t(widget.locale, 'parcelFailed')}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: Text(t(widget.locale, 'createParcelTitle')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(widget.locale, 'createParcelIntro'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(widget.locale, 'createParcelDemoAccounts'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              Text(
                '${DemoCredentials.landownerEmail} · …9876543210',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                decoration: deco(t(widget.locale, 'parcelNameLabel')),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? t(widget.locale, 'fieldRequired') : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: deco(t(widget.locale, 'assignOwnerEmail')),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              Text(
                t(widget.locale, 'assignOwnerOr'),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: deco(t(widget.locale, 'assignOwnerPhone')),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 18),
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t(widget.locale, 'birdscaleUploads'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickBoundary,
                      icon: const Icon(Icons.polyline_rounded),
                      label: Text(
                        _boundaryLabel ?? t(widget.locale, 'pickBoundaryGeojson'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickNdvi,
                      icon: const Icon(Icons.layers_rounded),
                      label: Text(
                        _ndviPick?.name ?? t(widget.locale, 'pickOrthomosaicNdvi'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickDem,
                      icon: const Icon(Icons.terrain_rounded),
                      label: Text(_demPick?.name ?? t(widget.locale, 'pickDem')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                ),
                child: _busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Text(t(widget.locale, 'createParcelSubmit')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
