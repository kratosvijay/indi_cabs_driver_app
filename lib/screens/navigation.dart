import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng origin;
  final LatLng destination;
  final String destinationAddress;

  const NavigationScreen({
    super.key,
    required this.origin,
    required this.destination,
    required this.destinationAddress,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  late final String _apiKey;

  @override
  void initState() {
    super.initState();
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null) throw Exception("API Key not found");
    _apiKey = apiKey;

    _setupMap();
  }

  Future<void> _setupMap() async {
    _markers.add(
      Marker(
        markerId: const MarkerId('origin'),
        position: widget.origin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    );
    _markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    await _drawRoute();
  }

  Future<void> _drawRoute() async {
    PolylinePoints polylinePoints = PolylinePoints(apiKey: _apiKey);
    final request = RoutesApiRequest(
      origin: PointLatLng(widget.origin.latitude, widget.origin.longitude),
      destination: PointLatLng(
        widget.destination.latitude,
        widget.destination.longitude,
      ),
      travelMode: TravelMode.driving,
    );

    RoutesApiResponse result = await polylinePoints
        .getRouteBetweenCoordinatesV2(request: request);

    if (result.routes.isNotEmpty) {
      final route = result.routes.first;
      if (route.polylinePoints != null) {
        final List<LatLng> polylineCoordinates = route.polylinePoints!
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();

        if (mounted) {
          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: polylineCoordinates,
                color: AppColors.primary,
                width: 6,
              ),
            );
          });
        }
      }
    }
  }

  Future<void> _centerMap() async {
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            widget.origin.latitude < widget.destination.latitude
                ? widget.origin.latitude
                : widget.destination.latitude,
            widget.origin.longitude < widget.destination.longitude
                ? widget.origin.longitude
                : widget.destination.longitude,
          ),
          northeast: LatLng(
            widget.origin.latitude > widget.destination.latitude
                ? widget.origin.latitude
                : widget.destination.latitude,
            widget.origin.longitude > widget.destination.longitude
                ? widget.origin.longitude
                : widget.destination.longitude,
          ),
        ),
        100.0, // padding
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ProAppBar(titleText: 'Navigate to ${widget.destinationAddress}'),
      body: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: CameraPosition(target: widget.origin, zoom: 15),
        markers: _markers,
        polylines: _polylines,
        onMapCreated: (controller) {
          _mapController.complete(controller);
          _centerMap();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerMap,
        child: const Icon(Icons.gps_fixed),
      ),
    );
  }
}
