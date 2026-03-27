import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      return await getLastKnownLocation();
    }
  }

  static Future<Position?> getLastKnownLocation() async {
    return await Geolocator.getLastKnownPosition();
  }

  static String formatLocation(Position position) {
    return
        'Latitude: ${position.latitude}\n'
        'Longitude: ${position.longitude}\n'
        'Maps: https://maps.google.com/?q=${position.latitude},${position.longitude}';
  }
}