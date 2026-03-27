const admin = require('firebase-admin');

// Initialize with application default credentials
admin.initializeApp({
  // Provide the project ID so it knows what to query
  projectId: "indicabs-prod",
  databaseURL: "https://indicabs-prod-default-rtdb.firebaseio.com"
});

const db = admin.database();

async function checkDrivers() {
  console.log("Fetching driver_locations from RTDB...");
  const ref = db.ref('driver_locations');
  const snap = await ref.once('value');
  const data = snap.val();
  
  if (!data) {
    console.log("RTDB 'driver_locations' is EMPTY or NULL.");
  } else {
    console.log("RTDB Data:");
    console.log(JSON.stringify(data, null, 2));
    
    // Check timestamps
    const now = Date.now();
    for (const [id, loc] of Object.entries(data)) {
      console.log(`Driver ${id}:`);
      console.log(`  Age: ${(now - loc.updatedAt) / 1000} seconds`);
      console.log(`  Is older than 20s? ${(now - loc.updatedAt) > 20000}`);
      
      const doc = await admin.firestore().collection('drivers').doc(id).get();
      if (!doc.exists) {
        console.log(`  Firestore Doc: MISING!`);
      } else {
        const fdata = doc.data();
        console.log(`  isOnline: ${fdata.isOnline}`);
        console.log(`  status: ${fdata.status}`);
      }
    }
  }
  process.exit(0);
}

checkDrivers().catch(e => {
  console.error(e);
  process.exit(1);
});
