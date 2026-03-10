import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/user/data/user_firestore_repository.dart';
import 'package:govipservices/features/user/models/app_user.dart';
import 'package:govipservices/features/user/models/user_phone.dart';
import 'package:govipservices/features/user/models/user_role.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final UserFirestoreRepository _userRepo = UserFirestoreRepository();

  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _countryCodeController = TextEditingController(text: '+225');
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  bool get _returnToCaller {
    final Object? args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      return args['returnToCaller'] == true;
    }
    return false;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _countryCodeController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFF991B1B) : const Color(0xFF0F766E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);
    try {
      final UserCredential credentials = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final User? authUser = credentials.user;
      if (authUser == null) {
        throw FirebaseAuthException(code: 'null-user', message: 'Compte non cree');
      }

      final String displayName = _displayNameController.text.trim();
      await authUser.updateDisplayName(displayName);

      final String phone = _phoneController.text.trim();
      final UserPhone? userPhone = phone.isEmpty
          ? null
          : UserPhone(
              countryCode: _countryCodeController.text.trim(),
              number: phone,
            );

      final AppUser user = AppUser(
        uid: authUser.uid,
        email: _emailController.text.trim(),
        displayName: displayName.isEmpty ? null : displayName,
        role: UserRole.simpleUser,
        phone: userPhone,
        photoURL: authUser.photoURL,
        materialPhotoUrl: null,
        service: null,
        isServiceProvider: false,
        createdAt: null,
        updatedAt: null,
        archived: false,
        meta: <String, dynamic>{
          'authEmailSource': 'firebase_auth',
          if (displayName.isNotEmpty) 'firstName': displayName.split(' ').first,
        },
      );

      try {
        await _userRepo.setUser(authUser.uid, user);
      } on FirebaseException catch (e) {
        _showMessage(
          'Compte cree, mais profil non enregistre (${e.code})${e.message == null ? '' : ' - ${e.message}'}',
          error: true,
        );
        return;
      }

      if (!mounted) return;
      _showMessage('Compte cree avec succes.');
      if (_returnToCaller) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(
        '${_authErrorToText(e)} (${e.code})${e.message == null ? '' : ' - ${e.message}'}',
        error: true,
      );
    } on FirebaseException catch (e) {
      _showMessage(
        'Creation du compte impossible (${e.code})${e.message == null ? '' : ' - ${e.message}'}',
        error: true,
      );
    } catch (e, s) {
      debugPrint('signup unknown error: $e');
      debugPrintStack(stackTrace: s);
      _showMessage('Cr\u00E9ation du compte impossible pour le moment. [$e]', error: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0F9FF), Color(0xFFECFDF5), Color(0xFFF8FAFC)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 0,
                  color: Colors.white.withOpacity(0.95),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SignupHeader(),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _displayNameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Nom complet',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().length < 2) return 'Nom trop court';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (value) {
                              final String v = (value ?? '').trim();
                              if (v.isEmpty || !v.contains('@')) return 'Email invalide';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _countryCodeController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Indicatif',
                                    prefixIcon: Icon(Icons.flag_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 4,
                                child: TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'T\u00E9l\u00E9phone (optionnel)',
                                    prefixIcon: Icon(Icons.phone_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _hidePassword,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if ((value ?? '').length < 6) return '6 caracteres minimum';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _hideConfirmPassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Confirmer le mot de passe',
                              prefixIcon: const Icon(Icons.lock_reset_outlined),
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _hideConfirmPassword = !_hideConfirmPassword),
                                icon: Icon(
                                  _hideConfirmPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value != _passwordController.text) return 'Les mots de passe diffèrent';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              child: Text(_isSubmitting ? 'Cr\u00E9ation...' : 'Cr\u00E9er mon compte'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('D\u00E9j\u00E0 inscrit ?'),
                              TextButton(
                                onPressed: () => Navigator.of(context).pushReplacementNamed(
                                  AppRoutes.authLogin,
                                ),
                                child: const Text('Se connecter'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _authErrorToText(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Cet email est d\u00E9j\u00E0 utilis\u00E9.';
      case 'weak-password':
        return 'Mot de passe trop faible.';
      case 'invalid-email':
        return 'Format d\'email invalide.';
      default:
        return e.message ?? 'Cr\u00E9ation du compte impossible.';
    }
  }
}

class _SignupHeader extends StatelessWidget {
  const _SignupHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFDBEAFE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF1D4ED8)),
        ),
        const SizedBox(height: 10),
        Text(
          'Cr\u00E9er un compte',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Inscription rapide pour r\u00E9server ou publier vos trajets.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
        ),
      ],
    );
  }
}
