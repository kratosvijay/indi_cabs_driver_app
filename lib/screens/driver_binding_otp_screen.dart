import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pinput/pinput.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/screens/homepage.dart';

class DriverBindingOtpScreen extends StatefulWidget {
  final String vehicleId;
  final User user;

  const DriverBindingOtpScreen({
    super.key,
    required this.vehicleId,
    required this.user,
  });

  @override
  State<DriverBindingOtpScreen> createState() => _DriverBindingOtpScreenState();
}

class _DriverBindingOtpScreenState extends State<DriverBindingOtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  int _secondsRemaining = 60;
  Timer? _timer;

  // Mock feature: User types any OTP to bind since we don't have real Operator backend sending SMS yet.
  // In production, this would use Firebase Phone Auth OR a specialized Cloud Function trigger.
  // For now, adhering to the "verifyOtp and bind" flow requested.

  @override
  void initState() {
    super.initState();
    _startTimer();
    // In a real scenario, we might trigger an OTP send here via Cloud Function to the Operator
    // For this specific flow (Driver changing vehicle), the requirement implies the Driver enters an OTP
    // provided by the Operator (offline/verbally) or sent to the Driver.
    // Assuming simulation of "OTP sent to Driver" for security.
    _simulateSendOtp();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _secondsRemaining = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
      }
    });
  }

  Future<void> _simulateSendOtp() async {
    // Simulating network delay for sending OTP
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      Get.snackbar(
        "OTP Sent",
        "An OTP has been sent to your registered mobile number.",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.length != 6) {
      Get.snackbar("Invalid OTP", "Please enter a 6-digit OTP");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Mock Verification: Accept any 6 digit code for now, or specific one
      // If we used real Firebase Auth, we'd use PhoneAuthProvider.credential...
      await Future.delayed(const Duration(seconds: 1)); // Mock delay

      await _bindVehicle(widget.vehicleId);
    } catch (e) {
      Get.snackbar("Error", "Invalid OTP or system error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _bindVehicle(String vehicleId) async {
    try {
      // 1. Aggressive Cleanup: Find ALL vehicles currently assigned to this driver
      // Done OUTSIDE transaction to avoid limitations on queries inside transactions
      final existingVehiclesSnapshot = await _firestore
          .collection('vehicles')
          .where('assignedDriverId', isEqualTo: widget.user.uid)
          .get();

      await _firestore.runTransaction((transaction) async {
        // 1. READ FIRST: Fetch New Vehicle Data
        final vehicleRef = _firestore.collection('vehicles').doc(vehicleId);
        final vehicleSnapshot = await transaction.get(vehicleRef);

        if (!vehicleSnapshot.exists) {
          throw Exception("Vehicle not found!");
        }

        final vehicleData = vehicleSnapshot.data();
        // newVehicleType removed as we use vClass below

        // 2. NOW WRITES: Unbind Old Vehicles
        for (final doc in existingVehiclesSnapshot.docs) {
          if (doc.id != vehicleId) {
            transaction.update(doc.reference, {
              'assignedDriverId': null,
              'status': 'Available',
            });
          }
        }

        // 3. Update New Vehicle
        transaction.update(vehicleRef, {
          'assignedDriverId': widget.user.uid,
          'status': 'On Duty',
        });

        // 4. Update Driver with FULL vehicle details
        // Mapping Fleet Vehicle schema to Individual Driver schema
        final String brand = vehicleData?['brand'] ?? '';
        final String model = vehicleData?['model'] ?? '';
        final String plate = vehicleData?['plateNumber'] ?? '';
        final String vClass = vehicleData?['class'] ?? 'Unknown';

        final driverRef = _firestore.collection('drivers').doc(widget.user.uid);
        transaction.update(driverRef, {
          'vehicleId': vehicleId,
          'vehicleType':
              vClass, // Map 'class' to 'vehicleType' for ride matching
          'vehicleClass': vClass,
          'vehicleBrand': brand,
          'vehicleModel': model,
          'carName': '$brand $model'.trim(), // "Toyota Etios"
          'vehicleNumber': plate,
          'vehicleDetailsFilled':
              true, // varied based on your schema, helpful flag
        });
      });

      Get.offAll(() => DriverHomePage(user: widget.user));
      Get.snackbar(
        "Success",
        "Vehicle changed successfully!",
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      debugPrint("BINDING ERROR: $e"); // Log for debugging
      throw Exception("Failed to bind vehicle: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: TextStyle(
        fontSize: 20,
        color: isDark ? Colors.white : Colors.black, // Adaptive text color
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey.shade900
            : Colors.white, // Adaptive input bg
        border: Border.all(
          color: isDark
              ? Colors.grey.shade700
              : Colors.grey.shade300, // Adaptive border
        ),
        borderRadius: BorderRadius.circular(12),
      ),
    );

    return Scaffold(
      appBar: const ProAppBar(titleText: "Verify Assignment"),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_open_rounded, size: 60, color: AppColors.primary),
              const SizedBox(height: 20),
              const Text(
                "Enter OTP",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: null, // Inherits from Theme (black/white)
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Please enter the OTP provided by your Fleet Operator to confirm this vehicle assignment.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),
              Pinput(
                length: 6,
                controller: _otpController,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: defaultPinTheme.copyDecorationWith(
                  border: Border.all(color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 32),
              ProButton(
                text: "Verify & Bind Vehicle",
                onPressed: _isLoading ? null : _verifyOtp,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _secondsRemaining > 0
                    ? null
                    : () {
                        _startTimer();
                        _simulateSendOtp();
                      },
                child: Text(
                  _secondsRemaining > 0
                      ? "Resend OTP in $_secondsRemaining s"
                      : "Resend OTP",
                  style: TextStyle(
                    color: _secondsRemaining > 0
                        ? Colors.grey
                        : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
