import 'package:project_taxi_driver_app/domain/entities/driver.dart';

abstract class DriverRepository {
  Future<List<Driver>> getDrivers();
  Future<void> addDriver(Driver driver);
  Future<void> updateDriver(Driver driver);
  Future<void> deleteDriver(String id);
  Future<Driver?> getDriverById(String id);
}
