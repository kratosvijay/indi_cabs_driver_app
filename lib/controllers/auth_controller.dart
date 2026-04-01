import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:project_taxi_driver_app/screens/car_selection.dart';
import 'package:project_taxi_driver_app/screens/document_verificaton.dart';
import 'package:project_taxi_driver_app/screens/fleet_dashboard.dart';
import 'package:project_taxi_driver_app/screens/homepage.dart';
import 'package:project_taxi_driver_app/screens/login.dart';
import 'package:project_taxi_driver_app/screens/driver_vehicle_selection_screen.dart';
import 'package:project_taxi_driver_app/widgets/status_slider.dart';
import 'package:project_taxi_driver_app/widgets/ride_request.dart';
import 'package:project_taxi_driver_app/screens/ride_acepted.dart';
import 'package:project_taxi_driver_app/screens/ride_started.dart';
import 'package:project_taxi_driver_app/screens/ride_payment.dart';
import 'package:project_taxi_driver_app/controllers/home_page_controller.dart';
import 'package:project_taxi_driver_app/controllers/wallet_controller.dart';

class AuthController extends GetxController {
  static AuthController get instance => Get.find();

  // Variables
  final _auth = FirebaseAuth.instance;
  late final Rx<User?> firebaseUser;

  // Firestore references
  final _db = FirebaseFirestore.instance;

  @override
  void onInit() {
    super.onInit();
    // Initialize firebaseUser immediately
    firebaseUser = Rx<User?>(_auth.currentUser);
    firebaseUser.bindStream(_auth.authStateChanges());
  }

  // Determine where to go after successful login or auto-login check
  Future<void> decideRoute({DriverStatus? initialStatus}) async {
    User? user = firebaseUser.value;

    if (user == null) {
      Get.offAll(() => const LoginScreen());
      return;
    }

    try {
      // Check Driver Collection by Querying UID field
      // This is necessary because document IDs will now be human-readable (indi-drv-X)
      // but Auth provides the randomized Firebase UID.
      QuerySnapshot driverQuery = await _db
          .collection('drivers')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (driverQuery.docs.isNotEmpty) {
        final driverDoc = driverQuery.docs.first;
        final driverDocId = driverDoc.id; // Correct Document ID (e.g. indi-drv-1)
        final data = driverDoc.data() as Map<String, dynamic>;

        // Persist the Document ID for use in other screens
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('driverDocId', driverDocId);

        // --- NEW: Check for Active Rides to Restore State ---
        try {
          var activeRidesSnapshot = await _db
              .collection('ride_requests')
              .where('driverId', isEqualTo: driverDocId) // Use professional ID
              .where('driverUid', isEqualTo: user.uid) // Required for security rules
              .where(
                'status',
                whereIn: ['accepted', 'arrived', 'started', 'completed'],
              )
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

          // Check Rental Requests if no Standard Ride found
          if (activeRidesSnapshot.docs.isEmpty) {
            activeRidesSnapshot = await _db
                .collection('rental_requests')
                .where('driverId', isEqualTo: driverDocId) // Use professional ID
                .where('driverUid', isEqualTo: user.uid) // Required for security rules
                .where(
                  'status',
                  whereIn: ['accepted', 'arrived', 'started', 'completed'],
                )
                .orderBy('createdAt', descending: true)
                .limit(1)
                .get();
          }

          if (activeRidesSnapshot.docs.isNotEmpty) {
            final rideDoc = activeRidesSnapshot.docs.first;
            final rideData = rideDoc.data();
            // Ensure rideId is present
            rideData['rideId'] ??= rideDoc.id;

            final rideRequest = RideRequest.fromJson(rideData);
            final status = rideRequest.status;
            debugPrint(
              "DEBUG: Found active ride ${rideRequest.rideId} with status $status. Restoring...",
            );

            if (status == 'accepted' || status == 'arrived') {
              // Initialize Controller
              Get.put(
                HomePageController(
                  user: user,
                  isActingDriver: data['role'] == 'actingDriver',
                  initialStatus: DriverStatus.goTo,
                ),
                permanent: true,
              );
              Get.offAll(() => RideAcceptedScreen(rideRequest: rideRequest));
              return;
            } else if (status == 'started') {
              // Initialize Controller
              Get.put(
                HomePageController(
                  user: user,
                  isActingDriver: data['role'] == 'actingDriver',
                  initialStatus: DriverStatus.goTo,
                ),
                permanent: true,
              );
              Get.offAll(() => RideStartedScreen(rideRequest: rideRequest));
              return;
            } else if (status == 'completed') {
              // Check if earnings record exists
              final earningsSnapshot = await _db
                  .collection('earnings')
                  .where('rideId', isEqualTo: rideRequest.rideId)
                  .limit(1)
                  .get();

              if (earningsSnapshot.docs.isEmpty) {
                debugPrint(
                  "DEBUG: Restoring RidePaymentScreen (No earnings found)",
                );
                // If totalFare is present in rideRequest, use it.
                Get.offAll(
                  () => RidePaymentScreen(
                    rideRequest: rideRequest,
                    totalAmount: rideRequest.rideFare,
                  ),
                );
                return;
              }
            }
          }
        } catch (e) {
          debugPrint("DEBUG: Error checking for active rides: $e");
          // Fallthrough to normal flow
        }
        // ----------------------------------------------------

        debugPrint("DEBUG: decideRoute CALLED. Stack: ${StackTrace.current}");
        debugPrint("DEBUG: Driver Data -> $data"); // DEBUG LOG

        // Check for Acting Driver Role
        if (data['role'] == 'actingDriver') {
          debugPrint("DEBUG: Route -> DriverHomePage (Acting)");
          Get.offAll(
            () => DriverHomePage(
              user: user,
              isActingDriver: true,
              initialStatus: initialStatus,
            ),
          );
          return;
        }

        // Check for Fleet Driver Role
        if (data['role'] == 'fleet_driver') {
          String? vehicleId = data['vehicleId'];

          if (vehicleId != null &&
              vehicleId.isNotEmpty &&
              vehicleId != "null" &&
              vehicleId != "Select Vehicle") {
            Get.offAll(
              () => DriverHomePage(user: user, initialStatus: initialStatus),
            );
          } else {
            Get.offAll(() => DriverVehicleSelectionScreen(user: user));
          }
          return;
        }

        // --- NEW: Check for Pending Fleet Invite (Migration Logic) ---
        // If user is 'individual' (or unspecified) but has a pending 'fleet_driver' account created by Operator via phone
        if (user.phoneNumber != null) {
          final rawPhone = user.phoneNumber!.replaceFirst('+91', '');
          // Check both formatted (+91) and raw number
          final pendingFleetDocs = await _db
              .collection('drivers')
              .where('phoneNumber', whereIn: [user.phoneNumber, rawPhone])
              .where('role', isEqualTo: 'fleet_driver')
              .get();

          // If we find a doc that is NOT the current doc (different UID)
          final otherDocs = pendingFleetDocs.docs
              .where((d) => d.id != user.uid)
              .toList();

          if (otherDocs.isNotEmpty) {
            final pendingData = otherDocs.first.data();
            debugPrint("DEBUG: Found pending fleet invite! Migrating...");

            // Migrate fields
            await _db.collection('drivers').doc(user.uid).update({
              'role': 'fleet_driver',
              'fleetOperatorId': pendingData['fleetOperatorId'],
              'vehicleType': pendingData['vehicleType'], // "Select Vehicle"
              'vehicleId': null, // Reset to force selection
            });

            // Delete the temporary pending doc
            await _db.collection('drivers').doc(otherDocs.first.id).delete();

            // Reload & Redirect
            Get.offAll(() => DriverVehicleSelectionScreen(user: user));
            return;
          }
        }
        // -----------------------------------------------------------

        if (data.containsKey('isApproved') && data['isApproved'] == true) {
          debugPrint(
            "DEBUG: Route -> DriverHomePage (Reason: isApproved=true)",
          );
          Get.offAll(
            () => DriverHomePage(user: user, initialStatus: initialStatus),
          );
        } else if (data.containsKey('documentsSubmitted') &&
            data['documentsSubmitted'] == true) {
          debugPrint(
            "DEBUG: Route -> DocumentVerificationScreen (Reason: documentsSubmitted=true, Pending/Rejected)",
          );
          Get.offAll(() => DocumentVerificationScreen(user: user));
        } else if (data.containsKey('vehicleDetailsFilled') &&
            data['vehicleDetailsFilled'] == true) {
          debugPrint(
            "DEBUG: Route -> DocumentVerificationScreen (Reason: vehicleDetailsFilled=true, Needs Docs)",
          );
          Get.offAll(() => DocumentVerificationScreen(user: user));
        } else {
          debugPrint("DEBUG: Route -> CarSelectionScreen (Reason: Default)");
          Get.offAll(() => CarSelectionScreen(user: user));
        }
        return;
      }

      // Check Fleet Operator Collection
      DocumentSnapshot fleetDoc = await _db
          .collection('fleet_operators')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (fleetDoc.exists) {
        Get.offAll(() => FleetDashboardScreen(user: user));
        return;
      }

      // --- NEW: Check for Pending Fleet Invite for NEW Users (No Driver Doc yet) ---
      if (user.phoneNumber != null) {
        final rawPhone = user.phoneNumber!.replaceFirst('+91', '');
        final pendingFleetDocs = await _db
            .collection('drivers')
            .where('phoneNumber', whereIn: [user.phoneNumber, rawPhone])
            .where('role', isEqualTo: 'fleet_driver')
            .get();

        // Filter out our own UID (though unlikely to match if we don't exist)
        final otherDocs = pendingFleetDocs.docs
            .where((d) => d.id != user.uid)
            .toList();

        if (otherDocs.isNotEmpty) {
          final pendingData = otherDocs.first.data();
          debugPrint(
            "DEBUG: Found pending fleet invite for NEW USER! Creating profile...",
          );

          // Create new driver doc with migrated data
          await _db.collection('drivers').doc(user.uid).set({
            ...pendingData,
            'uid': user.uid, // Ensure UID matches Auth UID
            'phoneNumber': user.phoneNumber, // Use authenticated phone number
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Delete the temporary pending doc
          await _db.collection('drivers').doc(otherDocs.first.id).delete();

          // Redirect
          Get.offAll(() => DriverVehicleSelectionScreen(user: user));
          return;
        }
      }
      // ---------------------------------------------------------------------------

      // If neither, likely registration incomplete or error
      Get.offAll(() => const LoginScreen());
      Get.snackbar("Error", "User profile not found. Please contact support.");
    } catch (e) {
      Get.snackbar("Error", "Failed to fetch user profile: $e");
      Get.offAll(() => const LoginScreen());
    }
  }

  Future<void> logout() async {
    // Force delete controllers to ensure their onClose() cancels Firestore streams,
    // thereby preventing permission-denied crashes upon sign out.
    Get.delete<HomePageController>(force: true);
    try {
      Get.delete<WalletController>(force: true);
    } catch (_) {}
    
    await _auth.signOut();
    Get.offAll(() => const LoginScreen());
  }
}
