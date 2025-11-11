import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

class SOSService {
  static Future<void> sendSosAlert() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ No user is currently signed in.');
        return;
      }

      final uid = user.uid;
      final db = FirebaseDatabase.instance.ref();

      // 🔹 1. Fetch user profile info
      final userSnapshot = await db.child('users/$uid').get();
      if (!userSnapshot.exists) {
        print('❌ No user data found in database for UID: $uid');
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

      // 🔹 2. Get current location
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print('❌ Location permission denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 🔹 3. Construct complete SOS alert payload (base info)
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
        'timestamp': DateTime.now().toIso8601String(),
        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
        },
      };

      // 🔹 4. Send to user's emergency contacts (sos_alerts)
      // ✅ Support both "contacts" and "sos_contacts" just in case
      DatabaseReference contactsRef = db.child('contacts/$uid');
      DataSnapshot contactsSnapshot = await contactsRef.get();

      if (!contactsSnapshot.exists) {
        // Try fallback node name if main is empty
        contactsRef = db.child('sos_contacts/$uid');
        contactsSnapshot = await contactsRef.get();
      }

      if (contactsSnapshot.exists) {
        final contacts = Map<String, dynamic>.from(contactsSnapshot.value as Map);

        for (final contactId in contacts.keys) {
          // 🚫 Prevent sending to self
          if (contactId == uid) {
            print('⚠️ Skipped sending SOS to self ($uid)');
            continue;
          }

          // 🧩 Add recipients list (for listener filtering)
          final updatedAlertData = Map<String, dynamic>.from(alertData);
          updatedAlertData['recipients'] = [contactId];

          // 📦 Save to sos_alerts node
          await db.child('sos_alerts/$contactId/$uid').set(updatedAlertData);
          print('📨 SOS sent to contact: $contactId');
        }
      } else {
        print('ℹ️ No emergency contacts found for this user.');
      }

      // 🔹 5. Send to responder_alerts (for real-time monitoring)
      await db.child('responder_alerts').push().set(alertData);
      print('🚨 SOS alert successfully pushed to responder_alerts.');

      // 🔹 6. Optional: log to sender’s own history
      await db.child('user_alerts/$uid').push().set(alertData);
      print('🗂️ SOS alert logged under user_alerts/$uid');

      // ✅ 7. Log success
      print("✅ SOS alert successfully sent to responders and contacts.");
    } catch (e) {
      print('❌ Error sending SOS alert: $e');
    }
  }
}