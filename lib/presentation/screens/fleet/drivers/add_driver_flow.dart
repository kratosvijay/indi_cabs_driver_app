import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/screens/license_verification.dart';
import 'package:project_taxi_driver_app/screens/sign_up.dart'; // For UserRole
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class FleetDriverOnboardingScreen extends StatefulWidget {
  const FleetDriverOnboardingScreen({super.key});

  @override
  State<FleetDriverOnboardingScreen> createState() =>
      _FleetDriverOnboardingScreenState();
}

class _FleetDriverOnboardingScreenState
    extends State<FleetDriverOnboardingScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController(); // Added Name field
  final _emailController = TextEditingController(); // Added Email field

  bool _isVerifying = false;
  // bool _isOtpSent = false; // Unused
  // String? _verificationId; // Unused in simulation

  // Steps: 0 = Info Input, 1 = OTP Verification
  int _step = 0;

  void _sendOtp() async {
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();

    if (phone.length < 10 || name.isEmpty) {
      Get.snackbar("Error", "Please enter a valid name and phone number");
      return;
    }

    setState(() => _isVerifying = true);

    try {
      // Create OTP Request in Firestore
      // "No need to generate random 6 digit otp instead generate a otp via firestore"
      // This implies a Backend/Cloud Function will listen to this 'pending' status
      // and update the document with the generated OTP.
      await FirebaseFirestore.instance
          .collection('otp_verifications')
          .doc(phone)
          .set({
            // 'otp': ..., // We DO NOT generate it here. Backend must do it.
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'attempts': 0,
          });

      Get.snackbar(
        "OTP Requested",
        "Request sent to server. Waiting for SMS...",
        duration: const Duration(seconds: 5),
      );

      setState(() {
        _isVerifying = false;
        _step = 1;
      });
    } catch (e) {
      Get.snackbar("Error", "Failed to request OTP: $e");
      setState(() => _isVerifying = false);
    }
  }

  void _verifyOtp() async {
    final enteredOtp = _otpController.text.trim();
    final phone = _phoneController.text.trim();

    if (enteredOtp.length != 6) {
      Get.snackbar("Error", "Please enter a 6-digit OTP");
      return;
    }

    setState(() => _isVerifying = true);

    try {
      // Use Cloud Function to Verify OTP & Create Driver safely
      final HttpsCallable callable = FirebaseFunctions.instanceFor(
        region: 'asia-south1',
      ).httpsCallable('verifyOtpAndCreateDriver');

      // We can pass a desired UID, or let server generate one.
      // For consistency with file paths later, let's generate one or let server return it.
      // But we need the UID for the next screen (License Upload) immediately.
      // So let's generate one client-side (or server-side and await result).
      // Server side is better.

      final result = await callable.call({
        'phone': phone,
        'otp': enteredOtp,
        'driverData': {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'role': 'fleet_driver',
          'vehicleType': 'Select Vehicle',
        },
      });

      final data = result.data as Map<Object?, Object?>;
      final success = data['success'] as bool? ?? false;

      if (success) {
        final newDriverUid = data['uid'] as String;
        Get.snackbar("Success", "Driver verified! Proceeding to documents.");

        // Navigate to License Verification
        Get.to(
          () => LicenseVerificationScreen(
            role: UserRole.fleet,
            targetUid: newDriverUid,
          ),
        );
      } else {
        throw Exception("Verification returned failure");
      }
    } catch (e) {
      debugPrint("Detailed Verification Error: $e");
      Get.snackbar("Error", "Verification failed: $e");
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: const ProAppBar(titleText: "Onboard New Driver"),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStepIndicator(),
              const SizedBox(height: 40),
              if (_step == 0) _buildInfoForm() else _buildOtpForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStepCircle(1, _step >= 0, "Details"),
        _buildStepLine(_step >= 1),
        _buildStepCircle(2, _step >= 1, "OTP"),
        _buildStepLine(false), // Next steps happen in next screens
        _buildStepCircle(3, false, "Docs"),
      ],
    );
  }

  Widget _buildStepCircle(int number, bool isActive, String label) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.blue : Colors.grey[800],
            border: Border.all(color: isActive ? Colors.blue : Colors.grey),
          ),
          child: Center(
            child: Text(
              "$number",
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.blue : Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        color: isActive ? Colors.blue : Colors.grey[800],
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      ),
    );
  }

  Widget _buildInfoForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProTextField(
          controller: _nameController,
          hintText: "Full Name",
          icon: Icons.person,
        ),
        const SizedBox(height: 20),
        ProTextField(
          controller: _phoneController,
          hintText: "Phone Number",
          icon: Icons.phone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 20),
        ProTextField(
          controller: _emailController,
          hintText: "Email (Optional)",
          icon: Icons.email,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 40),
        ProButton(
          text: "Send OTP",
          onPressed: _sendOtp,
          isLoading: _isVerifying,
        ),
      ],
    );
  }

  Widget _buildOtpForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Enter OTP sent to ${_phoneController.text}",
          style: const TextStyle(color: Colors.white70, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        ProTextField(
          controller: _otpController,
          hintText: "Enter 6-digit OTP",
          icon: Icons.lock_clock,
          keyboardType: TextInputType.number,
          // textAlign: TextAlign.center, // Not supported by ProTextField
        ),
        const SizedBox(height: 40),
        ProButton(
          text: "Verify & Proceed",
          onPressed: _verifyOtp,
          isLoading: _isVerifying,
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => setState(() => _step = 0),
          child: const Text("Edit Phone Number"),
        ),
      ],
    );
  }
}
