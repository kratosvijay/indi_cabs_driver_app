import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class NavigationService {
  final String _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  Future<Map<String, dynamic>?> fetchRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    if (_apiKey.isEmpty) {
      debugPrint("NavigationService: API Key missing");
      return null;
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?'
      'origin=${origin.latitude},${origin.longitude}&'
      'destination=${destination.latitude},${destination.longitude}&'
      'mode=driving&'
      'key=$_apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if ((data['routes'] as List).isEmpty) return null;

        final route = data['routes'][0];
        final leg = route['legs'][0];
        final overviewPolyline = route['overview_polyline']['points'];

        // Decode polyline
        final polylinePoints = PolylinePoints.decodePolyline(overviewPolyline);
        final List<LatLng> routePoints = polylinePoints
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        return {
          'points': routePoints,
          'steps': leg['steps'], // List of maneuvers
          'distance': leg['distance']['text'],
          'duration': leg['duration']['text'],
          'bounds': route['bounds'],
        };
      } else {
        debugPrint("Directions API Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching route: $e");
    }
    return null;
  }
}
