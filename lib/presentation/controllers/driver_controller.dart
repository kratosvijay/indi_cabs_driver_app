import 'package:get/get.dart';
import 'package:project_taxi_driver_app/domain/entities/driver.dart';
import 'package:project_taxi_driver_app/domain/repositories/driver_repository.dart';
import 'package:project_taxi_driver_app/data/repositories/driver_repository_impl.dart';

class DriverController extends GetxController {
  final DriverRepository _repository = DriverRepositoryImpl();

  var drivers = <Driver>[].obs;
  var isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    fetchDrivers();
  }

  void fetchDrivers() async {
    isLoading.value = true;
    try {
      drivers.value = await _repository.getDrivers();
    } catch (e) {
      Get.snackbar("Error", e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> addDriver(Driver driver) async {
    try {
      await _repository.addDriver(driver);
      fetchDrivers();
      Get.back();
      Get.snackbar("Success", "Driver added successfully");
    } catch (e) {
      Get.snackbar("Error", e.toString());
    }
  }

  Future<void> deleteDriver(String id) async {
    try {
      await _repository.deleteDriver(id);
      fetchDrivers();
      Get.snackbar("Success", "Driver deleted");
    } catch (e) {
      Get.snackbar("Error", e.toString());
    }
  }
}
