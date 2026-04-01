import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/screens/driver_binding_otp_screen.dart';
import 'package:project_taxi_driver_app/controllers/auth_controller.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/services/id_service.dart';

class DriverVehicleSelectionScreen extends StatefulWidget {
  final User user;
  const DriverVehicleSelectionScreen({super.key, required this.user});

  @override
  State<DriverVehicleSelectionScreen> createState() =>
      _DriverVehicleSelectionScreenState();
}

class _DriverVehicleSelectionScreenState
    extends State<DriverVehicleSelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _operatorId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchOperatorId();
  }

  Future<void> _fetchOperatorId() async {
    try {
      final docId = await IdService.getDriverDocId(widget.user.uid);

      final driverDoc = await _firestore
          .collection('drivers')
          .doc(docId)
          .get();
      if (driverDoc.exists && driverDoc.data() != null) {
        setState(() {
          _operatorId =
              driverDoc.data()!['fleetOperatorId'] ??
              driverDoc.data()!['operatorId'];
          _isLoading = false;
        });
      } else {
        Get.snackbar("Error", "Driver profile error");
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar("Error", "Failed to fetch profile: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToOtpScreen(String vehicleId) {
    Get.to(
      () => DriverBindingOtpScreen(vehicleId: vehicleId, user: widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_operatorId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Error")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  "No Fleet Operator Linked",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  "This driver account is not linked to any fleet operator. Please ask your fleet manager to add you correctly.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 30),
                ProButton(
                  text: "Logout",
                  onPressed: () => AuthController.instance.logout(),
                  // backgroundColor: Colors.red,
                  // textColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const ProAppBar(titleText: "Select Vehicle"),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('vehicles')
            .where('ownerId', isEqualTo: _operatorId)
            //.where('assignedDriverId', isNull: true) // Firestore doesn't support isNull efficiently with other filters sometimes, check index
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allVehicles = snapshot.data!.docs;

          if (allVehicles.isEmpty) {
            return const Center(child: Text("No vehicles found in fleet."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: allVehicles.length,
            itemBuilder: (context, index) {
              final vehicle = allVehicles[index];
              final data = vehicle.data() as Map<String, dynamic>;
              final assignedId = data['assignedDriverId'];

              // Determine status
              bool isAvailable =
                  assignedId == null ||
                  assignedId.toString().isEmpty ||
                  assignedId == 'null';
              
              // Correctly check if currently assigned to ME (could be UID or DocId if legacy)
              // But in the database, assignedDriverId should generally be the UID for security rules consistency
              // However, we should check against the true identifier used in the vehicles collection.
              // Assuming vehicles collection uses Auth UID for assignedDriverId.
              bool isAssignedToMe = assignedId == widget.user.uid;
              bool isAssignedToOther = !isAvailable && !isAssignedToMe;

              String subtitle = data['plateNumber'] ?? 'Unknown Plate';
              if (isAssignedToMe) subtitle += " (Current Vehicle)";
              if (isAssignedToOther) subtitle += " (Assigned)";

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: isAssignedToMe
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isAvailable
                        ? AppColors.primary
                        : Colors.grey,
                    child: Icon(
                      Icons.directions_car,
                      color: isAvailable ? Colors.white : Colors.white70,
                    ),
                  ),
                  title: Text(
                    data['model'] ?? 'Unknown Model',
                    style: TextStyle(
                      color: isAssignedToOther ? Colors.grey : null,
                      decoration: isAssignedToOther
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(subtitle),
                  trailing: isAvailable
                      ? ElevatedButton(
                          onPressed: () => _navigateToOtpScreen(vehicle.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text("Select"),
                        )
                      : isAssignedToMe
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Text(
                          "Unavailable",
                          style: TextStyle(color: Colors.grey),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
