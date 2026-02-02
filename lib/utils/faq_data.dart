class FAQItem {
  final String question;
  final String answer;

  FAQItem({required this.question, required this.answer});
}

class FAQData {
  static final List<FAQItem> subscriptionFAQs = [
    FAQItem(
      question: 'Are the subscription plans really free?',
      answer:
          'Yes! Currently, all subscription plans are available as a Free Trial. You can activate any plan (1 Day, 7 Days, etc.) for ₹0.',
    ),
    FAQItem(
      question: 'What happens if I take a ride without an active plan?',
      answer:
          'If you accept a ride without an active plan, the "1 Day Plan" will be automatically activated for you as a free trial, allowing you to continue working seamlessly.',
    ),
    FAQItem(
      question: 'Do plans include GST?',
      answer:
          'Normally, plans would include 18% GST, but during the Free Trial period, the total cost is ₹0.00.',
    ),
  ];

  static final List<FAQItem> earningsFAQs = [
    FAQItem(
      question: 'How can I check my earnings?',
      answer:
          'Go to the "Earnings" section from the menu. You can view your Daily, Weekly, and Monthly earnings breakdowns.',
    ),
    FAQItem(
      question: 'Do cancelled rides count towards earnings?',
      answer:
          'No, only "Completed" rides are calculated in your total earnings. Cancelled or missed rides do not contribute to the payout.',
    ),
  ];

  static final List<FAQItem> walletFAQs = [
    FAQItem(
      question: 'How do I add money to my wallet?',
      answer:
          'Use the "Add Money" section on this screen. Enter the amount and tap "Add Money" to proceed with the transaction.',
    ),
    FAQItem(
      question: 'What is the "Settle" button for?',
      answer:
          'This allows you to settle your positive wallet balance. It initiates a request to transfer your earnings to your registered bank account.',
    ),
  ];

  static final List<FAQItem> dutyFAQs = [
    FAQItem(
      question: 'How do I manage vehicle types?',
      answer:
          'Use the toggles below to select which vehicle types you want to accept rides for. You can enable multiple types if your vehicle supports them.',
    ),
    FAQItem(
      question: 'Can I choose between Daily and Rental rides?',
      answer:
          'Yes, the settings are separated into "Daily Rides" and "Rental Rides". You can configure your preferences for each category independently.',
    ),
  ];
}
