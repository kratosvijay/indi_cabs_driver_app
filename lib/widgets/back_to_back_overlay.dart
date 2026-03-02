import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';

class BackToBackOverlayWidget extends StatelessWidget {
  const BackToBackOverlayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomePageController>()) {
      return const SizedBox.shrink();
    }

    return Obx(() {
      final homeController = Get.find<HomePageController>();
      final queuedRides = homeController.queuedRides;

      if (queuedRides.isEmpty) return const SizedBox.shrink();
      final queued = queuedRides.first;

      // If already accepted, show small indicator
      if (queued.status == 'accepted') {
        return Positioned(
          top: 100,
          left: 16,
          right: 16,
          child: Card(
            color: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
            child: ListTile(
              leading: const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 30,
              ),
              title: const Text(
                "Next Ride Queued",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "Pickup: ${queued.pickupTitle}",
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        );
      }

      // If searching (Offered), show full request card
      return Positioned(
        top: 80,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RideRequestCard(
            rideRequest: queued,
            onAccept: () {
              homeController.acceptBackToBackRide(queued);
            },
            onReject: () {
              homeController.queuedRides.remove(queued);
            },
          ),
        ),
      );
    });
  }
}
