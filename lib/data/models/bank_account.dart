import 'package:cloud_firestore/cloud_firestore.dart';

class BankAccount {
  final String id;
  final String name;
  final String maskedAccountNumber;
  final String encryptedAccountNumber;
  final String ifsc;
  final String status;
  final String cashfreeBeneId;
  final DateTime? createdAt;

  BankAccount({
    required this.id,
    required this.name,
    required this.maskedAccountNumber,
    required this.encryptedAccountNumber,
    required this.ifsc,
    required this.status,
    this.cashfreeBeneId = '',
    this.createdAt,
  });

  factory BankAccount.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return BankAccount(
      id: doc.id,
      name: data['name'] ?? '',
      maskedAccountNumber: data['maskedAccountNumber'] ?? '',
      encryptedAccountNumber: data['encryptedAccountNumber'] ?? '',
      ifsc: data['ifsc'] ?? '',
      status: data['status'] ?? 'pending',
      cashfreeBeneId: data['cashfreeBeneId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'maskedAccountNumber': maskedAccountNumber,
      'encryptedAccountNumber': encryptedAccountNumber,
      'ifsc': ifsc,
      'status': status,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}
