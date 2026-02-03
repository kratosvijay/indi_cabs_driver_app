// ignore_for_file: unused_field, prefer_final_fields, unused_local_variable

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';
import 'package:project_taxi_driver_app/screens/duty_setting.dart';
import 'package:project_taxi_driver_app/screens/earnings.dart';
import 'package:project_taxi_driver_app/screens/wallet_screen.dart';
import 'package:project_taxi_driver_app/screens/incentive.dart';
import 'package:project_taxi_driver_app/screens/notifications.dart';
import 'package:project_taxi_driver_app/screens/profile.dart';
import 'package:project_taxi_driver_app/screens/ride_details.dart';
import 'package:project_taxi_driver_app/services/notification_service.dart';
import 'package:project_taxi_driver_app/utils/app_colors.dart';
import 'package:project_taxi_driver_app/screens/help_screen.dart';
import 'package:project_taxi_driver_app/services/queue_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:project_taxi_driver_app/widgets/pro_library.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:project_taxi_driver_app/widgets/status_slider.dart';
import 'package:project_taxi_driver_app/screens/subscription_plans.dart';
import 'package:project_taxi_driver_app/screens/demand_areas_screen.dart';

class DriverHomePage extends StatefulWidget {
  final User user;
  final bool isActingDriver;
  final DriverStatus? initialStatus;

  const DriverHomePage({
    super.key,
    required this.user,
    this.isActingDriver = false,
    this.initialStatus,
  });

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage>
    with WidgetsBindingObserver {
  late final HomePageController controller;
  bool _isDashboardExpanded = false;

  @override
  void initState() {
    super.initState();
    // Initialize controller with user
    controller = Get.put(
      HomePageController(
        user: widget.user,
        isActingDriver: widget.isActingDriver,
        initialStatus: widget.initialStatus,
      ),
    );

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize Notification Service (FCM)
    NotificationService().initialize();
    // Initialize Notification Service (FCM)
    NotificationService().initialize();

    // Enable Wakelock to keep screen on
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('App lifecycle state changed to: $state');
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          backgroundColor: isDark ? Colors.black : Colors.white,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.lightEnd.withAlpha(150),
                  ),
                ),
                SizedBox(height: 24),
                CircularProgressIndicator(color: AppColors.lightEnd),
              ],
            ),
          ),
        );
      }

      return Scaffold(
        drawer: _buildAppDrawer(context),
        appBar: ProAppBar(
          toolbarHeight: 100,
          title: Obx(
            () => StatusSlider(
              currentStatus: controller.driverStatus.value,
              onStatusChanged: (status) =>
                  controller.handleStatusChange(status),
              offlineText: controller.getTranslatedString('offDuty'),
              onlineText: controller.getTranslatedString('onDuty'),
              goToText: controller.getTranslatedString('goTo'),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Obx(
                () => Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      onPressed: () {
                        Get.to(() => const NotificationsScreen());
                      },
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    if (controller.hasUnreadNotifications.value)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            // Conditional content based on driver status
            Obx(
              () => controller.driverStatus.value == DriverStatus.offline
                  ? // Off Duty - Show blank state
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.power_settings_new,
                            size: 80,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'turnOnToGetRides'.tr,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    )
                  : // On Duty or GoTo - Show map and features
                    Stack(
                      children: [
                        // Google Map
                        Obx(
                          () => GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target:
                                  controller.currentPosition.value ??
                                  const LatLng(
                                    13.0827,
                                    80.2707,
                                  ), // Default: Chennai
                              zoom: 14.5,
                            ),
                            mapType: MapType.normal,
                            polygons: controller.polygons,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            onMapCreated: (GoogleMapController mapController) {
                              if (!controller.mapController.isCompleted) {
                                controller.mapController.complete(
                                  mapController,
                                );
                              }
                            },
                          ),
                        ),

                        // Recenter Button - Fixed bottom-right
                        Positioned(
                          bottom: 24,
                          right: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FloatingActionButton(
                                heroTag: 'recenter',
                                backgroundColor: Colors.white,
                                onPressed: () =>
                                    controller.goToCurrentUserLocation(),
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),

            // Queue Position Banner
            Obx(() {
              final pos = QueueService().queuePosition.value;
              if (pos != null) {
                return Positioned(
                  top: 90, // Moved down to accommodate Dashboard
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.flight_takeoff,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "${'airportQueue'.tr}: #$pos",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (QueueService().queueStatus.value == 'offered_ride')
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              "(${'offeringRide'.tr})",
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }),

            // Dashboard - Collapsible
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: _buildDashboard(context),
            ),

            // Ride Request Card
            Obx(() {
              // Hide card if we are in the process of accepting (e.g. from overlay)
              if (controller.activeRideRequest.value != null &&
                  !controller.isRideAcceptanceInProgress.value) {
                if (controller.activeRideRequest.value!.rideType == 'rental') {
                  return const SizedBox.shrink();
                }

                return RideRequestCard(
                  rideRequest: controller.activeRideRequest.value!,
                  onAccept: controller.onRideAccepted,
                  onReject: () => controller.onRideRejected("card_reject"),
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      );
    });
  }

  Widget _buildAppDrawer(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              gradient: AppColors.getAppBarGradient(context),
            ),
            accountName: Text(
              widget.user.displayName ?? 'Driver',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Text(widget.user.email ?? ''),
            currentAccountPicture: CircleAvatar(
              backgroundImage: widget.user.photoURL != null
                  ? NetworkImage(widget.user.photoURL!)
                  : null,
              backgroundColor: Colors.white,
              child: widget.user.photoURL == null
                  ? const Icon(Icons.person, size: 40, color: Colors.grey)
                  : null,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Earnings Summary
                _buildEarningsSummaryBar(controller),
                const SizedBox(height: 24),

                Text(
                  "Menu",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[800],
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 16),

                // Menu Items
                _buildMenuItem(
                  icon: Icons.notifications_outlined,
                  title: controller.getTranslatedString('notifications'),
                  onTap: () {
                    Get.back(); // Close drawer
                    Get.to(() => NotificationsScreen());
                  },
                ),
                _buildMenuItem(
                  icon: Icons.person_outline,
                  title: controller.getTranslatedString('profile'),
                  onTap: () {
                    Get.back();
                    Get.to(() => ProfileScreen(user: widget.user));
                  },
                ),
                _buildMenuItem(
                  icon: Icons.currency_rupee,
                  title: controller.getTranslatedString('earnings'),
                  onTap: () {
                    Get.back();
                    Get.to(() => EarningsScreen(user: widget.user));
                  },
                ),
                _buildMenuItem(
                  icon: Icons.account_balance_wallet_outlined,
                  title: controller.getTranslatedString('wallet'),
                  onTap: () {
                    Get.back();
                    Get.to(() => WalletScreen(user: widget.user));
                  },
                ),
                _buildMenuItem(
                  icon: Icons.subscriptions_outlined,
                  title: "subscriptionPlans".tr,
                  onTap: () {
                    Get.back();
                    Get.to(() => const SubscriptionPlansScreen());
                  },
                ),
                _buildMenuItem(
                  icon: Icons.card_giftcard,
                  title: controller.getTranslatedString('incentives'),
                  onTap: () {
                    Get.back();
                    Get.to(() => const IncentivesScreen());
                  },
                ),
                _buildMenuItem(
                  icon: Icons.settings_outlined,
                  title: controller.getTranslatedString('dutySettings'),
                  onTap: () {
                    Get.back();
                    Get.to(() => DutySettingsScreen(user: widget.user));
                  },
                ),
                _buildMenuItem(
                  icon: Icons.map_outlined,
                  title: "nearbyDemandAreas".tr,
                  onTap: () {
                    Get.back();
                    Get.to(() => const DemandAreasScreen());
                  },
                ),
                _buildMenuItem(
                  icon: Icons.help_outline,
                  title: controller.getTranslatedString('help'),
                  onTap: () {
                    Get.back();
                    Get.to(() => const HelpScreen());
                  },
                ),
                const SizedBox(height: 12),
                Divider(color: isDark ? Colors.white10 : Colors.grey[200]),
                const SizedBox(height: 12),
                _buildMenuItem(
                  icon: Icons.logout,
                  title: controller.getTranslatedString('logout'),
                  onTap: () => controller.logout(context),
                  isDestructive: true,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsSummaryBar(HomePageController controller) {
    return Obx(() {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF2C2C2C), const Color(0xFF1E1E1E)]
                : [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : AppColors.primary).withValues(
                alpha: 0.3,
              ),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          controller.getTranslatedString('todayEarnings'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.visible, // Allow wrapping
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "₹${controller.todaysEarnings.value.toStringAsFixed(0)}",
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -1.0,
                    ),
                  ),
                ],
              ),
            ),
            if (controller.lastRide.value != null)
              Container(
                margin: const EdgeInsets.only(
                  left: 8,
                ), // Add margin for spacing
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: () {
                    Get.to(
                      () => RideDetailsScreen(ride: controller.lastRide.value!),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward, color: Colors.white),
                  tooltip: controller.getTranslatedString('lastRide'),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDestructive
        ? Colors.red
        : (isDark ? Colors.white : Colors.black87);
    final Color iconColor = isDestructive
        ? Colors.red
        : (isDark ? Colors.white70 : AppColors.primary);
    final Color backgroundColor = isDestructive
        ? Colors.red.withValues(alpha: 0.1)
        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100]!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF252525) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey[200]!,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Subscription Banner
        _buildSubscriptionBanner(context),
        const SizedBox(height: 12),

        // Collapsible Button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _isDashboardExpanded = !_isDashboardExpanded;
              });
            },
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.dashboard_outlined,
                        size: 18,
                        color: isDark ? Colors.white70 : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'dashboard'.tr,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    _isDashboardExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Expanded Cards
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _isDashboardExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              // 1. Wallet Card
                              _buildDashboardCard(
                                context,
                                "walletBalance".tr,
                                controller.walletBalance,
                                Icons.account_balance_wallet,
                                Colors.orange,
                                onTap: () => Get.to(
                                  () => WalletScreen(user: widget.user),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 2. Today's Earnings
                              _buildDashboardCard(
                                context,
                                "today".tr,
                                controller.todaysEarnings,
                                Icons.today,
                                Colors.green,
                                onTap: () => Get.to(
                                  () => EarningsScreen(user: widget.user),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 3. Last Order
                              _buildDashboardCard(
                                context,
                                "lastOrder".tr,
                                RxDouble(
                                  controller.lastRide.value?.earnings ?? 0,
                                ),
                                Icons.history,
                                Colors.blue,
                                onTap: () {
                                  if (controller.lastRide.value != null) {
                                    Get.to(
                                      () => RideDetailsScreen(
                                        ride: controller.lastRide.value!,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildSubscriptionBanner(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(() {
      final bool isActive = controller.isPlanActive;
      final String? planName = controller.subscriptionPlanName.value;
      final DateTime? expiry = controller.subscriptionExpiry.value;

      return GestureDetector(
        onTap: () => Get.to(() => const SubscriptionPlansScreen()),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? Colors.green : Colors.red,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.verified_user : Icons.warning_amber_rounded,
                color: isActive ? Colors.green : Colors.red,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive
                          ? "${'activePlan'.tr}: ${planName ?? 'unlimited'.tr}"
                          : "noActivePlan".tr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    if (isActive && expiry != null)
                      Text(
                        "${'expires'.tr}: ${expiry.day}/${expiry.month}/${expiry.year}",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    if (!isActive)
                      Text(
                        "rechargeMsg".tr,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isActive)
                ElevatedButton(
                  onPressed: () =>
                      Get.to(() => const SubscriptionPlansScreen()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    elevation: 0,
                  ),
                  child: Text("recharge".tr),
                ),
              if (isActive)
                const Icon(Icons.chevron_right, color: Colors.green, size: 20),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildDashboardCard(
    BuildContext context,
    String title,
    RxDouble value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Obx(
      () => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 130, // Fixed width for consistent look
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "₹${value.value.toStringAsFixed(0)}",
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
