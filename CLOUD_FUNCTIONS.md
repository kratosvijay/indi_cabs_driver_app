# Cloud Functions Implementation Guide

This project now includes comprehensive Firebase Cloud Functions for ride management:

## 📦 Cloud Functions

### 1. **distributeRideToDrivers**
- **Trigger**: Firestore onCreate (`ride_requests/{rideId}`)
- **Purpose**: Automatically distribute new ride requests to nearby drivers
- **Features**:
  - Finds online drivers within 10km radius
  - Filters by vehicle type
  - Respects blocked driver list (drivers who cancelled within 24 hours)
  - Distributes to top 3 closest drivers
  - Creates `notified_drivers` subcollection for tracking

### 2. **handleDriverCancellation**
- **Trigger**: Firestore onUpdate (`ride_requests/{rideId}`)
- **Purpose**: Handle driver cancellations and redistribute rides
- **Features**:
  - Blocks driver for 24 hours if they cancel before arriving
  - Updates ride status back to 'searching'
  - Clears driver assignment
  - Allows automatic redistribution

### 3. **calculateDynamicPricing**
- **Type**: Callable HTTPS function
- **Purpose**: Calculate final fare based on actual distance traveled
- **Tolerance Rules**:
  - **Extra Distance**: Up to 1.5km extra → no price update
  - **Less Distance**: Up to 5km less → no price update
- **Minimum Fare**: Always enforces the minimum fare from pricing rules
- **Examples**:
  - 10km estimated, 12km actual → Price updated (+2km exceeds tolerance)
  - 10km estimated, 11km actual → No update (1km within 1.5km tolerance)
  - 10km estimated, 3km actual → Price updated (-7km exceeds tolerance)
  - 10km estimated, 6km actual → No update (4km within 5km tolerance)
  - 0km actual → Minimum fare applied (e.g., ₹170 for Sedan)

### 4. **cleanupBlockedDrivers**
- **Trigger**: Scheduled (every 24 hours)
- **Purpose**: Remove expired driver blocks
- **Features**:
  - Runs daily to clean up blocked_drivers subcollections
  - Removes blocks where `blockedUntil` has passed

## 🚀 Deployment

### Prerequisites
1. Install Node.js dependencies:
```bash
cd functions
npm install
```

2. Build TypeScript:
```bash
npm run build
```

3. Deploy functions:
```bash
npm run deploy
```

Or deploy all at once:
```bash
firebase deploy --only functions
```

## 📊 Firestore Structure

### ride_requests/{rideId}
```
{
  status: 'searching' | 'accepted' | 'arrived' | 'started' | 'completed' | 'cancelled',
  driverId: string,
  safetyPin: string, // 4-digit OTP created by user app for ride verification
  actualDistance: number,
  finalAmount: number,
  priceUpdated: boolean,
  pricingReason: string,
  // ... other fields
}
```

### ride_requests/{rideId}/notified_drivers/{driverId}
```
{
  driverId: string,
  distance: number,
  notifiedAt: timestamp
}
```

### ride_requests/{rideId}/blocked_drivers/{driverId}
```
{
  blockedUntil: timestamp,
  reason: string
}
```

### ride_requests/{rideId}/messages/{messageId}
```
{
  text: string,
  senderId: string,
  timestamp: timestamp
}
```

### pricing_rules/Chennai
```
{
  city_name: "Chennai",
  currency_symbol: "₹",
  isSurgeActive: false,
  surgeMultiplier: 1,
  vehicle_types: {
    Sedan: {
      baseFare: 55,
      minimumFare: 170,
      perKilometer: 24,
      perMinute: 2
    },
    SUV: {
      baseFare: 100,
      minimumFare: 200,
      perKilometer: 32
    },
    // ... other vehicle types
  }
}
```

## 🔧 Flutter Integration

The app now calls the cloud function when ending a ride:

```dart
final callable = FirebaseFunctions.instance.httpsCallable('calculateDynamicPricing');
final result = await callable.call({
  'rideId': rideId,
  'actualDistanceKm': actualDistance,
});
```

## 🛡️ Security Rules

Ensure your `firestore.rules` allows:
- Drivers to read their assigned rides
- Cloud functions to write to all ride_requests
- Users to read/write their own messages

## 📝 Notes

- The pricing_rules collection should have a document named "Chennai" (or your city name)
- Each city document should contain a `vehicle_types` map with vehicle configurations
- Vehicle types must match the names used in ride requests (e.g., "Sedan", "SUV", "Auto")
- If pricing rules are not found, the function will use default values (baseFare: 50, perKm: 10)
- Make sure to run `npm install` in the functions directory to get the Firebase packages
