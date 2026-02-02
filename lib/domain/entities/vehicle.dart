class Vehicle {
  final String id;
  final String plateNumber;
  final String model;
  final String type; // e.g., Sedan, SUV, Truck
  final String status; // Active, Maintenance, InTrip
  final String? assignedDriverId;
  final String? imageUrl;
  final double fuelLevel;
  final DateTime lastMaintenanceDate;

  Vehicle({
    required this.id,
    required this.plateNumber,
    required this.model,
    required this.type,
    required this.status,
    this.assignedDriverId,
    this.imageUrl,
    required this.fuelLevel,
    required this.lastMaintenanceDate,
  });
}
