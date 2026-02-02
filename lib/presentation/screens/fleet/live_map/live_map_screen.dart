import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LiveMapScreen extends StatefulWidget {
  final User user;
  const LiveMapScreen({super.key, required this.user});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  List<DocumentSnapshot> _drivers = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Keep screen on while monitoring
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _updateMarkers(List<DocumentSnapshot> drivers) {
    _markers.clear();
    for (var driver in drivers) {
      final data = driver.data() as Map<String, dynamic>;
      final GeoPoint? location = data['currentLocation'];
      final bool isOnline = data['isOnline'] ?? false;
      final String name = data['name'] ?? 'Unknown Driver';
      final String status = isOnline ? 'Online' : 'Offline';

      if (location != null && isOnline) {
        _markers.add(
          Marker(
            markerId: MarkerId(driver.id),
            position: LatLng(location.latitude, location.longitude),
            infoWindow: InfoWindow(title: name, snippet: status),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isOnline ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
            ),
          ),
        );
      }
    }
  }

  void _focusOnDriver(DocumentSnapshot driver) {
    final data = driver.data() as Map<String, dynamic>;
    final GeoPoint? location = data['currentLocation'];

    if (location != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          15,
        ),
      );
      // Optional: Show info window logic if needed (requires custom handling or marker tap)
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Driver location not available")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dark Theme Colors
    final Color cardColor = const Color(0xFF181B21);
    final Color neonBlue = const Color(0xFF00E5FF);
    final Color textWhite = Colors.white;
    final Color textGrey = Colors.white54;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115), // _bgDark equivalent
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('drivers')
            .where('fleetOperatorId', isEqualTo: widget.user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error: ${snapshot.error}",
                style: TextStyle(color: textWhite),
              ),
            );
          }

          if (snapshot.hasData) {
            _drivers = snapshot.data!.docs;
            // Update markers whenever data changes
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _updateMarkers(_drivers);
                });
              }
            });
          }

          return Column(
            children: [
              // Map Section (Top)
              Expanded(
                flex: 2,
                child: GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(13.0827, 80.2707), // Default: Chennai/India
                    zoom: 12,
                  ),
                  markers: _markers,
                  myLocationEnabled: false, // Don't show operator's location
                  mapType: MapType.normal,
                  // Dark Mode Map Style could be added here
                ),
              ),

              // Driver List Section (Bottom)
              Expanded(
                flex: 1,
                child: Container(
                  color: const Color(0xFF0F1115),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Text(
                              "Active Drivers",
                              style: TextStyle(
                                color: textWhite,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              "${_drivers.where((d) => (d.data() as Map)['isOnline'] == true).length} Online",
                              style: TextStyle(color: neonBlue),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _drivers.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, index) {
                            final driver = _drivers[index];
                            final data = driver.data() as Map<String, dynamic>;
                            final bool isOnline = data['isOnline'] ?? false;
                            final String name = data['name'] ?? 'Unknown';
                            final String phone = data['phoneNumber'] ?? '';

                            return Card(
                              color: cardColor,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isOnline
                                      ? neonBlue.withValues(alpha: 0.3)
                                      : Colors.transparent,
                                ),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isOnline
                                      ? Colors.green.withValues(alpha: 0.2)
                                      : Colors.grey.withValues(alpha: 0.2),
                                  child: Icon(
                                    Icons.person,
                                    color: isOnline
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(color: textWhite),
                                ),
                                subtitle: Text(
                                  isOnline
                                      ? "Online • $phone"
                                      : "Offline • $phone",
                                  style: TextStyle(color: textGrey),
                                ),
                                onTap: () => _focusOnDriver(driver),
                                trailing: isOnline
                                    ? const Icon(
                                        Icons.my_location,
                                        color: Colors.blue,
                                      )
                                    : const Icon(
                                        Icons.location_off,
                                        color: Colors.grey,
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
