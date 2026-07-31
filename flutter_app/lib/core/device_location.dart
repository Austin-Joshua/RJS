import 'package:geolocator/geolocator.dart';

/// Thrown when GPS or permission blocks a location read.
class DeviceLocationException implements Exception {
  const DeviceLocationException(this.message, {this.deniedForever = false});

  final String message;
  final bool deniedForever;

  @override
  String toString() => message;
}

/// Best-effort current position with permission + GPS checks.
abstract final class DeviceLocation {
  static Future<Position> current({
    Duration timeout = const Duration(seconds: 15),
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const DeviceLocationException(
        'Location services are off. Turn on GPS in Settings, or type coordinates.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        'Location permission blocked. Open Settings → FarmSync → Location, or type coordinates.',
        deniedForever: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(
        'Location permission denied — enter latitude and longitude manually.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: accuracy, timeLimit: timeout),
    );
  }

  /// Returns null when GPS/permission unavailable — for silent auto-fill on open.
  static Future<Position?> tryCurrent({Duration timeout = const Duration(seconds: 12)}) async {
    try {
      return await current(timeout: timeout);
    } on DeviceLocationException {
      return null;
    }
  }
}
