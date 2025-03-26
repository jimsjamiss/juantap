import 'package:flutter/material.dart';

class PreloaderScreen extends StatefulWidget {
  const PreloaderScreen({super.key});

  @override
  State<PreloaderScreen> createState() => _PreloaderScreenState();
}

class _PreloaderScreenState extends State<PreloaderScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // ✅ Important for overflow issues
      backgroundColor: const Color(0xFF3D8D7A),
      body: SizedBox.expand( // ✅ Prevents layout issues inside Center/Stack
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Spinning circle
              RotationTransition(
                turns: _controller,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.6),
                      width: 8,
                    ),
                  ),
                ),
              ),

              // Static logo
              Image.asset(
                'assets/images/app_logo.png',
                width: 80,
                height: 80,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
