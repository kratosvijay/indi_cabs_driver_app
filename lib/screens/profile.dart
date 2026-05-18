import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:project_taxi_driver_app/screens/document_verificaton.dart';
import 'package:project_taxi_driver_app/screens/qr_settings_screen.dart';
import 'package:project_taxi_driver_app/screens/language.dart';
import 'package:project_taxi_driver_app/screens/login.dart';
import 'package:project_taxi_driver_app/screens/reviews_screen.dart'; // **NEW IMPORT**
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/screens/driver_vehicle_selection_screen.dart';
import 'package:project_taxi_driver_app/services/id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  final User user;
  const ProfileScreen({super.key, required this.user});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _languageHasChanged = false;
  String _selectedLanguageCode = 'en';
  bool _isLoading = true;
  bool _isUploadingImage = false;
  String? _driverDocId;

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Profile',
      'performance': 'Performance',
      'yourPerformance': 'Your Performance',
      'rating': 'Rating',
      'acceptanceRate': 'Acceptance Rate',
      'cancellationRate': 'Cancellation Rate',
      'close': 'Close',
      'updateDocs': 'Update Documents',
      'appLanguage': 'App Language Setting',
      'deleteAccount': 'Delete Account',
      'deleteConfirmTitle': 'Delete Account',
      'deleteConfirmMsg':
          'Are you sure you want to delete your account? This action cannot be undone.',
      'no': 'No',
      'yes': 'Yes',
      'dutySettings': 'QR Settings',
      'myReviews': 'My Reviews', // **NEW**
    },
    'ta': {
      'title': 'சுயவிவரம்',
      'performance': 'செயல்திறன்',
      'yourPerformance': 'உங்கள் செயல்திறன்',
      'rating': 'மதிப்பீடு',
      'acceptanceRate': 'ஏற்றுக்கொள்ளும் விகிதம்',
      'cancellationRate': 'ரத்து விகிதம்',
      'close': 'மூடு',
      'updateDocs': 'ஆவணங்களைப் புதுப்பிக்கவும்',
      'appLanguage': 'பயன்பாட்டு மொழி அமைப்பு',
      'deleteAccount': 'கணக்கை நீக்கு',
      'deleteConfirmTitle': 'கணக்கை நீக்கு',
      'deleteConfirmMsg':
          'உங்கள் கணக்கை நிச்சயமாக நீக்க விரும்புகிறீர்களா? இந்தச் செயலைச் செயல்தவிர்க்க முடியாது.',
      'no': 'இல்லை',
      'yes': 'ஆம்',
      'dutySettings': 'QR அமைப்புகள்',
    },
    'hi': {
      'title': 'प्रोफ़ाइल',
      'performance': 'प्रदर्शन',
      'yourPerformance': 'आपका प्रदर्शन',
      'rating': 'रेटिंग',
      'acceptanceRate': 'स्वीकृति दर',
      'cancellationRate': 'रद्दीकरण दर',
      'close': 'बंद करें',
      'updateDocs': 'दस्तावेज़ अपडेट करें',
      'appLanguage': 'ऐप भाषा सेटिंग',
      'deleteAccount': 'खाता हटाएं',
      'deleteConfirmTitle': 'खाता हटाएं',
      'deleteConfirmMsg':
          'क्या आप वाकई अपना खाता हटाना चाहते हैं? यह क्रिया पूर्ववत नहीं की जा सकती।',
      'no': 'नहीं',
      'yes': 'हाँ',
      'dutySettings': 'QR सेटिंग्स',
    },
    'te': {
      'title': 'ప్రొఫైల్',
      'performance': 'పనితీరు',
      'yourPerformance': 'మీ పనితీరు',
      'rating': 'రేటింగ్',
      'acceptanceRate': 'అంగీకార రేటు',
      'cancellationRate': 'రద్దు రేటు',
      'close': 'మూసివేయండి',
      'updateDocs': 'పత్రాలను నవీకరించండి',
      'appLanguage': 'యాప్ భాషా సెట్టింగ్',
      'deleteAccount': 'ఖాతాను తొలగించండి',
      'deleteConfirmTitle': 'ఖాతాను తొలగించండి',
      'deleteConfirmMsg':
          'మీరు ఖచ్చితంగా మీ ఖాతాను తొలగించాలనుకుంటున్నారా? ఈ చర్యను అన్డు చేయలేరు.',
      'no': 'లేదు',
      'yes': 'అవును',
      'dutySettings': 'QR సెట్టింగ్‌లు',
    },
    'kn': {
      'title': 'ಪ್ರೊಫೈಲ್',
      'performance': 'ಕಾರ್ಯಕ್ಷಮತೆ',
      'yourPerformance': 'ನಿಮ್ಮ ಕಾರ್ಯಕ್ಷಮತೆ',
      'rating': 'ರೇಟಿಂಗ್',
      'acceptanceRate': 'ಸ್ವೀಕಾರ ದರ',
      'cancellationRate': 'ರದ್ದತಿ ದರ',
      'close': 'ಮುಚ್ಚಿ',
      'updateDocs': 'ದಾಖಲೆಗಳನ್ನು ನವೀಕರಿಸಿ',
      'appLanguage': 'ಅಪ್ಲಿಕೇಶನ್ ಭಾಷಾ ಸೆಟ್ಟಿಂಗ್',
      'deleteAccount': 'ಖಾತೆಯನ್ನು ಅಳಿಸಿ',
      'deleteConfirmTitle': 'ಖಾತೆಯನ್ನು ಅಳಿಸಿ',
      'deleteConfirmMsg':
          'ನಿಮ್ಮ ಖಾತೆಯನ್ನು ಅಳಿಸಲು ನೀವು ಖಚಿತವಾಗಿ ಬಯಸುವಿರಾ? ಈ ಕ್ರಿಯೆಯನ್ನು ಹಿಂತಿರುಗಿಸಲು ಸಾಧ್ಯವಿಲ್ಲ.',
      'no': 'ಇಲ್ಲ',
      'yes': 'ಹೌದು',
      'dutySettings': 'QR ಸೆಟ್ಟಿಂಗ್‌ಗಳು',
    },
    'ml': {
      'title': 'പ്രൊഫൈൽ',
      'performance': 'പ്രകടനം',
      'yourPerformance': 'നിങ്ങളുടെ പ്രകടനം',
      'rating': 'റേറ്റിംഗ്',
      'acceptanceRate': 'സ്വീകാര്യത നിരക്ക്',
      'cancellationRate': 'റദ്ദാക്കൽ നിരക്ക്',
      'close': 'അടയ്ക്കുക',
      'updateDocs': 'പ്രമാണങ്ങൾ അപ്ഡേറ്റ് ചെയ്യുക',
      'appLanguage': 'അപ്ലിക്കേഷൻ ഭാഷാ ക്രമീകരണം',
      'deleteAccount': 'അക്കൗണ്ട് ഇല്ലാതാക്കുക',
      'deleteConfirmTitle': 'അക്കൗണ്ട് ഇല്ലാതാക്കുക',
      'deleteConfirmMsg':
          'നിങ്ങളുടെ അക്കൗണ്ട് ഇല്ലാതാക്കാൻ നിങ്ങൾ തീർച്ചയായും ആഗ്രഹിക്കുന്നുണ്ടോ? ഈ പ്രവൃത്തി റദ്ദാക്കാനാവില്ല.',
      'no': 'ഇല്ല',
      'yes': 'അതെ',
      'dutySettings': 'QR ക്രമീകരണങ്ങൾ',
    },
    'gu': {
      'title': 'પ્રોફાઇલ',
      'performance': 'પ્રદર્શન',
      'yourPerformance': 'તમારું પ્રદર્શન',
      'rating': 'રેટિંગ',
      'acceptanceRate': 'સ્વીકૃતિ દર',
      'cancellationRate': 'રદ કરવાનો દર',
      'close': 'બંધ કરો',
      'updateDocs': 'દસ્તાવેજો અપડેટ કરો',
      'appLanguage': 'એપ્લિકેશન ભાષા સેટિંગ',
      'deleteAccount': 'એકાઉન્ટ કાઢી નાખો',
      'deleteConfirmTitle': 'એકાઉન્ટ કાઢી નાખો',
      'deleteConfirmMsg':
          'શું તમે ખરેખર તમારું એકાઉન્ટ કાઢી નાખવા માંગો છો? આ ક્રિયાને પૂર્વવત્ કરી શકાતી નથી.',
      'no': 'ના',
      'yes': 'હા',
      'dutySettings': 'QR સેટિંગ્સ',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final docId = await IdService.getDriverDocId(widget.user.uid);
    if (mounted) {
      setState(() {
        _selectedLanguageCode = prefs.getString('selectedLanguage') ?? 'en';
        _driverDocId = docId;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImageAndUpdate() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (pickedFile != null) {
      setState(() {
        _isUploadingImage = true;
      });
      await _uploadImageToFirebase(File(pickedFile.path));
      setState(() {
        _isUploadingImage = false;
      });
    }
  }

  Future<void> _uploadImageToFirebase(File imageFile) async {
    try {
      final String uid = widget.user.uid;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('driver_profile_pictures')
          .child('$uid.jpg');

      final uploadTask = storageRef.putFile(imageFile);
      final snapshot = await uploadTask.whenComplete(() => {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Update Firestore
      final docId = _driverDocId ?? uid;
      await FirebaseFirestore.instance.collection('drivers').doc(docId).update({
        'photoUrl': downloadUrl,
      });

      // Update Firebase Auth profile
      await widget.user.updateProfile(photoURL: downloadUrl);

      if (mounted) {
        Get.snackbar(
          'Success',
          'Profile picture updated successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to upload profile picture. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  String _getTranslatedString(String key) {
    return _translations[_selectedLanguageCode]?[key] ??
        _translations['en']![key]!;
  }

  void _showDeleteAccountDialog() {
    Get.dialog(
      AlertDialog(
        title: Text(_getTranslatedString('deleteConfirmTitle')),
        content: Text(_getTranslatedString('deleteConfirmMsg')),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(_getTranslatedString('no')),
          ),
          TextButton(
            onPressed: _deleteAccount,
            child: Text(
              _getTranslatedString('yes'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    try {
      // 1. Delete data from firestore
      final docId = _driverDocId ?? widget.user.uid;
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(docId)
          .delete();

      // 2. Delete user authentication
      await widget.user.delete();

      // 3. Optional: clear preferences and sign out if user.delete() didn't
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Get.offAll(() => const LoginScreen());
        Get.snackbar(
          'Success',
          "Account deleted successfully.",
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          "Error: ${e.message}. Please log in again to delete your account.",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          "An error occurred while deleting your account.",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Get.back(result: _languageHasChanged);
      },
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF121212)
            : const Color(0xFFF5F5F5),
        appBar: ProAppBar(titleText: _getTranslatedString('title')),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('drivers')
              .doc(_driverDocId ?? widget.user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData ||
                snapshot.data == null ||
                !snapshot.data!.exists) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!.data();
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final driverData = data as Map<String, dynamic>;

            // Robust Name Resolution: displayName -> name -> firstName+lastName -> "Driver"
            dynamic rawName = driverData['displayName'] ?? driverData['name'];
            String displayName = rawName?.toString() ?? '';

            if (displayName.isEmpty) {
              final firstName = driverData['firstName'] ?? '';
              final lastName = driverData['lastName'] ?? '';
              displayName = '$firstName $lastName'.trim();
            }

            if (displayName.isEmpty) {
              displayName = 'Driver';
            }

            final photoUrl = driverData['photoUrl'];

            // Real Performance Data
            final double rating =
                (driverData['rating'] as num?)?.toDouble() ?? 0.0;
            final double acceptanceRate =
                (driverData['acceptanceRate'] as num?)?.toDouble() ?? 0.0;
            final double cancellationRate =
                (driverData['cancellationRate'] as num?)?.toDouble() ?? 0.0;

            return ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 20,
              ),
              children: [
                // 1. Profile Header
                FadeInSlide(
                  delay: 0.4,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _isUploadingImage ? null : _pickImageAndUpdate,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? Colors.blueAccent
                                      : Colors.blue.shade600,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withValues(alpha: 0.2),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: photoUrl != null
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl == null
                                    ? Icon(
                                        Icons.person,
                                        size: 50,
                                        color: Colors.grey.shade400,
                                      )
                                    : null,
                              ),
                            ),
                            if (_isUploadingImage)
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.5),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF121212)
                                          : const Color(0xFFF5F5F5),
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.blue.withValues(alpha: 0.2)
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark
                                ? Colors.blueAccent.withValues(alpha: 0.5)
                                : Colors.blue.shade200,
                          ),
                        ),
                        child: Text(
                          "Verified Driver",
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.blueAccent
                                : Colors.blue.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // 2. Performance Stats Row (New Feature)
                FadeInSlide(
                  delay: 0.5,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatItem(
                          _getTranslatedString('rating'),
                          "$rating ★",
                          Colors.amber,
                          isDark,
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                        _buildStatItem(
                          "Acceptance", // Shortened for UI
                          "${acceptanceRate.toInt()}%",
                          Colors.green,
                          isDark,
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                        _buildStatItem(
                          "Cancel", // Shortened for UI
                          "${cancellationRate.toInt()}%",
                          Colors.redAccent,
                          isDark,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // 3. Menu Options
                _buildSectionHeader("Account", isDark),
                const SizedBox(height: 10),
                FadeInSlide(
                  delay: 0.6,
                  child: Column(
                    children: [
                      _buildProfileOption(
                        icon: Icons.document_scanner_rounded,
                        title: _getTranslatedString('updateDocs'),
                        subtitle: "Manage license & registration",
                        isDark: isDark,
                        onTap: () {
                          Get.to(
                            () => DocumentVerificationScreen(
                              user: widget.user,
                              driverDocId: _driverDocId,
                            ),
                          );
                        },
                      ),

                      // --- NEW: Change Vehicle (Fleet Only) ---
                      if ((driverData['role'] ?? '') == 'fleet_driver') ...[
                        _buildProfileOption(
                          icon: Icons.directions_car_filled_rounded,
                          title: "Change Vehicle",
                          subtitle: "Select a different fleet vehicle",
                          isDark: isDark,
                          onTap: () {
                            // Navigate to vehicle selection
                            Get.to(
                              () => DriverVehicleSelectionScreen(
                                user: widget.user,
                              ),
                            );
                          },
                        ),
                      ],

                      // ----------------------------------------
                      _buildProfileOption(
                        icon: Icons.qr_code_2_rounded,
                        title: _getTranslatedString('dutySettings'),
                        subtitle: "Manage UPI & QR codes",
                        isDark: isDark,
                        onTap: () {
                          Get.to(() => QrSettingsScreen(user: widget.user));
                        },
                      ),

                      // --- NEW: My Reviews ---
                      _buildProfileOption(
                        icon: Icons.star_rate_rounded,
                        title: _getTranslatedString('myReviews'),
                        subtitle: "View passenger ratings & comments",
                        isDark: isDark,
                        onTap: () {
                          Get.to(() => ReviewsScreen(user: widget.user));
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _buildSectionHeader("Preferences", isDark),
                const SizedBox(height: 10),
                FadeInSlide(
                  delay: 0.7,
                  child: Column(
                    children: [
                      _buildProfileOption(
                        icon: Icons.language,
                        title: _getTranslatedString('appLanguage'),
                        subtitle: "English, Tamil, Hindi...",
                        isDark: isDark,
                        onTap: () async {
                          final result = await Get.to<bool>(
                            () => const LanguageSelectionScreen(
                              isFromProfile: true,
                            ),
                          );
                          if (result == true) {
                            _languageHasChanged = true;
                            _loadInitialData(); // Updated name
                          }
                        },
                      ),
                      _buildProfileOption(
                        icon: Icons.delete_forever_rounded,
                        title: _getTranslatedString('deleteAccount'),
                        subtitle: "Permanently remove account",
                        isDark: isDark,
                        color: Colors.redAccent,
                        onTap: _showDeleteAccountDialog,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                Center(
                  child: Text(
                    "Version 1.2.1",
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required bool isDark,
    Color? color,
  }) {
    final iconColor = color ?? (isDark ? Colors.white : Colors.blueAccent);
    final textColor = color ?? (isDark ? Colors.white : Colors.black87);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
