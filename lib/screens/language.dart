import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/screens/login.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageSelectionScreen extends StatefulWidget {
  final bool isFromProfile;

  const LanguageSelectionScreen({super.key, this.isFromProfile = false});

  @override
  State<LanguageSelectionScreen> createState() =>
      _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String _initialLanguageCode = 'en';
  String _selectedLanguageCode = 'en';

  final Map<String, String> _languages = {
    'en': 'English',
    'ta': 'தமிழ்',
    'hi': 'हिंदी',
    'te': 'తెలుగు',
    'kn': 'ಕನ್ನಡ',
    'ml': 'മലയാളം',
    'gu': 'ગુજરાતી',
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentLanguage();
  }

  Future<void> _loadCurrentLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      final lang = prefs.getString('selectedLanguage') ?? 'en';
      setState(() {
        _initialLanguageCode = lang;
        _selectedLanguageCode = lang;
      });
    }
  }

  Future<void> _saveLanguageAndContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', _selectedLanguageCode);

    // Immediately update locale
    Get.updateLocale(Locale(_selectedLanguageCode));

    if (mounted) {
      if (widget.isFromProfile) {
        // Pop with a result indicating if the language was changed.
        final hasChanged = _initialLanguageCode != _selectedLanguageCode;
        Get.back(result: hasChanged);
      } else {
        Get.off(() => const LoginScreen());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ProAppBar(
        titleText: 'Select Language',
        // If not from profile (onboarding flow), don't show back button unless specifically needed
        automaticallyImplyLeading: widget.isFromProfile,
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(24.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16.0,
                mainAxisSpacing: 16.0,
                childAspectRatio: 1.3,
              ),
              itemCount: _languages.length,
              itemBuilder: (context, index) {
                final entry = _languages.entries.elementAt(index);
                final isSelected = entry.key == _selectedLanguageCode;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedLanguageCode = entry.key;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? const Color(0xFF2C2C2C) : Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? Colors.white10 : Colors.grey[300]!),
                        width: isSelected ? 0 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white : Colors.grey[800]),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: ProButton(text: "Save", onPressed: _saveLanguageAndContinue),
          ),
        ],
      ),
    );
  }
}
