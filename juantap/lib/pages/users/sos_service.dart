import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';   // <-- ADD THIS
import 'package:http/http.dart' as http;
import 'dart:convert';

class SOSService {

  static DateTime? _lastSosTime; // <--- ADD THIS

  // ===========================================================
  //  ORS Reverse Geocoding (Exact place names from OpenRouteService)
  // ===========================================================
  static Future<String> getPlaceNameFromORS(double lat, double lng) async {
    const String apiKey = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjZkNTQ2YzZmZmE0ZDQ0Yzc5OWFiMTQ3Yzg2ZTllZTI5IiwiaCI6Im11cm11cjY0In0=";

    final url = Uri.parse(
        "https://api.openrouteservice.org/geocode/reverse"
            "?api_key=$apiKey"
            "&point.lat=$lat"
            "&point.lon=$lng"
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["features"] != null && data["features"].isNotEmpty) {
          final props = data["features"][0]["properties"];

          return [
            props["name"],
            props["street"],
            props["locality"],
            props["county"],
            props["region"],
            props["country"],
          ].where((e) => e != null && e.toString().trim().isNotEmpty).join(", ");
        }
      }

      return "Unknown Location";
    } catch (e) {
      print("❌ ORS Geocode Error: $e");
      return "Unknown Location";
    }
  }

  // ===========================================================
  //  Convert lat/lng → human readable place name (Reverse Geocode)
  // ===========================================================
  static Future<String> _getPlaceName(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        return [
          p.name,
          p.street,
          p.locality,
          p.subLocality,
          p.administrativeArea,
          p.country
        ].where((e) => e != null && e!.trim().isNotEmpty).join(", ");
      }

      return "Unknown Location";
    } catch (e) {
      print("❌ Reverse geocoding error: $e");
      return "Unknown Location";
    }
  }

  // ===================================================================
  //  DEFAULT SOS (Without Proof)
  // ===================================================================

  static Future<void> sendSosAlert() async {


    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ No user signed in.');
        return;
      }

      final uid = user.uid;
      final db = FirebaseDatabase.instance.ref();

      // 🔹 Fetch user profile
      final userSnapshot = await db.child("users/$uid").get();
      if (!userSnapshot.exists) {
        print('❌ User data not found for UID: $uid');
        return;
      }

      final userData = Map<String, dynamic>.from(userSnapshot.value as Map);

      final username = userData['username'] ?? 'Unknown';
      final email = userData['email'] ?? '';
      final phone = userData['phone'] ?? '';
      final address = userData['address'] ?? '';
      final birthdate = userData['birthdate'] ?? '';
      final nationality = userData['nationality'] ?? '';
      final profileImage = userData['profileImage'] ?? '';

      // 🔹 Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print("❌ Location permission denied.");
        return;
      }

      // 🔹 Get location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // NEW — Convert coordinates into a readable place
      final placeName = await getPlaceNameFromORS(
        position.latitude,
        position.longitude,
      );


      final timestamp = DateTime.now().toIso8601String();

      // 🔹 Build alert payload (NO PROOF)
      final alertData = {
        'userId': uid,
        'username': username,
        'email': email,
        'phone': phone,
        'address': address,
        'birthdate': birthdate,
        'nationality': nationality,
        'profileImage': profileImage,
        'reason': 'SOS Alert',
        'timestamp': timestamp,
        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
          'placeName': placeName,
        },

        'crimeType': null,
        'proofUrl': null,
        'isVideo': null,
      };

      // 🔹 Send to Contacts
      DatabaseReference contactsRef = db.child("contacts/$uid");
      DataSnapshot contactsSnapshot = await contactsRef.get();

      // fallback
      if (!contactsSnapshot.exists) {
        contactsRef = db.child("sos_contacts/$uid");
        contactsSnapshot = await contactsRef.get();
      }

      if (contactsSnapshot.exists) {
        final contacts = Map<String, dynamic>.from(contactsSnapshot.value as Map);

        for (final contactId in contacts.keys) {
          if (contactId == uid) continue;

          await db.child("sos_alerts/$contactId/$uid").set(alertData);
          print("📨 Sent SOS to contact: $contactId");
        }
      } else {
        print("ℹ️ No emergency contacts found.");
      }

      // 🔹 Send to Responders
      await db.child("responder_alerts").push().set(alertData);
      print("🚨 Sent SOS to responder_alerts.");

      // 🔹 Save to History
      await db.child("user_alerts/$uid").push().set(alertData);
      print("🗂️ Saved SOS to user history.");

      print("✅ SOS alert sent successfully (NO PROOF).");

    } catch (e) {
      print("❌ Error sending SOS: $e");
    }
  }

  // ===================================================================
  //  SOS WITH PHOTO / VIDEO PROOF + CRIME TYPE
  // ===================================================================
  static Future<void> sendSosAlertWithProof({
    required String proofUrl,
    required bool isVideo,
    required String crimeType,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("❌ No user signed in.");
        return;
      }

      final uid = user.uid;
      final db = FirebaseDatabase.instance.ref();

      // 🔹 Fetch user profile
      final userSnapshot = await db.child("users/$uid").get();
      if (!userSnapshot.exists) {
        print("❌ User data not found for UID: $uid");
        return;
      }

      final userData = Map<String, dynamic>.from(userSnapshot.value as Map);

      final username = userData['username'] ?? 'Unknown';
      final email = userData['email'] ?? '';
      final phone = userData['phone'] ?? '';
      final address = userData['address'] ?? '';
      final birthdate = userData['birthdate'] ?? '';
      final nationality = userData['nationality'] ?? '';
      final profileImage = userData['profileImage'] ?? '';

      // 🔹 Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print("❌ Location permission denied.");
        return;
      }

      // 🔹 Get accurate location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final placeName = await getPlaceNameFromORS(
        position.latitude,
        position.longitude,
      );

      final timestamp = DateTime.now().toIso8601String();

      // 🔹 Build full alert with proof
      final alertData = {
        'userId': uid,
        'username': username,
        'email': email,
        'phone': phone,
        'address': address,
        'birthdate': birthdate,
        'nationality': nationality,
        'profileImage': profileImage,

        'reason': 'SOS Alert',
        'crimeType': crimeType,
        'proofUrl': proofUrl,
        'isVideo': isVideo,

        'timestamp': timestamp,

        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
          'placeName': placeName,
        }
      };

      // 🔹 Send to Contacts
      DatabaseReference contactsRef = db.child("contacts/$uid");
      DataSnapshot contactsSnapshot = await contactsRef.get();

      // fallback
      if (!contactsSnapshot.exists) {
        contactsRef = db.child("sos_contacts/$uid");
        contactsSnapshot = await contactsRef.get();
      }

      if (contactsSnapshot.exists) {
        final contacts = Map<String, dynamic>.from(contactsSnapshot.value as Map);

        for (final contactId in contacts.keys) {
          if (contactId == uid) continue;

          await db.child("sos_alerts/$contactId/$uid").set(alertData);
          print("📨 Sent SOS WITH PROOF to contact: $contactId");
        }
      } else {
        print("ℹ️ No emergency contacts found.");
      }

      // 🔹 Send to Responders (real-time)
      await db.child("responder_alerts").push().set(alertData);
      print("🚨 Sent SOS WITH PROOF to responder_alerts.");

      // 🔹 Save to History
      await db.child("user_alerts/$uid").push().set(alertData);
      print("🗂️ Saved SOS WITH PROOF to user history.");

      print("✅ SOS alert WITH PROOF sent successfully.");

    } catch (e) {
      print("❌ Error sending SOS with proof: $e");
    }
  }
}