import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';
import 'package:project_taxi_driver_app/screens/settlement_screen.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/widgets/faq_sheet.dart';
import 'package:project_taxi_driver_app/utils/faq_data.dart';

class WalletScreen extends StatelessWidget {
  final User user;
  const WalletScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    // Inject controller if not already present
    final WalletController controller = Get.put(WalletController());
    final TextEditingController amountController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currencyFormatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: ProAppBar(
        titleText: 'myWallet'.tr,
        actions: [
          IconButton(
            onPressed: () {
              Get.bottomSheet(
                FAQSheet(title: "Wallet Help", faqs: FAQData.walletFAQs),
              );
            },
            icon: const Icon(Icons.help_outline, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FadeInSlide(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Balance Card
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E1E1E), const Color(0xFF2C2C2C)]
                        : [Colors.blueAccent, Colors.blue.shade800],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'currentBalance'.tr,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'wallet'.tr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Obx(
                      () => Text(
                        currencyFormatter.format(controller.balance.value),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Add Money Section
              Text(
                'addMoney'.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              // Custom styled text field for amount
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    icon: Icon(
                      Icons.currency_rupee,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    hintText: 'enterAmount'.tr,
                    hintStyle: TextStyle(
                      color: isDark
                          ? Colors.grey.shade600
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Obx(
                      () => ProButton(
                        text: controller.isLoading.value
                            ? "Adding..." // Ideally should be translated too but 'addMoney' is used generally
                            : 'addMoney'.tr,
                        isLoading: controller.isLoading.value,
                        onPressed: () {
                          final amount = double.tryParse(amountController.text);
                          if (amount != null && amount > 0) {
                            controller.addMoney(amount);
                            amountController.clear();
                            FocusScope.of(context).unfocus();
                          } else {
                            Get.snackbar(
                              'invalidAmount'.tr,
                              'enterValidAmount'.tr,
                              snackPosition: SnackPosition.TOP,
                              backgroundColor: Colors.red,
                              colorText: Colors.white,
                              margin: const EdgeInsets.all(16),
                              borderRadius: 12,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Obx(
                      () => ProButton(
                        text: 'settle'.tr,
                        isLoading: controller.isLoading.value,
                        // textColor: isDark ? Colors.white : Colors.black,
                        onPressed: () {
                          if (controller.balance.value <= 0) {
                            Get.snackbar('error'.tr, 'noBalanceToSettle'.tr);
                            return;
                          }

                          Get.to(() => SettlementScreen(user: user));
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // Transactions
              Text(
                'recentTransactions'.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Obx(() {
                if (controller.transactions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.history,
                            size: 48,
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "noTransactions".tr,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade500,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: controller.transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = controller.transactions[index];
                    final isCredit = transaction.type == 'credit';
                    return FadeInSlide(
                      delay: 0.2 + (index * 0.05),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade900 : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isCredit
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCredit ? Icons.add : Icons.remove,
                              color: isCredit ? Colors.green : Colors.red,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            isCredit ? 'moneyAdded'.tr : 'ridePayment'.tr,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              DateFormat(
                                'dd MMM, hh:mm a',
                              ).format(transaction.createdAt),
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          trailing: Text(
                            "${isCredit ? '+' : '-'}${currencyFormatter.format(transaction.amount)}",
                            style: TextStyle(
                              color: isCredit ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
