import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';

class EmailSupportScreen extends StatefulWidget {
  const EmailSupportScreen({super.key});

  @override
  State<EmailSupportScreen> createState() => _EmailSupportScreenState();
}

class _EmailSupportScreenState extends State<EmailSupportScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _sendEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Get.snackbar(
        "Success",
        "Your query has been submitted. We will contact you shortly.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ProAppBar(titleText: "Email Support"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "How can we help you?",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Fill out the form below and our team will get back to you via email.",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              ProTextField(
                controller: _subjectController,
                labelText: "Subject",
                hintText: "E.g. Issue with payment",
                maxLines: 1,
              ),
              const SizedBox(height: 20),

              ProTextField(
                controller: _messageController,
                labelText: "Message",
                hintText: "Describe your issue in detail...",
                maxLines: 6,
                height: 150,
              ),

              const SizedBox(height: 40),

              ProButton(
                text: "Send Query",
                isLoading: _isLoading,
                onPressed: _sendEmail,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Basic TextField Wrapper
class ProTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final int maxLines;
  final double? height;

  const ProTextField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    this.maxLines = 1,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            ),
          ),
          child: TextFormField(
            controller: controller,
            maxLines: maxLines,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'This field is required';
              }
              return null;
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hintText,
              hintStyle: TextStyle(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
