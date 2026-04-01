import 'dart:async';
import 'package:project_taxi_driver_app/services/id_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pinput/pinput.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart'; // Changed from foundation
import 'package:get/get.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';

class WalletTransaction {
  final String id;
  final double amount;
  final String type; // 'credit' or 'debit'
  final DateTime createdAt;
  final String description;

  WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
    required this.description,
  });

  factory WalletTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WalletTransaction(
      id: doc.id,
      amount: (data['amount'] ?? 0.0).toDouble(),
      type: data['type'] ?? 'credit',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      description: data['description'] ?? '',
    );
  }
}

class WalletController extends GetxController {
  static WalletController get instance => Get.find();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  RxDouble balance = 0.0.obs;
  RxList<WalletTransaction> transactions = <WalletTransaction>[].obs;
  RxBool isLoading = false.obs;
  
  final List<StreamSubscription> _subscriptions = [];
  RxList<String> savedUpiIds = <String>[].obs;

  // Settlement Features
  RxBool autoSettleEnabled = false.obs;
  RxString autoSettleUpiId = "".obs;
  RxInt settlementsThisWeek = 0.obs;
  Rx<DateTime?> lastSettlementReset = Rx<DateTime?>(null);
  Rx<DateTime?> lastSettlementDate = Rx<DateTime?>(null);

  // Pending Subscription State
  Map<String, dynamic>? _pendingSubscription;

  final CFPaymentGatewayService _cashfree = CFPaymentGatewayService();
  String? _driverDocId;

  Future<void> _loadDocId() async {
    if (_driverDocId != null) return;
    final user = _auth.currentUser;
    if (user != null) {
      _driverDocId = await IdService.getDriverDocId(user.uid);
      debugPrint("WalletController: Final driverDocId: $_driverDocId");
    }
  }

  @override
  void onInit() {
    super.onInit();
    // Delay heavy data fetching until after the first frame
    // This allows the screen transition animation to run smoothly
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDocId();
      fetchWalletData();
      fetchUpiIds();
    });
    _initCashfree();
  }

  void _initCashfree() {
    _cashfree.setCallback(verifyPayment, onError);
  }

  void verifyPayment(String orderId) {
    debugPrint("Cashfree Payment Success for Order: $orderId");
    try {
      if (_pendingSubscription != null) {
        _finalizeSubscriptionPurchase(
          orderId, // Use orderId as reference
          _pendingSubscription!,
        );
        _pendingSubscription = null;
      }
    } catch (e) {
      Get.snackbar("Error", "Post-payment processing failed: $e");
    }
  }

  void onError(CFErrorResponse error, String orderId) {
    debugPrint("Cashfree Payment Error: ${error.getMessage()}");
    if (_pendingSubscription != null) {
      _pendingSubscription = null;
      Get.defaultDialog(
        title: "Transaction Failed",
        middleText: "Payment could not be completed. Please try again.",
        textConfirm: "OK",
        confirmTextColor: Colors.white,
        onConfirm: () => Get.back(),
      );
    } else {
      Get.snackbar("Error", "Payment Failed: ${error.getMessage()}");
    }
    isLoading.value = false;
  }

  @override
  void onClose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.onClose();
  }

  Future<void> fetchUpiIds() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      debugPrint("Fetching UPI IDs for ${user.uid} (Doc: $_driverDocId)...");
      _subscriptions.add(_db
          .collection('drivers')
          .doc(_driverDocId ?? user.uid)
          .collection('saved_upi_ids')
          .snapshots()
          .listen((snapshot) {
            debugPrint("UPI IDs update: ${snapshot.docs.length} found");
            savedUpiIds.value = snapshot.docs.map((doc) => doc.id).toList();
          }, onError: (e) => debugPrint("UPI IDs stream error: $e")));
    } catch (e) {
      debugPrint("Error fetching UPI IDs: $e");
    }
  }

  Future<void> verifyAndAddUpi(String upiId, String name) async {
    final user = _auth.currentUser;
    if (user == null || user.phoneNumber == null) {
      Get.snackbar("Error", "User phone number not found");
      return;
    }

    try {
      isLoading.value = true;
      Get.back(); // Close initial dialog

      // 1. Trigger OTP
      await _db.collection('otp_verifications').doc(user.phoneNumber).set({
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      isLoading.value = false;

      // 2. Show OTP Dialog using Pinput
      final otpController = TextEditingController();
      Get.dialog(
        AlertDialog(
          title: const Text("Verify UPI Addition"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("An OTP has been sent to ${user.phoneNumber}"),
              const SizedBox(height: 20),
              Pinput(
                controller: otpController,
                length: 6,
                onCompleted: (pin) async {
                  Get.back(); // Close OTP dialog
                  await _finalizeUpiAddition(upiId, name, pin, user.phoneNumber!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: const Text("Cancel"),
            ),
          ],
        ),
      );
    } catch (e) {
      isLoading.value = false;
      Get.snackbar("Error", "Failed to initiate verification: $e");
    }
  }

  Future<void> _finalizeUpiAddition(String upiId, String name, String otp, String phone) async {
    try {
      isLoading.value = true;
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('verifyUpiIdWithOtp');
      
      final result = await callable.call({
        'upiId': upiId,
        'name': name,
        'otp': otp,
        'phone': phone,
      });

      isLoading.value = false;
      if (result.data['success'] == true) {
        Get.snackbar("Success", "UPI ID Added Successfully");
        // refresh savedUpiIds list is handled by snapshot listener
      } else {
        Get.snackbar("Error", result.data['message'] ?? "Verification failed");
      }
    } catch (e) {
      isLoading.value = false;
      Get.snackbar("Error", "Verification failed: $e");
    }
  }

  // Deprecated: explicit add without verification
  // Future<void> addUpiId(String upiId) async { ... }

  Future<void> deleteUpiId(String upiId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db
          .collection('drivers')
          .doc(_driverDocId ?? user.uid)
          .collection('saved_upi_ids')
          .doc(upiId)
          .delete();
      Get.snackbar("Success", "UPI ID deleted");
    } catch (e) {
      Get.snackbar("Error", "Failed to delete UPI ID: $e");
    }
  }

  Future<void> fetchWalletData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _listenToAutoSettleSettings(user);

    try {
      // Listen to wallet document
      _subscriptions.add(_db
          .collection('drivers')
          .doc(_driverDocId ?? user.uid)
          .collection('wallet')
          .doc('balance')
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists) {
              balance.value = (snapshot.data()?['currentBalance'] ?? 0.0)
                  .toDouble();
            } else {
              balance.value = 0.0;
            }
          }, onError: (e) => debugPrint("Wallet balance stream error: \$e")));

      // Listen to transactions
      _subscriptions.add(_db
          .collection('drivers')
          .doc(_driverDocId ?? user.uid)
          .collection('wallet_transactions')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
            transactions.value = snapshot.docs
                .map((doc) => WalletTransaction.fromFirestore(doc))
                .toList();
          }, onError: (e) => debugPrint("Transactions stream error: \$e")));
    } catch (e) {
      Get.snackbar("Error", "Failed to fetch wallet data: $e");
    }
  }

  void _listenToAutoSettleSettings(User user) {
    _subscriptions.add(_db.collection('drivers').doc(_driverDocId ?? user.uid).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        autoSettleEnabled.value = data?['autoSettleEnabled'] ?? false;
        autoSettleUpiId.value = data?['autoSettleUpiId'] ?? "";
      }
    }, onError: (e) => debugPrint("Driver autoSettle stream error: \$e")));

    _subscriptions.add(_db
        .collection('drivers')
        .doc(_driverDocId ?? user.uid)
        .collection('wallet')
        .doc('metadata')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            settlementsThisWeek.value =
                snapshot.data()?['settlementsThisWeek'] ?? 0;
            final resetTimestamp = snapshot.data()?['lastSettlementReset'];
            if (resetTimestamp is Timestamp) {
              lastSettlementReset.value = resetTimestamp.toDate();
            }
            final settlementTimestamp = snapshot.data()?['lastSettlementDate'];
            if (settlementTimestamp is Timestamp) {
              lastSettlementDate.value = settlementTimestamp.toDate();
            }
          }
        }, onError: (e) => debugPrint("Wallet metadata stream error: \$e")));
  }

  Future<void> updateAutoSettleSettings(bool enabled, String upiId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.collection('drivers').doc(_driverDocId ?? user.uid).set({
        'autoSettleEnabled': enabled,
        'autoSettleUpiId': upiId,
      }, SetOptions(merge: true));
    } catch (e) {
      Get.snackbar("Error", "Failed to update settings: $e");
    }
  }

  Future<void> creditWallet(
    double amount,
    String paymentId, {
    String description = 'Money Added to Wallet',
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.runTransaction((transaction) async {
        final balanceRef = _db
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .collection('wallet')
            .doc('balance');
        final balanceDoc = await transaction.get(balanceRef);

        double currentBalance = 0.0;
        if (balanceDoc.exists) {
          currentBalance = (balanceDoc.data()?['currentBalance'] ?? 0.0)
              .toDouble();
        }

        final newBalance = currentBalance + amount;
        transaction.set(balanceRef, {
          'currentBalance': newBalance,
        }, SetOptions(merge: true));

        // Add Transaction Record
        final transactionRef = _db
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .collection('wallet_transactions')
            .doc();
        transaction.set(transactionRef, {
          'amount': amount,
          'type': 'credit',
          'createdAt': FieldValue.serverTimestamp(),
          'description': description,
          'paymentId': paymentId,
        });
      });
    } catch (e) {
      Get.snackbar("Error", "Wallet update failed: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> settleBalance(String upiId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (balance.value <= 0) {
      Get.snackbar("Error", "Insufficient balance to settle.");
      return;
    }

    try {
      isLoading.value = true;
      Get.back(); // Close dialog

      // Simulate bank processing delay
      await Future.delayed(const Duration(seconds: 2));

      await _db.runTransaction((transaction) async {
        final balanceRef = _db
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .collection('wallet')
            .doc('balance');
        final balanceDoc = await transaction.get(balanceRef);

        double currentBalance = 0.0;
        if (balanceDoc.exists) {
          currentBalance = (balanceDoc.data()?['currentBalance'] ?? 0.0)
              .toDouble();
        }

        if (currentBalance <= 0) throw Exception("Insufficient balance");

        // Check and update settlement limits
        final metadataRef = _db
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .collection('wallet')
            .doc('metadata');
        final metadataDoc = await transaction.get(metadataRef);

        int currentCount = 0;
        DateTime? lastReset;

        if (metadataDoc.exists) {
          currentCount = metadataDoc.data()?['settlementsThisWeek'] ?? 0;
          final ts = metadataDoc.data()?['lastSettlementReset'];
          if (ts is Timestamp) lastReset = ts.toDate();
        }

        // Logic to reset count if it's a new week (Sunday)
        final now = DateTime.now();
        // Calculate the most recent Sunday midnight
        final lastSunday = now.subtract(Duration(days: now.weekday % 7));
        final startOfLastSunday = DateTime(
          lastSunday.year,
          lastSunday.month,
          lastSunday.day,
        );

        if (lastReset == null || lastReset.isBefore(startOfLastSunday)) {
          // New week started, reset count
          currentCount = 0;
          lastReset = startOfLastSunday; // Mark reset time
        }

        // 1/Day Limit Check
        final lastDate = metadataDoc.data()?['lastSettlementDate'];
        if (lastDate is Timestamp) {
          final lastSettle = lastDate.toDate();
          if (lastSettle.year == now.year &&
              lastSettle.month == now.month &&
              lastSettle.day == now.day) {
            throw Exception("Only 1 settlement per day is allowed. Next reset: Midnight.");
          }
        }

        if (currentCount >= 7) {
          throw Exception("Weekly settlement limit (7) reached.");
        }

        // Update limit metadata
        transaction.set(metadataRef, {
          'settlementsThisWeek': currentCount + 1,
          'lastSettlementReset': Timestamp.fromDate(lastReset),
          'lastSettlementDate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Debit the full amount
        transaction.set(balanceRef, {
          'currentBalance': 0.0,
        }, SetOptions(merge: true));

        // Add Transaction Record
        final transactionRef = _db
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .collection('wallet_transactions')
            .doc();
        transaction.set(transactionRef, {
          'amount': currentBalance,
          'type': 'debit',
          'createdAt': FieldValue.serverTimestamp(),
          'description': 'Settled to UPI: $upiId',
          'upiId': upiId,
          'status': 'pending',
        });
      });

      Get.snackbar(
        "Processing",
        "Settlement initiated! Funds will be transferred shortly.",
      );
    } catch (e) {
      Get.snackbar("Error", "Failed to settle balance: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> activateFreeTrialPlan(String planName, int durationDays) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _db.runTransaction((transaction) async {
        final driverRef = _db.collection('drivers').doc(_driverDocId ?? user.uid);

        // Fetch current expiry
        final driverDoc = await transaction.get(driverRef);
        DateTime currentExpiry = DateTime.now();

        if (driverDoc.exists &&
            driverDoc.data()!.containsKey('subscriptionExpiry')) {
          final ts = driverDoc.data()!['subscriptionExpiry'];
          if (ts is Timestamp) {
            final exp = ts.toDate();
            if (exp.isAfter(DateTime.now())) {
              currentExpiry = exp;
            }
          }
        }

        final newExpiry = currentExpiry.add(Duration(days: durationDays));

        // Update Driver Subscription
        transaction.set(driverRef, {
          'subscriptionExpiry': Timestamp.fromDate(newExpiry),
          'subscriptionPlan': planName,
        }, SetOptions(merge: true));

        // Create Zero-Cost Transaction Record
        final transactionRef = driverRef
            .collection('wallet_transactions')
            .doc();
        transaction.set(transactionRef, {
          'amount': 0.0,
          'type': 'credit', // Credit of 0, purely informational
          'createdAt': FieldValue.serverTimestamp(),
          'description': 'Auto-Activation: $planName',
          'status': 'success',
          'method': 'system_trial',
        });
      });

      // Update local state if needed (listeners should handle it)
      debugPrint("Free Trial Activated: $planName for $durationDays days");
    } catch (e) {
      debugPrint("Failed to activate free trial: $e");
      rethrow;
    }
  }

  Future<void> buySubscriptionPlan(
    String planName,
    double price,
    int durationDays,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      isLoading.value = true;

      // Check if purchase would exceed credit limit (-300)
      // Note: Current balance is fetched in real-time.
      // If balance - price < -300, warn user?
      // Requirement says: "everyday morning 12 it should check...".
      // It doesn't explicitly forbid the transaction, but let's allow it
      // and let the daily check handle off-roading, or warn them.

      await _db.runTransaction((transaction) async {
        final driverRef = _db.collection('drivers').doc(_driverDocId ?? user.uid);
        final walletRef = driverRef.collection('wallet').doc('balance');

        final walletDoc = await transaction.get(walletRef);
        double currentBalance = 0.0;
        if (walletDoc.exists) {
          currentBalance = (walletDoc.data()?['currentBalance'] ?? 0.0)
              .toDouble();
        }

        final newBalance = currentBalance - price;

        // Update Wallet
        transaction.set(walletRef, {
          'currentBalance': newBalance,
        }, SetOptions(merge: true));

        // Create Transaction Record
        final transactionRef = driverRef
            .collection('wallet_transactions')
            .doc();
        transaction.set(transactionRef, {
          'amount': price,
          'type': 'debit',
          'createdAt': FieldValue.serverTimestamp(),
          'description': 'Plan Purchase: $planName',
          'status': 'success',
        });

        // Update Driver Subscription
        // Calculate new expiry
        // If current expiry is in future, add to it? Or reset?
        // Usually extend. Let's fetch current expiry first?
        // For simplicity/safety in transaction, better to read driver doc.
        final driverDoc = await transaction.get(driverRef);

        DateTime currentExpiry = DateTime.now();
        if (driverDoc.exists &&
            driverDoc.data()!.containsKey('subscriptionExpiry')) {
          final ts = driverDoc.data()!['subscriptionExpiry'];
          if (ts is Timestamp) {
            final exp = ts.toDate();
            if (exp.isAfter(DateTime.now())) {
              currentExpiry = exp;
            }
          }
        }

        final newExpiry = currentExpiry.add(Duration(days: durationDays));

        transaction.set(driverRef, {
          'subscriptionExpiry': Timestamp.fromDate(newExpiry),
          'subscriptionPlan': planName,
          // If they were offroaded and this brings balance up (unlikely for purchase,
          // but if they added money separately), we handle that elsewhere.
          // Purchase usually LOWERS balance.
        }, SetOptions(merge: true));
      });

      Get.snackbar("Success", "Plan activated! Valid for $durationDays days.");
      Get.back(); // Close plan screen
    } catch (e) {
      Get.snackbar("Error", "Plan purchase failed: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> initiatePlanPurchase(
    String planName,
    double totalPrice,
    int durationDays,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (totalPrice <= 0) {
      isLoading.value = true;
      await _finalizeSubscriptionPurchase(
        "FREE_TRIAL_${DateTime.now().millisecondsSinceEpoch}",
        {
          'planName': planName,
          'price': totalPrice,
          'durationDays': durationDays,
        },
      );
      return;
    }

    try {
      isLoading.value = true;
      _pendingSubscription = {
        'planName': planName,
        'price': totalPrice,
        'durationDays': durationDays,
      };

      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('createCashfreeOrder');
      final result = await callable.call({
        'amount': totalPrice,
        'phone': user.phoneNumber ?? "9999999999",
      });

      if (result.data['success'] == true) {
        final paymentSessionId = result.data['paymentSessionId'];
        final orderId = result.data['orderId'];

        var session = CFSessionBuilder()
            .setEnvironment(
              CFEnvironment.PRODUCTION,
            ) // Set to PRODUCTION for live subscription keys
            .setOrderId(orderId)
            .setPaymentSessionId(paymentSessionId)
            .build();

        var cfWebCheckoutPayment = CFWebCheckoutPaymentBuilder()
            .setSession(session)
            .build();

        _cashfree.doPayment(cfWebCheckoutPayment);
      } else {
        throw Exception("Failed to create Cashfree order");
      }
    } catch (e) {
      _pendingSubscription = null;
      isLoading.value = false;
      Get.snackbar("Error", "Failed to initiate payment: $e");
    }
  }

  Future<void> _finalizeSubscriptionPurchase(
    String paymentId,
    Map<String, dynamic> planDetails,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String planName = planDetails['planName'];
    final double price = planDetails['price'];
    final int durationDays = planDetails['durationDays'];

    try {
      await _db.runTransaction((transaction) async {
        final driverRef = _db.collection('drivers').doc(_driverDocId ?? user.uid);

        // 1. Update Subscription Expiry
        final driverDoc = await transaction.get(driverRef);
        DateTime currentExpiry = DateTime.now();

        if (driverDoc.exists &&
            driverDoc.data()!.containsKey('subscriptionExpiry')) {
          final ts = driverDoc.data()!['subscriptionExpiry'];
          if (ts is Timestamp) {
            final exp = ts.toDate();
            if (exp.isAfter(DateTime.now())) {
              currentExpiry = exp;
            }
          }
        }

        final newExpiry = currentExpiry.add(Duration(days: durationDays));

        transaction.set(driverRef, {
          'subscriptionExpiry': Timestamp.fromDate(newExpiry),
          'subscriptionPlan': planName,
        }, SetOptions(merge: true));

        // 2. Record Transaction (Payment received directly)
        final transactionRef = driverRef
            .collection('wallet_transactions')
            .doc();
        transaction.set(transactionRef, {
          'amount': price,
          'type': 'debit', // Conceptually a purchase
          'createdAt': FieldValue.serverTimestamp(),
          'description': 'Plan Purchase: $planName',
          'paymentId': paymentId,
          'status': 'success',
          'method': 'cashfree_direct',
        });
      });

      // Success Dialog
      Get.defaultDialog(
        title: "Purchase Successful",
        middleText: "Your $planName is now active!",
        textConfirm: "Awesome",
        confirmTextColor: Colors.white,
        onConfirm: () {
          Get.back(); // Close dialog
          Get.back(); // Close subscription screen if needed, or stay
        },
      );
    } catch (e) {
      Get.defaultDialog(
        title: "Activation Error",
        middleText:
            "Payment successful but plan activation failed. Support ID: $paymentId",
        textCancel: "Close",
      );
    } finally {
      isLoading.value = false;
    }
  }
}
