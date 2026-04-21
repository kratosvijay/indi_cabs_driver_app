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
  /// [externalUser] can be passed directly from login screens for immediate navigation.
  Future<void> decideRoute({DriverStatus? initialStatus, User? externalUser}) async {
    // Priority: Explicitly passed user, then current firebase user Rx value, then FirebaseAuth instance.
    User? user = externalUser ?? firebaseUser.value ?? _auth.currentUser;

    if (user == null) {
      debugPrint("Auth: No user found in decideRoute. Redirecting to Login.");
      Get.offAll(() => const LoginScreen());
      return;
    }

    try {
      // Check Driver Collection by Querying UID field
      // This is necessary because document IDs will now be human-readable (indi-drv-X)
      // but Auth provides the randomized Firebase UID.
      QuerySnapshot<Map<String, dynamic>> driverQuery = await _db
          .collection('drivers')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      // --- FALLBACK: If UID search fails, search by Phone Number ---
      if (driverQuery.docs.isEmpty && user.phoneNumber != null) {
        debugPrint(
          "Auth: UID match failed. Attempting PhoneNumber fallback for Drivers...",
        );
        final rawPhone = user.phoneNumber!.replaceFirst('+91', '');
        driverQuery = await _db
            .collection('drivers')
            .where('phoneNumber', whereIn: [user.phoneNumber, rawPhone])
            .limit(1)
            .get(const GetOptions(source: Source.server));

        if (driverQuery.docs.isNotEmpty) {
          final docId = driverQuery.docs.first.id;
          debugPrint("Auth: Found driver by phone ($docId). Updating UID link.");
          await _db.collection('drivers').doc(docId).update({'uid': user.uid});
        }
      }

      if (driverQuery.docs.isNotEmpty) {
        final driverDoc = driverQuery.docs.first;
        final driverDocId = driverDoc.id; // Correct Document ID (e.g. indi-drv-1)
        final data = driverDoc.data();

        // Persist the Document ID for use in other screens
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('driverDocId', driverDocId);

        // --- NEW: Check for Active Rides to Restore State ---
        try {
          QuerySnapshot<Map<String, dynamic>> activeRidesSnapshot = await _db
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
              // Skip restoration if the ride was completed more than 2 hours ago
              bool isStale = false;
              final doneRideData = rideDoc.data();
              final completedAt = doneRideData['completedAt'] ??
                  doneRideData['updatedAt'] ??
                  doneRideData['createdAt'];
              if (completedAt is Timestamp) {
                final age = DateTime.now().difference(completedAt.toDate());
                if (age.inHours >= 2) {
                  debugPrint(
                    "DEBUG: Skipping stale completed ride (${age.inHours}h old).",
                  );
                  isStale = true;
                }
              }

              if (!isStale) {
                // Check if earnings record exists.
                // Query by rideId only — driverId in earnings is the professional ID,
                // NOT the auth UID, so filtering by user.uid would never match.
                final earningsSnapshot = await _db
                    .collection('earnings')
                    .where('rideId', isEqualTo: rideRequest.rideId)
                    .limit(1)
                    .get();

                if (earningsSnapshot.docs.isEmpty) {
                  debugPrint(
                    "DEBUG: Restoring RidePaymentScreen (No earnings found)",
                  );
                  Get.offAll(
                    () => RidePaymentScreen(
                      rideRequest: rideRequest,
                      totalAmount: rideRequest.rideFare,
                    ),
                  );
                  return;
                }
                debugPrint(
                  "DEBUG: Completed ride has earnings. Skipping restore.",
                );
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
        final String? phoneNumber = user.phoneNumber;
        if (phoneNumber != null && phoneNumber.isNotEmpty) {
          final rawPhone = phoneNumber.replaceFirst('+91', '');
          // Check both formatted (+91) and raw number
          final QuerySnapshot<Map<String, dynamic>> pendingFleetDocs = await _db
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

      // --- FALLBACK: If UID search fails, search by Phone Number ---
      if (!fleetDoc.exists && user.phoneNumber != null) {
        debugPrint(
          "Auth: Fleet Operator UID match failed. Attempting PhoneNumber fallback...",
        );
        final rawPhone = user.phoneNumber!.replaceFirst('+91', '');
        final QuerySnapshot<Map<String, dynamic>> fleetQuery = await _db
            .collection('fleet_operators')
            .where('phoneNumber', whereIn: [user.phoneNumber, rawPhone])
            .limit(1)
            .get();

        if (fleetQuery.docs.isNotEmpty) {
          final oldDoc = fleetQuery.docs.first;
          debugPrint(
            "Auth: Found fleet operator by phone (${oldDoc.id}). Migrating to new UID...",
          );

          // Migrate document to new UID key
          final data = oldDoc.data();
          data['uid'] = user.uid; // Ensure UID is updated in data

          await _db.collection('fleet_operators').doc(user.uid).set(data);
          await _db.collection('fleet_operators').doc(oldDoc.id).delete();

          // Refresh fleetDoc for subsequent logic
          fleetDoc = await _db.collection('fleet_operators').doc(user.uid).get();
        }
      }

      if (fleetDoc.exists) {
        Get.offAll(() => FleetDashboardScreen(user: user));
        return;
      }

      // --- NEW: Check for Pending Fleet Invite for NEW Users (No Driver Doc yet) ---
      if (user.phoneNumber != null) {
        final rawPhone = user.phoneNumber!.replaceFirst('+91', '');
        final QuerySnapshot<Map<String, dynamic>> pendingFleetDocs = await _db
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
