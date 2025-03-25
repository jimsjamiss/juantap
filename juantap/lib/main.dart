import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:juantap/pages/users/home.dart';
import 'package:juantap/pages/users/login.dart';
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
      initialRoute: '/',
      routes: {
        '/': (context) => SplashScreen(),
        '/home': (context) => HomePage(),
        '/login': (context) => LoginPage(),
        '/registration': (context) => Registration(),
      },
    );
  }
}