import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:project_taxi_driver_app/domain/entities/driver.dart';

class DriverModel extends Driver {
  DriverModel({
    required super.id,
    required super.name,
    required super.email,
    required super.phoneNumber,
    required super.licenseNumber,
    required super.status,
    super.currentVehicleId,
    super.profileImageUrl,
    required super.joinedDate,
    required super.rating,
    super.upiIds,
    super.activeUpiId,
  });

  factory DriverModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DriverModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      licenseNumber: data['licenseNumber'] ?? '',
      status: data['status'] ?? 'Inactive',
      currentVehicleId: data['currentVehicleId'],
      profileImageUrl: data['profileImageUrl'],
      joinedDate:
          (data['joinedDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      rating: (data['rating'] ?? 0.0).toDouble(),
      upiIds: List<String>.from(data['upiIds'] ?? []),
      activeUpiId: data['activeUpiId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'licenseNumber': licenseNumber,
      'status': status,
      'currentVehicleId': currentVehicleId,
      'profileImageUrl': profileImageUrl,
      'joinedDate': Timestamp.fromDate(joinedDate),
      'rating': rating,
      'upiIds': upiIds,
      'activeUpiId': activeUpiId,
    };
  }
}
