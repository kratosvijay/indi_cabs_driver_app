import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/screens/sign_up.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/screens/otp.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneAuthScreen extends StatefulWidget {
  final bool isRegistering;

  const PhoneAuthScreen({super.key, required this.isRegistering});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  String _selectedLanguageCode = 'en';

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'loginTitle': 'Login with Phone',
      'enterMobile': 'Enter Your Mobile Number',
      'mobileLabel': 'Mobile Number',
      'sendOtp': 'Send OTP',
      'enterOtp': 'Enter the OTP',
      'verifyOtp': 'Verify OTP',
      'resend': "Didn't receive code? Resend OTP",
      'notRegistered': 'This number is not registered. Please register first.',
      'failedOtp': 'Failed to verify OTP. Please try again.',
      'unexpectedError': 'An unexpected error occurred. Please try again.',
    },
    'ta': {
      'loginTitle': 'தொலைபேசி மூலம் உள்நுழையவும்',
      'enterMobile': 'உங்கள் மொபைல் எண்ணை உள்ளிடவும்',
      'mobileLabel': 'கைபேசி எண்',
      'sendOtp': 'OTP அனுப்பவும்',
      'enterOtp': 'OTP ஐ உள்ளிடவும்',
      'verifyOtp': 'OTP ஐ சரிபார்க்கவும்',
      'resend': 'குறியீடு வரவில்லையா? மீண்டும் OTP அனுப்பவும்',
      'notRegistered':
          'இந்த எண் பதிவு செய்யப்படவில்லை. முதலில் பதிவு செய்யவும்.',
      'failedOtp': 'OTP ஐ சரிபார்க்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
      'unexpectedError': 'எதிர்பாராத பிழை ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.',
    },
    'hi': {
      'loginTitle': 'फ़ोन से लॉगिन करें',
      'enterMobile': 'अपना मोबाइल नंबर दर्ज करें',
      'mobileLabel': 'मोबाइल नंबर',
      'sendOtp': 'ओटीपी भेजें',
      'enterOtp': 'ओटीपी दर्ज करें',
      'verifyOtp': 'ओटीपी सत्यापित करें',
      'resend': 'कोड नहीं मिला? ओटीपी फिर से भेजें',
      'notRegistered': 'यह नंबर पंजीकृत नहीं है। कृपया पहले पंजीकरण करें।',
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
      });
    }
  }

  String _getTranslatedString(String key) {
    return _translations[_selectedLanguageCode]?[key] ??
        _translations['en']![key]!;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _navigateToOtp() async {
    final String phoneNumber = "+91${_phoneController.text.trim()}";
    if (phoneNumber.length != 13) {
      Get.snackbar(
        'Error',
        "Please enter a valid 10-digit mobile number.",
        backgroundColor: Colors.red.withValues(alpha: 0.1),
        colorText: Colors.red,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String rawNumber = _phoneController.text.trim();

      // Preliminary check for registered user
      final driverCheck = await _firestore
          .collection('drivers')
          .where('phoneNumber', whereIn: [phoneNumber, rawNumber])
          .limit(1)
          .get();
      final operatorCheck = await _firestore
          .collection('fleet_operators')
          .where('phoneNumber', whereIn: [phoneNumber, rawNumber])
          .limit(1)
          .get();

      if (driverCheck.docs.isEmpty && operatorCheck.docs.isEmpty) {
        if (mounted) {
          Get.snackbar(
            'Error',
            _getTranslatedString('notRegistered'),
            backgroundColor: Colors.red.withValues(alpha: 0.1),
            colorText: Colors.red,
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      setState(() => _isLoading = false);
      
      // Instant Navigation to revamped OtpScreen
      Get.to(() => OtpScreen(
        phoneNumber: phoneNumber,
        role: UserRole.individual, // Default or derived role
        userData: const {}, // Login context
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Get.snackbar('Error', e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: ProAppBar(
        titleText: _getTranslatedString('loginTitle'),
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeInSlide(
                  delay: 0.2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _getTranslatedString('enterMobile'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 30),
                      ProTextField(
                        controller: _phoneController,
                        hintText: _getTranslatedString('mobileLabel'),
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 30),
                      ProButton(
                        text: _getTranslatedString('sendOtp'),
                        onPressed: _isLoading ? null : _navigateToOtp,
                        isLoading: _isLoading,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
