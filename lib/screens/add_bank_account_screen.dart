import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:pinput/pinput.dart';

class AddBankAccountScreen extends StatefulWidget {
  const AddBankAccountScreen({super.key});

  @override
  State<AddBankAccountScreen> createState() => _AddBankAccountScreenState();
}

class _AddBankAccountScreenState extends State<AddBankAccountScreen> {
  final controller = Get.find<WalletController>();

  // controllers for inputs
  final nameController = TextEditingController();
  final accNoController = TextEditingController();
  final confirmAccNoController = TextEditingController();
  final ifscController = TextEditingController();
  final otpController = TextEditingController();

  final RxInt currentStep = 0.obs; // 0: Input, 1: OTP
  final RxString selectedAccountType = 'savings'.obs;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ProAppBar(titleText: "Add Bank Account".tr),
      body: Obx(() {
        return currentStep.value == 0
            ? _buildInputStep(isDark)
            : _buildOtpStep(isDark);
      }),
    );
  }

  Widget _buildInputStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "bankAccountDetailsMsg".tr,
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 25),
          ProTextField(
            hintText: "accHolderName".tr,
            icon: Icons.person_outline,
            controller: nameController,
          ),
          const SizedBox(height: 15),
          ProTextField(
            hintText: "accNumber".tr,
            icon: Icons.account_balance_outlined,
            controller: accNoController,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 15),
          ProTextField(
            hintText: "confirmAccNumber".tr,
            icon: Icons.check_circle_outline,
            controller: confirmAccNoController,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 15),
          ProTextField(
            hintText: "ifscCode".tr,
            icon: Icons.code,
            controller: ifscController,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 15),
          Obx(
            () => DropdownButtonFormField<String>(
              initialValue: selectedAccountType.value,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                hintText: "Account Type",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'savings',
                  child: Text("Savings Account"),
                ),
                DropdownMenuItem(
                  value: 'current',
                  child: Text("Current Account"),
                ),
              ],
              onChanged: (value) {
                if (value != null) selectedAccountType.value = value;
              },
            ),
          ),
          const SizedBox(height: 30),
          Obx(
            () => ProButton(
              text: "verifyAndProceed".tr,
              isLoading: controller.isLoading.value,
              onPressed: _onVerifyPressed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 60), // Manual top spacing for better visual balance
          Icon(
            Icons.security,
            size: 64,
            color: isDark ? Colors.blue.shade300 : Colors.blue,
          ),
          const SizedBox(height: 20),
          Text(
            "verificationRequired".tr,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "otpSentMsg".tr,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 40),
          Pinput(
            controller: otpController,
            length: 6,
            onCompleted: (pin) => _onFinalizePressed(),
            defaultPinTheme: PinTheme(
              width: 50,
              height: 55,
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade400),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Obx(
            () => ProButton(
              text: "Add Bank Account".tr,
              isLoading: controller.isLoading.value,
              onPressed: _onFinalizePressed,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => currentStep.value = 0,
            child: Text("backToEdit".tr),
          ),
        ],
      ),
    );
  }

  Future<void> _onVerifyPressed() async {
    final name = nameController.text.trim();
    final accNo = accNoController.text.trim();
    final confirmAcc = confirmAccNoController.text.trim();
    final ifsc = ifscController.text.trim().toUpperCase();

    if (name.isEmpty || accNo.isEmpty || confirmAcc.isEmpty || ifsc.isEmpty) {
      Get.snackbar("Error", "All fields are required");
      return;
    }

    if (accNo != confirmAcc) {
      Get.snackbar("Error", "Account numbers do not match");
      return;
    }

    final ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
    if (!ifscRegex.hasMatch(ifsc)) {
      Get.snackbar("Error", "Invalid IFSC format");
      return;
    }

    final success = await controller.initiateBankAccountVerification(
      name: name,
      accountNumber: accNo,
      ifsc: ifsc,
      accountType: selectedAccountType.value,
      showOtpDialog: false, // Handle OTP in this screen
    );

    if (success) {
      currentStep.value = 1;
    }
  }

  Future<void> _onFinalizePressed() async {
    final otp = otpController.text.trim();
    if (otp.length != 6) {
      Get.snackbar("Error", "Please enter a valid 6-digit OTP");
      return;
    }

    final success = await controller.finalizeBankAccountAddition(
      name: nameController.text.trim(),
      accountNumber: accNoController.text.trim(),
      ifsc: ifscController.text.trim().toUpperCase(),
      otp: otp,
      accountType: selectedAccountType.value,
      phone: Get.find<WalletController>().userPhoneNumber ?? "",
    );

    if (success) {
      // Use Get.back with closeOverlays to ensure we close the screen 
      // even if a snackbar is currently visible.
      Get.back(closeOverlays: true); 
    }
  }
}
