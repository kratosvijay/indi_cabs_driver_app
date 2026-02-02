// ignore_for_file: avoid_types_as_parameter_names

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:project_taxi_driver_app/screens/ride_details.dart';

import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/screens/wallet_screen.dart';
import 'package:project_taxi_driver_app/widgets/faq_sheet.dart';
import 'package:project_taxi_driver_app/utils/faq_data.dart';
import 'package:project_taxi_driver_app/services/location_service.dart';

import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:http/http.dart' as http;

// --- Updated Data Models ---

enum RideStatus { completed, cancelled, missed }

class Ride {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final double distance;
  final String time;
  final double earnings;
  final DateTime timestamp;
  final LatLng pickupLocation;
  final LatLng dropoffLocation;
  final RideStatus status;
  final String? cancelledBy; // 'Driver' or 'Customer'

  Ride({
    required this.id,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.distance,
    required this.time,
    required this.earnings,
    required this.timestamp,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.status,
    this.cancelledBy,
    this.stops = const [],
    this.rideType = 'daily',
    this.packageName,
    this.extraTimeCost,
    this.extraDistanceCost,
  });

  final List<RideStop> stops;
  final String rideType;
  final String? packageName;
  final double? extraTimeCost;
  final double? extraDistanceCost;

  factory Ride.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // debugPrint("Ride Data for ${doc.id}: $data");

    RideStatus status = RideStatus.completed;
    if (data['status'] == 'cancelled') {
      status = RideStatus.cancelled;
    } else if (data['status'] == 'missed') {
      status = RideStatus.missed;
    }

    // Handle GeoPoints
    LatLng pickup = const LatLng(0, 0);
    if (data['pickupLocation'] != null) {
      if (data['pickupLocation'] is GeoPoint) {
        final p = data['pickupLocation'] as GeoPoint;
        pickup = LatLng(p.latitude, p.longitude);
      } else if (data['pickupLocation'] is Map) {
        final p = data['pickupLocation'] as Map<String, dynamic>;
        pickup = LatLng(p['latitude'] ?? 0, p['longitude'] ?? 0);
      }
    }

    LatLng dropoff = const LatLng(0, 0);
    final dropoffData = data['dropoffLocation'] ?? data['destinationLocation'];
    if (dropoffData != null) {
      if (dropoffData is GeoPoint) {
        final d = dropoffData;
        dropoff = LatLng(d.latitude, d.longitude);
      } else if (dropoffData is Map) {
        final d = dropoffData as Map<String, dynamic>;
        dropoff = LatLng(d['latitude'] ?? 0, d['longitude'] ?? 0);
      }
    }

    // Handle Timestamp
    DateTime timestamp = DateTime.now();
    if (data['completedAt'] != null) {
      timestamp = (data['completedAt'] as Timestamp).toDate();
    } else if (data['createdAt'] != null) {
      timestamp = (data['createdAt'] as Timestamp).toDate();
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is int) return value.toDouble();
      if (value is double) return value;
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return Ride(
      id: doc.id,
      pickupAddress:
          data['pickupTitle'] ??
          data['pickupFullAddress'] ??
          data['pickupAddress'] ??
          'Unknown Pickup',
      dropoffAddress:
          data['dropoffTitle'] ??
          data['dropoffFullAddress'] ??
          data['dropoffAddress'] ??
          data['destinationAddress'] ??
          'Unknown Dropoff',
      // Fix: Prioritize actualDistance (from ride completion) over estimated rideDistance
      distance: parseDouble(data['actualDistance'] ?? data['rideDistance']),
      // Fix: Calculate time if actualDuration is present, else default
      time: data['actualDuration'] != null
          ? '${parseDouble(data['actualDuration']).toStringAsFixed(0)} min'
          : '0 min',
      earnings: parseDouble(data['rideFare']) + parseDouble(data['tip']),
      timestamp: timestamp,
      pickupLocation: pickup,
      dropoffLocation: dropoff,
      status: status,
      cancelledBy: data['cancelledBy'],
      stops: _parseStops(data['intermediateStops']),
      rideType: data['rideType'] ?? 'daily',
      packageName: data['packageName'],
      extraTimeCost: parseDouble(data['extraTimeCost']),
      extraDistanceCost: parseDouble(data['extraDistanceCost']),
    );
  }

  static List<RideStop> _parseStops(dynamic rawStops) {
    if (rawStops == null || rawStops is! List) return [];
    return rawStops.map((s) {
      final loc = s['location'];
      double lat = 0.0;
      double lng = 0.0;
      if (loc is GeoPoint) {
        lat = loc.latitude;
        lng = loc.longitude;
      } else if (loc is Map) {
        lat = (loc['latitude'] as num).toDouble();
        lng = (loc['longitude'] as num).toDouble();
      }
      return RideStop(
        title: s['address']?.split(',')[0] ?? 'Stop',
        fullAddress: s['address'] ?? '',
        location: LatLng(lat, lng),
      );
    }).toList();
  }
}

class EarningsScreen extends StatefulWidget {
  final User user;
  const EarningsScreen({super.key, required this.user});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  late TabController _tabController;

  List<Ride> _allRides = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchRides();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchRides() async {
    try {
      // Fetch Daily Rides
      final dailySnapshot = await FirebaseFirestore.instance
          .collection('ride_requests')
          .where('driverId', isEqualTo: widget.user.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      // Fetch Rental Rides
      final rentalSnapshot = await FirebaseFirestore.instance
          .collection('rental_requests')
          .where('driverId', isEqualTo: widget.user.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final dailyRides = dailySnapshot.docs.map(
        (doc) => Ride.fromFirestore(doc),
      );
      final rentalRides = rentalSnapshot.docs.map(
        (doc) => Ride.fromFirestore(doc),
      );

      final allRides = [...dailyRides, ...rentalRides];
      // Sort combined list by timestamp descending
      allRides.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Limit to 100 recent
      final rides = allRides.take(100).toList();

      if (mounted) {
        setState(() {
          _allRides = rides;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching rides: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: ProAppBar(title: Text('earnings'.tr)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = null;
                    });
                    _fetchRides();
                  },
                  child: Text('retry'.tr),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: ProAppBar(
        title: Text('earnings'.tr),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    Get.bottomSheet(
                      FAQSheet(
                        title: "earningsHelp".tr,
                        faqs: FAQData.earningsFAQs,
                      ),
                    );
                  },
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                ),
                IconButton(
                  onPressed: () {
                    Get.to(() => WalletScreen(user: widget.user));
                  },
                  icon: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'daily'.tr),
            Tab(text: 'weekly'.tr),
            Tab(text: 'monthly'.tr),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          DailyEarningsView(allRides: _allRides),
          WeeklyEarningsView(allRides: _allRides),
          MonthlyEarningsView(allRides: _allRides),
        ],
      ),
    );
  }
}

// --- Daily View ---
class DailyEarningsView extends StatefulWidget {
  final List<Ride> allRides;
  const DailyEarningsView({super.key, required this.allRides});

  @override
  State<DailyEarningsView> createState() => _DailyEarningsViewState();
}

class _DailyEarningsViewState extends State<DailyEarningsView> {
  late List<DateTime> _dates;
  late DateTime _selectedDate;
  final ScrollController _scrollController = ScrollController();
  RideStatus _selectedStatus = RideStatus.completed;

  // Helper to get rides for a specific date
  List<Ride> _getRidesForDate(DateTime date) {
    return widget.allRides.where((ride) {
      return ride.timestamp.year == date.year &&
          ride.timestamp.month == date.month &&
          ride.timestamp.day == date.day;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _initializeDates();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedDate(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeDates() {
    _dates = [];
    final today = DateTime.now();
    _selectedDate = DateTime(today.year, today.month, today.day);
    for (int i = 0; i < 15; i++) {
      final date = today.subtract(Duration(days: i));
      _dates.add(DateTime(date.year, date.month, date.day));
    }
    _dates = _dates.reversed.toList();
  }

  void _scrollToSelectedDate() {
    if (!_scrollController.hasClients) return;
    final selectedIndex = _dates.indexOf(_selectedDate);
    if (selectedIndex != -1) {
      final itemWidth = 70.0;
      final screenWidth = MediaQuery.of(context).size.width;
      final offset =
          (selectedIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Ride> ridesForSelectedDate = _getRidesForDate(_selectedDate);
    List<Ride> completedRides = ridesForSelectedDate
        .where((r) => r.status == RideStatus.completed)
        .toList();
    List<Ride> cancelledRides = ridesForSelectedDate
        .where((r) => r.status == RideStatus.cancelled)
        .toList();
    List<Ride> missedRides = ridesForSelectedDate
        .where((r) => r.status == RideStatus.missed)
        .toList();
    double totalEarnings = completedRides.fold(
      0.0,
      (sum, ride) => sum + ride.earnings,
    );

    List<Ride> displayedRides;
    switch (_selectedStatus) {
      case RideStatus.completed:
        displayedRides = completedRides;
        break;
      case RideStatus.cancelled:
        displayedRides = cancelledRides;
        break;
      case RideStatus.missed:
        displayedRides = missedRides;
        break;
    }

    return Column(
      children: [
        // Date Scroller
        Container(
          height: 80,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[900]
              : Colors.grey[200],
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: _dates.length,
            itemBuilder: (context, index) {
              final date = _dates[index];
              final isSelected = date == _selectedDate;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return GestureDetector(
                onTap: () => setState(() => _selectedDate = date),
                child: Container(
                  width: 60,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(date),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date.day.toString(),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Total Earnings Card
        Card(
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "${DateFormat('MMMM d').format(_selectedDate)} ${'earnings'.tr}",
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "₹${totalEarnings.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Summary Cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              GestureDetector(
                onTap: () =>
                    setState(() => _selectedStatus = RideStatus.completed),
                child: _buildSummaryCard(
                  "All Rides",
                  completedRides.length.toString(),
                  Colors.blue,
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _selectedStatus = RideStatus.cancelled),
                child: _buildSummaryCard(
                  "Cancelled",
                  cancelledRides.length.toString(),
                  Colors.red,
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _selectedStatus = RideStatus.missed),
                child: _buildSummaryCard(
                  "Missed",
                  missedRides.length.toString(),
                  Colors.orange,
                ),
              ),
            ],
          ),
        ),
        // Ride List
        Expanded(
          child: displayedRides.isEmpty
              ? const Center(child: Text("No rides for this day."))
              : ListView.builder(
                  itemCount: displayedRides.length,
                  itemBuilder: (context, index) {
                    final ride = displayedRides[index];
                    return RideListItem(ride: ride);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(title),
          ],
        ),
      ),
    );
  }
}

// --- Weekly View ---
class WeeklyEarningsView extends StatefulWidget {
  final List<Ride> allRides;
  const WeeklyEarningsView({super.key, required this.allRides});

  @override
  State<WeeklyEarningsView> createState() => _WeeklyEarningsViewState();
}

class _WeeklyEarningsViewState extends State<WeeklyEarningsView> {
  late List<DateTime> _weekStarts;
  late DateTime _selectedWeekStart;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeWeeks();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedDate(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeWeeks() {
    _weekStarts = [];
    final today = DateTime.now();
    _selectedWeekStart = today.subtract(Duration(days: today.weekday - 1));
    _selectedWeekStart = DateTime(
      _selectedWeekStart.year,
      _selectedWeekStart.month,
      _selectedWeekStart.day,
    );

    for (int i = 0; i < 5; i++) {
      final weekStart = _selectedWeekStart.subtract(Duration(days: i * 7));
      _weekStarts.add(weekStart);
    }
    _weekStarts = _weekStarts.reversed.toList();
  }

  void _scrollToSelectedDate() {
    if (!_scrollController.hasClients) return;
    final selectedIndex = _weekStarts.indexOf(_selectedWeekStart);
    if (selectedIndex != -1) {
      final itemWidth = 140.0;
      final screenWidth = MediaQuery.of(context).size.width;
      final offset =
          (selectedIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final ridesForSelectedWeek = widget.allRides.where((ride) {
      return ride.timestamp.isAfter(
            _selectedWeekStart.subtract(const Duration(microseconds: 1)),
          ) &&
          ride.timestamp.isBefore(weekEnd.add(const Duration(days: 1)));
    }).toList();
    final completedRides = ridesForSelectedWeek
        .where((r) => r.status == RideStatus.completed)
        .toList();
    final int cancelledRides = ridesForSelectedWeek
        .where((r) => r.status == RideStatus.cancelled)
        .length;
    final int missedRides = ridesForSelectedWeek
        .where((r) => r.status == RideStatus.missed)
        .length;
    final double totalEarnings = completedRides.fold(
      0.0,
      (sum, ride) => sum + ride.earnings,
    );

    return Column(
      children: [
        Container(
          height: 80,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[900]
              : Colors.grey[200],
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: _weekStarts.length,
            itemBuilder: (context, index) {
              final date = _weekStarts[index];
              final isSelected = date == _selectedWeekStart;
              final endOfWeek = date.add(const Duration(days: 6));
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return GestureDetector(
                onTap: () => setState(() => _selectedWeekStart = date),
                child: Container(
                  width: 130,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      "${DateFormat('MMM d').format(date)} - ${DateFormat('MMM d').format(endOfWeek)}",
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Card(
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "weekEarnings".tr,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "₹${totalEarnings.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryCard(
                "allRides".tr,
                completedRides.length.toString(),
                Colors.blue,
              ),
              _buildSummaryCard(
                "cancelled".tr,
                cancelledRides.toString(),
                Colors.red,
              ),
              _buildSummaryCard(
                "missed".tr,
                missedRides.toString(),
                Colors.orange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(title),
          ],
        ),
      ),
    );
  }
}

// --- Monthly View ---
class MonthlyEarningsView extends StatefulWidget {
  final List<Ride> allRides;
  const MonthlyEarningsView({super.key, required this.allRides});

  @override
  State<MonthlyEarningsView> createState() => _MonthlyEarningsViewState();
}

class _MonthlyEarningsViewState extends State<MonthlyEarningsView> {
  late List<DateTime> _months;
  late DateTime _selectedMonth;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeMonths();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedDate(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeMonths() {
    _months = [];
    final today = DateTime.now();
    _selectedMonth = DateTime(today.year, today.month);
    for (int i = 0; i < 5; i++) {
      _months.add(DateTime(today.year, today.month - i));
    }
    _months = _months.reversed.toList();
  }

  void _scrollToSelectedDate() {
    if (!_scrollController.hasClients) return;
    final selectedIndex = _months.indexOf(_selectedMonth);
    if (selectedIndex != -1) {
      final itemWidth = 110.0;
      final screenWidth = MediaQuery.of(context).size.width;
      final offset =
          (selectedIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ridesForSelectedMonth = widget.allRides.where((ride) {
      return ride.timestamp.year == _selectedMonth.year &&
          ride.timestamp.month == _selectedMonth.month;
    }).toList();
    final completedRides = ridesForSelectedMonth
        .where((r) => r.status == RideStatus.completed)
        .toList();
    final int cancelledRides = ridesForSelectedMonth
        .where((r) => r.status == RideStatus.cancelled)
        .length;
    final int missedRides = ridesForSelectedMonth
        .where((r) => r.status == RideStatus.missed)
        .length;
    final double totalEarnings = completedRides.fold(
      0.0,
      (sum, ride) => sum + ride.earnings,
    );

    return Column(
      children: [
        Container(
          height: 80,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[900]
              : Colors.grey[200],
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: _months.length,
            itemBuilder: (context, index) {
              final date = _months[index];
              final isSelected = date == _selectedMonth;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return GestureDetector(
                onTap: () => setState(() => _selectedMonth = date),
                child: Container(
                  width: 100,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      DateFormat('MMMM').format(date),
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Card(
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "monthEarnings".tr,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "₹${totalEarnings.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryCard(
                "allRides".tr,
                completedRides.length.toString(),
                Colors.blue,
              ),
              _buildSummaryCard(
                "cancelled".tr,
                cancelledRides.toString(),
                Colors.red,
              ),
              _buildSummaryCard(
                "missed".tr,
                missedRides.toString(),
                Colors.orange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(title),
          ],
        ),
      ),
    );
  }
}

class RideListItem extends StatefulWidget {
  final Ride ride;
  const RideListItem({super.key, required this.ride});

  @override
  State<RideListItem> createState() => _RideListItemState();
}

class _RideListItemState extends State<RideListItem> {
  String? _translatedPickup;
  String? _translatedDropoff;

  @override
  void initState() {
    super.initState();
    _translateAddresses();
  }

  Future<void> _translateAddresses() async {
    // Only translate if we have a valid key and it's not English
    final langCode = Get.locale?.languageCode ?? 'en';
    if (langCode == 'en') return;

    // Parallel fetch
    final results = await Future.wait([
      LocationService().getLocalizedAddress(
        widget.ride.pickupLocation,
        langCode,
      ),
      LocationService().getLocalizedAddress(
        widget.ride.dropoffLocation,
        langCode,
      ),
    ]);

    if (mounted) {
      setState(() {
        if (results[0] != null) _translatedPickup = results[0];
        if (results[1] != null) _translatedDropoff = results[1];
      });
    }
  }

  String _shortenAddress(String address) {
    if (address.isEmpty || address == 'Unknown') return address;
    // If it looks like a full address (has commas), take first 2 parts
    if (address.contains(',')) {
      final parts = address.split(',');
      if (parts.length > 2) {
        return "${parts[0].trim()}, ${parts[1].trim()}";
      }
    }
    return address;
  }

  @override
  Widget build(BuildContext context) {
    final displayDropoff = _translatedDropoff ?? widget.ride.dropoffAddress;
    final displayPickup = _translatedPickup ?? widget.ride.pickupAddress;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        title: Text("To: ${_shortenAddress(displayDropoff)}"),
        subtitle: Text("From: ${_shortenAddress(displayPickup)}"),
        trailing: widget.ride.status == RideStatus.completed
            ? Text(
                "₹${widget.ride.earnings.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green,
                ),
              )
            : Text(
                widget.ride.status.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.ride.status == RideStatus.cancelled
                      ? Colors.red
                      : Colors.orange,
                ),
              ),
        onTap: () {
          Get.to(() => RideDetailsScreen(ride: widget.ride));
        },
      ),
    );
  }
}
