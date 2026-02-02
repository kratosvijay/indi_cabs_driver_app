IndiCabs - Driver App

This is the official Flutter application for drivers on the IndiCabs platform. It allows drivers to register, manage their documents, go on-duty, accept ride requests, navigate, and track their earnings.

This app works in conjunction with a separate Rider App and a backend (which may include Cloud Functions for ride matching and payments).

Features

Onboarding: A multi-page introduction to the app's features.

Multi-Language Support: UI supports English, Tamil, Hindi, Telugu, Kannada, Malayalam, and Gujarati.

Authentication:

Secure sign-up with Phone OTP verification.

Phone OTP login for existing users.

Registration flow for both Individual Drivers and Fleet Operators.

Driver Registration:

Profile creation with name, email, and profile picture upload.

Vehicle Details: Submission of car name, model, and vehicle number.

Document Upload: Multi-image upload for:

Driver's License (Front & Back)

Vehicle RC (Front & Back)

Aadhar Card (Front & Back)

PAN Card

Permit, Insurance, & Fitness certificates

Status Management:

Pending Verification: Drivers are locked in a "Pending" screen until an admin approves their documents.

Rejection Handling: Displays the admin's rejection reason and allows drivers to re-submit documents.

Core Home Screen:

Live Google Map centered on the driver's current location.

Duty Status Slider:

Off Duty: App is idle.

On Duty: Driver is active and listening for rides.

GoTo: Driver sets a custom destination to receive rides heading in that direction.

Ride Request Flow:

Listens for real-time ride requests based on vehicle type and driver's dutyPreferences.

Displays the closest ride request on a bottom-panel card.

Plays an alert sound and vibrates to notify the driver.

30-second countdown timer to accept or reject.

Drivers can reject rides; repeated rejections for the same ride are handled.

Ride In-Progress:

Live map with polyline route from driver to pickup.

Navigation button to open Google Maps.

"Arrived" slider to notify the user.

3-minute free wait timer; tracks waiting fee minutes afterward.

OTP Verification to start the ride.

Ability to cancel the ride with a specified reason.

Earnings & History:

Daily View: Scrollable calendar to check daily earnings, total rides, and ride list.

Weekly View: Scrollable weekly summary of earnings.

Monthly View: Scrollable monthly summary of earnings.

Ride Details: A detailed view of a past ride, including map, route, and fare.

Driver Profile:

View profile picture and name.

Check performance (Rating, Acceptance, Cancellation).

Navigate to update documents or change app language.

Delete Account: Securely delete the driver's auth record and Firestore document.

Tech Stack & Key Packages

Framework: Flutter & Dart

Backend: Firebase

Authentication: Phone Auth

Database: Cloud Firestore

Storage: Firebase Storage (for profile pictures & documents)

Mapping & Location:

Maps_flutter: For displaying the map.

geolocator: For real-time driver location updates.

flutter_polyline_points: To draw routes on the map.

http: For Google Places API (GoTo screen) & Directions API.

State Management: StatefulWidget & StreamBuilder (for live data).

Utilities:

shared_preferences: To store user's language and onboarding status.

flutter_dotenv: To securely manage API keys.

intl: For date and number formatting.

image_picker: For uploading documents.

audioplayers, vibration: For ride request alerts.

wakelock_plus: To keep the screen on while on-duty.

Setup Instructions

1. Prerequisites

Flutter SDK installed.

Firebase CLI installed (npm install -g firebase-tools).

A new project created on the Firebase Console.

2. Firebase Project Setup

Enable Services: In your Firebase Console, enable:

Authentication: Add the "Phone Number" sign-in provider.

Cloud Firestore: Create a database.

Storage: Create a storage bucket.

Add Your App: Add a new Android and/or iOS app to your Firebase project.

Android (Important): For Phone Auth to work, you must add your app's SHA-1 fingerprint to the Android app settings in the Firebase Console.

Google Maps:

Go to the Google Cloud Console for your Firebase project.

Enable the Maps SDK for Android, Maps SDK for iOS, Places API, and Directions API.

Copy your API Key.

3. Local Project Setup

Clone the Repository (or use your current code).

Create .env File: In the project's root directory (same level as pubspec.yaml), create a file named dotenv.env.

Add API Key: Add your Google Maps API key to this file:

GOOGLE_MAPS_API_KEY=YOUR_API_KEY_HERE


Install Dependencies:

flutter pub get


4. Deploy Backend Rules

Your app will not work without the correct server-side permissions. You must deploy the rules files from your project root.

Log in to Firebase:

firebase login


Initialize Firebase (if you haven't):

firebase init firestore
firebase init storage


(This links your local project to your Firebase project and pulls the default rules files. Overwrite them with the ones from this project).

Deploy Both Rules:

firebase deploy --only firestore,storage


5. Create Firestore Indexes (CRITICAL)

Your app's queries will fail (often with a PERMISSION_DENIED error) if these indexes are not built.

Go to your Firebase Console -> Cloud Firestore -> Indexes and create the following indexes:

Index 1: For Phone Number Login

Collection ID: drivers

Field 1: phoneNumber (Ascending)

Query scopes: Collection

Index 2: For Phone Number Login

Collection ID: fleet_operators

Field 1: phoneNumber (Ascending)

Query scopes: Collection

Index 3: For Driver Ride Requests (Homepage)

Collection ID: ride_requests

Field 1: status (Ascending)

Field 2: vehicleType (Ascending)

Query scopes: Collection

Index 4: For Driver Earnings (Homepage)

Collection ID: ride_requests

Field 1: driverId (Ascending)

Field 2: status (Ascending)

Field 3: createdAt (Descending)

Query scopes: Collection

6. Run the App

After the rules are deployed and the indexes are "Enabled" (this may take a few minutes), you can run your app:

flutter run
