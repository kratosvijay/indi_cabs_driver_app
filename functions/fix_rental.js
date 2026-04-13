const admin = require("firebase-admin");
const serviceAccount = require("/tmp/firebasekey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: "indicabs-prod"
});

const db = admin.firestore();

async function fixRental() {
  console.log("Moving rental ride to correct collection...");
  
  try {
    // Get the ride from ride_requests
    const rideDoc = await db.collection("ride_requests").doc("ID000000000000004").get();
    
    if (rideDoc.exists) {
      const data = rideDoc.data();
      
      // Copy to rental_requests
      await db.collection("rental_requests").doc("ID000000000000004").set(data);
      console.log("✓ Rental ride created in rental_requests collection");
      
      // Keep it in ride_requests too for reference
      console.log("✓ Also keeping copy in ride_requests for driver app access");
    } else {
      console.log("✗ Rental ride not found in ride_requests");
    }
    
    process.exit(0);
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
}

fixRental();
