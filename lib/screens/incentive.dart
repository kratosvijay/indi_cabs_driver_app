import 'package:flutter/material.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IncentivesScreen extends StatefulWidget {
  const IncentivesScreen({super.key});

  @override
  State<IncentivesScreen> createState() => _IncentivesScreenState();
}

class _IncentivesScreenState extends State<IncentivesScreen> {
  late List<DateTime> _dates;
  late DateTime _selectedDate;
  String _selectedLanguageCode = 'en';
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  // --- Translations ---
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'title': 'Incentives',
      'noPlan': 'No incentive plan available for the selected date.',
    },
    'ta': {
      'title': 'ஊக்கத்தொகை',
      'noPlan': 'தேர்ந்தெடுக்கப்பட்ட தேதிக்கு ஊக்கத்தொகை திட்டம் இல்லை.',
    },
    'hi': {
      'title': 'प्रोत्साहन',
      'noPlan': 'चयनित तिथि के लिए कोई प्रोत्साहन योजना उपलब्ध नहीं है।',
    },
    'te': {
      'title': 'ప్రోత్సాహకాలు',
      'noPlan': 'ఎంచుకున్న తేదీకి ప్రోత్సాహక ప్రణాళిక అందుబాటులో లేదు.',
    },
    'kn': {
      'title': 'ಪ್ರೋತ್ಸಾಹಕಗಳು',
      'noPlan': 'ಆಯ್ದ ದಿನಾಂಕಕ್ಕಾಗಿ ಯಾವುದೇ ಪ್ರೋತ್ಸಾಹಕ ಯೋಜನೆ ಲಭ್ಯವಿಲ್ಲ.',
    },
    'ml': {
      'title': 'പ്രോത്സാഹനങ്ങൾ',
      'noPlan': 'തിരഞ്ഞെടുത്ത തീയതിക്ക് ഇൻസെന്റീവ് പ്ലാൻ ലഭ്യമല്ല.',
    },
    'gu': {
      'title': 'પ્રોત્સાહનો',
      'noPlan': 'પસંદ કરેલી તારીખ માટે કોઈ પ્રોત્સાહક યોજના ઉપલબ્ધ નથી.',
    },
  };

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _loadLanguage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelectedDate() {
    if (!_scrollController.hasClients) {
      return; // Guard against controller not being attached
    }

    final selectedIndex = _dates.indexOf(_selectedDate);
    if (selectedIndex != -1) {
      final double itemWidth = 68.0; // 60 width + 8 margin
      final screenWidth = MediaQuery.of(context).size.width;
      final offset =
          (selectedIndex * itemWidth) - (screenWidth / 2) + (itemWidth / 2);

      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _initializeDates() {
    _dates = [];
    final today = DateTime.now();
    _selectedDate = DateTime(
      today.year,
      today.month,
      today.day,
    ); // Normalize to midnight

    for (int i = -15; i <= 15; i++) {
      final date = today.add(Duration(days: i));
      _dates.add(DateTime(date.year, date.month, date.day));
    }
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLanguageCode = prefs.getString('selectedLanguage') ?? 'en';
        _isLoading = false;
      });
      // Corrected: Scroll only after the main UI is ready to be built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedDate();
      });
    }
  }

  String _getTranslatedString(String key) {
    return _translations[_selectedLanguageCode]?[key] ??
        _translations['en']![key]!;
  }

  String _getDayAbbreviation(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: ProAppBar(
        toolbarHeight: 100,
        titleText: _getTranslatedString('title'),
      ),
      body: Column(
        children: [
          Container(
            height: 80,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.grey[200],
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: _dates.length,
              itemBuilder: (context, index) {
                final date = _dates[index];
                final isSelected = date == _selectedDate;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    width: 60,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                                ? AppColors.primary.withValues(alpha: 0.3)
                                : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getDayAbbreviation(date.weekday),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white70 : Colors.black87),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white : Colors.black),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                _getTranslatedString('noPlan'),
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.grey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
