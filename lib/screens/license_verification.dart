import 'dart:io';
import 'package:project_taxi_driver_app/screens/sign_up.dart'; // For UserRole

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:project_taxi_driver_app/screens/aadhar_verification.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_taxi_driver_app/utils/upload_progress_dialog.dart';
import 'package:project_taxi_driver_app/screens/login.dart';

class LicenseVerificationScreen extends StatefulWidget {
  final User? user; // Made nullable for fleet use
  final UserRole role; // Reverted back to UserRole
  final String? targetUid;
  final String? driverDocId; // New parameter

  const LicenseVerificationScreen({
    super.key,
    this.user,
    required this.role,
    this.targetUid,
    this.driverDocId,
  });

  @override
  State<LicenseVerificationScreen> createState() =>
      _LicenseVerificationScreenState();
}

class _LicenseVerificationScreenState extends State<LicenseVerificationScreen> {
  final TextEditingController _licenseController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  File? _frontImage;
  File? _backImage;
  String _selectedLanguageCode = 'en';
  bool _isLanguageLoading = true;

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'License Verification',
      'instruction':
          'Please enter your driving license details and upload photos.',
      'licenseNumber': 'License Number',
      'frontPhoto': 'License Front Photo',
      'backPhoto': 'License Back Photo',
      'submit': 'Submit & Verify',
      'fillAllFields': 'Please fill in all fields and upload both photos.',
      'uploading': 'Uploading documents...',
      'success': 'Documents submitted successfully!',
      'camera': 'Camera',
      'gallery': 'Gallery',
      'invalidLicense': 'Please enter a valid license number.',
    },
    'ta': {
      'title': 'உரிமம் சரிபார்ப்பு',
      'instruction':
          'உங்கள் ஓட்டுநர் உரிம விவரங்களை உள்ளிட்டு புகைப்படங்களைப் பதிவேற்றவும்.',
      'licenseNumber': 'உரிமம் எண்',
      'frontPhoto': 'உரிமம் முன் பக்கம்',
      'backPhoto': 'உரிமம் பின் பக்கம்',
      'submit': 'சமர்ப்பிக்கவும்',
      'fillAllFields':
          'எல்லா விவரங்களையும் நிரப்பவும் மற்றும் புகைப்படங்களைப் பதிவேற்றவும்.',
      'uploading': 'ஆவணங்கள் பதிவேற்றப்படுகின்றன...',
      'success': 'ஆவணங்கள் வெற்றிகரமாக சமர்ப்பிக்கப்பட்டன!',
      'camera': 'கேமரா',
      'gallery': 'கேலரி',
      'invalidLicense': 'சரியான உரிம எண்ணை உள்ளிடவும்.',
    },
    'hi': {
      'title': 'लाइसेंस सत्यापन',
      'instruction':
          'कृपया अपना ड्राइविंग लाइसेंस विवरण दर्ज करें और फ़ोटो अपलोड करें।',
      'licenseNumber': 'लाइसेंस नंबर',
      'frontPhoto': 'लाइसेंस सामने की फोटो',
      'backPhoto': 'लाइसेंस पीछे की फोटो',
      'submit': 'जमा करें और सत्यापित करें',
      'fillAllFields': 'कृपया सभी फ़ील्ड भरें और दोनों फ़ोटो अपलोड करें।',
      'uploading': 'दस्तावेज़ अपलोड हो रहे हैं...',
      'success': 'दस्तावेज़ सफलतापूर्वक जमा हो गए!',
      'camera': 'कैमरा',
      'gallery': 'गेलरी',
      'invalidLicense': 'कृपया एक मान्य लाइसेंस नंबर दर्ज करें।',
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
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isFront) async {
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
                  _getImage(ImageSource.gallery, isFront);
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
                  _getImage(ImageSource.camera, isFront);
                  Get.back();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _getImage(ImageSource source, bool isFront) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        if (isFront) {
          _frontImage = File(pickedFile.path);
        } else {
          _backImage = File(pickedFile.path);
        }
      });
    }
  }

  bool _validateLicenseNumber(String license) {
    // Basic alphanumeric check, minimum length check
    // Enhance regex as per specific country requiremens if needed
    // Example: RJ14 20210040869 (Space optional, alphanumeric)
    if (license.length < 5) return false;
    final RegExp licenseRegex = RegExp(r'^[a-zA-Z0-9\s-]+$');
    return licenseRegex.hasMatch(license);
  }

  Future<void> _submitVerification() async {
    final licenseNo = _licenseController.text.trim();

    if (licenseNo.isEmpty || _frontImage == null || _backImage == null) {
      Get.snackbar(
        'Error',
        _getTranslatedString('fillAllFields'),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    if (!_validateLicenseNumber(licenseNo)) {
      Get.snackbar(
        'Error',
        _getTranslatedString('invalidLicense'),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      Get.snackbar(
        'Info',
        _getTranslatedString('uploading'),
        backgroundColor: Colors.blue,
        colorText: Colors.white,
      );

      final uid = widget.targetUid ?? widget.user!.uid;

      if (!mounted) return;
      final progressNotifier = ValueNotifier<double>(0.0);
      UploadProgressDialog.show(context, progressNotifier);

      Map<int, double> fileProgress = {};
      int totalFiles = 2;

      Future<String> uploadFile(File file, String path, int index) async {
        final ref = FirebaseStorage.instance.ref().child('driver_documents/$uid/$path');
        final uploadTask = ref.putFile(file);
        
        uploadTask.snapshotEvents.listen((snapshot) {
          double p = snapshot.bytesTransferred / snapshot.totalBytes;
          fileProgress[index] = p;
          double totalProgress = fileProgress.values.fold(0.0, (a, b) => a + b) / totalFiles;
          progressNotifier.value = totalProgress;
        });

        final snapshot = await uploadTask;
        return await snapshot.ref.getDownloadURL();
      }

      final urls = await Future.wait([
        uploadFile(_frontImage!, 'license_front.jpg', 0),
        uploadFile(_backImage!, 'license_back.jpg', 1),
      ]);

      if (mounted) Navigator.pop(context); // Close dialog

      final frontUrl = urls[0];
      final backUrl = urls[1];

      // Use driverDocId if provided, otherwise fallback to UID (for legacy/fleet)
      final docId = widget.driverDocId ?? uid;

      await _firestore.collection('drivers').doc(docId).update({
        'licenseNumber': licenseNo,
        'licenseFrontUrl': frontUrl,
        'licenseBackUrl': backUrl,
        'documentsSubmitted': true,
        // 'isApproved': false, // Already false by default, keeping it false until verification
      });

      Get.snackbar(
        'Success',
        _getTranslatedString('success'),
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );

      // Navigate to Aadhar Verification
      if (widget.targetUid != null) {
        // Fleet Mode: Push to stack
        Get.to(
          () => AadharVerificationScreen(
            user: widget.user,
            role: widget.role,
            targetUid: uid,
          ),
        );
      } else {
        // Driver Mode: Replace stack
        Get.offAll(
          () => AadharVerificationScreen(
            user: widget.user,
            role: widget.role,
            driverDocId: widget.driverDocId,
          ),
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        "Submission failed: ${e.toString()}",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildImagePicker(String label, File? image, VoidCallback onTap) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(image, fit: BoxFit.cover),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, size: 40, color: Colors.white),
                      SizedBox(height: 8),
                      Text(
                        "Tap to upload",
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
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
          onPressed: () {
            if (Navigator.canPop(context)) {
              Get.back();
            } else {
              Get.offAll(() => const LoginScreen());
            }
          },
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
                      Text(
                        _getTranslatedString('instruction'),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      ProTextField(
                        controller: _licenseController,
                        hintText: _getTranslatedString('licenseNumber'),
                        icon: Icons.badge,
                        // textCapitalization: TextCapitalization.characters, // Not supported by ProTextField yet
                      ),

                      const SizedBox(height: 30),

                      _buildImagePicker(
                        _getTranslatedString('frontPhoto'),
                        _frontImage,
                        () => _pickImage(true),
                      ),

                      const SizedBox(height: 20),

                      _buildImagePicker(
                        _getTranslatedString('backPhoto'),
                        _backImage,
                        () => _pickImage(false),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ProButton(
                  text: _getTranslatedString('submit'),
                  onPressed: _submitVerification,
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
}
