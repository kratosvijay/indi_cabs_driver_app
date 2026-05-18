import 'package:flutter/material.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';

class RentalOverlayCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const RentalOverlayCard({
    super.key,
    required this.ride,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final String vehicleClass = ride['vehicleClass'] ?? 'Rental';
    final String packageName = ride['packageName'] ?? 'Rental Package';
    final String packageDetails = _getPackageDetails(ride);
    final String pickupTitle = ride['pickupTitle'] ?? 'Pickup';
    final String? pickupArea = ride['pickupArea'] as String?; // **NEW**
    final String pickupAddress = ride['pickupFullAddress'] ?? '';
    final String driverDist =
        (ride['driverDistance'] as num?)?.toDouble().toStringAsFixed(1) ?? "0.0";
    final int? driverDur = (ride['driverDuration'] as num?)?.toDouble().toInt();
    final String rideFare = (ride['rideFare'] as num?)?.toStringAsFixed(0) ?? "0";

    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkStart : Colors.white;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            blurRadius: 15,
            color: Colors.black.withValues(alpha: 0.15),
            offset: const Offset(0, 4),
          ),
        ],
        border: isDark ? null : Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Header
            Center(
              child: Text(
                "$vehicleClass RENTAL".toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : AppColors.primary,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Pickup
            _buildDetailRow(
              Icons.location_on,
              pickupTitle,
              pickupAddress,
              pickupArea, // **NEW**
              "$driverDist km Away${driverDur != null ? " (~$driverDur mins)" : ""}",
              primaryTextColor,
              secondaryTextColor,
              isDark,
              isPickup: true,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: Icon(Icons.more_vert, color: secondaryTextColor.withValues(alpha: 0.5), size: 16),
            ),

            // 3. Package Info (Replaces Dropoff)
            _buildDetailRow(
              Icons.work_history,
              packageName,
              packageDetails,
              null, // No area for package
              "Rental Package",
              primaryTextColor,
              secondaryTextColor,
              isDark,
            ),

            const SizedBox(height: 20),
            Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey.shade200),
            const SizedBox(height: 20),

            // 4. Price & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Price & Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "₹$rideFare",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Actions
                Row(
                  children: [
                    TextButton(
                      onPressed: onReject,
                      style: TextButton.styleFrom(
                        backgroundColor: isDark 
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: Text(
                        "Pass",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Accept",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (ride['tip'] != null && (ride['tip'] as num) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.card_giftcard, color: Colors.white, size: 14),
                        const SizedBox(width: 8),
                        Text(
                          "Customer Added TIP: ₹${(ride['tip'] as num).toStringAsFixed(0)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String subtitle,
    String? area, // **NEW**
    String meta,
    Color primaryTextColor,
    Color secondaryTextColor,
    bool isDark, {
    bool isPickup = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark 
                ? (isPickup ? Colors.green.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.15))
                : (isPickup ? Colors.green.shade50 : Colors.blue.shade50),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isPickup ? Colors.green : Colors.blue,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (area != null && area.isNotEmpty && area != title) ...[
                          const SizedBox(height: 2),
                          Text(
                            area,
                            style: TextStyle(
                              color: primaryTextColor.withValues(alpha: 0.8),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    meta,
                    style: TextStyle(
                      color: isPickup ? (isDark ? Colors.greenAccent : Colors.green) : (isDark ? Colors.lightBlueAccent : Colors.blue),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 13,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getPackageDetails(Map<String, dynamic> ride) {
    final duration = ride['durationHours'];
    final kmLimit = ride['kmLimit'];
    if (duration != null && kmLimit != null) {
      return "$duration Hours / $kmLimit km Package";
    }
    return ride['packageName'] ?? 'Standard Package';
  }
}
