import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:project_taxi_driver_app/presentation/screens/fleet/vehicles/fleet_vehicle_otp_screen.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_taxi_driver_app/utils/upload_progress_dialog.dart';
import 'package:project_taxi_driver_app/screens/sign_up.dart'; // For UserRole

// Enum to manage the verification status
enum VerificationStatus { initial, pending, rejected }

class DocumentVerificationScreen extends StatefulWidget {
  final User user;
  final bool isFleet;
  final String? vehicleId;
  final UserRole role;
  final String? driverDocId; // New parameter

  const DocumentVerificationScreen({
    super.key,
    required this.user,
    this.isFleet = false,
    this.vehicleId,
    this.role = UserRole.individual,
    this.driverDocId,
  });

  @override
  State<DocumentVerificationScreen> createState() =>
      _DocumentVerificationScreenState();
}

class _DocumentVerificationScreenState
    extends State<DocumentVerificationScreen> {
  bool _isLoading = false;
  VerificationStatus _status = VerificationStatus.initial;
  String _selectedLanguageCode = 'en';

  // State for holding the selected image files
  File? _rcFront, _rcBack;
  File? _permit, _insurance, _fitness;
  String? _rejectionReason;

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Document Verification',
      'rc': 'Car RC Book',
      'pan': 'PAN Card',
      'permit': 'Transport Permit',
      'insurance': 'Vehicle Insurance',
      'fitness': 'Fitness Certificate',
      'next': 'Submit Documents',
      'upload': 'Upload',
      'front': 'Front Side',
      'back': 'Back Side',
      'cancel': 'Cancel',
      'save': 'Save',
      'uploadAllDocs': 'Please upload all required documents to proceed.',
      'uploadError': 'An error occurred. Please try again.',
      'pendingTitle': 'Verification in Progress',
      'pendingMsg':
          'We are reviewing your documents. You will be notified once the process is complete.',
      'rejectedTitle': 'Action Required',
      'reason': 'Reason:',
      'rejectedMsg': '\nPlease re-upload the correct documents.',
      'reupload': 'Update Documents',
    },
    'ta': {
      'title': 'ஆவண சரிபார்ப்பு',
      'rc': 'கார் ஆர்.சி',
      'pan': 'பான் கார்டு',
      'permit': 'அனுமதி',
      'insurance': 'கார் காப்பீடு',
      'fitness': 'உடற்தகுதி சான்றிதழ்',
      'next': 'சமர்ப்பிக்கவும்',
      'upload': 'பதிவேற்று',
      'front': 'முன்பக்கம்',
      'back': 'பின்பக்கம்',
      'cancel': 'ரத்துசெய்',
      'save': 'சேமி',
      'uploadAllDocs': 'அனைத்து ஆவணங்களையும் பதிவேற்றவும்.',
      'uploadError': 'பிழை ஏற்பட்டது.',
      'pendingTitle': 'சரிபார்ப்பு செயல்பாட்டில் உள்ளது',
      'pendingMsg': 'உங்கள் ஆவணங்கள் மதிப்பாய்வு செய்யப்படுகின்றன.',
      'rejectedTitle': 'ஆவணங்கள் நிராகரிக்கப்பட்டன',
      'reason': 'காரணம்:',
      'rejectedMsg': '\nசரியான ஆவணங்களை மீண்டும் பதிவேற்றவும்.',
      'reupload': 'மீண்டும் பதிவேற்றவும்',
    },
    'hi': {
      'title': 'दस्तावेज़ सत्यापन',
      'rc': 'कार आरसी',
      'pan': 'पैन कार्ड',
      'permit': 'परमिट',
      'insurance': 'कार बीमा',
      'fitness': 'फिटनेस प्रमाणपत्र',
      'next': 'जमा करें',
      'upload': 'अपलोड करें',
      'front': 'सामने',
      'back': 'पीछे',
      'cancel': 'रद्द करें',
      'save': 'सहेजें',
      'uploadAllDocs': 'कृपया सभी दस्तावेज़ अपलोड करें।',
      'uploadError': 'त्रुटि हुई।',
      'pendingTitle': 'सत्यापन जारी है',
      'pendingMsg': 'हम आपके दस्तावेजों की समीक्षा कर रहे हैं।',
      'rejectedTitle': 'अस्वीकृत',
      'reason': 'कारण:',
      'rejectedMsg': '\nकृपया सही दस्तावेज़ अपलोड करें।',
      'reupload': 'पुनः अपलोड करें',
    },
  };

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _checkDriverStatus();
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

  Future<void> _checkDriverStatus() async {
    final driverDoc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.driverDocId ?? widget.user.uid)
        .get();
    if (driverDoc.exists && mounted) {
      final data = driverDoc.data()!;
      if (data.containsKey('rejectionReason') &&
          data['rejectionReason'] != null) {
        setState(() {
          _status = VerificationStatus.rejected;
          _rejectionReason = data['rejectionReason'];
        });
      } else if (data.containsKey('documentsSubmitted') &&
          data['documentsSubmitted'] == true &&
          data['isApproved'] == false) {
        setState(() {
          _status = VerificationStatus.pending;
        });
      }
    }
  }

  Future<File?> _pickImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.photo_library, color: AppColors.primary),
                  ),
                  title: const Text(
                    'Choose from Gallery',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Get.back(result: ImageSource.gallery),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.photo_camera, color: AppColors.primary),
                  ),
                  title: const Text(
                    'Take a Photo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Get.back(result: ImageSource.camera),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
    if (source == null) return null;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 50);
    return pickedFile != null ? File(pickedFile.path) : null;
  }

  Future<void> _showUploadDialog(
    String title,
    Function(File? front, File? back) onSave, {
    bool isSingleImage = false,
  }) async {
    File? tempFront;
    File? tempBack;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_getTranslatedString('upload')} $title',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _buildImagePickerBox(
                      _getTranslatedString('front'),
                      tempFront,
                      () async {
                        final image = await _pickImage(context);
                        if (image != null) {
                          setDialogState(() => tempFront = image);
                        }
                      },
                    ),
                    if (!isSingleImage) ...[
                      const SizedBox(height: 16),
                      _buildImagePickerBox(
                        _getTranslatedString('back'),
                        tempBack,
                        () async {
                          final image = await _pickImage(context);
                          if (image != null) {
                            setDialogState(() => tempBack = image);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Get.back(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              _getTranslatedString('cancel'),
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              onSave(tempFront, tempBack);
                              Get.back();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _getTranslatedString('save'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildImagePickerBox(
    String label,
    File? imageFile,
    VoidCallback onPick,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onPick,
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(
                  alpha: imageFile != null ? 0.5 : 0.2,
                ),
                width: 1,
              ),
              image: imageFile != null
                  ? DecorationImage(
                      image: FileImage(imageFile),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageFile == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        color: AppColors.primary,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Tap to upload",
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.black26,
                    ),
                    child: const Center(
                      child: Icon(Icons.edit, color: Colors.white),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitDocuments() async {
    if (_rcFront == null ||
        _rcBack == null ||
        _permit == null ||
        _insurance == null ||
        _fitness == null) {
      Get.snackbar(
        'Required',
        _getTranslatedString('uploadAllDocs'),
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        borderRadius: 12,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    setState(() => _isLoading = true);
    final uid = widget.user.uid;

    try {
      // Define Storage Path
      String storageBase;
      if (widget.isFleet && widget.vehicleId != null) {
        storageBase = 'fleet_documents/vehicles/${widget.vehicleId}';
      } else {
        storageBase = 'driver_documents/$uid';
      }

      if (!mounted) return;
      final progressNotifier = ValueNotifier<double>(0.0);
      UploadProgressDialog.show(context, progressNotifier);

      Map<int, double> fileProgress = {};
      int totalFiles = 5;

      Future<String> uploadFile(File file, String name, int index) async {
        final ref = FirebaseStorage.instance.ref().child('$storageBase/$name');
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
        uploadFile(_rcFront!, 'rc_front.jpg', 0),
        uploadFile(_rcBack!, 'rc_back.jpg', 1),
        uploadFile(_permit!, 'permit.jpg', 2),
        uploadFile(_insurance!, 'insurance.jpg', 3),
        uploadFile(_fitness!, 'fitness.jpg', 4),
      ]);
      
      if (mounted) Navigator.pop(context); // Close dialog

      if (widget.isFleet && widget.vehicleId != null) {
        // Fleet Update
        await FirebaseFirestore.instance
            .collection('vehicles')
            .doc(widget.vehicleId)
            .set({
              'documents': {
                'rcFront': urls[0],
                'rcBack': urls[1],
                'permit': urls[2],
                'insurance': urls[3],
                'fitness': urls[4],
              },
              'status': 'Pending Verification',
              'documentsSubmitted': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

        if (mounted) {
          Get.to(
            () => FleetVehicleOtpScreen(
              vehicleId: widget.vehicleId!,
              user: widget.user,
            ),
          );
        }
      } else {
        // Driver Update (Existing)
        final docId = widget.driverDocId ?? uid;

        await FirebaseFirestore.instance.collection('drivers').doc(docId).set({
          'documents': {
            'rcFront': urls[0],
            'rcBack': urls[1],
            'permit': urls[2],
            'insurance': urls[3],
            'fitness': urls[4],
          },
          'documentsSubmitted': true,
          'isApproved': false,
          'rejectionReason': null,
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() {
            _status = VerificationStatus.pending;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          e.toString(),
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showExitDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Exit App',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to exit the app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'No',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Yes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (shouldExit == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == VerificationStatus.pending) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) await _showExitDialog();
        },
        child: _buildStatusScreen(
          icon: Icons.hourglass_top,
          title: _getTranslatedString('pendingTitle'),
          message: _getTranslatedString('pendingMsg'),
        ),
      );
    }
    if (_status == VerificationStatus.rejected) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) await _showExitDialog();
        },
        child: _buildStatusScreen(
          icon: Icons.error_outline,
          title: _getTranslatedString('rejectedTitle'),
          message:
              "${_getTranslatedString('reason')} $_rejectionReason${_getTranslatedString('rejectedMsg')}",
          isRejected: true,
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _showExitDialog();
      },
      child: Scaffold(
        appBar: ProAppBar(
          titleText: _getTranslatedString('title'),
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _showExitDialog,
          ),
        ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildProUploadCard(
              title: _getTranslatedString('rc'),
              icon: Icons.directions_car,
              isUploaded: _rcFront != null && _rcBack != null,
              onTap: () => _showUploadDialog(
                _getTranslatedString('rc'),
                (front, back) => setState(() {
                  _rcFront = front;
                  _rcBack = back;
                }),
              ),
            ),

            // Aadhar Card Removed
            _buildProUploadCard(
              title: _getTranslatedString('permit'),
              icon: Icons.assignment_turned_in,
              isUploaded: _permit != null,
              onTap: () => _showUploadDialog(
                _getTranslatedString('permit'),
                (front, back) => setState(() {
                  _permit = front;
                }),
                isSingleImage: true,
              ),
            ),
            _buildProUploadCard(
              title: _getTranslatedString('insurance'),
              icon: Icons.security,
              isUploaded: _insurance != null,
              onTap: () => _showUploadDialog(
                _getTranslatedString('insurance'),
                (front, back) => setState(() {
                  _insurance = front;
                }),
                isSingleImage: true,
              ),
            ),
            _buildProUploadCard(
              title: _getTranslatedString('fitness'),
              icon: Icons.health_and_safety,
              isUploaded: _fitness != null,
              onTap: () => _showUploadDialog(
                _getTranslatedString('fitness'),
                (front, back) => setState(() {
                  _fitness = front;
                }),
                isSingleImage: true,
              ),
            ),
          ],
        ),
      ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          child: ProButton(
            text: _getTranslatedString('next'),
            onPressed: _isLoading ? null : _submitDocuments,
            isLoading: _isLoading,
          ),
        ),
      ),
    );
  }

  Widget _buildProUploadCard({
    required String title,
    required IconData icon,
    required bool isUploaded,
    required VoidCallback onTap,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isUploaded
              ? Colors.green.withValues(alpha: 0.5)
              : (isDark ? Colors.white10 : Colors.grey.shade100),
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUploaded
                        ? Colors.green.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isUploaded ? Icons.check : icon,
                    color: isUploaded ? Colors.green : AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isUploaded ? "Completed" : "Tap to upload",
                        style: TextStyle(
                          fontSize: 12,
                          color: isUploaded ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark ? Colors.white30 : Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusScreen({
    required IconData icon,
    required String title,
    required String message,
    bool isRejected = false,
  }) {
    return Scaffold(
      appBar: ProAppBar(
        titleText: _getTranslatedString('title'),
        automaticallyImplyLeading: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _showExitDialog,
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: (isRejected ? Colors.red : AppColors.primary)
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 64,
                    color: isRejected ? Colors.red : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ),
                if (isRejected) ...[
                  const SizedBox(height: 48),
                  ProButton(
                    text: _getTranslatedString('reupload'),
                    onPressed: () => setState(() {
                      _status = VerificationStatus.initial;
                      _rejectionReason = null;
                    }),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
