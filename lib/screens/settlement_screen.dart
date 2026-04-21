import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:intl/intl.dart';
import 'package:project_taxi_driver_app/data/models/bank_account.dart';
import 'package:project_taxi_driver_app/screens/add_bank_account_screen.dart';

class SettlementScreen extends StatelessWidget {
  final User user;
  const SettlementScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<WalletController>();
    // Ensure data is fetched
    if (controller.savedBankAccounts.isEmpty) controller.fetchBankAccounts();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    // Temp selection state
    final selectedBankAccount = Rx<BankAccount?>(null);
    // final selectedUpiId = Rx<String?>(null); // Commented out per user request (Cashfree UPI disabled)

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: ProAppBar(titleText: "settlement".tr),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Balance Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.blue.shade100,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    "availableBalance".tr,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.blue.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Obx(
                    () => Text(
                      currencyFormatter.format(controller.balance.value),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Saved Bank Accounts
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "selectBankAccount".tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Get.to(() => const AddBankAccountScreen()),
                  icon: const Icon(Icons.add),
                  label: Text("addNew".tr),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Expanded(
              child: Obx(() {
                if (controller.savedBankAccounts.isEmpty) {
                  return Center(
                    child: Text(
                      "noBankSaved".tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: controller.savedBankAccounts.length,
                  itemBuilder: (context, index) {
                    final bank = controller.savedBankAccounts[index];
                    return Obx(() {
                      final isSelected = selectedBankAccount.value?.id == bank.id;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade900 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : (isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade200),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            selectedBankAccount.value = bank;
                            // selectedUpiId.value = null; // Commented out per user request (Cashfree UPI disabled)
                          },
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected ? Colors.blue : Colors.grey,
                          ),
                          title: Text("${bank.name}\n${bank.maskedAccountNumber}"),
                          subtitle: Text("IFSC: ${bank.ifsc}"),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              Get.defaultDialog(
                                title: "Delete Bank Account",
                                content: const Text("Are you sure you want to remove this bank account?"),
                                textConfirm: "Delete",
                                textCancel: "Cancel",
                                confirmTextColor: Colors.white,
                                buttonColor: Colors.red,
                                onConfirm: () {
                                  controller.deleteBankAccount(bank.id);
                                  Get.back();
                                },
                              );
                            },
                          ),
                          isThreeLine: true,
                          selected: isSelected,
                        ),
                      );
                    });
                  },
                );
              }),
            ),
            /*
            const SizedBox(height: 20),
            // Saved UPI IDs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "selectUpiId".tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAddUpiDialog(context, controller),
                  icon: const Icon(Icons.add),
                  label: Text("addNew".tr),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Expanded(
              child: Obx(() {
                if (controller.savedUpiIds.isEmpty) {
                  return Center(
                    child: Text(
                      "noUpiSaved".tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: controller.savedUpiIds.length,
                  itemBuilder: (context, index) {
                    final upi = controller.savedUpiIds[index];
                    return Obx(() {
                      final isSelected = selectedUpiId.value == upi;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade900 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : (isDark
                                    ? Colors.grey.shade800
                                    : Colors.grey.shade200),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            selectedUpiId.value = upi;
                            selectedBankAccount.value = null;
                          },
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected ? Colors.blue : Colors.grey,
                          ),
                          title: Text(upi),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              Get.defaultDialog(
                                title: "Delete UPI ID",
                                content: const Text("Are you sure you want to remove this UPI ID?"),
                                textConfirm: "Delete",
                                textCancel: "Cancel",
                                confirmTextColor: Colors.white,
                                buttonColor: Colors.red,
                                onConfirm: () {
                                  controller.deleteUpiId(upi);
                                  Get.back();
                                },
                              );
                            },
                          ),
                          selected: isSelected,
                        ),
                      );
                    });
                  },
                );
              }),
            ),
            */

            const SizedBox(height: 10),

            // Settlement Limit Info (Temporarily increased to 99)
            Obx(() {
              final used = controller.settlementsThisWeek.value;
              final remaining = 99 - used;
              
              // Daily Limit Check (Disabled temporarily)
              bool alreadySettledToday = false;
              if (controller.lastSettlementDate.value != null && used >= 99) {
                final now = DateTime.now();
                final last = controller.lastSettlementDate.value!;
                if (last.year == now.year && last.month == now.month && last.day == now.day) {
                  alreadySettledToday = true;
                }
              }

              final hasSelection = selectedBankAccount.value != null; // || selectedUpiId.value != null; // Commented out UPI check
              final canSettle = remaining > 0 && hasSelection;
              
              debugPrint("UI Settle Check: used=$used, remaining=$remaining, alreadySettledToday=$alreadySettledToday, hasSelection=$hasSelection");

              return Column(
                children: [
                  Text(
                    "${'manualSettlementsRemaining'.tr}: ${remaining < 0 ? 0 : remaining}/99",
                    style: TextStyle(
                      color: remaining <= 0 ? Colors.red : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProButton(
                    text: "settleFullAmount".tr,
                    isLoading: controller.isLoading.value,
                    onPressed: !canSettle
                        ? null
                        : () {
                            controller.settleBalance(
                              bankAccount: selectedBankAccount.value,
                              // upiId: selectedUpiId.value, // Commented out UPI parameter
                            );
                          },
                    backgroundColor: !canSettle
                        ? Colors.grey
                        : null,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  /*
  void _showAddUpiDialog(BuildContext context, WalletController controller) {
    final upiController = TextEditingController();
    final nameController = TextEditingController();

    Get.defaultDialog(
      title: "addUpiTitle".tr,
      content: Column(
        children: [
          ProTextField(
            hintText: "UPI ID (e.g. name@bank)",
            icon: Icons.account_balance_wallet,
            controller: upiController,
          ),
          const SizedBox(height: 10),
          ProTextField(
            hintText: "Full Name (as per Bank)",
            icon: Icons.person,
            controller: nameController,
          ),
        ],
      ),
      textConfirm: "verifyAndAdd".tr,
      textCancel: "cancel".tr,
      confirmTextColor: Colors.white,
      onConfirm: () {
        final upi = upiController.text.trim();
        final name = nameController.text.trim();
        if (upi.isEmpty || name.isEmpty) {
          Get.snackbar("error".tr, "allFieldsRequired".tr);
          return;
        }
        if (!upi.contains("@")) {
          Get.snackbar("error".tr, "invalidUpiId".tr);
          return;
        }
        controller.verifyAndAddUpi(upi, name);
      },
    );
  }
  */
}
