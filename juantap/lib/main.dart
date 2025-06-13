import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:juantap/pages/admin/admin.dart';
import 'package:juantap/pages/responders/responder.dart';
import 'package:juantap/pages/users/call_page.dart';
import 'package:juantap/pages/users/check_in.dart';
import 'package:juantap/pages/users/contact_lists.dart';
import 'package:juantap/pages/users/contact_lists_requests.dart';
import 'package:juantap/pages/users/edit_profile.dart';
import 'package:juantap/pages/users/home.dart';
import 'package:juantap/pages/users/login.dart';
import 'package:juantap/pages/users/maps_location.dart';
import 'package:juantap/pages/users/signup.dart';
import 'package:juantap/pages/users/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const JuanTap());
}

class JuanTap extends StatelessWidget {
  const JuanTap({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'JuanTap',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthGate(),
      routes: {
        '/home': (context) => HomePage(),
        '/login': (context) => LoginPage(),
        '/registration': (context) => Registration(),
        '/edit_profile': (context) => EditProfilePage(),
        '/maps_location': (context) => MapsLocation(),
        '/check_in': (context) => CheckInPage(),
        '/contact_lists': (context) => ContactListPage(),
        '/contact_lists_requests': (context) => ContactListsRequestsPage(),
        '/adminDashboard': (context) => const admin(),
        '/responderDashboard': (context) => const ResponderDashboard(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Widget> _determineHomeScreen(User user) async {
    final roleSnapshot = await FirebaseDatabase.instance.ref('users/${user.uid}/role').get();
    final role = roleSnapshot.value;

    if (role == 'admin') {
      return const admin();
    } else if (role == 'responder') {
      return const ResponderDashboard();
    } else {
      return const HomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(); // While loading
        } else if (snapshot.hasData) {
          // If user is logged in, determine role
          return FutureBuilder<Widget>(
            future: _determineHomeScreen(snapshot.data!),
            builder: (context, futureSnapshot) {
              if (futureSnapshot.connectionState == ConnectionState.waiting) {
                return const SplashScreen(); // Waiting for role fetch
              } else if (futureSnapshot.hasData) {
                return futureSnapshot.data!;
              } else {
                return const LoginPage(); // Fallback on error
              }
            },
          );
        } else {
          return const LoginPage(); // Not logged in
        }
      },
    );
  }
}