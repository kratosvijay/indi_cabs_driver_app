import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/services/goto_timer_service.dart';

class GoToStatusBanner extends StatelessWidget {
  final VoidCallback? onExtend;
  final VoidCallback? onDeactivate;

  const GoToStatusBanner({
    super.key,
    this.onExtend,
    this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    final goToService = GoToTimerService.instance;

    return Obx(() {
      if (!goToService.isGoToActive.value) {
        return const SizedBox.shrink();
      }

      final destination = goToService.getDestinationAddress() ?? 'Unknown';
      final remainingTime = goToService.getRemainingTimeFormatted();
      final isExpiringSoon = goToService.remainingMinutes.value <= 10;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isExpiringSoon
                ? [Colors.orange.shade700, Colors.orange.shade500]
                : [Colors.blue.shade700, Colors.blue.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isExpiringSoon ? Icons.warning_amber : Icons.navigation,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'gotoDestination'.tr,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        destination,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      remainingTime,
                      style: TextStyle(
                        color: isExpiringSoon ? Colors.yellow : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Extend button
                    InkWell(
                      onTap: () {
                        _showExtendOptions(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.add_circle_outline,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'extendGoto'.tr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Deactivate button
                    InkWell(
                      onTap: () {
                        _showDeactivateConfirmation(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (isExpiringSoon) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.yellow,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GoTo will expire soon. Extend or it will switch to Online mode.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  void _showExtendOptions(BuildContext context) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'extendGoto'.tr,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildExtendOption(
              context,
              'extend30Min'.tr,
              const Duration(minutes: 30),
              Icons.timer_30,
            ),
            const SizedBox(height: 12),
            _buildExtendOption(
              context,
              'extend1Hour'.tr,
              const Duration(hours: 1),
              Icons.timer,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Get.back(),
              child: Text('cancel'.tr),
            ),
          ],
        ),
      ),
      isDismissible: true,
    );
  }

  Widget _buildExtendOption(
    BuildContext context,
    String label,
    Duration duration,
    IconData icon,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: () {
        GoToTimerService.instance.extendGoTo(duration);
        Get.back();
        Get.snackbar(
          'extendGoto'.tr,
          'GoTo extended by $label',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
        onExtend?.call();
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeactivateConfirmation(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: Text('deactivateGoto'.tr),
        content: const Text(
          'Are you sure you want to deactivate GoTo? You will switch to regular online mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              GoToTimerService.instance.deactivateGoTo();
              Get.back();
              Get.snackbar(
                'deactivateGoto'.tr,
                'GoTo deactivated. Switching to online mode.',
                snackPosition: SnackPosition.TOP,
                backgroundColor: Colors.orange,
                colorText: Colors.white,
                duration: const Duration(seconds: 2),
              );
              onDeactivate?.call();
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }
}

/// Show GoTo activation dialog
void showGoToActivationDialog({
  required String destination,
  required Duration duration,
  required VoidCallback onConfirm,
}) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  String durationText = '';
  if (hours > 0) {
    durationText = '$hours hour${hours > 1 ? 's' : ''}';
    if (minutes > 0) {
      durationText += ' and $minutes minute${minutes > 1 ? 's' : ''}';
    }
  } else {
    durationText = '$minutes minute${minutes > 1 ? 's' : ''}';
  }

  Get.dialog(
    AlertDialog(
      title: Row(
        children: [
          Icon(Icons.navigation, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(child: Text('gotoActivated'.tr)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${'gotoActivatedFor'.tr} $durationText',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    destination,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You will only receive ride requests towards this destination.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: Text('cancel'.tr),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () {
            Get.back();
            onConfirm();
            Get.snackbar(
              'gotoActivated'.tr,
              'You will receive requests towards $destination for $durationText',
              snackPosition: SnackPosition.TOP,
              backgroundColor: Colors.blue.shade700,
              colorText: Colors.white,
              duration: const Duration(seconds: 3),
              icon: const Icon(Icons.navigation, color: Colors.white),
            );
          },
          child: const Text(
            'Activate',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
    barrierDismissible: false,
  );
}
