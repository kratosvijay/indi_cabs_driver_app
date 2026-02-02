import 'package:project_taxi_driver_app/domain/entities/vehicle.dart';

abstract class VehicleRepository {
  Future<List<Vehicle>> getVehicles(String userId);
  Future<void> addVehicle(Vehicle vehicle);
  Future<void> updateVehicle(Vehicle vehicle);
  Future<void> deleteVehicle(String id);
  Future<Vehicle?> getVehicleById(String id);
}
