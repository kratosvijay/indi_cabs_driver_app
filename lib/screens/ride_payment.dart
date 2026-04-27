// ignore_for_file: unused_field

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';
import 'package:project_taxi_driver_app/screens/homepage.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:project_taxi_driver_app/widgets/status_slider.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_taxi_driver_app/services/id_service.dart';
import 'package:project_taxi_driver_app/screens/qr_settings_screen.dart';

class RidePaymentScreen extends StatefulWidget {
  final RideRequest rideRequest;
  final double totalAmount;
  final bool priceUpdated;
  final bool tollCrossed;
  final double tollCharge;

  const RidePaymentScreen({
    super.key,
    required this.rideRequest,
    required this.totalAmount,
    this.priceUpdated = false,
    this.tollCrossed = false,
    this.tollCharge = 0.0,
  });

  @override
  State<RidePaymentScreen> createState() => _RidePaymentScreenState();
}

class _RidePaymentScreenState extends State<RidePaymentScreen> {
  String? _driverUpiId;
  String? _driverName;
  String? _driverDocId;

  StreamSubscription<DocumentSnapshot>? _rideSubscription;
  bool _isDataLoaded = false;

  RideRequest? _fetchedRideRequest;
  RideRequest get _rideRequest => _fetchedRideRequest ?? widget.rideRequest;

  double _fetchedWalletAmount = 0.0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _fetchDriverUpiDetails();
    _startRideStream();
  }

  void _startRideStream() {
    try {
      _rideSubscription = FirebaseFirestore.instance
          .collection(
            widget.rideRequest.rideType == 'rental'
                ? 'rental_requests'
                : 'ride_requests',
          )
          .doc(widget.rideRequest.rideId)
          .snapshots()
          .listen(
            (doc) {
              if (doc.exists && doc.data() != null) {
                final data = doc.data() as Map<String, dynamic>;
                data['rideId'] ??= doc.id;

                // Explicitly get walletAmountUsed
                final wAmount =
                    (data['walletAmountUsed'] as num?)?.toDouble() ??
                    (data['paidByWallet'] as num?)?.toDouble() ??
                    0.0;

                debugPrint(
                  "RidePaymentScreen: Stream Update - walletAmountUsed: ${data['walletAmountUsed']}, Resolved: $wAmount",
                );

                if (mounted) {
                  setState(() {
                    _fetchedRideRequest = RideRequest.fromJson(data);
                    _fetchedWalletAmount = wAmount;
                    _isDataLoaded = true;
                  });
                }
              }
            },
            onError: (e) {
              debugPrint("Error in ride stream: $e");
              if (mounted) setState(() => _isDataLoaded = true);
            },
          );
    } catch (e) {
      debugPrint("Error starting ride stream: $e");
      if (mounted) setState(() => _isDataLoaded = true);
    }
  }

  Future<void> _fetchDriverUpiDetails() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (_driverDocId == null) {
          _driverDocId = await IdService.getDriverDocId(user.uid);
          debugPrint('RidePayment: Resolved DriverDocID: $_driverDocId');
        }

        final doc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(_driverDocId)
            .get();

        if (doc.exists) {
          final data = doc.data();
          debugPrint(
            'RidePayment: Fetched Driver Data. activeUpiId: ${data?['activeUpiId']}',
          );

          if (mounted) {
            setState(() {
              // OPTIMIZATION: Only update if the fetched data is non-null
              // This prevents stale Cloud data (lag) from overwriting a freshly saved local UPI ID
              final fetchedUpi = data?['activeUpiId'] ?? data?['upiId'];
              if (fetchedUpi != null) {
                _driverUpiId = fetchedUpi;
              } else if (data?['upiIds'] != null) {
                final list = List<String>.from(data!['upiIds']);
                if (list.isNotEmpty) _driverUpiId = list.first;
              }

              _driverName = (data?['userName'] ?? 'Customer').toString().trim();
            });
          }
        } else {
          debugPrint(
            'RidePayment: Driver document does not exist for ID: $_driverDocId',
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching driver UPI details: $e');
    }
  }

  Future<void> _addUpiId(String upiId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Ensure we have the Doc ID
      if (_driverDocId == null) {
        debugPrint("RidePayment: Resolving driverDocId in _addUpiId...");
        _driverDocId = await IdService.getDriverDocId(user.uid);
      }

      debugPrint("RidePayment: Adding UPI $upiId to Doc $_driverDocId");

      final docRef = FirebaseFirestore.instance
          .collection('drivers')
          .doc(_driverDocId);

      // Use set with merge to create/update fields reliably
      await docRef.set({
        'activeUpiId': upiId,
        'upiIds': FieldValue.arrayUnion([upiId]),
      }, SetOptions(merge: true));

      debugPrint("RidePayment: Firestore update successful for UPI: $upiId");

      // Set state FIRST to ensure UI updates immediately
      if (mounted) {
        setState(() {
          _driverUpiId = upiId;
        });
      }

      // Then trigger refresh (the fetch guard will now protect the local state)
      await _fetchDriverUpiDetails();

      Get.snackbar(
        'Success',
        'UPI ID added successfully',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      debugPrint('Error adding UPI ID: $e');
      Get.snackbar(
        'Error',
        'Failed to save UPI ID. Please check your connection.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _showAddUpiDialog() {
    final TextEditingController upiController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add UPI ID'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add your UPI ID to let customers scan and pay.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: upiController,
                      decoration: const InputDecoration(
                        labelText: 'UPI ID (e.g. name@bank)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payment),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a UPI ID';
                        }
                        if (!value.contains('@')) {
                          return 'Invalid format';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () async {
                      final result = await Get.to<String?>(
                        () => const QrScannerView(),
                      );
                      if (result != null && result.isNotEmpty) {
                        String extractedId = result;
                        if (result.startsWith('upi://')) {
                          try {
                            final uri = Uri.parse(result);
                            final pa = uri.queryParameters['pa'];
                            if (pa != null) extractedId = pa;
                          } catch (e) {
                            debugPrint("Error parsing UPI URI: $e");
                          }
                        }
                        upiController.text = extractedId;
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final newId = upiController.text.trim();
                Get.back();
                _addUpiId(newId);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildUpiSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_driverUpiId != null && _driverUpiId!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 20.0),
        child: Column(
          children: [
            Text(
              'scanToPay'.tr,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: QrImageView(
                data:
                    'upi://pay?pa=$_driverUpiId&pn=$_driverName&am=$_cashToCollect&cu=INR',
                version: QrVersions.auto,
                size: 200.0,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${'upiId'.tr}: $_driverUpiId',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    } else {
      // Empty state prompt
      return Padding(
        padding: const EdgeInsets.only(top: 20.0),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.blue.withAlpha(50), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Icon(Icons.qr_code_2, size: 48, color: Colors.blue),
                const SizedBox(height: 12),
                const Text(
                  'Accept QR Payments',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your UPI ID to let customers scan and pay you instantly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 16),
                ProButton(text: 'Add UPI ID', onPressed: _showAddUpiDialog),
              ],
            ),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _rideSubscription?.cancel();
    // WakelockPlus.disable(); // Keep screen on even after leaving this screen (handled by Home)
    super.dispose();
  }

  // Use explicitly fetched amount if available, otherwise fallback to request model
  double get _walletAmount => _fetchedWalletAmount > 0
      ? _fetchedWalletAmount
      : (_rideRequest.paidByWallet ?? 0.0);

  bool get _isCashPlusWallet {
    final method = _rideRequest.paymentMethod;
    final isMethodMatch =
        method == 'Cash + Wallet' || method.contains('Wallet');
    final hasWalletAmount = _walletAmount > 0;

    return isMethodMatch || hasWalletAmount;
  }

  bool get isLoadingData => !_isDataLoaded;

  bool get _isOnline => _rideRequest.paymentMethod == 'Online';
  bool get _isCashOnly =>
      !_isOnline &&
      !_isCashPlusWallet &&
      _rideRequest.paymentMethod != 'Wallet';

  double get _cashToCollect {
    if (_isOnline) return 0.0;
    if (_isCashPlusWallet) {
      double collected = widget.totalAmount - _walletAmount;
      return collected < 0 ? 0.0 : collected;
    }
    return widget.totalAmount;
  }

  void _showRatingDialog() {
    double rating = 0.0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('rateCustomer'.tr),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('rateExperience'.tr),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      onPressed: () {
                        setDialogState(() {
                          rating = index + 1.0;
                        });
                      },
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                    );
                  }),
                ),
              ],
            ),
            actions: [
              ProButton(
                text: 'submit'.tr,
                onPressed: () {
                  if (rating == 0.0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('selectRating'.tr),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Get.back();
                  _finishRide(rating);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _finishRide(double driverProvidedRating) async {
    // Ensure WalletController is available for GST deduction
    if (!Get.isRegistered<WalletController>()) {
      Get.put(WalletController());
    }
    final WalletController walletController = WalletController.instance;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 1. Capture Data Locally (Safety against widget disposal)
      final localTotalAmount = widget.totalAmount;
      final localRideId = _rideRequest.rideId;
      final localRideDistance = _rideRequest.rideDistance;
      final localRideType = _rideRequest.rideType;
      final localWaitingCharge = _rideRequest.waitingCharge;
      final localUserId = user.uid;
      final localCustomerId = _rideRequest.userId;

      final bool isOnline = _isOnline;
      final bool isCashPlusWallet = _isCashPlusWallet;
      final double walletAmt = _walletAmount;

      // 2. Navigation Logic
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('details_accepted_ride_id');

      // Prevent the just-finished ride from ghost-triggering due to local cache lag.
      // HomePageController may not be registered if the app was restored directly
      // to RidePaymentScreen (e.g. after a crash/restart mid-ride).
      if (Get.isRegistered<HomePageController>()) {
        Get.find<HomePageController>().ignoreRide(localRideId);
      }

      Get.offAll(
        () => DriverHomePage(user: user, initialStatus: DriverStatus.online),
      );

      // 3. Background Transactions
      // We use a separate async block or just continue here.
      // Since we already navigated, 'context' is unsafe, but Firebase calls are fine.

      // Credit Logic
      final amountToCredit = isOnline
          ? localTotalAmount
          : (isCashPlusWallet ? walletAmt : 0.0);

      // GST Deduction (5% of Total Fare)
      try {
        final gstAmount = double.parse(
          (localTotalAmount * 0.05).toStringAsFixed(2),
        );
        debugPrint(
          "[GST] Ride ID: $localRideId, Total Amount: $localTotalAmount, Calculated GST: $gstAmount",
        );

        if (gstAmount > 0) {
          // Use the localized controller instance
          await walletController.debitWallet(
            gstAmount,
            "gst_$localRideId",
            description: "5% GST Deduction: $localRideId",
          );
          debugPrint("[GST] Successfully triggered debit for $gstAmount");
        } else {
          debugPrint("[GST] Skipping deduction - Amount is 0");
        }
      } catch (e) {
        debugPrint("[GST] Failed to deduct GST: $e");
      }

      if (amountToCredit > 0) {
        try {
          // A. Credit Driver Wallet
          await WalletController.instance.creditWallet(
            amountToCredit,
            "ride_${_rideRequest.rideId}",
            description: "Ride Credit: ${_rideRequest.rideId}",
          );

          // B. Create Earnings Record
          try {
            await FirebaseFirestore.instance
                .collection('earnings')
                .doc(localRideId)
                .set({
                  'amount': localTotalAmount,
                  'createdAt': FieldValue.serverTimestamp(),
                  'details': {
                    'baseFare':
                        (localTotalAmount -
                        localWaitingCharge -
                        widget.tollCharge),
                    'distance': localRideDistance,
                    'rideType': localRideType,
                    'waitingCharge': localWaitingCharge,
                    'tollCharge': widget.tollCharge,
                  },
                  'driverId': localUserId,
                  'rideId': localRideId,
                  'status': 'completed',
                  'type': 'ride_fare',
                });
            debugPrint("Earnings record created for ride $localRideId");
          } catch (e) {
            debugPrint("Failed to create earnings record: $e");
          }

          // C. Deduct from Customer Wallet (Only if Cash + Wallet)
          if (isCashPlusWallet) {
            final amountToDeduct = walletAmt;

            if (amountToDeduct > 0) {
              await FirebaseFirestore.instance.runTransaction((
                transaction,
              ) async {
                final userRef = FirebaseFirestore.instance
                    .collection('users')
                    .doc(localCustomerId);

                final userSnapshot = await transaction.get(userRef);
                if (userSnapshot.exists) {
                  final userData = userSnapshot.data();
                  if (userData != null) {
                    var currentBalance = (userData['wallet_balance'] as num?)
                        ?.toDouble();
                    currentBalance ??= (userData['walletBalance'] as num?)
                        ?.toDouble();
                    currentBalance ??= 0.0;

                    final newBalance = currentBalance - amountToDeduct;

                    if (userData.containsKey('wallet_balance')) {
                      transaction.update(userRef, {
                        'wallet_balance': newBalance,
                      });
                    } else {
                      transaction.update(userRef, {
                        'walletBalance': newBalance,
                      });
                    }

                    final transactionRef = userRef
                        .collection('wallet_transactions')
                        .doc();
                    transaction.set(transactionRef, {
                      'amount': -amountToDeduct,
                      'description': 'Ride Payment: $localRideId',
                      'timestamp': FieldValue.serverTimestamp(),
                      'type': 'debit',
                    });
                  }
                }
              });
              debugPrint(
                "Deducted $amountToDeduct from customer $localCustomerId wallet.",
              );
            }
          }
        } catch (e) {
          debugPrint("Failed to process background wallet transactions: $e");
          // No valid context to show snackbar, just log.
        }
      }

      // D. Update Customer Rating
      if (driverProvidedRating > 0) {
        try {
          final userRef = FirebaseFirestore.instance
              .collection('users')
              .doc(localCustomerId);
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            final snapshot = await transaction.get(userRef);
            if (snapshot.exists) {
              final data = snapshot.data();
              if (data != null) {
                final currentRating =
                    (data['rating'] as num?)?.toDouble() ?? 5.0;
                final currentCount =
                    (data['ratingCount'] as num?)?.toInt() ?? 0;

                final newCount = currentCount + 1;
                final totalScore = currentCount == 0
                    ? 0.0
                    : (currentRating * currentCount);
                final newRating =
                    (totalScore + driverProvidedRating) / newCount;

                transaction.update(userRef, {
                  'rating': double.parse(newRating.toStringAsFixed(1)),
                  'ratingCount': newCount,
                });
              }
            }
          });
          debugPrint(
            "Successfully updated customer rating to $driverProvidedRating",
          );
        } catch (e) {
          debugPrint("Failed to update customer rating: $e");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('payment'.tr),
          automaticallyImplyLeading: false,
        ),
        body: isLoadingData
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 20),
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 50,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'rideCompleted'.tr,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 40),

                            // Fare Details
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    // Breakdown (Informational)
                                    Builder(
                                      builder: (context) {
                                        // Logic: totalAmount = Base/Package + Extras + Waiting + Tolls
                                        // We want to show the components separately.

                                        final isRental =
                                            _rideRequest.rideType == 'rental';
                                        final double baseFare = isRental
                                            ? (_rideRequest
                                                  .rideFare) // Package Price
                                            : (widget.totalAmount -
                                                  _rideRequest.waitingCharge -
                                                  widget.tollCharge);

                                        return Column(
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  isRental
                                                      ? '${'packageBaseFare'.tr} (${_rideRequest.packageName})'
                                                      : 'rideFare'.tr,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color:
                                                        Theme.of(
                                                              context,
                                                            ).brightness ==
                                                            Brightness.dark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[600],
                                                  ),
                                                ),
                                                Text(
                                                  '₹${baseFare.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.color,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (_rideRequest.waitingCharge >
                                                0) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    'waitingCharges'.tr,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color:
                                                          Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                          ? Colors.grey[400]
                                                          : Colors.grey[600],
                                                    ),
                                                  ),
                                                  Text(
                                                    '+ ₹${_rideRequest.waitingCharge.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.redAccent,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            const Divider(height: 20),
                                          ],
                                        );
                                      },
                                    ),

                                    // Toll Information (if applicable)
                                    if (widget.tollCharge > 0) ...[
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.withAlpha(100),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.directions,
                                                  color: Colors.orange,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  widget.tollCrossed
                                                      ? 'Toll Charges'
                                                      : 'Toll (Deducted)',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              widget.tollCrossed
                                                  ? '+ ₹${widget.tollCharge.toStringAsFixed(2)}'
                                                  : '- ₹${widget.tollCharge.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: widget.tollCrossed
                                                    ? Colors.orange
                                                    : Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(height: 20),
                                    ],

                                    // Price Update Status
                                    if (widget.priceUpdated) ...[
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withAlpha(20),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue.withAlpha(100),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.info_outline,
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Price recalculated based on actual distance traveled',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.blue[700],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(height: 20),
                                    ],

                                    // Rental Breakdown (Only if rental)
                                    if (_rideRequest.packageName != null) ...[
                                      Builder(
                                        builder: (context) {
                                          final usedDistance =
                                              _rideRequest.actualDistance ??
                                              0.0;
                                          final usedDuration =
                                              _rideRequest.actualDuration ??
                                              0.0;
                                          final limitDistance =
                                              _rideRequest.kmLimit ?? 0;
                                          final limitDuration =
                                              (_rideRequest.durationHours ??
                                                  0) *
                                              60;

                                          final extraDistance =
                                              (usedDistance > limitDistance)
                                              ? (usedDistance - limitDistance)
                                              : 0.0;
                                          final extraDuration =
                                              (usedDuration > limitDuration)
                                              ? (usedDuration - limitDuration)
                                              : 0.0;

                                          final extraDistanceCost =
                                              extraDistance *
                                              (_rideRequest.extraKmCharge ?? 0);
                                          final extraDurationCost =
                                              (extraDuration / 60) *
                                              (_rideRequest.extraHourCharge ??
                                                  0);

                                          return Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '${'baseFare'.tr} (${_rideRequest.packageName})',
                                                    style: const TextStyle(
                                                      fontSize:
                                                          0, // Hidden here because we show it in the top breakdown now
                                                      color: Colors.transparent,
                                                    ),
                                                  ),
                                                  const SizedBox.shrink(),
                                                ],
                                              ),
                                              if (extraDistance > 0 ||
                                                  extraDuration > 0) ...[
                                                const Divider(height: 20),
                                                if (extraDistance > 0) ...[
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        '${'extraDistance'.tr} (${extraDistance.toStringAsFixed(1)} km)',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          color:
                                                              Theme.of(
                                                                    context,
                                                                  ).brightness ==
                                                                  Brightness
                                                                      .dark
                                                              ? Colors.grey[400]
                                                              : Colors
                                                                    .grey[600],
                                                        ),
                                                      ),
                                                      Text(
                                                        '+ ₹${extraDistanceCost.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Colors.redAccent,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                ],
                                                if (extraDuration > 0) ...[
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        '${'extraTime'.tr} (${extraDuration.toStringAsFixed(0)} ${'mins'.tr})',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          color:
                                                              Theme.of(
                                                                    context,
                                                                  ).brightness ==
                                                                  Brightness
                                                                      .dark
                                                              ? Colors.grey[400]
                                                              : Colors
                                                                    .grey[600],
                                                        ),
                                                      ),
                                                      Text(
                                                        '+ ₹${extraDurationCost.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Colors.redAccent,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                              const Divider(height: 24),
                                            ],
                                          );
                                        },
                                      ),
                                    ],

                                    // Total (Always shown)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'totalFare'.tr,
                                          style: TextStyle(fontSize: 18),
                                        ),
                                        Text(
                                          '₹${widget.totalAmount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_isCashPlusWallet &&
                                        _walletAmount > 0) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'paidByWallet'.tr,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.green,
                                            ),
                                          ),
                                          Text(
                                            '- ₹${_walletAmount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 20),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'cashToCollect'.tr,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                          Text(
                                            '₹${_cashToCollect.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const Divider(height: 30),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('paymentMethod'.tr),
                                        Row(
                                          children: [
                                            Icon(
                                              _isOnline
                                                  ? Icons.credit_card
                                                  : _isCashPlusWallet
                                                  ? Icons.account_balance_wallet
                                                  : Icons.money,
                                              color: Colors.grey,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _rideRequest.paymentMethod,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Earned per km and Time Travelled
                            if (_rideRequest.actualDistance != null ||
                                _rideRequest.actualDuration != null)
                              Row(
                                children: [
                                  Expanded(
                                    child: Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          children: [
                                            Text(
                                              'earnedPerKm'.tr,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color:
                                                    Theme.of(
                                                          context,
                                                        ).brightness ==
                                                        Brightness.dark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "₹${(widget.totalAmount / ((_rideRequest.actualDistance ?? 0.0) < 1.0 ? 1.0 : (_rideRequest.actualDistance ?? 1.0))).toStringAsFixed(2)}",
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          children: [
                                            Text(
                                              'timeTaken'.tr,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color:
                                                    Theme.of(
                                                          context,
                                                        ).brightness ==
                                                        Brightness.dark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "${_rideRequest.actualDuration?.toStringAsFixed(1) ?? '0'} ${'mins'.tr}",
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            // UPI Section
                            if ((_isCashOnly || _isCashPlusWallet) &&
                                _cashToCollect > 0)
                              _buildUpiSection(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isCashOnly ||
                        (_isCashPlusWallet && _cashToCollect > 0))
                      ProButton(
                        text: 'cashCollected'.tr,
                        onPressed: _showRatingDialog,
                      )
                    else
                      ProButton(text: 'done'.tr, onPressed: _showRatingDialog),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}
