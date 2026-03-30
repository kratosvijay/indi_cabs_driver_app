import 'package:cloud_firestore/cloud_firestore.dart';

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
}
