import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:project_taxi_driver_app/widgets/places_models.dart';
import 'package:uuid/uuid.dart';

class PlacesService {
  final String apiKey;
  final Uuid _uuid = const Uuid();
  String? _sessionToken;
  Timer? _debounce;

  PlacesService({required this.apiKey}) {
    // Generate initial session token
    _sessionToken = _uuid.v4();
  }

  // Fetches autocomplete predictions with debouncing
  void fetchAutocompleteDebounced(
    String input,
    LatLng? locationBias, // Optional: Bias results near user
    Function(List<PlaceAutocompletePrediction>) onResult, {
    Duration debounceDuration = const Duration(milliseconds: 400),
  }) {
    if (apiKey.isEmpty) {
      debugPrint("PlacesService Error: API Key is missing.");
      onResult([]); // Return empty list if no API key
      return;
    }
    // Cancel previous debounce timer
    cancelDebounce();

    // Start a new timer
    _debounce = Timer(debounceDuration, () {
      if (input.isNotEmpty) {
        _fetchAutocompleteResults(
          input,
          locationBias,
        ).then(onResult).catchError((e) {
          debugPrint("Error in fetchAutocompleteDebounced callback: $e");
          onResult([]); // Return empty list on error
        });
      } else {
        onResult([]); // Clear results if input is empty
      }
    });
  }

  // Actual API call for autocomplete
  Future<List<PlaceAutocompletePrediction>> _fetchAutocompleteResults(
    String input,
    LatLng? locationBias,
  ) async {
    if (_sessionToken == null) {
      debugPrint("PlacesService Error: Session token is null.");
      return []; // Return empty list if no session token
    }
    final Uri uri = Uri.parse(
      'https://places.googleapis.com/v1/places:autocomplete',
    );
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': 'suggestions', // Required for Google Places (New)
    };
    final Map<String, dynamic> body = {
      'input': input,
      'sessionToken': _sessionToken,
      'includedRegionCodes': ['in'], // Bias results towards India
      // Add location bias if provided
      if (locationBias != null)
        'locationBias': {
          'circle': {
            'center': {
              'latitude': locationBias.latitude,
              'longitude': locationBias.longitude,
            },
            'radius': 50000.0, // Bias within 50km radius (adjust as needed)
          },
        },
    };

    try {
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final suggestions = data['suggestions'] as List?;
        if (suggestions != null) {
          return suggestions
              .map(
                (p) => PlaceAutocompletePrediction.fromJson(
                  p as Map<String, dynamic>,
                ),
              )
              .toList();
        } else {
          return []; // No suggestions found
        }
      } else {
        debugPrint(
          'PlacesService Error fetching autocomplete: ${response.statusCode} ${response.reasonPhrase}',
        );
        return []; // Return empty list on API error
      }
    } catch (e) {
      debugPrint('PlacesService Exception fetching autocomplete: $e');
      return []; // Return empty list on exception
    }
  }

  // Fetches detailed information for a specific place ID
  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    if (apiKey.isEmpty) {
      debugPrint("PlacesService Error: API Key is missing.");
      return null;
    }
    if (_sessionToken == null) {
      debugPrint(
        "PlacesService Error: Session token is null for getPlaceDetails.",
      );
      return null;
    }
    final Uri uri = Uri.parse(
      'https://places.googleapis.com/v1/places/$placeId',
    );
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask':
          'id,displayName,formattedAddress,location', // Specify fields needed
      // Include session token for billing purposes
      'X-Goog-Api-Client': 'session=${_sessionToken!}',
    };

    try {
      final response = await http.get(uri, headers: headers);

      // Generate a new session token for the *next* autocomplete request
      _sessionToken = _uuid.v4();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final locationData = data['location'] as Map<String, dynamic>?;

        if (locationData?['latitude'] != null &&
            locationData?['longitude'] != null) {
          return PlaceDetails(
            placeId: placeId,
            name: data['displayName']?['text'] as String? ?? 'Unknown Name',
            address:
                data['formattedAddress'] as String? ?? 'Address not available',
            location: LatLng(
              (locationData!['latitude'] as num).toDouble(),
              (locationData['longitude'] as num).toDouble(),
            ),
          );
        } else {
          debugPrint(
            'PlacesService Error: Invalid location data in place details response.',
          );
          return null;
        }
      } else {
        debugPrint(
          'PlacesService Error fetching place details: ${response.statusCode} ${response.reasonPhrase}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('PlacesService Exception fetching place details: $e');
      _sessionToken = _uuid.v4();
      return null;
    }
  }

  // Call this to cancel any pending debounced API call
  void cancelDebounce() {
    _debounce?.cancel();
  }
}
