import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:project_taxi_driver_app/screens/language.dart'; // Added LanguageSelectionScreen import

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      "icon": "drive_eta",
      "title": "Accept Rides, Start Earning",
      "description":
          "Receive ride requests from thousands of users in your area and start earning today.",
    },
    {
      "icon": "navigation",
      "title": "Navigate with Ease",
      "description":
          "Get clear, turn-by-turn directions to your rider's pickup and drop-off locations.",
    },
    {
      "icon": "account_balance_wallet",
      "title": "Track Your Earnings",
      "description":
          "Easily track your daily and weekly earnings, and get paid on time, every time.",
    },
  ];

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'drive_eta':
        return Icons.drive_eta;
      case 'navigation':
        return Icons.navigation;
      case 'account_balance_wallet':
        return Icons.account_balance_wallet;
      default:
        return Icons.help;
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', true);
    if (mounted) {
      Get.off(() => const LanguageSelectionScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip Button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    "Skip",
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[700],
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _onboardingData.length,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemBuilder: (context, index) {
                  return OnboardingPage(
                    icon: _getIconData(_onboardingData[index]["icon"]!),
                    title: _onboardingData[index]["title"]!,
                    description: _onboardingData[index]["description"]!,
                  );
                },
              ),
            ),

            // Indicators
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _onboardingData.length,
                  (index) => buildDot(index, context),
                ),
              ),
            ),

            // Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: ProButton(
                text: _currentPage == _onboardingData.length - 1
                    ? "Get Started"
                    : "Next",
                onPressed: () {
                  if (_currentPage == _onboardingData.length - 1) {
                    _completeOnboarding();
                  } else {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  AnimatedContainer buildDot(int index, BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: _currentPage == index ? 32 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index
            ? AppColors.primary
            : (isDark ? Colors.white24 : Colors.grey[300]),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const OnboardingPage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 80, color: AppColors.primary),
          ),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
