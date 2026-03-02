// ignore_for_file: unused_field

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';
import 'package:project_taxi_driver_app/screens/homepage.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:project_taxi_driver_app/screens/ride_acepted.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:project_taxi_driver_app/widgets/status_slider.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RidePaymentScreen extends StatefulWidget {
  final RideRequest rideRequest;
  final double totalAmount;

  const RidePaymentScreen({
    super.key,
    required this.rideRequest,
    required this.totalAmount,
  });

  @override
  State<RidePaymentScreen> createState() => _RidePaymentScreenState();
}

class _RidePaymentScreenState extends State<RidePaymentScreen> {
  String? _driverUpiId;
  String? _driverName;

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
        final doc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          if (mounted) {
            setState(() {
              _driverUpiId = data?['activeUpiId'];
              if (_driverUpiId == null && data?['upiIds'] != null) {
                final list = List<String>.from(data!['upiIds']);
                if (list.isNotEmpty) _driverUpiId = list.first;
              }
              _driverUpiId ??= data?['upiId'];
              _driverName = data?['userName'] ?? 'Customer'.trim();
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching driver UPI details: $e');
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
                  _finishRide();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _finishRide() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 1. Capture Data Locally (Safety against widget disposal)
      final localTotalAmount = widget.totalAmount;
      final localRideId = _rideRequest.rideId;
      final localRideFare = _rideRequest.rideFare;
      final localRideDistance = _rideRequest.rideDistance;
      final localRideType = _rideRequest.rideType;
      final localWaitingCharge = _rideRequest.waitingCharge;
      final localUserId = user.uid;
      final localCustomerId = _rideRequest.userId;

      final bool isOnline = _isOnline;
      final bool isCashPlusWallet = _isCashPlusWallet;
      final double walletAmt = _walletAmount;

      // 2. Navigation Logic (Handle Back-to-Back Ride)
      final homeController = Get.find<HomePageController>();
      final acceptedQueuedRides = homeController.queuedRides
          .where((r) => r.status == 'accepted')
          .toList();
      final queued = acceptedQueuedRides.isNotEmpty
          ? acceptedQueuedRides.first
          : null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('details_accepted_ride_id');

      if (queued != null && queued.status == 'accepted') {
        debugPrint("Transitioning to Queued Ride: ${queued.rideId}");

        // Stop ignoring the queued ride if it was ignored
        homeController.removeIgnoredRide(queued.rideId);

        // Reset State for New Ride
        homeController.activeRequests.clear();
        homeController.activeRequests.add(queued);
        homeController.queuedRides.removeWhere(
          (r) => r.rideId == queued.rideId,
        );
        homeController.hasActiveRide.value = true;
        // driverStatus is already goTo

        Get.offAll(() => RideAcceptedScreen(rideRequest: queued));
      } else {
        // Standard Flow: Go Home

        // Prevent the just-finished ride from ghost-triggering due to local cache lag
        homeController.ignoreRide(localRideId);

        homeController.queuedRides.clear(); // Clear queue if any garbage exists
        Get.offAll(
          () => DriverHomePage(user: user, initialStatus: DriverStatus.online),
        );
      }

      // 3. Background Transactions
      // We use a separate async block or just continue here.
      // Since we already navigated, 'context' is unsafe, but Firebase calls are fine.

      // Credit Logic
      double amountToCredit = 0.0;
      String description = "";

      if (isOnline) {
        amountToCredit = localTotalAmount;
        description = "Earnings for Ride ID: $localRideId (Online)";
      } else if (isCashPlusWallet) {
        amountToCredit = walletAmt;
        description = "Wallet Portion for Ride ID: $localRideId";
      }

      if (amountToCredit > 0) {
        try {
          // A. Credit Driver Wallet
          await WalletController.instance.creditWallet(
            amountToCredit,
            "ride_$localRideId",
            description: description,
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
                    'baseFare': localRideFare,
                    'distance': localRideDistance,
                    'rideType': localRideType,
                    'waitingCharge': localWaitingCharge,
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

            await FirebaseFirestore.instance.runTransaction((
              transaction,
            ) async {
              final userRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(localCustomerId);

              final userSnapshot = await transaction.get(userRef);
              if (userSnapshot.exists) {
                var currentBalance =
                    (userSnapshot.data()?['wallet_balance'] as num?)
                        ?.toDouble();
                currentBalance ??=
                    (userSnapshot.data()?['walletBalance'] as num?)?.toDouble();
                currentBalance ??= 0.0;

                final newBalance = currentBalance - amountToDeduct;

                if (userSnapshot.data()!.containsKey('wallet_balance')) {
                  transaction.update(userRef, {'wallet_balance': newBalance});
                } else {
                  transaction.update(userRef, {'walletBalance': newBalance});
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
            });
            debugPrint(
              "Deducted $amountToDeduct from customer $localCustomerId wallet.",
            );
          }
        } catch (e) {
          debugPrint("Failed to process background wallet transactions: $e");
          // No valid context to show snackbar, just log.
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
                                    // Breakdown (Only if waiting charge exists)
                                    if (_rideRequest.waitingCharge > 0) ...[
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'estimatedBill'.tr,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          Text(
                                            '₹${(widget.totalAmount - _rideRequest.waitingCharge).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'waitingCharges'.tr,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          Text(
                                            '+ ₹${_rideRequest.waitingCharge.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ],
                                      ),
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
                                                      fontSize: 16,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                  Text(
                                                    '₹${_rideRequest.rideFare.toStringAsFixed(2)}',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              if (extraDistance > 0) ...[
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      '${'extraDistance'.tr} (${extraDistance.toStringAsFixed(1)} km)',
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    Text(
                                                      '+ ₹${extraDistanceCost.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.redAccent,
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
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                    Text(
                                                      '+ ₹${extraDurationCost.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.redAccent,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                              ],
                                              const Divider(height: 20),
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
                                                color: Colors.grey,
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
                                                color: Colors.grey,
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

                            // QR Code for Payment
                            if ((_isCashOnly || _isCashPlusWallet) &&
                                _cashToCollect > 0 &&
                                _driverUpiId != null &&
                                _driverUpiId!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 20.0),
                                child: Column(
                                  children: [
                                    Text(
                                      'scanToPay'.tr,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: QrImageView(
                                        data:
                                            'upi://pay?pa=$_driverUpiId&pn=$_driverName&am=$_cashToCollect&cu=INR',
                                        version: QrVersions.auto,
                                        size: 200.0,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${'upiId'.tr}: $_driverUpiId',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
