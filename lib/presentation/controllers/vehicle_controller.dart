import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:project_taxi_driver_app/domain/entities/vehicle.dart';
import 'package:project_taxi_driver_app/domain/repositories/vehicle_repository.dart';
import 'package:project_taxi_driver_app/data/repositories/vehicle_repository_impl.dart';

class VehicleController extends GetxController {
  final VehicleRepository _repository =
      VehicleRepositoryImpl(); // Dependency Injection could be improved

  var vehicles = <Vehicle>[].obs;
  var isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    fetchVehicles();
  }

  void fetchVehicles() async {
    isLoading.value = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        vehicles.value = await _repository.getVehicles(user.uid);
      } else {
        vehicles.clear(); // Clear if no user
      }
    } catch (e) {
      Get.snackbar("Error", e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> addVehicle(Vehicle vehicle) async {
    try {
      await _repository.addVehicle(vehicle);
      fetchVehicles(); // Refresh list
      Get.back(); // Close modal
      Get.snackbar("Success", "Vehicle added successfully");
    } catch (e) {
      Get.snackbar("Error", e.toString());
    }
  }

  Future<void> deleteVehicle(String id) async {
    try {
      await _repository.deleteVehicle(id);
      fetchVehicles();
      Get.snackbar("Success", "Vehicle deleted");
    } catch (e) {
      Get.snackbar("Error", e.toString());
    }
  }
}
