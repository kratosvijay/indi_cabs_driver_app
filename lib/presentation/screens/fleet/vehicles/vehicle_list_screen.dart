import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/presentation/controllers/vehicle_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:project_taxi_driver_app/screens/car_selection.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart'; // Reusing Pro library

import 'package:project_taxi_driver_app/screens/fleet/batch_upload_screen.dart'; // Import

class VehicleListScreen extends StatelessWidget {
  const VehicleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Inject Controller
    final VehicleController controller = Get.put(VehicleController());

    return Scaffold(
      appBar: const ProAppBar(titleText: "Fleet Vehicles"),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: "batch_vehicle",
            onPressed: () => Get.to(
              () => const BatchUploadScreen(mode: BatchUploadMode.vehicle),
            ),
            label: const Text("Batch Upload"),
            icon: const Icon(Icons.upload_file),
            backgroundColor: Colors.blueGrey,
          ),
          const SizedBox(width: 16),
          FloatingActionButton.extended(
            heroTag: "add_vehicle",
            onPressed: () {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                Get.to(() => CarSelectionScreen(user: user, isFleet: true));
              } else {
                Get.snackbar("Error", "User not logged in");
              }
            },
            label: const Text("Add Vehicle"),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.vehicles.isEmpty) {
          return const Center(child: Text("No vehicles found. Add one!"));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.vehicles.length,
          itemBuilder: (context, index) {
            final vehicle = controller.vehicles[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(_getIconForType(vehicle.type)),
                ),
                title: Text("${vehicle.model} (${vehicle.plateNumber})"),
                subtitle: Text("Status: ${vehicle.status}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => controller.deleteVehicle(vehicle.id),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'sedan':
        return Icons.directions_car;
      case 'truck':
        return Icons.local_shipping;
      case 'bike':
        return Icons.motorcycle;
      default:
        return Icons.directions_car;
    }
  }
}
