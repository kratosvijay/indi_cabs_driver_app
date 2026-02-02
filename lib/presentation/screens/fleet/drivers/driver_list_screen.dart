import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/presentation/controllers/driver_controller.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/drivers/add_driver_flow.dart';

import 'package:project_taxi_driver_app/screens/fleet/batch_upload_screen.dart'; // Import

class DriverListScreen extends StatelessWidget {
  const DriverListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DriverController controller = Get.put(DriverController());

    return Scaffold(
      appBar: const ProAppBar(titleText: "Fleet Drivers"),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: "batch_driver",
            onPressed: () => Get.to(
              () => const BatchUploadScreen(mode: BatchUploadMode.driver),
            ),
            label: const Text("Batch Upload"),
            icon: const Icon(Icons.upload_file),
            backgroundColor: Colors.blueGrey,
          ),
          const SizedBox(width: 16),
          FloatingActionButton.extended(
            heroTag: "add_driver",
            onPressed: () => _showAddDriverDialog(context, controller),
            label: const Text("Add Driver"),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.drivers.isEmpty) {
          return const Center(child: Text("No drivers found. Add one!"));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.drivers.length,
          itemBuilder: (context, index) {
            final driver = controller.drivers[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: driver.profileImageUrl != null
                      ? NetworkImage(driver.profileImageUrl!)
                      : null,
                  child: driver.profileImageUrl == null
                      ? Text(driver.name[0])
                      : null,
                ),
                title: Text(driver.name),
                subtitle: Text("${driver.status} • ${driver.phoneNumber}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    Get.defaultDialog(
                      title: "Delete Driver",
                      middleText:
                          "Are you sure you want to delete this driver?",
                      textConfirm: "Yes",
                      textCancel: "No",
                      confirmTextColor: Colors.white,
                      onConfirm: () {
                        controller.deleteDriver(driver.id);
                        Get.back(); // Close dialog
                      },
                    );
                  },
                ),
              ),
            );
          },
        );
      }),
    );
  }

  void _showAddDriverDialog(
    BuildContext context,
    DriverController controller,
  ) async {
    await Get.to(() => const FleetDriverOnboardingScreen());
    controller.fetchDrivers();
  }
}
