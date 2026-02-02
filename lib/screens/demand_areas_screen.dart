import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:project_taxi_driver_app/services/demand_service.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:get/get.dart';

// Chennai Boundary Coordinates (provided by user)
const List<LatLng> chennaiBoundary = [
  LatLng(13.289375, 80.5609776),
  LatLng(13.292048, 80.5046726),
  LatLng(13.2933845, 80.4469944),
  LatLng(13.292048, 80.3797032),
  LatLng(13.2933845, 80.3330113),
  LatLng(13.2960575, 80.2794529),
  LatLng(13.3401573, 80.2506138),
  LatLng(13.3521831, 80.2190281),
  LatLng(13.3628722, 80.1682163),
  LatLng(13.3561916, 80.1160313),
  LatLng(13.3294672, 80.0610996),
  LatLng(13.2800192, 79.9677158),
  LatLng(13.2546231, 79.9292637),
  LatLng(13.1984749, 79.8894383),
  LatLng(13.1851044, 79.8605991),
  LatLng(13.1021909, 79.7740818),
  LatLng(13.0807893, 79.7122837),
  LatLng(13.0647369, 79.671085),
  LatLng(13.0125594, 79.638126),
  LatLng(12.938957, 79.6257664),
  LatLng(12.8666718, 79.6230198),
  LatLng(12.817131, 79.6312595),
  LatLng(12.7689197, 79.6463658),
  LatLng(12.7287367, 79.6724583),
  LatLng(12.7153409, 79.7328831),
  LatLng(12.7046238, 79.7658421),
  LatLng(12.7046238, 79.8345066),
  LatLng(12.6939062, 79.8866917),
  LatLng(12.6349515, 79.9169041),
  LatLng(12.6215508, 79.9443699),
  LatLng(12.5893863, 79.9718357),
  LatLng(12.5304075, 79.982822),
  LatLng(12.4821421, 79.9993015),
  LatLng(12.3185092, 80.0267674),
  LatLng(12.4472781, 80.0871922),
  LatLng(12.458006, 80.2107884),
  LatLng(12.5384508, 80.2821995),
  LatLng(12.6081494, 80.350864),
  LatLng(12.7501684, 80.3728367),
  LatLng(12.8840757, 80.3975559),
  LatLng(12.9162028, 80.4332615),
  LatLng(12.9884737, 80.4662205),
  LatLng(13.0500213, 80.4964329),
  LatLng(13.1596984, 80.5101658),
  LatLng(13.289375, 80.5609776),
];

class DemandAreasScreen extends StatefulWidget {
  const DemandAreasScreen({super.key});

  @override
  State<DemandAreasScreen> createState() => _DemandAreasScreenState();
}

class _DemandAreasScreenState extends State<DemandAreasScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final DemandService _demandService = DemandService();
  StreamSubscription? _demandSubscription;

  Set<Circle> _demandCircles = {};
  bool _isLoading = true;

  // Chennai center (approximate)
  static const LatLng _chennaiCenter = LatLng(13.0827, 80.2707);

  @override
  void initState() {
    super.initState();
    _startDemandMonitoring();
  }

  @override
  void dispose() {
    _demandSubscription?.cancel();
    super.dispose();
  }

  void _startDemandMonitoring() {
    _demandSubscription = _demandService
        .getDemandZones(minCount: 1)
        .listen(
          (zones) {
            debugPrint("DemandAreasScreen: ${zones.length} zones found");
            final circles = <Circle>{};
            for (var zone in zones) {
              Color circleColor;
              if (zone.count >= 5) {
                circleColor = Colors.red.withValues(alpha: 0.5); // High Demand
              } else if (zone.count >= 3) {
                circleColor = Colors.orange.withValues(
                  alpha: 0.5,
                ); // Medium Demand
              } else {
                circleColor = Colors.yellow.withValues(
                  alpha: 0.5,
                ); // Low Demand
              }

              circles.add(
                Circle(
                  circleId: CircleId(zone.geohash),
                  center: zone.center,
                  radius: 800, // Larger radius for overview
                  fillColor: circleColor,
                  strokeColor: circleColor.withValues(alpha: 0.8),
                  strokeWidth: 1,
                  zIndex: 2,
                ),
              );
            }
            if (mounted) {
              setState(() {
                _demandCircles = circles;
                _isLoading = false;
              });
            }
          },
          onError: (e) {
            debugPrint("Error fetching demand zones: $e");
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        );
  }

  Set<Polygon> _buildBoundaryPolygon() {
    return {
      Polygon(
        polygonId: const PolygonId('chennai_boundary'),
        points: chennaiBoundary,
        strokeColor: Colors.black,
        strokeWidth: 3,
        fillColor: Colors.transparent, // No fill, just the border line
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('nearbyDemandAreas'.tr),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppColors.getAppBarGradient(context),
          ),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _chennaiCenter,
              zoom: 9.5, // Zoomed out to see all of Chennai
            ),
            mapType: MapType.normal,
            polygons: _buildBoundaryPolygon(),
            circles: _demandCircles,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            onMapCreated: (controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
            },
          ),

          // Loading Indicator
          if (_isLoading) const Center(child: CircularProgressIndicator()),

          // Legend
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'demandLegend'.tr,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildLegendItem(Colors.red, 'highDemand'.tr),
                  _buildLegendItem(Colors.orange, 'mediumDemand'.tr),
                  _buildLegendItem(Colors.yellow, 'lowDemand'.tr),
                ],
              ),
            ),
          ),

          // Info Banner
          if (!_isLoading && _demandCircles.isEmpty)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'noDemandData'.tr,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
