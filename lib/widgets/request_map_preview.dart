import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';

/// Widget to show a small map preview of the request
class RequestMapPreview extends StatelessWidget {
  final RideRequest request;
  final double height;

  const RequestMapPreview({
    super.key,
    required this.request,
    this.height = 140,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate center point between pickup and dropoff
    final centerLat = (request.pickupLocation.latitude +
            request.dropoffLocation.latitude) /
        2;
    final centerLng = (request.pickupLocation.longitude +
            request.dropoffLocation.longitude) /
        2;

    // Calculate appropriate zoom level based on distance
    double zoom = 15.0;
    if (request.rideDistance > 20) {
      zoom = 11.0;
    } else if (request.rideDistance > 10) {
      zoom = 12.0;
    } else if (request.rideDistance > 5) {
      zoom = 13.0;
    }

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white54),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(centerLat, centerLng),
                zoom: zoom,
              ),
              mapType: MapType.normal,
              markers: {
                Marker(
                  markerId: const MarkerId('pickup'),
                  position: request.pickupLocation,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Pickup',
                    snippet: request.pickupTitle,
                  ),
                ),
                Marker(
                  markerId: const MarkerId('dropoff'),
                  position: request.dropoffLocation,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Dropoff',
                    snippet: request.dropoffTitle,
                  ),
                ),
                // Add intermediate stops
                ...request.stops.asMap().entries.map(
                      (entry) => Marker(
                        markerId: MarkerId('stop_${entry.key}'),
                        position: entry.value.location,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueYellow,
                        ),
                        infoWindow: InfoWindow(
                          title: 'Stop ${entry.key + 1}',
                          snippet: entry.value.title,
                        ),
                      ),
                    ),
              },
              zoomControlsEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              myLocationButtonEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),

            // Distance overlay badge
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.route,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${request.rideDistance.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Ride type badge
            if (request.rideType == 'rental')
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'RENTAL',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Multi-stop badge
            if (request.stops.isNotEmpty)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_location_alt,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${request.stops.length} STOPS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
