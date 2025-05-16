import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
      home: const AuthGate(), // NEW: Auth checker
      routes: {
        '/home': (context) => HomePage(),
        '/login': (context) => LoginPage(),
        '/registration': (context) => Registration(),
        '/edit_profile': (context) => EditProfilePage(),
        '/maps_location': (context) => MapsLocation(),
        '/check_in': (context) => CheckInPage(),
        '/contact_lists': (context) => ContactListPage(),
        '/contact_lists_requests': (context) => ContactListsRequestsPage(),
        // '/call_page': (context) => CallPage
        //   (
        //     userID: FirebaseAuth.instance.currentUser!.uid,
        //     userName: FirebaseAuth.instance.currentUser!.displayName ?? 'User',
        //   ),
      },
    );
  }
}

// NEW: Auth Gate to handle login state
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(); // while loading
        } else if (snapshot.hasData) {
          return HomePage(); // user is logged in
        } else {
          return LoginPage(); // not logged in
        }
      },
    );
  }
}
