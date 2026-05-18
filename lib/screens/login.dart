// ignore_for_file: unused_field, prefer_final_fields

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/screens/phone_auth.dart';
import 'package:project_taxi_driver_app/screens/sign_up.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSigningIn = false;
  String _selectedLanguageCode = 'en';
  bool _isLoading = true;

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'welcome': 'Welcome Driver',
      'subtitle': 'Login or Register to get started',
      'login': 'Login',
      'register': 'Register',
    },
    'ta': {
      'welcome': 'ஓட்டுநரை வரவேற்கிறோம்',
      'subtitle': 'தொடங்குவதற்கு உள்நுழையவும் அல்லது பதிவு செய்யவும்',
      'login': 'உள்நுழைய',
      'register': 'பதிவு செய்ய',
    },
    'hi': {
      'welcome': 'ड्राइवर का स्वागत है',
      'subtitle': 'शुरू करने के लिए लॉगिन या रजिस्टर करें',
      'login': 'लॉगिन',
      'register': 'रजिस्टर',
    },
    'te': {
      'welcome': 'డ్రైవర్‌కు స్వాగతం',
      'subtitle': 'ప్రారంభించడానికి లాగిన్ చేయండి లేదా నమోదు చేసుకోండి',
      'login': 'లాగిన్',
      'register': 'నమోదు చేసుకోండి',
    },
    'kn': {
      'welcome': 'ಚಾಲಕರಿಗೆ ಸ್ವಾಗತ',
      'subtitle': 'ಪ್ರಾರಂಭಿಸಲು ಲಾಗಿನ್ ಮಾಡಿ ಅಥವಾ ನೋಂದಾಯಿಸಿ',
      'login': 'ಲಾಗಿನ್',
      'register': 'ನೋಂದಾಯಿಸಿ',
    },
    'ml': {
      'welcome': 'ഡ്രൈവർക്ക് സ്വാഗതം',
      'subtitle': 'ആരംഭിക്കുന്നതിന് ലോഗിн ചെയ്യുക അല്ലെങ്കിൽ രജിസ്റ്റർ ചെയ്യുക',
      'login': 'ലോഗിൻ',
      'register': 'രജിസ്റ്റർ ചെയ്യുക',
    },
    'gu': {
      'welcome': 'ડ્રાઇવરનું સ્વાગત છે',
      'subtitle': 'શરૂ કરવા માટે લોગિન કરો અથવા નોંધણી કરો',
      'login': 'લોગિન',
      'register': 'નોંધણી કરો',
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
        _isLoading = false;
      });
    }
  }

  String _getTranslatedString(String key) {
    return _translations[_selectedLanguageCode]?[key] ??
        _translations['en']![key]!;
  }

  void _navigateToAuth(bool isRegistering) {
    if (isRegistering) {
      // Navigate to SignUpScreen for registration
      Get.to(() => const SignUpScreen());
    } else {
      // Navigate to PhoneAuthScreen for login
      Get.to(() => const PhoneAuthScreen(isRegistering: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAppBarGradient(context),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 60),
                          // App Logo with Glow
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/logos/app_logo.png',
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Welcome Text
                          FadeInSlide(
                            delay: 0.1,
                            child: Column(
                              children: [
                                Text(
                                  _getTranslatedString('welcome'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _getTranslatedString('subtitle'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Action Buttons
                          FadeInSlide(
                            delay: 0.3,
                            child: Column(
                              children: [
                                ProButton(
                                  text: _getTranslatedString('login'),
                                  onPressed: () => _navigateToAuth(false),
                                ),
                                const SizedBox(height: 20),
                                ProButton(
                                  text: _getTranslatedString('register'),
                                  textColor: Colors.white,
                                  onPressed: () => _navigateToAuth(true),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
