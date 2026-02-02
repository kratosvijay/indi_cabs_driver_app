class Driver {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String licenseNumber;
  final String status; // Active, Inactive, OnTrip
  final String? currentVehicleId;
  final String? profileImageUrl;
  final DateTime joinedDate;
  final double rating;
  final List<String> upiIds;
  final String? activeUpiId;

  Driver({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.licenseNumber,
    required this.status,
    this.currentVehicleId,
    this.profileImageUrl,
    required this.joinedDate,
    required this.rating,
    this.upiIds = const [],
    this.activeUpiId,
  });
}
