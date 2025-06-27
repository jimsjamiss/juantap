import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';
import 'email_service.dart';

class Registration extends StatefulWidget {
  const Registration({super.key});

  @override
  State<Registration> createState() => _RegistrationState();
}

class _RegistrationState extends State<Registration> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  String _selectedRole = 'user';

  String _generateOtp() {
    final random = Random();
    return (random.nextInt(900000) + 100000).toString(); // 6-digit OTP
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      try {
        final UserCredential credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        final user = credential.user;
        if (user != null) {
          await user.updateDisplayName(_nameController.text.trim());

          final dbRef = FirebaseDatabase.instance.ref("users/${user.uid}");
          await dbRef.set({
            "username": _nameController.text.trim(),
            "email": _emailController.text.trim(),
            "phone": _phoneController.text.trim(),
            "role": _selectedRole,
          });

          final otpCode = _generateOtp();
          final success = await EmailService.sendOtpEmail(
            userEmail: _emailController.text.trim(),
            otpCode: otpCode,
          );

          if (success) {
            _showOtpModal(otpCode);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Failed to send OTP email."), backgroundColor: Colors.red),
            );
          }
        }
      } on FirebaseAuthException catch (e) {
        String message = 'Registration failed.';
        if (e.code == 'email-already-in-use') {
          message = 'Email is already in use.';
        } else if (e.code == 'weak-password') {
          message = 'Password is too weak.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showOtpModal(String otpCode) {
    final TextEditingController _otpController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text("Verify Email"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter the 6-digit code sent to your email."),
              const SizedBox(height: 10),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: "Enter OTP"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (_otpController.text.trim() == otpCode) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Email verified!"), backgroundColor: Colors.green),
                  );
                  _clearFormAndGoBack();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Invalid OTP."), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text("Verify"),
            ),
          ],
        );
      },
    );
  }

  void _clearFormAndGoBack() {
    _nameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF417B63),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                color: Color(0xFFF7F6D9),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(140),
                ),
              ),
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 24),
              child: const Text(
                "Create Account",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 220, 32, 16),
            child: Center(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildField(_nameController, "Full Name", validator: (v) => v!.isEmpty ? "Required" : null),
                      _buildField(_emailController, "Email Address", validator: (v) {
                        if (v!.isEmpty) return "Required";
                        if (!RegExp(r'\S+@\S+\.\S+').hasMatch(v)) return "Invalid email";
                        return null;
                      }),
                      _buildField(_phoneController, "Phone Number", validator: (v) => v!.isEmpty ? "Required" : null),
                      _buildField(_passwordController, "Password", obscureText: !_isPasswordVisible, toggle: () {
                        setState(() => _isPasswordVisible = !_isPasswordVisible);
                      }, validator: (v) => v!.length < 6 ? "Min 6 chars" : null),
                      _buildField(_confirmPasswordController, "Confirm Password", obscureText: !_isConfirmPasswordVisible, toggle: () {
                        setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible);
                      }, validator: (v) => v != _passwordController.text ? "Passwords don't match" : null),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF7F6D9),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(40),
                            ),
                          ),
                          child: const Text("Sign Up"),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String hint,
      {bool obscureText = false, VoidCallback? toggle, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white70),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white70),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          suffixIcon: toggle != null
              ? IconButton(
            icon: Icon(
              obscureText ? Icons.visibility_off : Icons.visibility,
              color: Colors.white70,
            ),
            onPressed: toggle,
          )
              : null,
        ),
      ),
    );
  }
}