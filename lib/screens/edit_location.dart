import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/widgets/places_service.dart';
import 'package:project_taxi_driver_app/widgets/places_models.dart';

class EditLocationScreen extends StatefulWidget {
  final LatLng initialLocation;

  const EditLocationScreen({super.key, required this.initialLocation});

  @override
  State<EditLocationScreen> createState() => _EditLocationScreenState();
}

class _EditLocationScreenState extends State<EditLocationScreen> {
  final Completer<GoogleMapController> _mapController = Completer();

  late LatLng _selectedLocation;
  String _selectedAddress = "Loading...";

  // --- Places API State ---
  late final String _apiKey;
  late final PlacesService _placesService;
  final TextEditingController _searchController = TextEditingController();
  List<PlaceAutocompletePrediction> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null) {
      throw Exception("API Key not found in .env file");
    }
    _apiKey = apiKey;
    _placesService = PlacesService(apiKey: _apiKey);
    _getAddressFromLatLng(_selectedLocation);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _placesService.cancelDebounce();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _placesService.fetchAutocompleteDebounced(
      value,
      _selectedLocation, // Bias results to the current map location
      (results) {
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      },
    );
  }

  Future<void> _onSearchResultSelected(
    PlaceAutocompletePrediction prediction,
  ) async {
    // Hide keyboard
    FocusManager.instance.primaryFocus?.unfocus();

    // Clear search and results
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _isSearching = false;
    });

    try {
      final details = await _placesService.getPlaceDetails(prediction.placeId);
      if (details != null && mounted) {
        // Validation removed per user request (Tamil Nadu-wide support)
        final controller = await _mapController.future;
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(details.location, 17),
        );
        setState(() {
          _selectedLocation = details.location;
          _selectedAddress = details.address;
        });
      }
    } catch (e) {
      debugPrint("Error getting place details: $e");
    }
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$_apiKey',
    );
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        if (mounted) {
          final address = data['results'][0]['formatted_address'];
          setState(() {
            _selectedAddress = address;
          });
        }
      }
    }
  }

  void _saveLocation() {
    // Geofence checking removed per user request
    Get.back(
      result: {'location': _selectedLocation, 'address': _selectedAddress},
    );
  }

  Future<void> _goToCurrentLocation() async {
    // Request permission if needed
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final LatLng currentLatLng = LatLng(
        position.latitude,
        position.longitude,
      );
      final controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newLatLngZoom(currentLatLng, 17));
      setState(() {
        _selectedLocation = currentLatLng;
      });
      _getAddressFromLatLng(currentLatLng);
    } catch (e) {
      debugPrint("Error getting current location: $e");
      if (mounted) {
        Get.snackbar("Error", "Could not fetch current location.", 
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.shade100,
            colorText: Colors.red.shade900);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. Google Map
          GoogleMap(
            myLocationEnabled: true,
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 17,
            ),
            myLocationButtonEnabled: false,
            mapType: MapType.normal,
            onMapCreated: (controller) {
              _mapController.complete(controller);
            },
            onCameraMove: (position) {
              _selectedLocation = position.target;
            },
            onCameraIdle: () {
              _getAddressFromLatLng(_selectedLocation);
            },
          ),

          // 2. Center Pin
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Icon(
                Icons.location_on,
                color: Colors.redAccent.shade400,
                size: 50,
                shadows: const [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),

          // 3. Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.black54 : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () => Get.back(),
              ),
            ),
          ),

          // 4. Search Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 72,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: "Search address...",
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      suffixIcon: _isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : Icon(
                              Icons.search,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : Colors.grey[200],
                      ),
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.location_on,
                            size: 20,
                            color: Colors.grey,
                          ),
                          title: Text(
                            result.description,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          onTap: () => _onSearchResultSelected(result),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // 5. "Locate Me" Button
          Positioned(
            bottom: 300,
            right: 20,
            child: FloatingActionButton(
              heroTag: 'locate_me_fab',
              onPressed: _goToCurrentLocation,
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              child: Icon(Icons.my_location, color: AppColors.primary),
            ),
          ),

          // 6. Bottom Details Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      "Select Location",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.location_on,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedAddress,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ProButton(
                      text: "Confirm Location",
                      onPressed: _saveLocation,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
