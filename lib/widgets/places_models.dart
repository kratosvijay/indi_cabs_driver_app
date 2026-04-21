import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Model for Google Places API Autocomplete predictions
class PlaceAutocompletePrediction {
  final String description;
  final String placeId;
  final String mainText;
  final String secondaryText;

  PlaceAutocompletePrediction({
    required this.description,
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlaceAutocompletePrediction.fromJson(Map<String, dynamic> json) {
    debugPrint("Autocomplete Prediction JSON: $json");
    final prediction = json['placePrediction'] ?? json['prediction'] ?? json;
    
    final textData = prediction['text'] as Map<String, dynamic>?;
    final description = textData?['text'] as String? ?? 'Unknown Prediction';
    final placeId = prediction['placeId'] as String? ?? '';

    // Extract structured formatting if available (Google Places API New)
    final structuredFormat = prediction['structuredFormat'] as Map<String, dynamic>?;
    final mainText = structuredFormat?['mainText']?['text'] as String? ?? description;
    final secondaryText = structuredFormat?['secondaryText']?['text'] as String? ?? '';

    return PlaceAutocompletePrediction(
      description: description,
      placeId: placeId,
      mainText: mainText,
      secondaryText: secondaryText,
    );
  }
}

// Model for Google Places API Details response
class PlaceDetails {
  final String placeId;
  final String name;
  final String address;
  final LatLng location;

  PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json, String id) {
    final locationData = json['location'] as Map<String, dynamic>?;
    final lat = (locationData?['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (locationData?['longitude'] as num?)?.toDouble() ?? 0.0;

    return PlaceDetails(
      placeId: id,
      name: json['displayName']?['text'] as String? ?? 'Unknown Name',
      address: json['formattedAddress'] as String? ?? 'Unknown Address',
      location: LatLng(lat, lng),
    );
  }
}
