import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  Future<String?> getLocalizedAddress(
    LatLng location,
    String languageCode,
  ) async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null) {
        debugPrint("LocationService: API Key missing");
        return null;
      }

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${location.latitude},${location.longitude}&key=$apiKey&language=$languageCode',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final parsed = json.decode(response.body);
        if (parsed['status'] == 'OK' && parsed['results'].isNotEmpty) {
          // Return the first formatted address
          return parsed['results'][0]['formatted_address'];
        }
      }
    } catch (e) {
      debugPrint("LocationService: Error resolving address: $e");
    }
    return null;
  }
}
