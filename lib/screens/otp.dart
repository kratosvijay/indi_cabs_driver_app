import 'dart:io';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:pinput/pinput.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/screens/fleet_dashboard.dart';
import 'package:project_taxi_driver_app/screens/sign_up.dart';
import 'package:project_taxi_driver_app/screens/license_verification.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/controllers/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_taxi_driver_app/utils/upload_progress_dialog.dart';
import 'package:project_taxi_driver_app/services/id_service.dart';

class OtpScreen extends StatefulWidget {
  final String? verificationId;
  final String? phoneNumber;
  final UserRole role;
  final Map<String, dynamic> userData;
  final File? imageFile;

  const OtpScreen({
    super.key,
    this.verificationId,
    this.phoneNumber,
    required this.role,
    required this.userData,
    this.imageFile,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with CodeAutoFill {
  final TextEditingController _otpController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = false;
  bool _isSendingOtp = false;
  String? _verificationId;
  int? _resendToken;
  
  String _selectedLanguageCode = 'en';
  bool _isLanguageLoading = true;

  // Timer logic
  int _secondsRemaining = 60;
  Timer? _timer;
  bool _canResend = false;

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
    _verificationId = widget.verificationId;
    if (_verificationId == null && widget.phoneNumber != null) {
      _sendOtp();
    }
    _startTimer();
    listenForCode();
  }

  @override
  void codeUpdated() {
    setState(() {
      _otpController.text = code ?? "";
    });
    if (code != null && code!.length == 6) {
      _verifyOtp();
    }
  }

  void _startTimer() {
    setState(() {
      _canResend = false;
      _secondsRemaining = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        setState(() {
          _canResend = true;
          timer.cancel();
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _sendOtp() async {
    if (widget.phoneNumber == null) return;

    setState(() {
      _isSendingOtp = true;
      _isLoading = false;
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber!,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          _otpController.text = credential.smsCode ?? "";
          await _verifyOtp(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            Get.snackbar(
              'Error',
              "Verification failed: ${e.message}",
              backgroundColor: Colors.red.withValues(alpha: 0.1),
              colorText: Colors.red,
            );
            setState(() {
              _isSendingOtp = false;
              _isLoading = false;
            });
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
              _isSendingOtp = false;
            });
            Get.snackbar(
              'Success',
              "OTP Sent Successfully",
              backgroundColor: Colors.green.withValues(alpha: 0.1),
              colorText: Colors.green,
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _isSendingOtp = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingOtp = false);
        Get.snackbar('Error', e.toString());
      }
    }
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
    _timer?.cancel();
    _otpController.dispose();
    unregisterListener();
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

  Future<void> _verifyOtp([PhoneAuthCredential? credential]) async {
    if (_otpController.text.trim().length != 6 && credential == null) {
      Get.snackbar(
        'Error',
        _getTranslatedString('invalidOtp'),
        backgroundColor: Colors.red.withValues(alpha: 0.1),
        colorText: Colors.red,
      );
      return;
    }

    if (_verificationId == null && credential == null) {
      Get.snackbar(
        'Wait',
        "Please wait for the service to initiate the verification code.",
        backgroundColor: Colors.orange.withValues(alpha: 0.1),
        colorText: Colors.orange,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authCredential = credential ??
          PhoneAuthProvider.credential(
            verificationId: _verificationId!,
            smsCode: _otpController.text.trim(),
          );

      final UserCredential userCredential = await _auth.signInWithCredential(
        authCredential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        // If userData is empty, it means we are in Login flow (from PhoneAuthScreen)
        if (widget.userData.isEmpty) {
          await AuthController.instance.decideRoute(externalUser: user);
          return;
        }

        // Registration flow
        if (widget.role == UserRole.individual ||
            widget.role == UserRole.actingDriver) {
          final String displayId = await _createIndividualDriver(user);
          if (mounted) {
            Get.offAll(
              () => LicenseVerificationScreen(
                user: user,
                role: widget.role,
                driverDocId: displayId,
              ),
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
          "${_getTranslatedString('unexpectedError')}: $e",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String> _createIndividualDriver(User user) async {
    String? photoUrl;
    if (widget.imageFile != null) {
      photoUrl = await _uploadProfilePicture(user.uid, widget.imageFile!);
    }

    final fullName = '${widget.userData['firstName']} ${widget.userData['lastName']}'.trim();

    await user.updateProfile(
      displayName: fullName,
      photoURL: photoUrl,
    );

    // Generate sequential Driver ID
    final nextId = await IdService.getNextDriverId();
    final displayId = 'indi-drv-$nextId';

    await _firestore.collection('drivers').doc(displayId).set({
      ...widget.userData,
      'uid': user.uid,
      'displayId': displayId,
      'name': fullName, // Standardized field for dashboards
      'displayName': fullName,
      'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'isOnline': false,
      'documentsSubmitted': false,
      'isApproved': false,
      'isBlocked': false,
    });

    // Initialize Wallet
    await _firestore
        .collection('drivers')
        .doc(displayId) // Use displayId instead of user.uid
        .collection('wallet')
        .doc('balance')
        .set({
      'currentBalance': 0.0,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    await _firestore
        .collection('drivers')
        .doc(displayId)
        .collection('wallet')
        .doc('metadata')
        .set({
      'lastSettlementDate': null,
    });

    // Persist the Document ID for use in other screens
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driverDocId', displayId);

    return displayId;
  }

  Future<void> _createFleetOperator(User user) async {
    final companyName = widget.userData['companyName'];
    await user.updateProfile(displayName: companyName);
    await _firestore.collection('fleet_operators').doc(user.uid).set({
      ...widget.userData,
      'uid': user.uid,
      'name': companyName, // Added for consistency
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

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.getAppBarGradient(context),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: ProAppBar(
          titleText: _getTranslatedString('title'),
          backgroundColor: Colors.transparent, // Ensure AppBar is also transparent
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Get.back(),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: FadeInSlide(
              delay: 0.2,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      _getTranslatedString('instruction'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.phoneNumber != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.phoneNumber!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    Pinput(
                      length: 6,
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      defaultPinTheme: PinTheme(
                        width: 50,
                        height: 55,
                        textStyle: const TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white54),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedPinTheme: PinTheme(
                        width: 55,
                        height: 60,
                        textStyle: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white),
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      onCompleted: (pin) => _verifyOtp(),
                    ),
                    const SizedBox(height: 40),
                    if (_isSendingOtp)
                      const Column(
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            "Sending OTP...",
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      )
                    else ...[
                      ProButton(
                        text: _getTranslatedString('verify'),
                        onPressed: (_isLoading || _isSendingOtp || _verificationId == null) ? null : _verifyOtp,
                        isLoading: _isLoading,
                        // backgroundColor: Colors.white,
                        // textColor: AppColors.primary,
                      ),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _canResend
                                ? "Didn't receive code?"
                                : "Resend in ${_secondsRemaining}s",
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (_canResend)
                            TextButton(
                              onPressed: () {
                                _startTimer();
                                _sendOtp();
                              },
                              child: const Text(
                                "Resend OTP",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
