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
import 'package:project_taxi_driver_app/data/models/bank_account.dart';

class WalletTransaction {
  final String id;
  final double amount;
  final String type; // 'credit' or 'debit'
  final DateTime createdAt;
  final String description;
  final String status; // 'pending', 'success', 'failed'

  WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
    required this.description,
    this.status = 'success',
  });

  factory WalletTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WalletTransaction(
      id: doc.id,
      amount: (data['amount'] ?? 0.0).toDouble(),
      type: data['type'] ?? 'credit',
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      description: data['description'] ?? '',
      status: data['status'] ?? 'success',
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
  final Map<String, String> _lastKnownStatuses = {};
  // RxList<String> savedUpiIds = <String>[].obs; // Commented out per user request (Cashfree UPI disabled)
  RxList<BankAccount> savedBankAccounts = <BankAccount>[].obs;

  // Settlement Features
  RxInt settlementsThisWeek = 0.obs;
  Rx<DateTime?> lastSettlementReset = Rx<DateTime?>(null);
  Rx<DateTime?> lastSettlementDate = Rx<DateTime?>(null);

  // Queued Subscription State
  RxString queuedPlanName = "".obs;
  RxInt queuedPlanDurationDays = 0.obs;

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

  String? get userPhoneNumber => _auth.currentUser?.phoneNumber;

  @override
  void onInit() {
    super.onInit();
    // Delay heavy data fetching until after the first frame
    // This allows the screen transition animation to run smoothly
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDocId();
      fetchWalletData();
      // fetchUpiIds(); // Commented out per user request (Cashfree UPI disabled)
      fetchBankAccounts();
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

  /*
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
  */

  void fetchBankAccounts() {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      _subscriptions.add(_db
          .collection('drivers')
          .doc(_id)
          .collection('bank_accounts')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
            debugPrint("Bank accounts update: ${snapshot.docs.length} found");
            savedBankAccounts.value = snapshot.docs
                .map((doc) => BankAccount.fromFirestore(doc))
                .toList();
          }, onError: (e) => debugPrint("Bank accounts stream error: $e")));
    } catch (e) {
      debugPrint("Error fetching bank accounts: $e");
    }
  }

  Future<bool> initiateBankAccountVerification({
    required String name,
    required String accountNumber,
    required String ifsc,
    String accountType = 'savings',
    bool showOtpDialog = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.phoneNumber == null) {
      Get.snackbar("Error", "User phone number not found");
      return false;
    }

    try {
      isLoading.value = true;

      // 1. Penny Drop Verification (Bank Account exists check)
      final verifyCallable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('initiateBankAccountVerification');
      
      final verifyResult = await verifyCallable.call({
          'driverId': _id,
          'name': name,
          'accountNumber': accountNumber,
          'ifsc': ifsc,
          'accountType': accountType,
          'phone': user.phoneNumber,
          'upiId': "", // Satisfy backend validation
          'method': 'bank',
      });

      if (verifyResult.data['success'] != true) {
        isLoading.value = false;
        debugPrint("[BANK_VERIFY] Penny Drop Failed: ${verifyResult.data['message']}");
        Get.snackbar("Verification Failed", verifyResult.data['message'] ?? "Could not verify bank details");
        return false;
      }

      debugPrint("[BANK_VERIFY] Penny Drop Success. Initiating OTP for: ${user.phoneNumber}");

      // 2. Trigger OTP for security
      try {
        await _db.collection('otp_verifications').doc(user.phoneNumber).set({
          'requestedAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
        debugPrint("[BANK_VERIFY] OTP Firestore document created successfully.");
      } catch (dbError) {
        debugPrint("[BANK_VERIFY] ERROR writing to otp_verifications: $dbError");
        isLoading.value = false;
        Get.snackbar("Error", "Could not initiate OTP verification. Please contact support.");
        return false;
      }

      isLoading.value = false;

      if (showOtpDialog) {
        // 3. Show OTP Dialog using Pinput
        final otpController = TextEditingController();
        Get.dialog(
          AlertDialog(
            title: const Text("Verify Account Addition"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Account Verified! Enter OTP sent to ${user.phoneNumber} to save."),
                const SizedBox(height: 20),
                Pinput(
                  controller: otpController,
                  length: 6,
                  onCompleted: (pin) async {
                    Get.back(); // Close OTP dialog
                    await finalizeBankAccountAddition(
                      name: name,
                      accountNumber: accountNumber,
                      ifsc: ifsc,
                      otp: pin,
                      phone: user.phoneNumber!,
                    );
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
      }
      return true;
    } catch (e) {
      isLoading.value = false;
      Get.snackbar("Error", "Failed to initiate verification: $e");
      return false;
    }
  }

  Future<bool> finalizeBankAccountAddition({
    required String name,
    required String accountNumber,
    required String ifsc,
    required String otp,
    required String phone,
    String accountType = 'savings',
  }) async {
    try {
      isLoading.value = true;
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('verifyBankAccountWithOtp');

      final result = await callable.call({
        'name': name,
        'accountNumber': accountNumber,
        'ifsc': ifsc,
        'otp': otp,
        'phone': phone,
        'accountType': accountType,
        'upiId': "", // Satisfy backend validation
        'method': 'bank',
      });

      isLoading.value = false;
      if (result.data['success'] == true) {
        Get.snackbar("Success", "Bank Account Added Successfully");
        fetchBankAccounts(); // Refresh the list
        return true;
      } else {
        Get.snackbar("Error", result.data['message'] ?? "Verification failed");
        return false;
      }
    } catch (e) {
      isLoading.value = false;
      Get.snackbar("Error", "Failed to finalize addition: $e");
      return false;
    }
  }

  Future<void> deleteBankAccount(String accountId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      if (_driverDocId == null) await _loadDocId();
      await _db
          .collection('drivers')
          .doc(_id)
          .collection('bank_accounts')
          .doc(accountId)
          .delete();
      Get.snackbar("Success", "Bank account removed");
    } catch (e) {
      Get.snackbar("Error", "Failed to delete bank account: $e");
    }
  }

  /*
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
  */

  String get _id => _driverDocId ?? _auth.currentUser?.uid ?? "";

  void fetchWalletData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Ensure we have the correct ID before starting any listeners
    if (_driverDocId == null) {
      await _loadDocId();
    }

    // Cancel existing listeners to prevent duplicates
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    try {
      _subscriptions.add(_db
          .collection('drivers')
          .doc(_id)
          .collection('wallet')
          .doc('balance')
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          balance.value = (snapshot.data()?['currentBalance'] ?? 0.0).toDouble();
        }
      }, onError: (e) => debugPrint("Balance stream error: $e")));

      _listenToWalletMetadata(user);

      // Listen to transactions
      _subscriptions.add(_db
          .collection('drivers')
          .doc(_id)
          .collection('wallet_transactions')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
            final newList = snapshot.docs
                .map((doc) => WalletTransaction.fromFirestore(doc))
                .toList();

            // Notify on status changes (e.g., pending -> success/failed)
            for (var tx in newList) {
              if (_lastKnownStatuses.containsKey(tx.id)) {
                final oldStatus = _lastKnownStatuses[tx.id];
                if (oldStatus == 'pending' && tx.status != 'pending') {
                  _notifyStatusChange(tx);
                }
              }
              _lastKnownStatuses[tx.id] = tx.status;
            }

            transactions.value = newList;
          }, onError: (e) => debugPrint("Transactions stream error: $e")));
    } catch (e) {
      Get.snackbar("Error", "Failed to fetch wallet data: $e");
    }
  }

  void _notifyStatusChange(WalletTransaction tx) {
    if (tx.status == 'success') {
      Get.snackbar(
        "Settlement Successful",
        "₹${tx.amount.toStringAsFixed(2)} has been successfully transferred to your account.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
        icon: const Icon(Icons.check_circle, color: Colors.white),
      );
    } else if (tx.status == 'failed') {
      Get.snackbar(
        "Settlement Failed",
        "The payout of ₹${tx.amount.toStringAsFixed(2)} was unsuccessful. Please check your bank details.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.redAccent,
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
        icon: const Icon(Icons.error, color: Colors.white),
      );
    }
  }

  void _listenToWalletMetadata(User user) {
    _subscriptions.add(_db.collection('drivers').doc(_id).snapshots().listen((snapshot) async {
      if (snapshot.exists) {
        final data = snapshot.data();
        queuedPlanName.value = data?['queuedPlanName'] ?? "";
        queuedPlanDurationDays.value = data?['queuedPlanDurationDays'] ?? 0;

        // Auto Promotion Check
        if (queuedPlanName.value.isNotEmpty) {
          bool shouldPromote = false;
          if (data!.containsKey('subscriptionExpiry')) {
            final ts = data['subscriptionExpiry'];
            if (ts is Timestamp) {
              if (ts.toDate().isBefore(DateTime.now())) {
                shouldPromote = true;
              }
            } else {
              shouldPromote = true;
            }
          } else {
            shouldPromote = true;
          }

          if (shouldPromote) {
             await _promoteQueuedPlan(user);
          }
        }
      }
    }, onError: (e) => debugPrint("Driver info stream error: $e")));

    _subscriptions.add(_db
        .collection('drivers')
        .doc(_id)
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
        }, onError: (e) => debugPrint("Wallet metadata stream error: $e")));
  }

  Future<void> _promoteQueuedPlan(User user) async {
      try {
        await _db.runTransaction((transaction) async {
           final driverRef = _db.collection('drivers').doc(_driverDocId ?? user.uid);
           final driverDoc = await transaction.get(driverRef);
           if (!driverDoc.exists) return;
           
           final data = driverDoc.data()!;
           final queuedName = data['queuedPlanName'];
           final queuedDays = data['queuedPlanDurationDays'] ?? 0;

           if (queuedName == null || queuedName == "") return;

           final newExpiry = DateTime.now().add(Duration(days: queuedDays));

           transaction.set(driverRef, {
              'subscriptionPlan': queuedName,
              'subscriptionExpiry': Timestamp.fromDate(newExpiry),
              'queuedPlanName': FieldValue.delete(),
              'queuedPlanDurationDays': FieldValue.delete(),
           }, SetOptions(merge: true));
        });
        debugPrint("Queued Plan Promoted successfully!");
      } catch (e) {
        debugPrint("Failed to promote queued plan: $e");
      }
  }

  Future<void> creditWallet(
    double amount,
    String paymentId, {
    String description = 'Money Added to Wallet',
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Guard against ₹0 credit records (ghost transactions)
    if (amount <= 0) {
      debugPrint("WalletController: Skipping credit for zero amount.");
      return;
    }

    try {
      isLoading.value = true;

      // 2. Ensure Driver Doc ID is resolved before performing the transaction
      if (_driverDocId == null) {
        await _loadDocId();
      }

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

      // 3. Trigger In-App Notification for the Driver
      Get.snackbar(
        "Payment Received",
        "₹${amount.toStringAsFixed(2)} has been credited to your wallet.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
        icon: const Icon(Icons.account_balance_wallet, color: Colors.white),
      );

      debugPrint("WalletController: Credit successful for amount: $amount");
    } catch (e) {
      debugPrint("WalletController: Credit failed: $e");
      Get.snackbar("Error", "Wallet update failed: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> debitWallet(
    double amount,
    String paymentId, {
    String description = 'Money Deducted from Wallet',
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (amount <= 0) {
      debugPrint("WalletController: Skipping debit for zero amount.");
      return;
    }

    try {
      isLoading.value = true;
      if (_driverDocId == null) {
        await _loadDocId();
      }

      await _db.runTransaction((transaction) async {
        final balanceRef = _db
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .collection('wallet')
            .doc('balance');
        final balanceDoc = await transaction.get(balanceRef);

        double currentBalance = 0.0;
        if (balanceDoc.exists) {
          currentBalance = (balanceDoc.data()?['currentBalance'] ?? 0.0).toDouble();
        }

        final newBalance = currentBalance - amount;
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
          'amount': amount, // Store as positive value, type identifies debit
          'type': 'debit',
          'createdAt': FieldValue.serverTimestamp(),
          'description': description,
          'paymentId': paymentId,
        });
      });
    } catch (e) {
      debugPrint("Error debiting wallet: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> settleBalance({String? upiId, BankAccount? bankAccount}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (balance.value <= 0) {
      Get.snackbar("Error", "Insufficient balance to settle.");
      return;
    }

    try {
      isLoading.value = true;
      
      // Ensure DocID is loaded
      if (_driverDocId == null) {
        await _loadDocId();
      }
      
      debugPrint("Settlement initiated for driver: $_id");
      Get.back(); // Close dialog

      debugPrint("Settlement initiated for driver: $_id");
      Get.back(); // Close dialog

      // Note: We no longer call a Cloud Function directly. 
      // Saving the transaction as 'pending' to Firestore triggers 
      // the 'processWalletSettlement' background function automatically.

      await _db.runTransaction((transaction) async {
        final balanceRef = _db
            .collection('drivers')
            .doc(_id)
            .collection('wallet')
            .doc('balance');
        final balanceDoc = await transaction.get(balanceRef);

        double currentBalance = 0.0;
        if (balanceDoc.exists) {
          currentBalance = (balanceDoc.data()?['currentBalance'] ?? 0.0)
              .toDouble();
        }

        if (currentBalance <= 0) throw Exception("Insufficient balance");

        final metadataRef = _db
            .collection('drivers')
            .doc(_id)
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

        final now = DateTime.now();
        final lastSunday = now.subtract(Duration(days: now.weekday % 7));
        final startOfLastSunday = DateTime(
          lastSunday.year,
          lastSunday.month,
          lastSunday.day,
        );

        if (lastReset == null || lastReset.isBefore(startOfLastSunday)) {
          currentCount = 0;
          lastReset = startOfLastSunday;
        }

        if (currentCount >= 99) {
          throw Exception("Weekly settlement limit reached.");
        }

        transaction.set(metadataRef, {
          'settlementsThisWeek': currentCount + 1,
          'lastSettlementReset': Timestamp.fromDate(lastReset),
          'lastSettlementDate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(balanceRef, {
          'currentBalance': 0.0,
        }, SetOptions(merge: true));

        final transactionRef = _db
            .collection('drivers')
            .doc(_driverDocId ?? user.uid)
            .collection('wallet_transactions')
            .doc();

        final Map<String, dynamic> txData = {
          'amount': currentBalance,
          'type': 'debit',
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
          'phone': user.phoneNumber, // Include real phone for Cashfree registration
          'upiId': "bank_payout", // Sentinel value to bypass backend validation (cannot be empty)
        };

        if (bankAccount != null) {
          txData['description'] = "Settlement requested to Bank: ${bankAccount.maskedAccountNumber}";
          txData['bankAccount'] = bankAccount.encryptedAccountNumber;
          txData['ifsc'] = bankAccount.ifsc;
          txData['maskedAccount'] = bankAccount.maskedAccountNumber;
          txData['bankAccountId'] = bankAccount.id; // Firestore doc ID for bene lookup
          txData['cashfreeBeneId'] = bankAccount.cashfreeBeneId; // Pre-computed bene ID
          txData['bankHolderName'] = bankAccount.name; // Real driver name for re-registration
        } else if (upiId != null) {
          txData['description'] = "Settlement requested to UPI: $upiId";
          txData['upiId'] = upiId;
        } else {
          throw Exception("No payout destination selected");
        }

        transaction.set(transactionRef, txData);
      });

      Get.snackbar(
        "Settlement Initiated",
        "Your payout is being processed in the background. You will receive a notification once the bank completes it.",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar("Settlement Error", "Failed to initiate settlement: $e");
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

        final driverDoc = await transaction.get(driverRef);
        DateTime currentExpiry = DateTime.now();
        bool hasActivePlan = false;

        if (driverDoc.exists &&
            driverDoc.data()!.containsKey('subscriptionExpiry')) {
          final ts = driverDoc.data()!['subscriptionExpiry'];
          if (ts is Timestamp) {
            final exp = ts.toDate();
            if (exp.isAfter(DateTime.now())) {
              currentExpiry = exp;
              hasActivePlan = true;
            }
          }
        }

        if (hasActivePlan) {
          final existingQueue = driverDoc.data()?['queuedPlanName'];
          if (existingQueue != null && existingQueue != "") {
             throw Exception("You already have a plan ($existingQueue) queued. Please wait for it to activate.");
          }
          // Queue the trial plan
          transaction.set(driverRef, {
            'queuedPlanName': planName,
            'queuedPlanDurationDays': durationDays,
          }, SetOptions(merge: true));
          debugPrint("Trial Plan Queued: $planName");
        } else {
          // Activate immediately
          final newExpiry = currentExpiry.add(Duration(days: durationDays));
          transaction.set(driverRef, {
            'subscriptionExpiry': Timestamp.fromDate(newExpiry),
            'subscriptionPlan': planName,
          }, SetOptions(merge: true));
          debugPrint("Trial Plan Activated Immediately: $planName");
        }
        
        // Ensure no transaction record for 0 amount to avoid ghost entries
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

    // CRITICAL: Ensure DocID is loaded before any subscription action
    if (_driverDocId == null) {
      await _loadDocId();
    }

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
            .setEnvironment(CFEnvironment.PRODUCTION)
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
      String errorMsg = e.toString();
      if (e is FirebaseFunctionsException) {
        errorMsg = "${e.code}: ${e.message}";
      }
      Get.snackbar("Payment Error", "Failed to initiate: $errorMsg");
    }
  }

  Future<void> _finalizeSubscriptionPurchase(
    String paymentId,
    Map<String, dynamic> planDetails,
  ) async {
    // Ensure DocID is available
    if (_driverDocId == null) {
      await _loadDocId();
    }
    
    if (_driverDocId == null) {
      Get.snackbar("Error", "Could not identify driver document. Contact support.");
      return;
    }

    final String planName = planDetails['planName'];
    final double price = planDetails['price'];
    final int durationDays = planDetails['durationDays'];

    try {
      await _db.runTransaction((transaction) async {
        final driverRef = _db.collection('drivers').doc(_driverDocId!);

        // 1. Update Subscription Expiry
        final driverDoc = await transaction.get(driverRef);
        DateTime currentExpiry = DateTime.now();
        bool hasActivePlan = false;

        if (driverDoc.exists &&
            driverDoc.data()!.containsKey('subscriptionExpiry')) {
          final ts = driverDoc.data()!['subscriptionExpiry'];
          if (ts is Timestamp) {
            final exp = ts.toDate();
            if (exp.isAfter(DateTime.now())) {
              currentExpiry = exp;
              hasActivePlan = true;
            }
          }
        }

        if (hasActivePlan) {
           final existingQueue = driverDoc.data()?['queuedPlanName'];
           if (existingQueue != null && existingQueue != "") {
               throw Exception("You already have a \"$existingQueue\" plan queued. Please wait for it to activate before purchasing another.");
           }
           transaction.set(driverRef, {
              'queuedPlanName': planName,
              'queuedPlanDurationDays': durationDays,
           }, SetOptions(merge: true));
        } else {
           final newExpiry = currentExpiry.add(Duration(days: durationDays));
           transaction.set(driverRef, {
             'subscriptionExpiry': Timestamp.fromDate(newExpiry),
             'subscriptionPlan': planName,
           }, SetOptions(merge: true));
        }

        // 2. Record Transaction (Payment received directly)
        if (price > 0) {
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
        }
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
