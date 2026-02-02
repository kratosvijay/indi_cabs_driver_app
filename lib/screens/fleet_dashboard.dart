import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added
import 'package:get/get.dart';

import 'package:project_taxi_driver_app/screens/login.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/vehicles/vehicle_list_screen.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/drivers/driver_list_screen.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/drivers/add_driver_flow.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/live_map/live_map_screen.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/analytics/fleet_analytics_screen.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/settings/fleet_settings_screen.dart';
import 'package:project_taxi_driver_app/utils/fleet_translations.dart'; // Added

class FleetDashboardScreen extends StatefulWidget {
  final User user;
  const FleetDashboardScreen({super.key, required this.user});

  @override
  State<FleetDashboardScreen> createState() => _FleetDashboardScreenState();
}

class _FleetDashboardScreenState extends State<FleetDashboardScreen> {
  // Navigation State
  int _selectedIndex = 0;
  final List<String> _menuItems = [
    "Dashboard",
    "Drivers",
    "Vehicles",
    "Live Map",
    "Analytics",
    "Settings",
  ];

  final List<IconData> _menuIcons = [
    Icons.dashboard_rounded,
    Icons.people_alt_rounded,
    Icons.directions_car_filled_rounded,
    Icons.map_rounded,
    Icons.bar_chart_rounded,
    Icons.settings_rounded,
  ];

  // Theme Constants
  final Color _bgDark = const Color(0xFF0F1115);
  final Color _cardDark = const Color(0xFF181B21);
  final Color _neonBlue = const Color(0xFF00E5FF);
  final Color _neonTeal = const Color(0xFF00FFA3);
  final Color _textWhite = Colors.white;
  final Color _textGrey = Colors.white54;

  // Stats State
  int _tripsToday = 0;
  double _revenueToday = 0.0;
  List<int> _weeklyTrips = List.filled(7, 0); // Last 7 days trip counts
  double _weeklyCompletionRate = 0.0;
  bool _isLoadingStats = true;

  // Map State
  Set<Marker> _mapMarkers = {};

  // Language State
  String _selectedLanguageCode = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _fetchDashboardStats();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguageCode = prefs.getString('selectedLanguage') ?? 'en';
      });
    }
  }

  String _t(String key) {
    return FleetTranslations.get(_selectedLanguageCode, key);
  }

  Future<void> _fetchDashboardStats() async {
    try {
      // 1. Get Drivers
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('fleetOperatorId', isEqualTo: widget.user.uid)
          .get();

      final driverIds = driversSnapshot.docs.map((d) => d.id).toList();

      // Update Map Markers
      final Set<Marker> markers = {};
      for (var doc in driversSnapshot.docs) {
        final data = doc.data();
        if (data.containsKey('currentLocation')) {
          final geoPoint = data['currentLocation'] as GeoPoint;
          final isOnline = data['isOnline'] ?? false;
          markers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: LatLng(geoPoint.latitude, geoPoint.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                isOnline ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
              ),
              infoWindow: InfoWindow(title: data['name'] ?? 'Driver'),
            ),
          );
        }
      }

      if (driverIds.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoadingStats = false;
            _mapMarkers = markers;
          });
        }
        return;
      }

      // 2. Get Recent Rides (Last 30 days logic for simplicity, or just chunked)
      // Re-using Logic from FleetAnalyticsScreen
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      int trips = 0;
      double revenue = 0.0;
      List<int> weeklyTrips = List.filled(7, 0);
      int totalPeriodRides = 0;
      int completedPeriodRides = 0;

      // Chunking logic (Limit 10 for whereIn)
      for (var i = 0; i < driverIds.length; i += 10) {
        final end = (i + 10 < driverIds.length) ? i + 10 : driverIds.length;
        final chunk = driverIds.sublist(i, end);

        final ridesSnapshot = await FirebaseFirestore.instance
            .collection('ride_requests')
            .where('driverId', whereIn: chunk)
            .get();

        for (var doc in ridesSnapshot.docs) {
          final data = doc.data();
          if (data['createdAt'] is Timestamp) {
            final date = (data['createdAt'] as Timestamp).toDate();

            // Today's Stats
            if (date.isAfter(startOfToday)) {
              trips++;
              if (data['status'] == 'completed') {
                revenue +=
                    (data['totalFare'] ??
                            data['fare'] ??
                            data['rideFare'] ??
                            0.0)
                        .toDouble();
              }
            }

            // Weekly Stats
            final difference = now.difference(date).inDays;
            if (difference < 7 && difference >= 0) {
              weeklyTrips[6 - difference]++;
            }

            // Completion Rate
            totalPeriodRides++;
            if (data['status'] == 'completed') completedPeriodRides++;
          }
        }
      }

      final rate = totalPeriodRides > 0
          ? (completedPeriodRides / totalPeriodRides) * 100
          : 0.0;

      if (mounted) {
        setState(() {
          _tripsToday = trips;
          _revenueToday = revenue;
          _weeklyTrips = weeklyTrips;
          _weeklyCompletionRate = rate;
          _mapMarkers = markers;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching dashboard stats: $e");
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Breakpoint for Mobile/Tablet
        final isMobile = constraints.maxWidth < 900;

        return PopScope(
          canPop: _selectedIndex == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            setState(() {
              _selectedIndex = 0;
            });
          },
          child: Scaffold(
            backgroundColor: _bgDark,
            // Mobile Drawer
            drawer: isMobile
                ? Drawer(
                    backgroundColor: _cardDark,
                    child: _buildSidebarContent(),
                  )
                : null,
            appBar: isMobile
                ? AppBar(
                    backgroundColor: _bgDark,
                    title: Text(
                      "Indi Cabs Fleet",
                      style: TextStyle(color: _textWhite),
                    ),
                    centerTitle: true,
                    iconTheme: IconThemeData(color: _textWhite),
                  )
                : null,
            body: Row(
              children: [
                // Desktop Sidebar (Permanent)
                if (!isMobile) _buildSidebarContent(width: 260),

                // Main Content Area
                Expanded(
                  child: Column(
                    children: [
                      // Desktop Header
                      if (!isMobile) _buildHeader(),

                      // Body Content
                      Expanded(
                        child: _selectedIndex == 3
                            ? LiveMapScreen(user: widget.user)
                            : _selectedIndex == 4
                            ? FleetAnalyticsScreen(user: widget.user)
                            : _selectedIndex == 5
                            ? FleetSettingsScreen(
                                user: widget.user,
                                onLanguageChanged: _loadLanguage,
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: _buildDashboardContent(
                                  isMobile: isMobile,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Sidebar Content (Reusable) ---
  Widget _buildSidebarContent({double? width}) {
    // If width is null, it takes available width (Drawer). Else fixed width (Sidebar).
    return Container(
      width: width,
      color: _cardDark,
      child: Column(
        children: [
          // Logo Area (Only show if width provided / desktop)
          if (width != null) ...[
            Container(
              height: 80,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: _neonBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _neonBlue),
                    ),
                    child: Icon(Icons.flash_on_rounded, color: _neonBlue),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "INDI CABS FLEET",
                    style: TextStyle(
                      color: _textWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
          ] else
            const SizedBox(height: 40), // Spacing for Drawer
          // Menu Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 20),
              itemCount: _menuItems.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedIndex == index;
                // Translate the menu item key
                final label = _t(_menuItems[index]);
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        // Close drawer if mobile
                        if (width == null) Get.back();

                        // Navigation Logic
                        if (_menuItems[index] == "Vehicles") {
                          Get.to(() => const VehicleListScreen());
                        } else if (_menuItems[index] == "Drivers") {
                          Get.to(() => const DriverListScreen());
                        } else {
                          setState(() => _selectedIndex = index);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _neonBlue.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: _neonBlue.withValues(alpha: 0.5),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _menuIcons[index],
                              color: isSelected ? _neonBlue : _textGrey,
                              size: 22,
                            ),
                            const SizedBox(width: 16),
                            // Sidebar Menu Item Fix
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: isSelected ? _textWhite : _textGrey,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // User Profile Snippet
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey[800],
                  child: const Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.displayName ?? "Operator",
                        style: TextStyle(
                          color: _textWhite,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "Admin",
                        style: TextStyle(color: _neonTeal, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.logout,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: _logout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Header ---
  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: _bgDark,
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(_menuItems[_selectedIndex]),
                  style: TextStyle(
                    color: _textWhite,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _t('realTimeOverview'),
                  style: TextStyle(color: _textGrey, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Search Bar
          Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: _textGrey),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    style: TextStyle(color: _textWhite),
                    decoration: InputDecoration(
                      hintText: _t('searchHint'),
                      hintStyle: TextStyle(color: _textGrey),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Notifications
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.notifications_none_rounded, color: _textWhite),
                onPressed: () {},
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(
                    color: _neonBlue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Main Content ---
  Widget _buildDashboardContent({bool isMobile = false}) {
    // Show different content based on selected index
    if (_selectedIndex == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Stats Row - Responsive
          if (isMobile)
            Wrap(
              runSpacing: 16,
              spacing: 16,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('vehicles')
                        .where('ownerId', isEqualTo: widget.user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final count = snapshot.hasData
                          ? snapshot.data!.docs.length
                          : 0;
                      return _buildStatCard(
                        title: _t('totalVehicles'),
                        value: "$count",
                        trend: "+0%",
                        icon: Icons.directions_car,
                        color: _neonBlue,
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('drivers')
                        .where('role', isEqualTo: 'fleet_driver')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final count = snapshot.hasData
                          ? snapshot.data!.docs.length
                          : 0;
                      return _buildStatCard(
                        title: _t('activeDrivers'),
                        value: "$count",
                        trend: "+0%",
                        icon: Icons.person_pin_circle,
                        color: _neonTeal,
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: _buildStatCard(
                    title: _t('tripsToday'),
                    value: _isLoadingStats ? "..." : "$_tripsToday",
                    trend: "+0%",
                    icon: Icons.trip_origin,
                    color: Colors.purpleAccent,
                  ),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: _buildStatCard(
                    title: _t('revenue'),
                    value: _isLoadingStats
                        ? "..."
                        : "₹${_revenueToday.toStringAsFixed(0)}",
                    trend: "+0%",
                    icon: Icons.currency_rupee,
                    color: Colors.orangeAccent,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('vehicles')
                        .where('ownerId', isEqualTo: widget.user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final count = snapshot.hasData
                          ? snapshot.data!.docs.length
                          : 0;
                      return _buildStatCard(
                        title: _t('totalVehicles'),
                        value: "$count",
                        trend: "+0%",
                        icon: Icons.directions_car,
                        color: _neonBlue,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('drivers')
                        .where('role', isEqualTo: 'fleet_driver')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final count = snapshot.hasData
                          ? snapshot.data!.docs.length
                          : 0;
                      return _buildStatCard(
                        title: _t('activeDrivers'),
                        value: "$count",
                        trend: "+0%",
                        icon: Icons.person_pin_circle,
                        color: _neonTeal,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildStatCard(
                    title: _t('tripsToday'),
                    value: _isLoadingStats ? "..." : "$_tripsToday",
                    trend: "+0%",
                    icon: Icons.trip_origin,
                    color: Colors.purpleAccent,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildStatCard(
                    title: _t('revenue'),
                    value: _isLoadingStats
                        ? "..."
                        : "₹${_revenueToday.toStringAsFixed(0)}",
                    trend: "+0%",
                    icon: Icons.currency_rupee,
                    color: Colors.orangeAccent,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 32),

          // 2. Middle Section: Live Map + Analytics
          // Use LayoutBuilder or isMobile check
          if (isMobile)
            Column(
              children: [
                SizedBox(height: 300, child: _buildLiveMapPanel()),
                const SizedBox(height: 24),
                // No fixed height for generic column, let it stack
                _buildAnalyticsPanel(isMobile: true),
              ],
            )
          else
            SizedBox(
              height: 500,
              child: Row(
                children: [
                  // Live Map PAnel
                  Expanded(flex: 2, child: _buildLiveMapPanel()),
                  const SizedBox(width: 24),
                  // Analytics Panel
                  Expanded(flex: 1, child: _buildAnalyticsPanel()),
                ],
              ),
            ),
        ],
      );
    }

    // Placeholder for other tabs
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_menuIcons[_selectedIndex], size: 64, color: _textGrey),
          const SizedBox(height: 16),
          Text(
            "${_t('section')} ${_t(_menuItems[_selectedIndex])}",
            style: TextStyle(color: _textWhite, fontSize: 24),
          ),
          const SizedBox(height: 8),
          Text(_t('comingSoon'), style: TextStyle(color: _neonBlue)),
        ],
      ),
    );
  }

  // --- Extracted Panels for cleaner code ---

  Widget _buildLiveMapPanel() {
    return _buildGlassCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _t('liveTracking'),
                    style: TextStyle(
                      color: _textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        "LIVE",
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[900],
                border: Border.all(color: Colors.white10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(17.3850, 78.4867), // Default Hyderabad
                    zoom: 10,
                  ),
                  onMapCreated: (controller) {},
                  markers: _mapMarkers,
                  mapType: MapType.normal,
                  zoomControlsEnabled: true,
                  liteModeEnabled: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsPanel({bool isMobile = false}) {
    // Inner widgets
    final performanceCard = _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('fleetPerformance'),
              style: TextStyle(
                color: _textWhite,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (isMobile) const SizedBox(height: 20) else const Spacer(),
            // Real Chart (Weekly Trips)
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY:
                      (_weeklyTrips.isNotEmpty &&
                          _weeklyTrips.reduce((a, b) => a > b ? a : b) > 0)
                      ? (_weeklyTrips.reduce((a, b) => a > b ? a : b) * 1.2)
                            .toDouble()
                      : 10.0,
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(7, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: _weeklyTrips[index].toDouble(),
                          color: _neonBlue,
                          width: 12,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_t('completionRate'), style: TextStyle(color: _textGrey)),
                Text(
                  "${_weeklyCompletionRate.toStringAsFixed(1)}%",
                  style: TextStyle(
                    color: _neonTeal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final quickActionsCard = _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('quickActions'),
              style: TextStyle(
                color: _textWhite,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 20),
            _buildQuickActionButton(
              _t('addNewDriver'),
              Icons.person_add,
              _neonBlue,
              () => Get.to(() => const FleetDriverOnboardingScreen()),
            ),
            const SizedBox(height: 12),
            _buildQuickActionButton(
              _t('registerVehicle'),
              Icons.directions_car,
              _neonTeal,
              () => Get.to(() => const VehicleListScreen()),
            ),
          ],
        ),
      ),
    );

    if (isMobile) {
      return Column(
        children: [
          // Fixed heights for mobile specific
          SizedBox(height: 280, child: performanceCard),
          const SizedBox(height: 24),
          SizedBox(height: 280, child: quickActionsCard),
        ],
      );
    } else {
      return Column(
        children: [
          Expanded(child: performanceCard),
          const SizedBox(height: 24),
          Expanded(child: quickActionsCard),
        ],
      );
    }
  }

  // --- Widgets ---

  Widget _buildStatCard({
    required String title,
    required String value,
    required String trend,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trend,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            value,
            style: TextStyle(
              color: _textWhite,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: _textGrey, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }

  Widget _buildQuickActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(16),
            color: color.withValues(alpha: 0.05),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: _textWhite,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // --- Logic ---
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Get.offAll(() => const LoginScreen());
    }
  }
}
