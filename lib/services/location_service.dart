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
          final results = parsed['results'] as List;
          
          for (var result in results) {
            final types = List<String>.from(result['types'] ?? []);
            if (types.contains('airport') ||
                types.contains('train_station') ||
                types.contains('transit_station') ||
                types.contains('bus_station')) {
              return result['formatted_address'];
            }
          }
          
          final firstResult = results[0];
          final components = firstResult['address_components'] as List;
          String? subpremise, premise, streetNumber, route, sublocality, locality;

          for (var c in components) {
            final types = List<String>.from(c['types'] ?? []);
            final longName = c['long_name'] as String;
            if (types.contains('subpremise')) subpremise = longName;
            if (types.contains('premise')) premise = longName;
            if (types.contains('street_number')) streetNumber = longName;
            if (types.contains('route')) route = longName;
            if (types.contains('sublocality')) sublocality = longName;
            if (types.contains('locality')) locality = longName;
          }

          List<String> parts = [];
          if (subpremise != null && premise != null) {
            parts.add("$subpremise, $premise");
          } else if (premise != null) {
            parts.add(premise);
          } else if (subpremise != null) {
            parts.add("Unit $subpremise");
          }

          if (streetNumber != null && route != null) {
            parts.add("$streetNumber, $route");
          } else if (route != null) {
            parts.add(route);
          }

          if (sublocality != null) parts.add(sublocality);
          if (locality != null && locality != sublocality) parts.add(locality);

          if (parts.isNotEmpty) return parts.join(", ");
          return firstResult['formatted_address'];
        }
      }
    } catch (e) {
      debugPrint("LocationService: Error resolving address: $e");
    }
    return null;
  }

  /// Returns structured location data (name and address)
  Future<Map<String, String>?> getLocalizedLocationData(
    LatLng location,
    String languageCode,
  ) async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null) return null;

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${location.latitude},${location.longitude}&key=$apiKey&language=$languageCode',
      );

      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final parsed = json.decode(response.body);
      if (parsed['status'] != 'OK' || parsed['results'].isEmpty) return null;

      final results = parsed['results'] as List;
      final firstResult = results[0];
      final components = firstResult['address_components'] as List;

      String? name;
      String? sublocality, neighborhood, premise, pointOfInterest, airport, park;

      for (var c in components) {
        final types = List<String>.from(c['types'] ?? []);
        final longName = c['long_name'] as String;

        if (types.contains('point_of_interest') || types.contains('establishment')) pointOfInterest = longName;
        if (types.contains('airport')) airport = longName;
        if (types.contains('park')) park = longName;
        if (types.contains('premise')) premise = longName;
        if (types.contains('sublocality')) sublocality = longName;
        if (types.contains('neighborhood')) neighborhood = longName;
      }

      // Priority for the "Name" field (the bold first line)
      name = airport ?? pointOfInterest ?? park ?? premise ?? sublocality ?? neighborhood;

      return {
        'name': name ?? firstResult['formatted_address'].split(',')[0],
        'address': firstResult['formatted_address'],
      };
    } catch (e) {
      debugPrint("LocationService: Error resolving structured data: $e");
    }
    return null;
  }
}
