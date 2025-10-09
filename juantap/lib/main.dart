import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'firebase_options.dart';

// ✅ Import your pages
import 'package:juantap/pages/admin/admin.dart';
import 'package:juantap/pages/responders/responder.dart';
import 'package:juantap/pages/users/home.dart';
import 'package:juantap/pages/users/login.dart';
import 'package:juantap/pages/users/splash_screen.dart';
import 'package:juantap/pages/users/signup.dart';
import 'package:juantap/pages/users/edit_profile.dart';
import 'package:juantap/pages/users/maps_location.dart';
import 'package:juantap/pages/users/check_in.dart';
import 'package:juantap/pages/users/contact_lists.dart';
import 'package:juantap/pages/users/contact_lists_requests.dart';
import 'package:juantap/pages/responders/edit_responder_profile.dart';

// 🧩 New import for admin login
import 'package:juantap/pages/admin/admin_login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb) {
      debugPrint("🌐 Running on Web — initializing Firebase Web manually...");

      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyB4lyiOI8bUh9QbjTAUD6B2fl62U9eu8ZU",
          authDomain: "juantap-db-2dbeb.firebaseapp.com",
          databaseURL: "https://juantap-db-2dbeb-default-rtdb.firebaseio.com",
          projectId: "juantap-db-2dbeb",
          storageBucket: "juantap-db-2dbeb.appspot.com",
          messagingSenderId: "201901470099",
          appId: "1:201901470099:web:bd254aa6d087968438b866",
          measurementId: "G-M02NM47ELK",
        ),
      );
      debugPrint("✅ Firebase Web initialized successfully");
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint("📱 Firebase initialized for Mobile/Desktop");
    }
  } catch (e, stack) {
    debugPrint("🔥 Firebase init error: $e");
    debugPrintStack(stackTrace: stack);
  }

  runApp(const JuanTap());
}

class JuanTap extends StatelessWidget {
  const JuanTap({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JuanTap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),

      // 🧭 Show admin login as the first view on Web
      home: kIsWeb
          ? (FirebaseAuth.instance.currentUser == null
          ? const AdminLoginPage()
          : const AdminDashboardPage())
          : const AuthGate(),

      routes: {
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/registration': (context) => const Registration(),
        '/edit_profile': (context) => const EditProfilePage(),
        '/maps_location': (context) => const MapsLocation(),
        '/check_in': (context) => CheckInPage(),
        '/contact_lists': (context) => ContactListPage(),
        '/contact_lists_requests': (context) =>
            ContactListsRequestsPage(),
        '/responderDashboard': (context) => const ResponderDashboard(),
        '/admin': (context) => const AdminDashboardPage(),
        '/edit_responder_profile': (context) =>
        const EditResponderProfilePage(),

        // 🆕 Added route for admin login
        '/admin_login': (context) => const AdminLoginPage(),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Widget> _determineHomeScreen(User user) async {
    try {
      final roleSnapshot =
      await FirebaseDatabase.instance.ref('users/${user.uid}/role').get();
      final role = roleSnapshot.value;

      if (role == 'admin') {
        return const AdminDashboardPage();
      } else if (role == 'responder') {
        return const ResponderDashboard();
      } else {
        return const HomePage();
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching user role: $e");
      return const LoginPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        } else if (snapshot.hasData) {
          return FutureBuilder<Widget>(
            future: _determineHomeScreen(snapshot.data!),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const SplashScreen();
              } else {
                return roleSnapshot.data ?? const LoginPage();
              }
            },
          );
        } else {
          return const LoginPage();
        }
      },
    );
  }
}
