import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:project_taxi_driver_app/screens/otp.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { individual, actingDriver, fleet }

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _managerNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Removed UPI Controller as requested

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  String _selectedLanguageCode = 'en';
  bool _isLanguageLoading = true;
  File? _imageFile;
  UserRole _selectedRole = UserRole.individual;

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Registration',
      'firstName': 'First Name',
      'lastName': 'Last Name',
      'email': 'Email ID',
      'mobile': 'Mobile Number',
      'next': 'Next',
      'individual': 'Individual Driver',
      'actingDriver': 'Acting Driver',
      'fleet': 'Fleet Operator',
      'companyName': 'Company Name',
      'managerName': 'Manager Name',
      'fillAllFields': 'Please fill in all fields.',
      'phoneRegistered': 'This phone number is already registered.',
      'registerAs': 'Register As',
      'camera': 'Camera',
      'gallery': 'Gallery',
      'choosePhoto': 'Choose Profile Photo',
    },
    'ta': {
      'title': 'பதிவு',
      'firstName': 'முதல் பெயர்',
      'lastName': 'கடைசி பெயர்',
      'email': 'மின்னஞ்சல் முகவரி',
      'mobile': 'கைபேசி எண்',
      'next': 'அடுத்து',
      'individual': 'தனி ஓட்டுநர்',
      'actingDriver': 'Acting Driver', // Common term
      'fleet': 'வாகனக் குழு உரிமையாளர்',
      'companyName': 'நிறுவனத்தின் பெயர்',
      'managerName': 'மேலாளர் பெயர்',
      'fillAllFields': 'அனைத்து விவரங்களையும் நிரப்பவும்.',
      'phoneRegistered': 'இந்த தொலைபேசி எண் ஏற்கனவே பதிவு செய்யப்பட்டுள்ளது.',
      'registerAs': 'பதிவு செய்யுங்கள்',
      'camera': 'கேமரா',
      'gallery': 'கேலரி',
      'choosePhoto': 'புகைப்படத்தைத் தேர்வுசெய்யவும்',
    },
    'hi': {
      'title': 'पंजीकरण',
      'firstName': 'पहला नाम',
      'lastName': 'अंतिम नाम',
      'email': 'ईमेल आईडी',
      'mobile': 'मोबाइल नंबर',
      'next': 'अगला',
      'individual': 'व्यक्तिगत ड्राइवर',
      'actingDriver': 'Acting Driver',
      'fleet': 'फ्लीट ऑपरेटर',
      'companyName': 'कंपनी का नाम',
      'managerName': 'प्रबंधक का नाम',
      'fillAllFields': 'कृपया सभी फ़ील्ड भरें।',
      'phoneRegistered': 'यह फ़ोन नंबर पहले से पंजीकृत है।',
      'registerAs': 'पंजीकरण करें',
      'camera': 'कैमरा',
      'gallery': 'गेलरी',
      'choosePhoto': 'फ़ोटो चुनें',
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
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyNameController.dispose();
    _managerNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? Colors.grey[900]! : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(Icons.photo_library, color: textColor),
                title: Text(
                  _getTranslatedString('gallery'),
                  style: TextStyle(color: textColor),
                ),
                onTap: () {
                  _getImage(ImageSource.gallery);
                  Get.back();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_camera, color: textColor),
                title: Text(
                  _getTranslatedString('camera'),
                  style: TextStyle(color: textColor),
                ),
                onTap: () {
                  _getImage(ImageSource.camera);
                  Get.back();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 50);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    final phoneNumber = "+91$phone";

    if (phone.isEmpty || _emailController.text.trim().isEmpty) {
      Get.snackbar(
        'Error',
        _getTranslatedString('fillAllFields'),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }
    if (phone.length != 10) {
      Get.snackbar(
        'Error',
        "Please enter a valid 10-digit mobile number.",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    Map<String, dynamic> userData = {};

    // Logic for Individual or Acting Driver is similar
    if (_selectedRole == UserRole.individual ||
        _selectedRole == UserRole.actingDriver) {
      if (_firstNameController.text.trim().isEmpty ||
          _lastNameController.text.trim().isEmpty) {
        Get.snackbar(
          'Error',
          _getTranslatedString('fillAllFields'),
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }
      userData = {
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phoneNumber': phoneNumber,
        'role': _selectedRole.name, // Store role explicitly if needed
        // 'upiId': Removed
      };
    } else {
      // Fleet Operator
      if (_companyNameController.text.trim().isEmpty ||
          _managerNameController.text.trim().isEmpty) {
        Get.snackbar(
          'Error',
          _getTranslatedString('fillAllFields'),
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }
      userData = {
        'companyName': _companyNameController.text.trim(),
        'managerName': _managerNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phoneNumber': phoneNumber,
        'role': _selectedRole.name,
      };
    }

    setState(() => _isLoading = true);

    try {
      final driverCheck = await _firestore
          .collection('drivers')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();
      final operatorCheck = await _firestore
          .collection('fleet_operators')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (driverCheck.docs.isNotEmpty || operatorCheck.docs.isNotEmpty) {
        if (mounted) {
          Get.snackbar(
            'Error',
            _getTranslatedString('phoneRegistered'),
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) {},
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            Get.snackbar(
              'Error',
              "Verification failed: ${e.message}",
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            Get.to(
              () => OtpScreen(
                verificationId: verificationId,
                userData: userData,
                role:
                    _selectedRole, // OtpScreen handles UserRole, need to check if it supports actingDriver
                imageFile: _imageFile,
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          "An error occurred: ${e.toString()}",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? Colors.grey[900]! : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black;

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
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeInSlide(
                        delay: 0.2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Role Dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: cardColor.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<UserRole>(
                                  value: _selectedRole,
                                  dropdownColor: cardColor,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                  ),
                                  icon: Icon(
                                    Icons.arrow_drop_down,
                                    color: textColor,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: UserRole.individual,
                                      child: Text(
                                        _getTranslatedString('individual'),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: UserRole.actingDriver,
                                      child: Text(
                                        _getTranslatedString('actingDriver'),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: UserRole.fleet,
                                      child: Text(
                                        _getTranslatedString('fleet'),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _selectedRole = value);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            if (_selectedRole == UserRole.individual ||
                                _selectedRole == UserRole.actingDriver)
                              ..._buildIndividualFields()
                            else
                              ..._buildFleetFields(),

                            ProTextField(
                              controller: _emailController,
                              hintText: _getTranslatedString('email'),
                              icon: Icons.email,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 20),
                            ProTextField(
                              controller: _phoneController,
                              hintText: _getTranslatedString('mobile'),
                              icon: Icons.phone,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ProButton(
                  text: _getTranslatedString('next'),
                  onPressed: _sendOtp,
                  isLoading: _isLoading,
                  // backgroundColor: Colors.white,
                  // textColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildIndividualFields() {
    return [
      Center(
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              backgroundImage: _imageFile != null
                  ? FileImage(_imageFile!)
                  : null,
              child: _imageFile == null
                  ? const Icon(Icons.person, size: 60, color: Colors.white60)
                  : null,
            ),
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.camera_alt,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      ProTextField(
        controller: _firstNameController,
        hintText: _getTranslatedString('firstName'),
        icon: Icons.person,
      ),
      const SizedBox(height: 20),
      ProTextField(
        controller: _lastNameController,
        hintText: _getTranslatedString('lastName'),
        icon: Icons.person,
      ),
      const SizedBox(height: 20),
    ];
  }

  List<Widget> _buildFleetFields() {
    return [
      ProTextField(
        controller: _companyNameController,
        hintText: _getTranslatedString('companyName'),
        icon: Icons.business,
      ),
      const SizedBox(height: 20),
      ProTextField(
        controller: _managerNameController,
        hintText: _getTranslatedString('managerName'),
        icon: Icons.person,
      ),
      const SizedBox(height: 20),
    ];
  }
}
