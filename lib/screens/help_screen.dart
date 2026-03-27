import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:project_taxi_driver_app/screens/email_support_screen.dart';
import 'package:project_taxi_driver_app/screens/chat_support_screen.dart';
import 'package:project_taxi_driver_app/screens/contact_us_screen.dart';
import 'package:project_taxi_driver_app/screens/terms_and_conditions_screen.dart';
import 'package:project_taxi_driver_app/screens/refunds_and_cancellations_screen.dart';

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
    return Scaffold(
      appBar: ProAppBar(titleText: "helpSupport".tr),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          const SizedBox(height: 10),

          // Support Section
          _buildSectionHeader(context, "support".tr),
          const SizedBox(height: 15),
          _buildHelpCard(
            context,
            icon: Icons.email_outlined,
            title: "emailSupport".tr,
            subtitle: "emailSupportSubtitle".tr,
            color: Colors.blueAccent,
            onTap: () => Get.to(() => const EmailSupportScreen()),
          ),
          const SizedBox(height: 15),
          _buildHelpCard(
            context,
            icon: Icons.chat_bubble_outline,
            title: "chatSupport".tr,
            subtitle: "chatSupportSubtitle".tr,
            color: Colors.purpleAccent,
            onTap: () => Get.to(() => const ChatSupportScreen()),
          ),
          const SizedBox(height: 15),
          _buildHelpCard(
            context,
            icon: Icons.phone_outlined,
            title: "callSupport".tr,
            subtitle: "callSupportSubtitle".tr,
            color: Colors.orangeAccent,
            onTap: () => _makePhoneCall("+919000000000"),
          ),

          const SizedBox(height: 30),

          // Policies Section
          _buildSectionHeader(context, "policies".tr),
          const SizedBox(height: 15),
          _buildPolicyItem(
            context,
            title: "contactUs".tr,
            icon: Icons.contact_page_outlined,
            onTap: () => Get.to(() => const ContactUsScreen()),
          ),
          _buildPolicyItem(
            context,
            title: "termsAndConditions".tr,
            icon: Icons.description_outlined,
            onTap: () => Get.to(() => const TermsAndConditionsScreen()),
          ),
          _buildPolicyItem(
            context,
            title: "refundsAndCancellations".tr,
            icon: Icons.assignment_return_outlined,
            onTap: () => Get.to(() => const RefundsAndCancellationsScreen()),
          ),

          const SizedBox(height: 30),

          // Services & Pricing Section
          _buildSectionHeader(context, "productsServices".tr),
          const SizedBox(height: 15),
          _buildServicesPricingCard(context),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeInSlide(
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildPolicyItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeInSlide(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.blueAccent),
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }

  Widget _buildServicesPricingCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeInSlide(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
        child: Column(
          children: [
            _buildServiceRow(context, "auto".tr, "₹30", "₹18"),
            const Divider(height: 30),
            _buildServiceRow(context, "hatchback".tr, "₹50", "₹20"),
            const Divider(height: 30),
            _buildServiceRow(context, "sedan".tr, "₹55", "₹22"),
            const Divider(height: 30),
            _buildServiceRow(context, "suv".tr, "₹100", "₹35"),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceRow(
    BuildContext context,
    String service,
    String base,
    String perKm,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          service,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "${"baseFare".tr}: $base",
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            Text(
              "${"perKm".tr}: $perKm",
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ],
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
