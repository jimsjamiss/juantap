import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

class SOSService {
  static Future<void> sendSosAlert() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final uid = user.uid;
      final userRef = FirebaseDatabase.instance.ref('users/$uid');
      final contactsRef = FirebaseDatabase.instance.ref('contacts/$uid');
      final sosRef = FirebaseDatabase.instance.ref('sos_alerts');
      final responderAlertRef = FirebaseDatabase.instance.ref('responder_alerts');

      final userSnapshot = await userRef.get();
      if (!userSnapshot.exists) return;

      final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
      final username = userData['username'] ?? 'Unknown';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // Send to contacts
      final contactsSnapshot = await contactsRef.get();
      if (contactsSnapshot.exists) {
        final contacts = Map<String, dynamic>.from(contactsSnapshot.value as Map);
        for (final contactId in contacts.keys) {
          await sosRef.child(contactId).child(uid).child('location').set({
            'username': username,
            'timestamp': DateTime.now().toIso8601String(),
            'lat': position.latitude,
            'lng': position.longitude,
          });
        }
      }

      // Send to responders
      final newResponderRef = responderAlertRef.push();
      await newResponderRef.set({
        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
          'userId': uid,
          'username': username,
        }
      });

      print("🚨 SOS sent successfully via SOSService");
    } catch (e) {
      print('❌ Error sending SOS: $e');
    }
  }
}