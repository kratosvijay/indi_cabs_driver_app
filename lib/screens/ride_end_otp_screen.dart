import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;
import 'package:pinput/pinput.dart';
import 'package:project_taxi_driver_app/screens/ride_payment.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class RideEndOtpScreen extends StatefulWidget {
  final RideRequest rideRequest;
  final maps.LatLng? driverLocation;
  final double accumulatedDistance; // in meters

  const RideEndOtpScreen({
    super.key,
    required this.rideRequest,
    this.driverLocation,
    required this.accumulatedDistance,
  });

  @override
  State<RideEndOtpScreen> createState() => _RideEndOtpScreenState();
}

class _RideEndOtpScreenState extends State<RideEndOtpScreen> {
  String get collectionPath => 'rental_requests'; // Only for rentals

  final TextEditingController _otpController = TextEditingController();
  String? _serverOtp;
  bool _isLoading = false;
  String _errorMessage = '';
  String _customerName = "Customer";

  @override
  void initState() {
    super.initState();
    _fetchOtp();
    if (widget.rideRequest.userName != null) {
      _customerName = widget.rideRequest.userName!;
    }
  }

  void _fetchOtp() {
    FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(widget.rideRequest.rideId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && mounted) {
            final data = snapshot.data();
            if (data != null) {
              setState(() {
                _serverOtp = data['endRidePin']?.toString();
                debugPrint("End OTP Fetched: $_serverOtp");
              });
            }
          }
        });
  }

  Future<void> _verifyAndEndRide() async {
    final enteredOtp = _otpController.text.trim();

    if (_serverOtp == null) {
      setState(() {
        _errorMessage = "Verifying system OTP... please wait.";
      });
      return;
    }

    if (enteredOtp != _serverOtp) {
      setState(() {
        _errorMessage = "Incorrect OTP. Please ask the customer.";
      });
      return;
    }

    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    try {
      // Amount is calculated in backend now

      double actualDistanceKm = 0.0;
      if (widget.accumulatedDistance > 0) {
        actualDistanceKm = widget.accumulatedDistance / 1000.0;
      }

      // Call Cloud Function for RENTAL billing
      final pricingFuture = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('calculateDynamicPricing')
          .call({
            'rideId': widget.rideRequest.rideId,
            'actualDistanceKm': actualDistanceKm,
            'waitingCharge': 0.0, // Usually implicit in rental duration
            'rideType': 'rental',
          });

      final result = await pricingFuture;
      final resultData = result.data as Map<String, dynamic>;

      final totalFare = (resultData['finalFare'] ?? 0.0).toDouble();
      final actualDuration = (resultData['actualDurationMinutes'] ?? 0.0)
          .toDouble();

      // Local update for UI transition (Backend updates Firestore)
      RideRequest updatedRequest = widget.rideRequest.copyWith(
        rideFare: totalFare,
        status: 'completed',
        actualDistance: actualDistanceKm,
        actualDuration: actualDuration,
      );

      // Update Firestore with final status and data
      final Map<String, dynamic> updateData = {
        'status': 'completed',
        'rideFare': totalFare, // For rentals, this includes package price + extras
        'baseFare': totalFare,
        'actualDistance': actualDistanceKm,
        'actualDuration': actualDuration,
        'completedAt': FieldValue.serverTimestamp(),
      };

      if (widget.driverLocation != null) {
        updateData['destinationLocation'] = GeoPoint(
          widget.driverLocation!.latitude,
          widget.driverLocation!.longitude,
        );
      }

      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(widget.rideRequest.rideId)
          .update(updateData);

      debugPrint("Rental Ride ${widget.rideRequest.rideId} marked as COMPLETED in Firestore");

      if (mounted) {
        Get.off(
          () => RidePaymentScreen(
            rideRequest: updatedRequest,
            totalAmount: totalFare,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to end ride: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pinput styling matching Start OTP
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: TextStyle(
        fontSize: 24,
        color: isDark ? Colors.white : Colors.black,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(12),
        color: isDark ? Colors.grey[800] : Colors.grey[100],
      ),
    );
    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(
        color: Colors.red,
      ), // Red for Stop/End? Or Green? Let's stick to theme, maybe Red for End action.
      borderRadius: BorderRadius.circular(12),
    );
    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        color: isDark ? Colors.red.withAlpha(50) : Colors.red.shade50,
      ),
    );

    return Scaffold(
      appBar: ProAppBar(titleText: "End Ride"),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              "Ask $_customerName for End OTP",
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Enter the 4-digit PIN to complete the ride",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 40),

            Pinput(
              controller: _otpController,
              length: 4,
              defaultPinTheme: defaultPinTheme,
              focusedPinTheme: focusedPinTheme,
              submittedPinTheme: submittedPinTheme,
              showCursor: true,
              autofocus: true,
              onCompleted: (pin) => _verifyAndEndRide(),
              onChanged: (_) {
                if (_errorMessage.isNotEmpty) {
                  setState(() => _errorMessage = '');
                }
              },
            ),

            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                _errorMessage,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyAndEndRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent, // Red for End Ride
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Verify & End Ride",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
