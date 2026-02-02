import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pinput/pinput.dart';
import 'package:project_taxi_driver_app/screens/ride_started.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class RideStartOtpScreen extends StatefulWidget {
  final RideRequest rideRequest;

  const RideStartOtpScreen({super.key, required this.rideRequest});

  @override
  State<RideStartOtpScreen> createState() => _RideStartOtpScreenState();
}

class _RideStartOtpScreenState extends State<RideStartOtpScreen> {
  String get collectionPath => widget.rideRequest.rideType == 'rental'
      ? 'rental_requests'
      : 'ride_requests';

  final TextEditingController _otpController = TextEditingController();
  String? _serverOtp;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchOtp();
    _fetchCustomerName();
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
                if (widget.rideRequest.rideType == 'rental') {
                  // Priority: startRidePin -> safetyPin -> otp
                  _serverOtp =
                      data['startRidePin']?.toString() ??
                      data['safetyPin']?.toString() ??
                      data['otp']?.toString();
                } else {
                  _serverOtp = data['safetyPin']?.toString();
                }
                debugPrint("Server OTP Fetched: $_serverOtp");
              });
            }
          }
        });
  }

  String _customerName = "Customer";
  Future<void> _fetchCustomerName() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.rideRequest.userId)
          .get();
      if (userDoc.exists && mounted) {
        final data = userDoc.data();
        setState(() {
          _customerName = data?['firstName'] ?? data?['userName'] ?? "Customer";
        });
      }
    } catch (e) {
      debugPrint("Error fetching name: $e");
    }
  }

  Future<void> _verifyAndStartRide() async {
    final enteredOtp = _otpController.text.trim();

    if (_serverOtp == null) {
      // Logic for if OTP isn't loaded yet (rare if coming from accepted screen)
      setState(() {
        _errorMessage = "Verifying system OTP... please wait.";
      });
      return;
    }

    if (enteredOtp != _serverOtp) {
      setState(() {
        _errorMessage = "Incorrect OTP. Please ask the customer.";
      });
      // Shake animation could go here
      return;
    }

    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    try {
      debugPrint("OTP Verified. Starting Ride...");
      final now = DateTime.now();
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(widget.rideRequest.rideId)
          .update({
            'status': 'started',
            'startedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        // Pass the updated rideRequest with startedAt set
        final updatedRequest = widget.rideRequest.copyWith(startedAt: now);
        Get.off(() => RideStartedScreen(rideRequest: updatedRequest));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to start ride: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pinput styling
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
      border: Border.all(color: Colors.green),
      borderRadius: BorderRadius.circular(12),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        color: isDark ? Colors.green.withAlpha(50) : Colors.green.shade50,
      ),
    );

    return Scaffold(
      appBar: ProAppBar(titleText: "Start Ride"),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Text(
              "Ask $_customerName for the OTP",
              style: TextStyle(
                fontSize: 18,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Enter the 4-digit PIN to start the ride",
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
              onCompleted: (pin) => _verifyAndStartRide(),
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
                onPressed: _isLoading ? null : () => _verifyAndStartRide(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Start Ride",
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
