import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ProAppBar(titleText: "termsAndConditions".tr),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInSlide(
              child: Text(
                "Terms and Conditions",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 15),
            FadeInSlide(
              delay: 0.1,
              child: Text(
                "Welcome to Indi Cabs. By using our application, you agree to comply with and be bound by the following terms and conditions of use, which together with our privacy policy govern Indi Cabs' relationship with you in relation to this application.",
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildSection(
              isDark,
              "1. Acceptance of Terms",
              "By accessing or using the Indi Cabs Driver App, you agree to be bound by these Terms and Conditions and all applicable laws and regulations.",
            ),
            _buildSection(
              isDark,
              "2. Driver Responsibilities",
              "As a driver on our platform, you are responsible for maintaining a valid driver's license, vehicle insurance, and complying with all local traffic laws and regulations.",
            ),
            _buildSection(
              isDark,
              "3. Privacy Policy",
              "Your use of the app is also governed by our Privacy Policy, which is incorporated into these terms by reference.",
            ),
            _buildSection(
              isDark,
              "4. Termination",
              "We reserve the right to terminate or suspend your access to our application immediately, without prior notice or liability, for any reason whatsoever.",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(bool isDark, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: FadeInSlide(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
