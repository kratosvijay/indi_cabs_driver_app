import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:project_taxi_driver_app/screens/email_support_screen.dart';
import 'package:project_taxi_driver_app/screens/chat_support_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (!await launchUrl(launchUri)) {
      Get.snackbar("Error", "Could not launch phone dialer");
    }
  }

  @override
  Widget build(BuildContext context) {
    // final isDark = Theme.of(context).brightness == Brightness.dark; // Unused

    return Scaffold(
      appBar: ProAppBar(titleText: "helpSupport".tr),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            _buildHelpCard(
              context,
              icon: Icons.email_outlined,
              title: "emailSupport".tr,
              subtitle: "emailSupportSubtitle".tr,
              color: Colors.blueAccent,
              onTap: () => Get.to(() => const EmailSupportScreen()),
            ),

            const SizedBox(height: 20),
            const SizedBox(height: 20),
            _buildHelpCard(
              context,
              icon: Icons.chat_bubble_outline,
              title: "chatSupport".tr,
              subtitle: "chatSupportSubtitle".tr,
              color: Colors.purpleAccent,
              onTap: () => Get.to(() => const ChatSupportScreen()),
            ),
            const SizedBox(height: 20),
            _buildHelpCard(
              context,
              icon: Icons.phone_outlined,
              title: "callSupport".tr,
              subtitle: "callSupportSubtitle".tr,
              color: Colors.orangeAccent,
              onTap: () => _makePhoneCall(
                "+919000000000",
              ), // Replace with actual support number
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeInSlide(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
