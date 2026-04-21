import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/screens/edit_location.dart';
import 'package:project_taxi_driver_app/services/navigation_service.dart';
import 'package:project_taxi_driver_app/screens/track_shared_ride_screen.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';
import 'package:geolocator/geolocator.dart';

class PostRideScreen extends StatefulWidget {
  final User user;
  final String vehicleClass;

  const PostRideScreen({
    super.key,
    required this.user,
    required this.vehicleClass,
  });

  @override
  State<PostRideScreen> createState() => _PostRideScreenState();
}

class _PostRideScreenState extends State<PostRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _startController = TextEditingController();
  final _destinationController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 2));
  int _totalSeats = 4;
  int _maxSeats = 4;
  double _pricePerSeat = 0;
  double _suggestedMin = 0;
  double _suggestedMax = 0;
  bool _isSubmitting = false;
  bool _priceAutoFilled = false;

  // Estimated distance in km
  double _estimatedDistanceKm = 0;
  String _routeDistanceText = "";
  String _routeDurationText = "";
  bool _isCalculatingRoute = false;

  LatLng? _startLatLng;
  LatLng? _destinationLatLng;

  static const double _pricePerKmMin = 1.6;
  static const double _pricePerKmMax = 2.4;
  static const double _suggestedFlexPercent = 0.1; // ±10%

  final _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // SUV gets 6 seats, others get 4
    if (widget.vehicleClass.toLowerCase() == 'suv') {
      _maxSeats = 6;
    } else {
      _maxSeats = 4;
    }
    // Default seats to max or 4
    _totalSeats = _maxSeats > 4 ? 4 : _maxSeats;
  }

  @override
  void dispose() {
    _startController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation(bool isStart) async {
    LatLng initial = (isStart ? _startLatLng : _destinationLatLng) ?? 
                          const LatLng(13.0827, 80.2707); // Default Fallback

    // Try to get current position from controller
    try {
      final homeController = Get.find<HomePageController>();
      if (homeController.currentPosition.value != null && (isStart ? _startLatLng : _destinationLatLng) == null) {
        initial = homeController.currentPosition.value!;
      }
    } catch (e) {
      // If controller not found, try Geolocator
      try {
        final pos = await Geolocator.getCurrentPosition();
        if ((isStart ? _startLatLng : _destinationLatLng) == null) {
          initial = LatLng(pos.latitude, pos.longitude);
        }
      } catch (_) {}
    }

    final result = await Get.to(() => EditLocationScreen(initialLocation: initial));

    if (result != null && result is Map) {
      setState(() {
        if (isStart) {
          _startLatLng = result['location'];
          _startController.text = result['address'];
        } else {
          _destinationLatLng = result['location'];
          _destinationController.text = result['address'];
        }
      });
      _fetchRouteDetails();
    }
  }

  Future<void> _fetchRouteDetails() async {
    if (_startLatLng == null || _destinationLatLng == null) return;

    setState(() {
      _isCalculatingRoute = true;
    });

    try {
      final routeData = await NavigationService().fetchRoute(_startLatLng!, _destinationLatLng!);
      
      if (routeData != null && mounted) {
        setState(() {
          _routeDistanceText = routeData['distance'] ?? "";
          _routeDurationText = routeData['duration'] ?? "";
          
          // Parse distance for calculation (e.g. "12.5 km" -> 12.5)
          final distStr = _routeDistanceText.replaceAll(RegExp(r'[^0-9.]'), '');
          _estimatedDistanceKm = double.tryParse(distStr) ?? 0;
          
          _isCalculatingRoute = false;
        });
        
        _recalculateSuggestedPrice();
      }
    } catch (e) {
      debugPrint("Error fetching route for post ride: $e");
      if (mounted) {
        setState(() => _isCalculatingRoute = false);
      }
    }
  }

  void _recalculateSuggestedPrice() {
    if (_estimatedDistanceKm <= 0) return;
    final suggested = _estimatedDistanceKm * ((_pricePerKmMin + _pricePerKmMax) / 2);
    setState(() {
      _suggestedMin = (suggested * (1 - _suggestedFlexPercent)).roundToDouble();
      _suggestedMax = (suggested * (1 + _suggestedFlexPercent)).roundToDouble();
      _pricePerSeat = suggested.roundToDouble();
      _priceAutoFilled = true;
    });
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (time == null || !mounted) return;

    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submitRide() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pricePerSeat <= 0) {
      Get.snackbar(
        'Price Required',
        'Please set a price per seat.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Fetch driver profile
      final uid = widget.user.uid;
      final driverQuery = await _db.collection('drivers').where('uid', isEqualTo: uid).limit(1).get();

      String driverName = widget.user.displayName ?? 'Driver';
      String driverPhone = widget.user.phoneNumber ?? '';
      String? driverPhotoUrl = widget.user.photoURL;
      double driverRating = 4.5;
      String vehicleModel = '';
      String vehicleNumber = '';

      if (driverQuery.docs.isNotEmpty) {
        final data = driverQuery.docs.first.data();
        driverName = data['displayName'] ?? data['name'] ?? driverName;
        driverPhone = data['phone'] ?? driverPhone;
        driverPhotoUrl = data['profileImage'] ?? driverPhotoUrl;
        driverRating = (data['rating'] as num?)?.toDouble() ?? 4.5;
        vehicleModel = data['vehicleModel'] ?? data['vehicleType'] ?? '';
        vehicleNumber = data['vehicleNumber'] ?? '';
      }

      await _db.collection('shared_rides').add({
        'driver_id': uid,
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'driver_photo_url': driverPhotoUrl,
        'driver_rating': driverRating,
        'vehicle_model': vehicleModel,
        'vehicle_number': vehicleNumber,
        'start_location': _startController.text.trim(),
        'destination': _destinationController.text.trim(),
        'start_latlng': _startLatLng != null 
            ? {'latitude': _startLatLng!.latitude, 'longitude': _startLatLng!.longitude} 
            : {'latitude': 0.0, 'longitude': 0.0},
        'destination_latlng': _destinationLatLng != null 
            ? {'latitude': _destinationLatLng!.latitude, 'longitude': _destinationLatLng!.longitude} 
            : {'latitude': 0.0, 'longitude': 0.0},
        'route_polyline': '',
        'departure_time': Timestamp.fromDate(_selectedDate),
        'total_seats': _totalSeats,
        'available_seats': _totalSeats,
        'price_per_seat': _pricePerSeat,
        'estimated_distance_km': _estimatedDistanceKm,
        'status': 'upcoming',
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Get.back();
      Get.snackbar(
        'Ride Posted!',
        'Your shared ride has been listed successfully.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade100,
        colorText: Colors.green.shade900,
        duration: const Duration(seconds: 3),
        icon: const Icon(Icons.check_circle, color: Colors.green),
      );
    } catch (e) {
      debugPrint('Error posting ride: $e');
      if (!mounted) return;
      Get.snackbar(
        'Error',
        'Failed to post ride. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final bgColor = isDark ? const Color(0xFF0E0E13) : const Color(0xFFF5F7FA);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white60 : Colors.grey.shade600;
    final fieldFill = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: const ProAppBar(
        titleText: 'Post a Ride',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Ride Tracker Button
              StreamBuilder<QuerySnapshot>(
                stream: _db
                    .collection('shared_rides')
                    .where('driver_id', isEqualTo: widget.user.uid)
                    .where('status', whereIn: ['upcoming', 'active'])
                    .limit(1)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    final ride = snapshot.data!.docs.first;
                    final rideData = ride.data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.track_changes_rounded, color: AppColors.primary, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Active Ride Found',
                                    style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Track your passengers and route',
                                    style: TextStyle(color: textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => Get.to(() => TrackSharedRideScreen(
                                    rideData: rideData,
                                    rideId: ride.id,
                                  )),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Track Ride', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Route Section
              _sectionCard(
                isDark: isDark,
                cardColor: cardColor,
                title: 'Route',
                child: Column(
                  children: [
                    _textField(
                      controller: _startController,
                      label: 'Start Location',
                      hint: 'Select takeoff point',
                      icon: Icons.my_location_rounded,
                      iconColor: AppColors.primary,
                      fillColor: fieldFill,
                      textColor: textPrimary,
                      hintColor: textSecondary,
                      readOnly: true,
                      onTap: () => _pickLocation(true),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Pick start location' : null,
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      controller: _destinationController,
                      label: 'Destination',
                      hint: 'Select arrival point',
                      icon: Icons.location_on,
                      iconColor: Colors.red.shade400,
                      fillColor: fieldFill,
                      textColor: textPrimary,
                      hintColor: textSecondary,
                      readOnly: true,
                      onTap: () => _pickLocation(false),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Pick destination' : null,
                    ),
                    if (_isCalculatingRoute)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        ),
                      )
                    else if (_routeDistanceText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.directions, color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Distance: $_routeDistanceText",
                                    style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    "Est. Duration: $_routeDurationText",
                                    style: TextStyle(color: textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                "Auto-Priced",
                                style: TextStyle(color: Colors.amber.shade700, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Departure Time
              _sectionCard(
                isDark: isDark,
                cardColor: cardColor,
                title: 'Departure Time',
                child: GestureDetector(
                  onTap: _pickDateTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: fieldFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: Colors.indigo.shade400, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('dd MMM yyyy, hh:mm a').format(_selectedDate),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right, color: textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Seats & Price
              _sectionCard(
                isDark: isDark,
                cardColor: cardColor,
                title: 'Seats & Pricing',
                child: Column(
                  children: [
                    // Total seats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Seats', style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                            Text('Available seats for passengers', style: TextStyle(color: textSecondary, fontSize: 12)),
                          ],
                        ),
                        Row(
                          children: [
                            _counterBtn(
                              icon: Icons.remove,
                              onTap: _totalSeats > 1 ? () => setState(() => _totalSeats--) : null,
                            ),
                            Container(
                              width: 44,
                              alignment: Alignment.center,
                              child: Text(
                                '$_totalSeats',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            _counterBtn(
                              icon: Icons.add,
                              onTap: _totalSeats < _maxSeats ? () => setState(() => _totalSeats++) : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Divider(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    const SizedBox(height: 14),
                    // Price per seat
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Price per Seat (₹)', style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                            if (_priceAutoFilled && _suggestedMin > 0)
                              Text(
                                'Suggested: ₹${_suggestedMin.toStringAsFixed(0)} – ₹${_suggestedMax.toStringAsFixed(0)}',
                                style: TextStyle(color: Colors.green.shade600, fontSize: 12),
                              ),
                          ],
                        ),
                        Row(
                          children: [
                            _counterBtn(
                              icon: Icons.remove,
                              onTap: _pricePerSeat > 10
                                  ? () => setState(() => _pricePerSeat = (_pricePerSeat - 10).clamp(
                                        _suggestedMin > 0 ? _suggestedMin : 10,
                                        double.infinity,
                                      ))
                                  : null,
                            ),
                            Container(
                              width: 60,
                              alignment: Alignment.center,
                              child: Text(
                                '₹${_pricePerSeat.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            _counterBtn(
                              icon: Icons.add,
                              onTap: () => setState(() {
                                final max = _suggestedMax > 0 ? _suggestedMax : double.infinity;
                                _pricePerSeat = (_pricePerSeat + 10).clamp(0, max);
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_priceAutoFilled && _suggestedMin > 0) ...[
                      const SizedBox(height: 10),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.lightEnd,
                          inactiveTrackColor: isDark ? Colors.white12 : Colors.grey.shade200,
                          thumbColor: AppColors.lightEnd,
                          overlayColor: AppColors.lightEnd.withValues(alpha: 0.15),
                        ),
                        child: Slider(
                          value: _pricePerSeat.clamp(_suggestedMin, _suggestedMax),
                          min: _suggestedMin,
                          max: _suggestedMax,
                          divisions: ((_suggestedMax - _suggestedMin) / 10).round().clamp(1, 100),
                          onChanged: (v) => setState(() => _pricePerSeat = v.roundToDouble()),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Earnings preview
              if (_pricePerSeat > 0)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: AppColors.getAppBarGradient(context),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigo.withValues(alpha: isDark ? 0.3 : 0.2),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Potential Earnings', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(
                              '₹${(_pricePerSeat * _totalSeats).toStringAsFixed(0)}',
                              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_totalSeats seats × ₹${_pricePerSeat.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              ProButton(
                text: 'Post Ride',
                isLoading: _isSubmitting,
                onPressed: _submitRide,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required bool isDark,
    required Color cardColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.transparent,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 0.5,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required Color fillColor,
    required Color textColor,
    required Color hintColor,
    VoidCallback? onTap,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      style: TextStyle(color: textColor, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hintColor.withValues(alpha: 0.7)),
        hintText: hint,
        hintStyle: TextStyle(color: hintColor.withValues(alpha: 0.4)),
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white10 
                : Colors.transparent,
          ),
        ),
        prefixIcon: Icon(icon, color: iconColor, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _counterBtn({required IconData icon, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: onTap != null 
              ? AppColors.lightEnd.withValues(alpha: 0.1) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: onTap != null 
                ? AppColors.lightEnd.withValues(alpha: 0.3) 
                : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
        child: Icon(
          icon, 
          size: 20, 
          color: onTap != null ? AppColors.lightEnd : Colors.grey,
        ),
      ),
    );
  }
}
