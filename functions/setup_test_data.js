const admin = require("firebase-admin");
const serviceAccount = require("/tmp/firebasekey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: "indicabs-prod"
});

const db = admin.firestore();

async function setupTestData() {
  try {
    console.log("Creating geofenced zones...");

    // Kolappancheri Toll
    await db.collection("geofenced_zones").doc("Kolappancheri_Toll").set({
      boundary: [
        new admin.firestore.GeoPoint(13.0686, 80.0773),
        new admin.firestore.GeoPoint(13.0686, 80.0713),
        new admin.firestore.GeoPoint(13.0626, 80.0713),
        new admin.firestore.GeoPoint(13.0626, 80.0773)
      ],
      surcharge_amount: 30
    });
    console.log("✓ Kolappancheri_Toll created");

    // Tambaram Toll
    await db.collection("geofenced_zones").doc("Tambaram_Toll").set({
      boundary: [
        new admin.firestore.GeoPoint(12.9200, 80.1270),
        new admin.firestore.GeoPoint(12.9200, 80.1220),
        new admin.firestore.GeoPoint(12.9150, 80.1220),
        new admin.firestore.GeoPoint(12.9150, 80.1270)
      ],
      surcharge_amount: 25
    });
    console.log("✓ Tambaram_Toll created");

    console.log("\nCreating test rides...");

    // Test Ride 1: Daily - Toll Crossed
    await db.collection("ride_requests").doc("ID000000000000001").set({
      rideId: "ID000000000000001",
      userId: "test_user_1",
      driverId: "test_driver_1",
      rideType: "daily",
      status: "completed",
      pickupTitle: "Velachery",
      pickupPlaceName: "Velachery Metro Station",
      pickupFullAddress: "Velachery, Chennai, Tamil Nadu",
      pickupLocation: new admin.firestore.GeoPoint(12.9700, 80.1100),
      dropoffTitle: "Tambaram",
      dropoffPlaceName: "Tambaram Station",
      dropoffFullAddress: "Tambaram, Chennai, Tamil Nadu",
      dropoffLocation: new admin.firestore.GeoPoint(12.9100, 80.1250),
      rideDistance: 15.5,
      rideFare: 350,
      tollPrice: 25,
      vehicleType: "Sedan",
      vehicleClass: "Sedan",
      paymentMethod: "Cash",
      safetyPin: "1234",
      convenienceFee: 0,
      waitingCharge: 0,
      createdAt: new Date(1715000000000),
      startedAt: new Date(1715000300000),
      actualDistance: 16,
      actualDuration: 25,
      completedAt: new Date()
    });
    console.log("✓ Test Ride 1 created (Toll Crossed)");

    // Test Ride 2: Daily - Toll NOT Crossed
    await db.collection("ride_requests").doc("ID000000000000002").set({
      rideId: "ID000000000000002",
      userId: "test_user_2",
      driverId: "test_driver_1",
      rideType: "daily",
      status: "completed",
      pickupTitle: "Mylapore",
      pickupPlaceName: "Mylapore Temple",
      pickupFullAddress: "Mylapore, Chennai, Tamil Nadu",
      pickupLocation: new admin.firestore.GeoPoint(13.0349, 80.2707),
      dropoffTitle: "Adyar",
      dropoffPlaceName: "Adyar Park",
      dropoffFullAddress: "Adyar, Chennai, Tamil Nadu",
      dropoffLocation: new admin.firestore.GeoPoint(13.0047, 80.2434),
      rideDistance: 8.5,
      rideFare: 250,
      tollPrice: 30,
      vehicleType: "Sedan",
      vehicleClass: "Sedan",
      paymentMethod: "Cash",
      safetyPin: "5678",
      convenienceFee: 0,
      waitingCharge: 0,
      createdAt: new Date(1715001000000),
      startedAt: new Date(1715001300000),
      actualDistance: 9,
      actualDuration: 18,
      completedAt: new Date()
    });
    console.log("✓ Test Ride 2 created (Toll NOT Crossed)");

    // Test Ride 3: Daily - Distance Tolerance Exceeded
    await db.collection("ride_requests").doc("ID000000000000003").set({
      rideId: "ID000000000000003",
      userId: "test_user_3",
      driverId: "test_driver_2",
      rideType: "daily",
      status: "completed",
      pickupTitle: "Velachery",
      pickupPlaceName: "Phoenix Mall",
      pickupFullAddress: "Phoenix Mall, Velachery, Chennai",
      pickupLocation: new admin.firestore.GeoPoint(12.9700, 80.1100),
      dropoffTitle: "Mahabalipuram",
      dropoffPlaceName: "Mahabalipuram Beach",
      dropoffFullAddress: "Mahabalipuram, Tamil Nadu",
      dropoffLocation: new admin.firestore.GeoPoint(12.6273, 80.1925),
      rideDistance: 40.0,
      rideFare: 900,
      tollPrice: 25,
      vehicleType: "Sedan",
      vehicleClass: "Sedan",
      paymentMethod: "Cash",
      safetyPin: "9012",
      convenienceFee: 0,
      waitingCharge: 0,
      createdAt: new Date(1715002000000),
      startedAt: new Date(1715002300000),
      actualDistance: 42.5,
      actualDuration: 65,
      completedAt: new Date()
    });
    console.log("✓ Test Ride 3 created (Tolerance Exceeded)");

    // Test Ride 4: Rental - Toll Crossed
    await db.collection("ride_requests").doc("ID000000000000004").set({
      rideId: "ID000000000000004",
      userId: "test_user_4",
      driverId: "test_driver_3",
      rideType: "rental",
      status: "completed",
      pickupTitle: "Velachery",
      pickupPlaceName: "Velachery",
      pickupFullAddress: "Velachery, Chennai",
      pickupLocation: new admin.firestore.GeoPoint(12.9700, 80.1100),
      dropoffTitle: "Tambaram",
      dropoffPlaceName: "Tambaram",
      dropoffFullAddress: "Tambaram, Chennai",
      dropoffLocation: new admin.firestore.GeoPoint(12.9100, 80.1250),
      packageName: "4-Hour Package",
      durationHours: 4,
      kmLimit: 50,
      rideFare: 500,
      extraHourCharge: 100,
      extraKmCharge: 10,
      vehicleType: "Sedan",
      vehicleClass: "Sedan",
      paymentMethod: "Card",
      startRidePin: "1111",
      endRidePin: "2222",
      createdAt: new Date(1715003000000),
      startedAt: new Date(1715003300000),
      actualDistance: 20,
      actualDuration: 240,
      completedAt: new Date()
    });
    console.log("✓ Test Ride 4 created (Rental + Toll)");

    // Test Ride 5: Multiple Tolls Crossed
    await db.collection("ride_requests").doc("ID000000000000005").set({
      rideId: "ID000000000000005",
      userId: "test_user_5",
      driverId: "test_driver_1",
      rideType: "daily",
      status: "completed",
      pickupTitle: "Velachery",
      pickupPlaceName: "Velachery",
      pickupFullAddress: "Velachery, Chennai",
      pickupLocation: new admin.firestore.GeoPoint(12.9700, 80.1100),
      dropoffTitle: "Chengalpattu",
      dropoffPlaceName: "Chengalpattu",
      dropoffFullAddress: "Chengalpattu, Tamil Nadu",
      dropoffLocation: new admin.firestore.GeoPoint(12.6704, 80.0772),
      rideDistance: 35.0,
      rideFare: 800,
      tollPrice: 55,
      vehicleType: "Sedan",
      vehicleClass: "Sedan",
      paymentMethod: "Cash",
      safetyPin: "3456",
      convenienceFee: 0,
      waitingCharge: 0,
      createdAt: new Date(1715004000000),
      startedAt: new Date(1715004300000),
      actualDistance: 35,
      actualDuration: 55,
      completedAt: new Date()
    });
    console.log("✓ Test Ride 5 created (Multiple Tolls)");

    // Test Ride 6: Waiting Charges
    await db.collection("ride_requests").doc("ID000000000000006").set({
      rideId: "ID000000000000006",
      userId: "test_user_6",
      driverId: "test_driver_2",
      rideType: "daily",
      status: "completed",
      pickupTitle: "Airport",
      pickupPlaceName: "Chennai Airport",
      pickupFullAddress: "Chennai Airport, Minambakkam",
      pickupLocation: new admin.firestore.GeoPoint(12.9942, 80.1608),
      dropoffTitle: "Downtown",
      dropoffPlaceName: "Downtown Chennai",
      dropoffFullAddress: "Downtown, Chennai",
      dropoffLocation: new admin.firestore.GeoPoint(13.0827, 80.2707),
      rideDistance: 12.0,
      rideFare: 300,
      tollPrice: 0,
      vehicleType: "Sedan",
      vehicleClass: "Sedan",
      paymentMethod: "Cash",
      safetyPin: "7890",
      convenienceFee: 0,
      waitingCharge: 6,
      createdAt: new Date(1715005000000),
      startedAt: new Date(1715005300000),
      actualDistance: 12,
      actualDuration: 25,
      completedAt: new Date()
    });
    console.log("✓ Test Ride 6 created (Waiting Charges)");

    console.log("\n✅ All test data created successfully!");
    process.exit(0);
  } catch (err) {
    console.error("Error:", err);
    process.exit(1);
  }
}

setupTestData();
