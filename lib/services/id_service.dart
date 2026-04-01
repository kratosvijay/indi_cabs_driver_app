import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class IdService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Gets the next sequential driver ID number and returns it.
  /// Uses a Firestore transaction to ensure uniqueness and concurrency safety.
  static Future<int> getNextDriverId() async {
    final counterRef = _db.collection('counters').doc('drivers');

    return await _db.runTransaction((transaction) async {
      final counterSnapshot = await transaction.get(counterRef);

      if (!counterSnapshot.exists) {
        // Initialize if it doesn't exist
        transaction.set(counterRef, {'lastId': 1});
        return 1;
      }

      final lastId = counterSnapshot.data()?['lastId'] as int? ?? 0;
      final nextId = lastId + 1;

      transaction.update(counterRef, {'lastId': nextId});
      return nextId;
    });
  }

  /// Retrieves the driver's professional document ID, recovering it from Firestore if necessary.
  static Future<String> getDriverDocId(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('driverDocId');

    if (storedId == null || storedId.isEmpty) {
      debugPrint("IdService: driverDocId not found in prefs. Attempting recovery for $uid...");
      try {
        final snapshot = await _db
            .collection('drivers')
            .where('uid', isEqualTo: uid)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          storedId = snapshot.docs.first.id;
          await prefs.setString('driverDocId', storedId);
          debugPrint("IdService: Recovered driverDocId: $storedId");
        } else {
          debugPrint("IdService: No matching driver document found for $uid. Using UID as fallback.");
          storedId = uid;
        }
      } catch (e) {
        debugPrint("IdService: Error recovering driverDocId: $e");
        storedId = uid;
      }
    }

    return storedId;
  }
}
