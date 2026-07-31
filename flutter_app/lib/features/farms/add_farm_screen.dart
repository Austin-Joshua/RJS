import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme.dart';
import '../../data/models/farm_models.dart';
import '../../data/repos/farm_repo.dart';
import 'soil_card_view.dart';

/// Add a farm (brief §2.2): location, land size, and the raw soil readings
/// the farmer has from a lab report or Soil Health Card.
///
/// Location can be captured from GPS or typed. Requiring a farmer to trace a
/// polygon on a phone before they can get any advice would lose most of them
/// at the first screen, so a pin plus an area is enough.
class AddFarmScreen extends ConsumerStatefulWidget {
  const AddFarmScreen({super.key});

  @override
  ConsumerState<AddFarmScreen> createState() => _AddFarmScreenState();
}

class _AddFarmScreenState extends ConsumerState<AddFarmScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _area = TextEditingController(text: '1.0');
  final _lat = TextEditingController(text: '10.7550');
  final _lon = TextEditingController(text: '79.0550');
  final _n = TextEditingController();
  final _p = TextEditingController();
  final _k = TextEditingController();
  final _ph = TextEditingController();
  final _oc = TextEditingController();
  final _ec = TextEditingController();
  final _water = TextEditingController();

  String _soilType = 'alluvial';
  bool _saving = false;
  bool _locating = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _area, _lat, _lon, _n, _p, _k, _ph, _oc, _ec, _water]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied — enter the coordinates instead.');
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(5);
        _lon.text = pos.longitude.toStringAsFixed(5);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  double? _num(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref.read(farmRepositoryProvider).create(
            name: _name.text.trim(),
            lat: double.parse(_lat.text.trim()),
            lon: double.parse(_lon.text.trim()),
            areaHa: double.parse(_area.text.trim()),
            soil: SoilReadingsIn(
              soilType: _soilType,
              nKgHa: double.parse(_n.text.trim()),
              pKgHa: double.parse(_p.text.trim()),
              kKgHa: double.parse(_k.text.trim()),
              ph: double.parse(_ph.text.trim()),
              ocPct: _num(_oc),
              ecDsM: _num(_ec),
              waterAvailableM3: _num(_water),
            ),
          );
      if (!mounted) return;
      ref.invalidate(farmsProvider);
      // §2.3 — the classified card is shown immediately, before anything else.
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.cream,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (_, controller) => SoilCardView(
            card: result.soilCard,
            farmName: result.farm.name,
            scrollController: controller,
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop(result.farm.id);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendly(Object e) {
    final s = '$e';
    if (s.contains('401')) return 'Your session expired. Sign in again.';
    if (s.contains('SocketException') || s.contains('Connection')) {
      return 'Cannot reach the server. Check your connection and try again.';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add farm')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Text('Your land', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            _field(_name, 'Farm name', hint: 'e.g. North field', required: true),
            _field(_area, 'Land size (hectares)', keyboard: true, required: true, min: 0.01, max: 10000),
            Row(
              children: [
                Expanded(child: _field(_lat, 'Latitude', keyboard: true, required: true, min: -90, max: 90)),
                const SizedBox(width: 12),
                Expanded(child: _field(_lon, 'Longitude', keyboard: true, required: true, min: -180, max: 180)),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 18),
                label: Text(_locating ? 'Locating…' : 'Use my current location'),
              ),
            ),
            const SizedBox(height: 20),
            Text('Soil readings', style: textTheme.titleMedium),
            Text(
              'From your Soil Health Card or lab report. N, P, K and pH are required — '
              'the rest sharpen the advice when you have them.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.clay),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _soilType,
              decoration: const InputDecoration(labelText: 'Soil type', border: OutlineInputBorder()),
              items: [
                for (final e in soilTypeOptions.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _soilType = v ?? 'alluvial'),
            ),
            const SizedBox(height: 12),
            _field(_n, 'Available nitrogen N (kg/ha)', keyboard: true, required: true, min: 0, max: 2000),
            _field(_p, 'Available phosphorus P (kg/ha)', keyboard: true, required: true, min: 0, max: 500),
            _field(_k, 'Available potassium K (kg/ha)', keyboard: true, required: true, min: 0, max: 2000),
            _field(_ph, 'Soil pH', keyboard: true, required: true, min: 0, max: 14),
            _field(_oc, 'Organic carbon (%)  — optional', keyboard: true, min: 0, max: 10),
            _field(_ec, 'Salinity EC (dS/m)  — optional', keyboard: true, min: 0, max: 50),
            _field(_water, 'Irrigation water for the season (m³)  — optional', keyboard: true, min: 0),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.terracotta)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.science_outlined),
                label: Text(_saving ? 'Saving…' : 'Save and see my soil card'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool keyboard = false,
    bool required = false,
    double? min,
    double? max,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
        inputFormatters: keyboard ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))] : null,
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        validator: (value) {
          final text = (value ?? '').trim();
          if (text.isEmpty) return required ? 'Required' : null;
          if (!keyboard) return null;
          final parsed = double.tryParse(text);
          if (parsed == null) return 'Enter a number';
          // Bounds match the server's validation, so a typo is caught here
          // rather than coming back as a 422 after a round trip.
          if (min != null && parsed < min) return 'Must be at least $min';
          if (max != null && parsed > max) return 'Must be at most $max';
          return null;
        },
      ),
    );
  }
}
