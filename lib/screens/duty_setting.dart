import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/faq_sheet.dart';
import 'package:project_taxi_driver_app/utils/faq_data.dart';

class DutySettingsScreen extends StatefulWidget {
  final User user;
  const DutySettingsScreen({super.key, required this.user});

  @override
  State<DutySettingsScreen> createState() => _DutySettingsScreenState();
}

class _DutySettingsScreenState extends State<DutySettingsScreen> {
  String _selectedLanguageCode = 'en';
  bool _isLoading = true;

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Duty Settings',
      'description': 'Choose the types of rides you want to receive.',
    },
    'ta': {
      'title': 'பணி அமைப்புகள்',
      'description': 'நீங்கள் பெற விரும்பும் சவாரி வகைகளைத் தேர்ந்தெடுக்கவும்.',
    },
    'hi': {
      'title': 'ड्यूटी सेटिंग्स',
      'description':
          'आप जिस प्रकार की सवारी प्राप्त करना चाहते हैं, उसे चुनें।',
    },
    'te': {
      'title': 'డ్యూటీ సెట్టింగ్‌లు',
      'description': 'మీరు స్వీకరించాలనుకుంటున్న రైడ్‌ల రకాలను ఎంచుకోండి.',
    },
    'kn': {
      'title': 'ಕರ್ತವ್ಯ ಸೆಟ್ಟಿಂಗ್‌ಗಳು',
      'description': 'ನೀವು ಸ್ವೀಕರಿಸಲು ಬಯಸುವ ಸವಾರಿಗಳ ಪ್ರಕಾರಗಳನ್ನು ಆರಿಸಿ.',
    },
    'ml': {
      'title': 'ഡ്യൂട്ടി ക്രമീകരണങ്ങൾ',
      'description':
          'നിങ്ങൾക്ക് ലഭിക്കാൻ ആഗ്രഹിക്കുന്ന സവാരികളുടെ തരം തിരഞ്ഞെടുക്കുക.',
    },
    'gu': {
      'title': 'ડ્યુટી સેટિંગ્સ',
      'description': 'તમે જે પ્રકારની રાઇડ્સ મેળવવા માંગો છો તે પસંદ કરો.',
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

  Future<void> _updateDutyPreference(
    String category,
    String vehicleType,
    bool accepts,
  ) async {
    // FIX: Use dot notation to update specific key in map without overwriting others
    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(widget.user.uid)
        .update({'dutyPreferences.${category}_$vehicleType': accepts});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ProAppBar(
        toolbarHeight: 100,
        titleText: _getTranslatedString('title'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: () {
                Get.bottomSheet(
                  FAQSheet(title: "Duty Help", faqs: FAQData.dutyFAQs),
                );
              },
              icon: const Icon(Icons.help_outline, color: Colors.white),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('drivers')
            .doc(widget.user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final driverData = snapshot.data!.data() as Map<String, dynamic>;
          String registeredVehicle = driverData['vehicleType'] ?? 'Hatchback';
          final vehicleClass = driverData['vehicleClass'];

          // If type is generic 'Car', fallback to 'vehicleClass'
          if (registeredVehicle.toLowerCase() == 'car' &&
              vehicleClass != null) {
            registeredVehicle = vehicleClass;
          }

          final dutyPreferences =
              (driverData['dutyPreferences'] as Map<String, dynamic>?) ?? {};

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text(
                _getTranslatedString('description'),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionHeader(context, "dailyRides".tr),
              _buildVehicleList(
                context,
                "daily",
                registeredVehicle,
                dutyPreferences,
              ),

              const SizedBox(height: 32),

              _buildSectionHeader(context, "rentalRides".tr),
              _buildVehicleList(
                context,
                "rental",
                registeredVehicle,
                dutyPreferences,
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildVehicleList(
    BuildContext context,
    String category,
    String registeredVehicle,
    Map<String, dynamic> preferences,
  ) {
    final List<Widget> toggles = [];

    // Logic for Hierarchy
    // Logic for Hierarchy
    final type = registeredVehicle.trim().toLowerCase();
    debugPrint(
      "DEBUG: Registered Vehicle Type -> '$registeredVehicle' (Normalized: '$type')",
    );

    if (type == 'auto' || type == 'auto_rickshaw') {
      toggles.add(
        _buildVehicleToggle(category, 'auto'.tr, preferences, true, false),
      );
    } else if (type == 'hatchback') {
      toggles.add(
        _buildVehicleToggle(category, 'hatchback'.tr, preferences, true, false),
      );
    } else if (type == 'sedan') {
      toggles.add(
        _buildVehicleToggle(category, 'sedan'.tr, preferences, true, false),
      );
      toggles.add(
        _buildVehicleToggle(category, 'hatchback'.tr, preferences, false, true),
      );
    } else if (type == 'suv') {
      toggles.add(
        _buildVehicleToggle(category, 'suv'.tr, preferences, true, false),
      );
      toggles.add(
        _buildVehicleToggle(category, 'sedan'.tr, preferences, false, true),
      );
      toggles.add(
        _buildVehicleToggle(category, 'hatchback'.tr, preferences, false, true),
      );
    } else if (type == 'bike') {
      toggles.add(
        _buildVehicleToggle(category, 'bike'.tr, preferences, true, false),
      );
    } else {
      // Fallback for debugging
      toggles.add(Text("Unknown Vehicle Type: $registeredVehicle"));
    }

    return Column(children: toggles);
  }

  Widget _buildVehicleToggle(
    String category,
    String vehicleType,
    Map<String, dynamic> preferences,
    bool isOwnType,
    bool canToggle,
  ) {
    final key = '${category}_$vehicleType';
    // If it's own type, it's ALWAYS true (mandatory).
    // If it's lower tier, it defaults to true unless toggled off.
    bool isEnabled = isOwnType ? true : (preferences[key] ?? true);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SwitchListTile(
        title: Text(
          vehicleType,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        value: isEnabled,
        activeThumbColor: AppColors.primary,
        onChanged: canToggle
            ? (bool value) {
                // Optimistic update handled by StreamBuilder but visual delay requires local state
                // However, simpler to just write to DB since Stream is fast.
                _updateDutyPreference(category, vehicleType, value);
              }
            : null,
      ),
    );
  }
}
