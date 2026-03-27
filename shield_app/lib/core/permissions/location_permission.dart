import 'package:permission_handler/permission_handler.dart';

class LocationPermission {
  static Future<bool> request() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }
}