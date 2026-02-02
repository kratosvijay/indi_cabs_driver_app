import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:project_taxi_driver_app/domain/entities/vehicle.dart';

class VehicleModel extends Vehicle {
  VehicleModel({
    required super.id,
    required super.plateNumber,
    required super.model,
    required super.type,
    required super.status,
    super.assignedDriverId,
    super.imageUrl,
    required super.fuelLevel,
    required super.lastMaintenanceDate,
  });

  factory VehicleModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Handle Image Logic
    String? displayImage = data['imageUrl'];
    if (displayImage == null && data['imageUrls'] is Map) {
      final images = data['imageUrls'] as Map<String, dynamic>;
      displayImage = images['front'] ?? images.values.firstOrNull;
    }

    return VehicleModel(
      id: doc.id,
      plateNumber: data['plateNumber'] ?? '',
      model: data['model'] ?? '',
      type: data['type'] ?? 'Unknown',
      status: data['status'] ?? 'Active',
      assignedDriverId: data['assignedDriverId'],
      imageUrl: displayImage,
      fuelLevel: (data['fuelLevel'] ?? 0).toDouble(),
      lastMaintenanceDate:
          (data['lastMaintenanceDate'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plateNumber': plateNumber,
      'model': model,
      'type': type,
      'status': status,
      'assignedDriverId': assignedDriverId,
      'imageUrl': imageUrl,
      'fuelLevel': fuelLevel,
      'lastMaintenanceDate': Timestamp.fromDate(lastMaintenanceDate),
    };
  }
}
