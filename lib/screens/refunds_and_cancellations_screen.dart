import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class RefundsAndCancellationsScreen extends StatelessWidget {
  const RefundsAndCancellationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ProAppBar(titleText: "refundsAndCancellations".tr),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInSlide(
              child: Text(
                "Refunds and Cancellations",
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
                "Our cancellation and refund policy is designed to be fair to both drivers and customers. Please read through the details below.",
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
              "1. Cancellation by Driver",
              "Drivers may cancel a ride request before starting it. Frequent cancellations without valid reasons may affect your driver rating and platform access.",
            ),
            _buildSection(
              isDark,
              "2. Cancellation by Customer",
              "If a customer cancels a ride after a certain period, a cancellation fee may be applied to compensate the driver for their time and fuel.",
            ),
            _buildSection(
              isDark,
              "3. Refund Eligibility",
              "Refunds are processed in cases of overcharging, technical errors, or service failures. Wallet balances are generally non-refundable but can be used for future platform services.",
            ),
            _buildSection(
              isDark,
              "4. Processing Time",
              "Approved refunds are typically processed within 5-7 business days to the original payment method or the user's wallet.",
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
                color: isDark ? Colors.orange.shade300 : Colors.orange.shade700,
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
