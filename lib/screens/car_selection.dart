import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:project_taxi_driver_app/screens/document_verificaton.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CarSelectionScreen extends StatefulWidget {
  final User user;
  final bool isFleet; // New parameter
  const CarSelectionScreen({
    super.key,
    required this.user,
    this.isFleet = false,
  });

  @override
  State<CarSelectionScreen> createState() => _CarSelectionScreenState();
}

class _CarSelectionScreenState extends State<CarSelectionScreen> {
  final TextEditingController _vehicleNumberController =
      TextEditingController();

  String _selectedVehicleType = 'Car';
  String? _selectedBrand;
  String? _selectedModel;

  bool _isLoading = false;
  String _selectedLanguageCode = 'en';

  File? _vehicleFront, _vehicleLeft, _vehicleRight, _vehicleBack;

  // Static Data for Vehicles
  final Map<String, Map<String, List<String>>> _vehicleData = {
    'Auto': {
      'Bajaj': ['RE Compact', 'Maxima', 'Maxima Z'],
      'Piaggio': ['Ape City', 'Ape Xtra', 'Ape DX'],
      'TVS': ['King', 'King Duramax'],
      'Mahindra': ['Alfa', 'Treo'],
      'Atul': ['Gem', 'Gem Paxx'],
    },
    'Car': {
      'Maruti Suzuki': [
        'Swift',
        'WagonR',
        'Dzire',
        'Baleno',
        'Ertiga',
        'Alto',
        'Celerio',
      ],
      'Hyundai': ['i10', 'i20', 'Aura', 'Xcent', 'Santro', 'Creta', 'Venue'],
      'Tata': ['Tiago', 'Tigor', 'Nexon', 'Altroz', 'Punch', 'Indigo'],
      'Mahindra': ['Bolero', 'XUV300', 'Verito'],
      'Honda': ['Amaze', 'City', 'Jazz'],
      'Toyota': ['Etios', 'Innova', 'Glanza'],
    },
  };

  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Vehicle Details',
      'vehicleType': 'Vehicle Type',
      'brand': 'Vehicle Brand',
      'model': 'Vehicle Model',
      'vehicleNumber': 'Vehicle Number (e.g., TN01AB1234)',
      'vehiclePictures': 'Vehicle Pictures (All Sides)',
      'next': 'Next',
      'fillAllFields': 'Please fill in all fields and upload pictures.',
      'vehicleRegistered': 'This vehicle number is already registered.',
      'upload': 'Upload',
      'front': 'Front Side',
      'back': 'Back Side',
      'left': 'Left Side',
      'right': 'Right Side',
      'cancel': 'Cancel',
      'save': 'Save',
      'select': 'Select',
    },
    'ta': {
      'title': 'வாகன விவரங்கள்',
      'vehicleType': 'வாகன வகை',
      'brand': 'வாகன பிராண்ட்',
      'model': 'வாகன மாடல்',
      'vehicleNumber': 'வாகன எண் (உதா: TN01AB1234)',
      'vehiclePictures': 'வாகன படங்கள் (அனைத்து பக்கங்களும்)',
      'next': 'அடுத்து',
      'fillAllFields': 'அனைத்து விவரங்களையும் நிரப்பவும்.',
      'vehicleRegistered': 'இவ்வாகன எண் ஏற்கனவே பதிவு செய்யப்பட்டுள்ளது.',
      'upload': 'பதிவேற்று',
      'front': 'முன்பக்கம்',
      'back': 'பின்பக்கம்',
      'left': 'இடது பக்கம்',
      'right': 'வலது பக்கம்',
      'cancel': 'ரத்துசெய்',
      'save': 'சேமி',
      'select': 'தேர்ந்தெடு',
    },
    'hi': {
      'title': 'वाहन विवरण',
      'vehicleType': 'वाहन का प्रकार',
      'brand': 'वाहन ब्रांड',
      'model': 'वाहन मॉडल',
      'vehicleNumber': 'वाहन संख्या (उदा. TN01AB1234)',
      'vehiclePictures': 'वाहन के चित्र (सभी तरफ)',
      'next': 'अगला',
      'fillAllFields': 'कृपया सभी फ़ील्ड भरें।',
      'vehicleRegistered': 'यह वाहन नंबर पहले से पंजीकृत है।',
      'upload': 'अपलोड करें',
      'front': 'सामने का हिस्सा',
      'back': 'पिछला हिस्सा',
      'left': 'बाईं ओर',
      'right': 'दाईं ओर',
      'cancel': 'रद्द करें',
      'save': 'सहेजें',
      'select': 'चुनें',
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
    _vehicleNumberController.dispose();
    super.dispose();
  }

  Future<File?> _pickImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('${_getTranslatedString('select')} Gallery'),
              onTap: () => Get.back(result: ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text('${_getTranslatedString('select')} Camera'),
              onTap: () => Get.back(result: ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 50);
    return pickedFile != null ? File(pickedFile.path) : null;
  }

  Future<void> _showCarPicturesDialog() async {
    File? tempFront = _vehicleFront;
    File? tempLeft = _vehicleLeft;
    File? tempRight = _vehicleRight;
    File? tempBack = _vehicleBack;

    final result = await showDialog<Map<String, File?>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                "${_getTranslatedString('upload')} ${_getTranslatedString('vehiclePictures')}",
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const SizedBox(height: 16),
                    _buildImagePickerBox(
                      _getTranslatedString('left'),
                      tempLeft,
                      () async {
                        final image = await _pickImage(context);
                        if (image != null) {
                          setDialogState(() => tempLeft = image);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildImagePickerBox(
                      _getTranslatedString('right'),
                      tempRight,
                      () async {
                        final image = await _pickImage(context);
                        if (image != null) {
                          setDialogState(() => tempRight = image);
                        }
                      },
                    ),
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
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: Text(_getTranslatedString('cancel')),
                ),
                ElevatedButton(
                  onPressed: () {
                    Get.back(
                      result: {
                        'front': tempFront,
                        'left': tempLeft,
                        'right': tempRight,
                        'back': tempBack,
                      },
                    );
                  },
                  child: Text(_getTranslatedString('save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _vehicleFront = result['front'];
        _vehicleLeft = result['left'];
        _vehicleRight = result['right'];
        _vehicleBack = result['back'];
      });
    }
  }

  Widget _buildImagePickerBox(
    String label,
    File? imageFile,
    VoidCallback onPick,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onPick,
          child: Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              image: imageFile != null
                  ? DecorationImage(
                      image: FileImage(imageFile),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageFile == null
                ? const Center(
                    child: Icon(
                      Icons.add_a_photo,
                      color: Colors.grey,
                      size: 40,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentUploadTile(
    String title,
    bool isUploaded,
    VoidCallback? onTap,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: ListTile(
        title: Text(title),
        trailing: isUploaded
            ? const Icon(Icons.check_circle, color: Colors.green)
            : Icon(Icons.upload_file, color: AppColors.primary),
        onTap: onTap,
      ),
    );
  }

  Future<void> _saveVehicleDetails() async {
    final vehicleNumber = _vehicleNumberController.text.trim().toUpperCase();

    if (_selectedBrand == null ||
        _selectedModel == null ||
        vehicleNumber.isEmpty ||
        _vehicleFront == null ||
        _vehicleLeft == null ||
        _vehicleRight == null ||
        _vehicleBack == null) {
      Get.snackbar(
        'Error',
        _getTranslatedString('fillAllFields'),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Duplicate Check
      // If Fleet, check 'vehicles' collection. If Driver, check 'drivers' (existing logic).
      // Actually, standard logic: Check if Plate is taken ANYWHERE?
      // For now, let's stick to checking 'drivers' for Driver flow and 'vehicles' for Fleet flow.
      // Ideally, a global 'vehicles' collection is better, but accommodating legacy.

      if (widget.isFleet) {
        final vehicleQuery = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('plateNumber', isEqualTo: vehicleNumber)
            .get();

        if (vehicleQuery.docs.isNotEmpty) {
          throw "Vehicle number already registered in fleet.";
        }
      } else {
        final vehicleQuery = await FirebaseFirestore.instance
            .collection('drivers')
            .where('vehicleNumber', isEqualTo: vehicleNumber)
            .get();
        final isTaken = vehicleQuery.docs.any(
          (doc) => doc.id != widget.user.uid,
        );
        if (isTaken) {
          throw _getTranslatedString('vehicleRegistered');
        }
      }

      // Upload Images
      // Path: isFleet ? 'fleet_documents/vehicles/$vehicleNumber/...' : 'driver_documents/$uid/...'
      // Using vehicleNumber or Random ID for fleet path.

      String storageBase = widget.isFleet
          ? 'fleet_documents/vehicles/${DateTime.now().millisecondsSinceEpoch}_$vehicleNumber'
          : 'driver_documents/${widget.user.uid}';

      Future<String> uploadFile(File file, String path) async {
        final ref = FirebaseStorage.instance.ref().child('$storageBase/$path');
        await ref.putFile(file);
        return await ref.getDownloadURL();
      }

      final urls = await Future.wait([
        uploadFile(_vehicleFront!, 'car_front.jpg'),
        uploadFile(_vehicleLeft!, 'car_left.jpg'),
        uploadFile(_vehicleRight!, 'car_right.jpg'),
        uploadFile(_vehicleBack!, 'car_back.jpg'),
      ]);

      String? newVehicleId;

      if (widget.isFleet) {
        // Save to 'vehicles' collection
        final docRef = FirebaseFirestore.instance
            .collection('vehicles')
            .doc(); // Auto ID
        newVehicleId = docRef.id;

        await docRef.set({
          'id': newVehicleId,
          'ownerId': widget.user.uid, // Fleet Owner
          'plateNumber': vehicleNumber,
          'brand': _selectedBrand,
          'model': _selectedModel,
          'type': _selectedVehicleType,
          'class': _selectedVehicleClass,
          'status': 'Pending Verification', // Fleet specific status
          'imageUrls': {
            'front': urls[0],
            'left': urls[1],
            'right': urls[2],
            'back': urls[3],
          },
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Driver Flow (Existing)
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(widget.user.uid)
            .set({
              'vehicleType':
                  (_selectedVehicleType == 'Car' &&
                      _selectedVehicleClass != null)
                  ? _selectedVehicleClass
                  : _selectedVehicleType,
              'vehicleNumber': vehicleNumber,
              'carName': "$_selectedBrand $_selectedModel",
              'vehicleBrand': _selectedBrand,
              'vehicleModel': _selectedModel,
              'vehicleClass': _selectedVehicleClass,
              'vehicleDetailsFilled': true,
              'documentsSubmitted': false,
              'isApproved': false,
              'rejectionReason': null,
              'documents': {
                'carFront': urls[0],
                'carLeft': urls[1],
                'carRight': urls[2],
                'carBack': urls[3],
              },
            }, SetOptions(merge: true));
      }

      if (mounted) {
        Get.to(
          () => DocumentVerificationScreen(
            user: widget.user,
            isFleet: widget.isFleet,
            vehicleId: newVehicleId, // Pass the new ID
          ),
        );
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

  InputDecoration _getDropdownDecoration(String label, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always, // Keeps label above
      labelStyle: TextStyle(
        color: isDark ? Colors.white70 : Colors.black87,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      filled: true,
      fillColor: isDark ? Colors.grey[850] : Colors.white,
    );
  }

  String? _selectedVehicleClass; // Hatchback, Sedan, SUV

  // Map to map Models to Classes
  final Map<String, String> _modelToClass = {
    // Maruti
    'Swift': 'Hatchback', 'WagonR': 'Hatchback', 'Dzire': 'Sedan',
    'Baleno': 'Hatchback',
    'Ertiga': 'SUV',
    'Alto': 'Hatchback',
    'Celerio': 'Hatchback',
    // Hyundai
    'i10': 'Hatchback', 'i20': 'Hatchback', 'Aura': 'Sedan',
    'Xcent': 'Sedan', 'Santro': 'Hatchback', 'Creta': 'SUV', 'Venue': 'SUV',
    // Tata
    'Tiago': 'Hatchback', 'Tigor': 'Sedan', 'Nexon': 'SUV',
    'Altroz': 'Hatchback', 'Punch': 'SUV', 'Indigo': 'Sedan',
    // Mahindra
    'Bolero': 'SUV', 'XUV300': 'SUV', 'Verito': 'Sedan',
    // Honda
    'Amaze': 'Sedan', 'City': 'Sedan', 'Jazz': 'Hatchback',
    // Toyota
    'Etios': 'Sedan', 'Innova': 'SUV', 'Glanza': 'Hatchback',
  };

  @override
  Widget build(BuildContext context) {
    // Get brands based on selected type
    final brands = _vehicleData[_selectedVehicleType]?.keys.toList() ?? [];

    // Get models based on selected brand
    List<String> models = [];
    if (_selectedBrand != null && _vehicleData[_selectedVehicleType] != null) {
      models = _vehicleData[_selectedVehicleType]![_selectedBrand] ?? [];
    }

    // Hot Reload Fix: Ensure selected value exists in items
    const validTypes = ['Car', 'Auto'];
    if (!validTypes.contains(_selectedVehicleType)) {
      _selectedVehicleType = 'Car';
    }

    return Scaffold(
      appBar: ProAppBar(titleText: _getTranslatedString('title')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Vehicle Type Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedVehicleType, // Must use value for updates
              decoration: _getDropdownDecoration(
                _getTranslatedString('vehicleType'),
                context,
              ),
              dropdownColor: Theme.of(context).cardColor,
              items: validTypes.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
              onChanged: (value) {
                if (value != null && value != _selectedVehicleType) {
                  setState(() {
                    _selectedVehicleType = value;
                    _selectedBrand = null;
                    _selectedModel = null;
                    _selectedVehicleClass = (value == 'Auto') ? 'Auto' : null;
                  });
                }
              },
            ),
            const SizedBox(height: 20),

            // Brand Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedBrand, // Must use value for updates
              decoration: _getDropdownDecoration(
                _getTranslatedString('brand'),
                context,
              ),
              dropdownColor: Theme.of(context).cardColor,
              hint: Text(
                "${_getTranslatedString('select')} ${_getTranslatedString('brand')}",
              ),
              items: brands.map((brand) {
                return DropdownMenuItem(value: brand, child: Text(brand));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedBrand = value;
                    _selectedModel = null;
                    // Only reset class if types is Car (since for Car, class depends on Model)
                    if (_selectedVehicleType == 'Car') {
                      _selectedVehicleClass = null;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 20),

            // Model Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedModel, // Must use value for updates
              decoration: _getDropdownDecoration(
                _getTranslatedString('model'),
                context,
              ),
              dropdownColor: Theme.of(context).cardColor,
              hint: Text(
                "${_getTranslatedString('select')} ${_getTranslatedString('model')}",
              ),
              items: models.map((model) {
                return DropdownMenuItem(value: model, child: Text(model));
              }).toList(),
              onChanged: _selectedBrand == null
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _selectedModel = value;
                          // Auto-select class based on model
                          if (_modelToClass.containsKey(value)) {
                            _selectedVehicleClass = _modelToClass[value];
                          }
                        });
                      }
                    },
            ),

            // Vehicle Class Dropdown (Only for Cars)
            if (_selectedVehicleType == 'Car') ...[
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue:
                    _selectedVehicleClass, // Must use value for auto-select to work
                decoration: _getDropdownDecoration("Vehicle Class", context),
                dropdownColor: Theme.of(context).cardColor,
                hint: const Text("Select Class"),
                items: ['Hatchback', 'Sedan', 'SUV']
                    .map(
                      (cls) => DropdownMenuItem(
                        value: cls,
                        child: Text(cls.toLowerCase().tr),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVehicleClass = value);
                  }
                },
              ),
            ],
            const SizedBox(height: 20),

            ProTextField(
              controller: _vehicleNumberController,
              hintText: _getTranslatedString('vehicleNumber'),
              icon: Icons.confirmation_number,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                UpperCaseTextFormatter(),
                LengthLimitingTextInputFormatter(10), // Optional: Limit length
              ],
            ),

            const SizedBox(height: 20),

            _buildDocumentUploadTile(
              _getTranslatedString('vehiclePictures'),
              _vehicleFront != null &&
                  _vehicleLeft != null &&
                  _vehicleRight != null &&
                  _vehicleBack != null,
              _showCarPicturesDialog,
            ),

            const SizedBox(height: 40),

            ProButton(
              text: _getTranslatedString('next'),
              onPressed: _isLoading ? null : _saveVehicleDetails,
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
