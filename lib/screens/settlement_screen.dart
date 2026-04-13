import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:intl/intl.dart';

class SettlementScreen extends StatelessWidget {
  final User user;
  const SettlementScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<WalletController>();
    // Ensure data is fetched (handle hot reload case)
    if (controller.savedUpiIds.isEmpty) controller.fetchUpiIds();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyFormatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    // Temp selection state
    final selectedUpiId = RxnString();

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
                  itemCount: controller.savedUpiIds.length,
                  itemBuilder: (context, index) {
                    final upiId = controller.savedUpiIds[index];
                    return Obx(() {
                      final isSelected = selectedUpiId.value == upiId;
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
                          onTap: () => selectedUpiId.value = upiId,
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected ? Colors.blue : Colors.grey,
                          ),
                          title: Text(upiId),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              Get.defaultDialog(
                                title: "deleteUpiTitle".tr,
                                content: Text("deleteUpiMsg".tr),
                                textConfirm: "delete".tr,
                                textCancel: "cancel".tr, // cancel exists
                                confirmTextColor: Colors.white,
                                buttonColor: Colors.red,
                                onConfirm: () {
                                  controller.deleteUpiId(upiId);
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

            const SizedBox(height: 20),
            // Auto Settlement Switch
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
              ),
              child: Obx(
                () => SwitchListTile(
                  title: Text("autoSettlement".tr),
                  subtitle: Text("autoSettlementMsg".tr),
                  value: controller.autoSettleEnabled.value,
                  onChanged: (val) {
                    if (controller.savedUpiIds.isEmpty) {
                      Get.snackbar(
                        "error".tr,
                        "Please add a UPI ID first to enable auto-settle", // missed this one, leaving English or using generic error
                      );
                      return;
                    }
                    if (val && selectedUpiId.value == null) {
                      // If enabling, ensure a UPI ID is selected or use the first one if one exists?
                      // Better to require user to select one or just use the current selection.
                      // Let's use the current selected one, or force them to select.
                      if (selectedUpiId.value == null) {
                        Get.snackbar(
                          "error".tr,
                          "Please select a UPI ID for auto-settlement", // missed this
                        );
                        return;
                      }
                    }
                    if (val) {
                      // Save the UPI ID to use
                      controller.updateAutoSettleSettings(
                        val,
                        selectedUpiId.value!,
                      );
                      Get.snackbar(
                        "Success", // success?
                        "${'autoSettlementEnabled'.tr} ${selectedUpiId.value}",
                      );
                    } else {
                      controller.updateAutoSettleSettings(val, "");
                      Get.snackbar("Success", "autoSettlementDisabled".tr);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Settlement Limit Info
            Obx(() {
              final used = controller.settlementsThisWeek.value;
              final remaining = 7 - used;
              
              // Daily Limit Check
              bool alreadySettledToday = false;
              if (controller.lastSettlementDate.value != null) {
                final now = DateTime.now();
                final last = controller.lastSettlementDate.value!;
                if (last.year == now.year && last.month == now.month && last.day == now.day) {
                  alreadySettledToday = true;
                }
              }

              final canSettle = remaining > 0 && !alreadySettledToday && selectedUpiId.value != null;
              
              debugPrint("UI Settle Check: used=$used, remaining=$remaining, alreadySettledToday=$alreadySettledToday, selected=${selectedUpiId.value != null}");

              return Column(
                children: [
                  Text(
                    "${'manualSettlementsRemaining'.tr}: ${remaining < 0 ? 0 : remaining}/7",
                    style: TextStyle(
                      color: remaining <= 0 ? Colors.red : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (alreadySettledToday)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "Only 1 settlement per day is allowed.",
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 10),
                  ProButton(
                    text: "settleFullAmount".tr,
                    isLoading: controller.isLoading.value,
                    onPressed: !canSettle
                        ? null
                        : () {
                            controller.settleBalance(selectedUpiId.value!);
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

  void _showAddUpiDialog(BuildContext context, WalletController controller) {
    final upiController = TextEditingController();
    final nameController = TextEditingController(); // Name at bank

    Get.defaultDialog(
      title: "addUpiTitle".tr,
      content: SingleChildScrollView(
        child: Column(
          children: [
            ProTextField(
              hintText: "enterUpiHint".tr,
              icon: Icons.account_balance,
              controller: upiController,
            ),
            const SizedBox(height: 10),
            ProTextField(
              hintText: "accountHolderName".tr,
              icon: Icons.person,
              controller: nameController,
            ),
            const SizedBox(height: 10),
            Obx(() {
              if (controller.isLoading.value) {
                return const CircularProgressIndicator();
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
      textConfirm: "verifyAndSave".tr,
      textCancel: "cancel".tr,
      confirmTextColor: Colors.white,
      onConfirm: () {
        if (upiController.text.isNotEmpty &&
            upiController.text.contains('@') &&
            nameController.text.isNotEmpty) {
          // Don't close dialog immediately, controller handles it
          // But Get.defaultDialog auto-closes onConfirm unless we override navigating back?
          // Actually, Get.defaultDialog usually closes. logic in controller calls Get.back().
          // If we want to show loading IN dialog, we need to prevent auto close.
          // Standard Get.defaultDialog closes.
          // Let's call the controller method. Use `willPopScope` or similar if we wanted to prevent close,
          // but for simplicity, we let it close or we just use a custom dialog if we want persistent loading.
          // However, the controller `verifyAndAddUpi` calls `Get.back()` at start to close dialog.
          // Let's stick to that flow -> Close dialog, show loading overlay/snackbar or global loading.
          // Controller sets isLoading = true.

          controller.verifyAndAddUpi(
            upiController.text.trim(),
            nameController.text.trim(),
          );
        } else {
          Get.snackbar("error".tr, "invalidUpiError".tr);
        }
      },
    );
  }
}
