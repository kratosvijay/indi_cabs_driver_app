import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// --- ADDED MISSING DATA MODEL ---
class PlaceAutocompletePrediction {
  final String description;
  final String placeId;

  PlaceAutocompletePrediction({
    required this.description,
    required this.placeId,
  });

  factory PlaceAutocompletePrediction.fromJson(Map<String, dynamic> json) {
    // This structure is based on the Google Places API v1 (new API)
    return PlaceAutocompletePrediction(
      description: json['placePrediction']['text']['text'] as String,
      placeId: json['placePrediction']['placeId'] as String,
    );
  }
}

class GoToScreen extends StatefulWidget {
  final Map<String, dynamic>? activeDestination;
  const GoToScreen({super.key, this.activeDestination});

  @override
  State<GoToScreen> createState() => _GoToScreenState();
}

class _GoToScreenState extends State<GoToScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // --- Places API State ---
  late final String _apiKey;
  Timer? _debounce;
  final Uuid _uuid = const Uuid();
  String? _sessionToken;
  List<PlaceAutocompletePrediction> _predictions = [];
  Map<String, dynamic>? _selectedPlace;
  List<Map<String, dynamic>> _recentGoToDestinations = [];

  @override
  void initState() {
    super.initState();
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null) throw Exception("API Key not found");
    _apiKey = apiKey;
    _sessionToken = _uuid.v4();
    _searchController.addListener(_onSearchChanged);
    _loadRecentDestinations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentDestinations() async {
    final prefs = await SharedPreferences.getInstance();
    final recentList = prefs.getStringList('recentGoTo') ?? [];
    if (mounted) {
      setState(() {
        _recentGoToDestinations = recentList
            .map((item) => jsonDecode(item) as Map<String, dynamic>)
            .toList();
      });
    }
  }

  Future<void> _deleteRecentDestination(int index) async {
    setState(() {
      _recentGoToDestinations.removeAt(index);
    });

    final prefs = await SharedPreferences.getInstance();
    final jsonList = _recentGoToDestinations
        .map((item) => jsonEncode(item))
        .toList();
    await prefs.setStringList('recentGoTo', jsonList);
  }

  Future<void> _saveRecentDestinations(
    Map<String, dynamic> newDestination,
  ) async {
    // Remove any existing entry with the same address
    _recentGoToDestinations.removeWhere(
      (item) => item['address'] == newDestination['address'],
    );
    // Add the new one to the top
    _recentGoToDestinations.insert(0, newDestination);
    // Limit to 5
    if (_recentGoToDestinations.length > 5) {
      _recentGoToDestinations = _recentGoToDestinations.sublist(0, 5);
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonList = _recentGoToDestinations
        .map((item) => jsonEncode(item))
        .toList();
    await prefs.setStringList('recentGoTo', jsonList);
  }

  void _onSearchChanged() {
    if (!_searchFocusNode.hasFocus) return;
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.isNotEmpty) {
        _fetchAutocompleteResults(_searchController.text);
      } else {
        if (mounted) setState(() => _predictions = []);
      }
    });
  }

  Future<void> _fetchAutocompleteResults(String input) async {
    if (_sessionToken == null) return;
    final uri = Uri.parse(
      'https://places.googleapis.com/v1/places:autocomplete',
    );
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
    };
    final body = jsonEncode({
      'input': input,
      'sessionToken': _sessionToken,
      'includedRegionCodes': ['in'],
    });
    final response = await http.post(uri, headers: headers, body: body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['suggestions'] != null && mounted) {
        setState(() {
          _predictions = (data['suggestions'] as List)
              .map((p) => PlaceAutocompletePrediction.fromJson(p))
              .toList();
        });
      }
    }
  }

  Future<void> _onPlaceSelected(String placeId, String description) async {
    FocusScope.of(context).unfocus();
    if (_sessionToken == null) return;
    final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
      'X-Goog-FieldMask': 'location',
    };
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final location = data['location'];
      if (location != null) {
        setState(() {
          _selectedPlace = {
            'address': description,
            'location': LatLng(location['latitude'], location['longitude']),
          };
          _searchController.text = description;
          _predictions = [];
        });
        _sessionToken = _uuid.v4();
      }
    }
  }

  Future<void> _saveAndSelectLocation(Map<String, dynamic> placeData) async {
    final destinationToSave = {
      'address': placeData['address'],
      'lat': (placeData['location'] as LatLng).latitude,
      'lng': (placeData['location'] as LatLng).longitude,
    };
    await _saveRecentDestinations(destinationToSave);
    if (mounted) {
      Get.back(result: placeData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ProAppBar(titleText: 'setGoToDestination'.tr),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ProTextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: 'enterDestination'.tr,
              icon: Icons.search,
            ),
          ),
          if (_predictions.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _predictions.length,
                itemBuilder: (context, index) {
                  final prediction = _predictions[index];
                  return ListTile(
                    leading: const Icon(Icons.location_on),
                    title: Text(prediction.description),
                    onTap: () => _onPlaceSelected(
                      prediction.placeId,
                      prediction.description,
                    ),
                  );
                },
              ),
            )
          else
            _buildRecentDestinationsList(),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ProButton(
              text: 'saveDestination'.tr,
              onPressed: _selectedPlace == null
                  ? null
                  : () => _saveAndSelectLocation(_selectedPlace!),
              // backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentDestinationsList() {
    if (_recentGoToDestinations.isEmpty) {
      return Expanded(child: Center(child: Text("noSavedDestinations".tr)));
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              "savedDestinations".tr,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _recentGoToDestinations.length,
              itemBuilder: (context, index) {
                final item = _recentGoToDestinations[index];

                // Check if this item is the ACTIVE destination
                bool isActive = false;
                if (widget.activeDestination != null) {
                  // Simple address string comparison
                  isActive =
                      widget.activeDestination!['address'] == item['address'];
                }

                return ListTile(
                  leading: Icon(
                    isActive ? Icons.location_on : Icons.location_history,
                    color: isActive ? AppColors.primary : Colors.grey,
                  ),
                  title: Text(
                    item['address'],
                    style: TextStyle(
                      color: isActive ? AppColors.primary : null,
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isActive,
                        activeThumbColor: AppColors.primary,
                        onChanged: (val) {
                          if (val) {
                            // Toggle ON: Select this location
                            final placeData = {
                              'address': item['address'],
                              'location': LatLng(item['lat'], item['lng']),
                            };
                            Get.back(result: placeData);
                          } else {
                            // Toggle OFF: Clear active destination
                            // Only if it WAS active (which it must be to toggle off)
                            Get.back(result: {'clear': true});
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _deleteRecentDestination(index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  onTap: () {
                    // Tapping row also activates it (UX choice)
                    if (!isActive) {
                      final placeData = {
                        'address': item['address'],
                        'location': LatLng(item['lat'], item['lng']),
                      };
                      Get.back(result: placeData);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
