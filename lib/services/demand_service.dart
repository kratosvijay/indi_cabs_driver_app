import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DemandZone {
  final String geohash;
  final LatLng center;
  final int count;

  DemandZone({
    required this.geohash,
    required this.center,
    required this.count,
  });

  factory DemandZone.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DemandZone(
      geohash: data['geohash'] ?? doc.id,
      center: LatLng(data['lat'] ?? 0.0, data['lng'] ?? 0.0),
      count: data['count'] ?? 0,
    );
  }
}

class DemandService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream active demand zones with at least 'minCount' rides
  Stream<List<DemandZone>> getDemandZones({int minCount = 2}) {
    return _firestore
        .collection('demand_zones')
        .where('count', isGreaterThanOrEqualTo: minCount)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => DemandZone.fromDoc(doc)).toList();
        });
  }
}
