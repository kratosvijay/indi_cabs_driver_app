import 'dart:io';
import 'package:project_taxi_driver_app/utils/app_colors.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/screens/fleet_dashboard.dart';
import 'package:project_taxi_driver_app/screens/sign_up.dart';
import 'package:project_taxi_driver_app/screens/license_verification.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_taxi_driver_app/utils/upload_progress_dialog.dart';

class OtpScreen extends StatefulWidget {
  final String verificationId;
  final UserRole role;
  final Map<String, dynamic> userData;
  final File? imageFile;

  const OtpScreen({
    super.key,
    required this.verificationId,
    required this.role,
    required this.userData,
    this.imageFile,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  String _selectedLanguageCode = 'en';
  bool _isLanguageLoading = true;

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Verify OTP',
      'instruction': 'Enter the OTP sent to your mobile number',
      'verify': 'Verify',
      'invalidOtp': 'Please enter a valid 6-digit OTP.',
      'failedOtp': 'Failed to verify OTP. Please try again.',
      'unexpectedError': 'An unexpected error occurred. Please try again.',
    },
    'ta': {
      'title': 'OTP ஐ சரிபார்க்கவும்',
      'instruction': 'உங்கள் மொபைல் எண்ணுக்கு அனுப்பப்பட்ட OTP ஐ உள்ளிடவும்',
      'verify': 'சரிபார்க்கவும்',
      'invalidOtp': 'சரியான 6 இலக்க OTP ஐ உள்ளிடவும்.',
      'failedOtp': 'OTP ஐ சரிபார்க்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
      'unexpectedError': 'எதிர்பாராத பிழை ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.',
    },
    'hi': {
      'title': 'ओटीपी सत्यापित करें',
      'instruction': 'आपके मोबाइल नंबर पर भेजा गया ओटीपी दर्ज करें',
      'verify': 'सत्यापित करें',
      'invalidOtp': 'कृपया एक मान्य 6-अंकीय ओटीपी दर्ज करें।',
      'failedOtp': 'ओटीपी सत्यापित करने में विफल। कृपया पुन: प्रयास करें।',
      'unexpectedError': 'एक अप्रत्याशित त्रुटि हुई। कृपया पुन: प्रयास करें।',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguageCode = prefs.getString('selectedLanguage') ?? 'en';
        _isLanguageLoading = false;
      });
    }
  }

  String _getTranslatedString(String key) {
    return _translations[_selectedLanguageCode]?[key] ??
        _translations['en']![key]!;
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<String?> _uploadProfilePicture(String uid, File imageFile) async {
    try {
      if (!mounted) return null;
      final progressNotifier = ValueNotifier<double>(0.0);
      UploadProgressDialog.show(context, progressNotifier);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('driver_profile_pictures')
          .child('$uid.jpg');
      final uploadTask = storageRef.putFile(imageFile);
      
      uploadTask.snapshotEvents.listen((snapshot) {
        progressNotifier.value = snapshot.bytesTransferred / snapshot.totalBytes;
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      if (mounted) Navigator.pop(context); // Close dialog

      return downloadUrl;
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close dialog on error
        Get.snackbar(
          'Error',
          "Failed to upload profile picture.",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
      return null;
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().length != 6) {
      Get.snackbar(
        'Error',
        _getTranslatedString('invalidOtp'),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: _otpController.text.trim(),
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        if (widget.role == UserRole.individual ||
            widget.role == UserRole.actingDriver) {
          await _createIndividualDriver(user);
          if (mounted) {
            Get.offAll(
              () => LicenseVerificationScreen(user: user, role: widget.role),
            );
          }
        } else {
          await _createFleetOperator(user);
          if (mounted) {
            Get.offAll(() => FleetDashboardScreen(user: user));
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          e.code == 'invalid-verification-code'
              ? _getTranslatedString('failedOtp')
              : "An error occurred: ${e.message}",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          _getTranslatedString('unexpectedError'),
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createIndividualDriver(User user) async {
    String? photoUrl;
    if (widget.imageFile != null) {
      photoUrl = await _uploadProfilePicture(user.uid, widget.imageFile!);
    }
    await user.updateProfile(
      displayName:
          '${widget.userData['firstName']} ${widget.userData['lastName']}',
      photoURL: photoUrl,
    );

    await _firestore.collection('drivers').doc(user.uid).set({
      ...widget.userData,
      'uid': user.uid,
      'displayName':
          '${widget.userData['firstName']} ${widget.userData['lastName']}',
      'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'isOnline': false,
      'documentsSubmitted': false,
      'isApproved': false,
      'isBlocked': false,
    });
  }

  Future<void> _createFleetOperator(User user) async {
    await user.updateProfile(displayName: widget.userData['companyName']);
    await _firestore.collection('fleet_operators').doc(user.uid).set({
      ...widget.userData,
      'uid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLanguageLoading) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ProAppBar(
        titleText: _getTranslatedString('title'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Get.back(),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAppBarGradient(context),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: FadeInSlide(
              delay: 0.2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _getTranslatedString('instruction'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 30),
                  ProTextField(
                    controller: _otpController,
                    hintText: '------',
                    icon: Icons.lock_outline,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 30),
                  ProButton(
                    text: _getTranslatedString('verify'),
                    onPressed: _isLoading ? null : _verifyOtp,
                    isLoading: _isLoading,
                    // backgroundColor: Colors.white,
                    // textColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
