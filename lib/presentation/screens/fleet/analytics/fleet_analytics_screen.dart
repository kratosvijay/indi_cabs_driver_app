import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FleetAnalyticsScreen extends StatefulWidget {
  final User user;
  const FleetAnalyticsScreen({super.key, required this.user});

  @override
  State<FleetAnalyticsScreen> createState() => _FleetAnalyticsScreenState();
}

class _FleetAnalyticsScreenState extends State<FleetAnalyticsScreen> {
  // Stats
  double totalRevenue = 0.0;
  int completedRides = 0;
  int cancelledRides = 0;
  int activeRides = 0;
  int totalRides = 0;
  bool isLoading = true;

  // Chart Data
  List<double> weeklyRevenue = List.filled(7, 0.0); // Last 7 days
  final List<String> weekDays = [];

  // Theme Colors
  final Color _bgDark = const Color(0xFF0F1115);
  final Color _cardDark = const Color(0xFF181B21);
  final Color _neonBlue = const Color(0xFF00E5FF);
  final Color _neonGreen = const Color(0xFF00FFA3);
  final Color _neonRed = const Color(0xFFFF2E63);
  final Color _textWhite = Colors.white;
  final Color _textGrey = Colors.white54;

  @override
  void initState() {
    super.initState();
    _initDays();
    _fetchAnalytics();
  }

  void _initDays() {
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      weekDays.add(DateFormat('E').format(now.subtract(Duration(days: i))));
    }
  }

  Future<void> _fetchAnalytics() async {
    try {
      // 1. Get Drivers
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('fleetOperatorId', isEqualTo: widget.user.uid)
          .get();

      final driverIds = driversSnapshot.docs.map((d) => d.id).toList();

      if (driverIds.isEmpty) {
        setState(() => isLoading = false);
        return;
      }

      // 2. Get Rides (Chunked because 'whereIn' limits to 10)
      List<QueryDocumentSnapshot> allRides = [];

      // Chunking logic
      for (var i = 0; i < driverIds.length; i += 10) {
        final end = (i + 10 < driverIds.length) ? i + 10 : driverIds.length;
        final chunk = driverIds.sublist(i, end);

        final ridesSnapshot = await FirebaseFirestore.instance
            .collection('ride_requests')
            .where('driverId', whereIn: chunk)
            // .where('createdAt', isGreaterThan: DateTime.now().subtract(const Duration(days: 30))) // Optional optimization
            .get();

        allRides.addAll(ridesSnapshot.docs);
      }

      // 3. Process Data
      double revenue = 0;
      int completed = 0;
      int cancelled = 0;
      int active = 0;
      List<double> localWeeklyRevenue = List.filled(7, 0.0);
      final now = DateTime.now();

      for (var doc in allRides) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'];
        final fare =
            (data['totalFare'] ?? data['fare'] ?? data['rideFare'] ?? 0.0)
                .toDouble();

        Timestamp? createdAt;
        if (data['createdAt'] is Timestamp) {
          createdAt = data['createdAt'];
        }

        // Aggregate counts
        if (status == 'completed') {
          completed++;
          revenue += fare;

          // Revenue Chart Logic
          if (createdAt != null) {
            final date = createdAt.toDate();
            final difference = now.difference(date).inDays;
            if (difference < 7 && difference >= 0) {
              // Index 6 is today, 0 is 6 days ago
              // difference 0 -> index 6
              // difference 6 -> index 0
              localWeeklyRevenue[6 - difference] += fare;
            }
          }
        } else if (status == 'cancelled') {
          cancelled++;
        } else if (status == 'started' ||
            status == 'arrived' ||
            status == 'accepted') {
          active++;
        }
      }

      if (mounted) {
        setState(() {
          totalRevenue = revenue;
          completedRides = completed;
          cancelledRides = cancelled;
          activeRides = active;
          totalRides = allRides.length;
          weeklyRevenue = localWeeklyRevenue;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching analytics: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: _neonBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildSummaryCards(),
                  const SizedBox(height: 24),
                  _buildRevenueChart(),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 900) {
                        return Column(
                          children: [
                            _buildStatusChart(),
                            const SizedBox(height: 24),
                            _buildEfficiencyCard(),
                          ],
                        );
                      } else {
                        return Row(
                          children: [
                            Expanded(child: _buildStatusChart()),
                            const SizedBox(width: 24),
                            Expanded(child: _buildEfficiencyCard()),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Fleet Analytics",
          style: TextStyle(
            color: _textWhite,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          "Real-time performance insights",
          style: TextStyle(color: _textGrey, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final children = [
          _buildStatCard(
            "Total Revenue",
            "₹${totalRevenue.toStringAsFixed(0)}",
            Icons.currency_rupee,
            _neonGreen,
          ),
          _buildStatCard(
            "Total Rides",
            "$totalRides",
            Icons.directions_car,
            _neonBlue,
          ),
          _buildStatCard(
            "Completed",
            "$completedRides",
            Icons.check_circle,
            Colors.purpleAccent,
          ),
          _buildStatCard(
            "Cancelled",
            "$cancelledRides",
            Icons.cancel,
            _neonRed,
          ),
        ];

        if (isMobile) {
          return GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.0, // Adjusted to prevent overflow (was 1.3)
            children: children,
          );
        } else {
          return Row(
            children: children
                .map(
                  (c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: c,
                    ),
                  ),
                )
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(16),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              color: _textWhite,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: _textGrey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      height: 350, // Fixed height for chart
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Revenue Trends (Last 7 Days)",
            style: TextStyle(
              color: _textWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY:
                    (weeklyRevenue.reduce(
                          (curr, next) => curr > next ? curr : next,
                        ) *
                        1.2) +
                    100, // Dynamic MaxY
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '₹${rod.toY.round()}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        if (value.toInt() >= 0 &&
                            value.toInt() < weekDays.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              weekDays[value.toInt()],
                              style: TextStyle(color: _textGrey, fontSize: 12),
                            ),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text(
                          '${value ~/ 1000}k',
                          style: TextStyle(color: _textGrey, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withValues(alpha: 0.05),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(7, (index) {
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: weeklyRevenue[index],
                        color: _neonBlue,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY:
                              (weeklyRevenue.reduce(
                                    (curr, next) => curr > next ? curr : next,
                                  ) *
                                  1.2) +
                              100,
                          color: Colors.white.withValues(alpha: 0.02),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChart() {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Ride Status",
            style: TextStyle(
              color: _textWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(
                    color: _neonGreen,
                    value: completedRides.toDouble(),
                    title:
                        '${((completedRides / (totalRides == 0 ? 1 : totalRides)) * 100).toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    color: _neonRed,
                    value: cancelledRides.toDouble(),
                    title:
                        '${((cancelledRides / (totalRides == 0 ? 1 : totalRides)) * 100).toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    color: _neonBlue,
                    value: activeRides.toDouble(),
                    title:
                        '${((activeRides / (totalRides == 0 ? 1 : totalRides)) * 100).toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem("Done", _neonGreen),
              const SizedBox(width: 16),
              _buildLegendItem("Cancel", _neonRed),
              const SizedBox(width: 16),
              _buildLegendItem("Active", _neonBlue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: _textGrey, fontSize: 12)),
      ],
    );
  }

  Widget _buildEfficiencyCard() {
    // A simplified efficiency metric
    final efficiency = totalRides > 0
        ? (completedRides / totalRides) * 100
        : 0.0;

    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Completion Rate",
            style: TextStyle(
              color: _textWhite,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 120,
                  width: 120,
                  child: CircularProgressIndicator(
                    value: efficiency / 100,
                    strokeWidth: 12,
                    backgroundColor: Colors.white10,
                    color: efficiency > 80
                        ? _neonGreen
                        : (efficiency > 50 ? Colors.orange : _neonRed),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${efficiency.toStringAsFixed(1)}%",
                      style: TextStyle(
                        color: _textWhite,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Success",
                      style: TextStyle(color: _textGrey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            "Based on total assigned rides vs completed rides.",
            style: TextStyle(color: _textGrey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
