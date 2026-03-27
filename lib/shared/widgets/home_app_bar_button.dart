import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────

class HomeAppBarButton extends StatefulWidget {
  const HomeAppBarButton({super.key});

  @override
  State<HomeAppBarButton> createState() => _HomeAppBarButtonState();
}

class _HomeAppBarButtonState extends State<HomeAppBarButton> {
  bool _isDriver = false;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  Future<void> _loadCapabilities() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final Map<String, dynamic>? data = doc.data();
      final bool isDriver =
          (data?['capabilities'] as Map<String, dynamic>?)?['parcelsProvider'] ==
                  true ||
              data?['isServiceProvider'] == true;
      if (mounted) setState(() => _isDriver = isDriver);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Sur iOS avec une page derrière : chevron retour simple — pas de menu
    if (Platform.isIOS && Navigator.canPop(context)) {
      return IconButton(
        tooltip: 'Retour',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.chevron_left, size: 32),
      );
    }

    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu_rounded),
      onPressed: () => _AppMenuDrawer.show(context, isDriver: _isDriver),
    );
  }
}

// ─── Drawer custom ────────────────────────────────────────────────────────────

class _AppMenuDrawer {
  static void show(BuildContext context, {required bool isDriver}) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => _DrawerSheet(isDriver: isDriver),
      transitionBuilder: (_, Animation<double> anim, __, Widget child) {
        final Animation<Offset> slide = Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        return SlideTransition(position: slide, child: child);
      },
    );
  }
}

class _DrawerSheet extends StatelessWidget {
  const _DrawerSheet({required this.isDriver});

  final bool isDriver;

  static const Color _teal = Color(0xFF0F766E);
  static const Color _tealLight = Color(0xFF14B8A6);

  void _navigate(BuildContext context, String route) {
    Navigator.of(context).pop(); // ferme le drawer
    if (route == AppRoutes.home) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (r) => false,
      );
    } else {
      Navigator.of(context).pushNamed(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final String name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : 'Mon compte';
    final String email = user?.email ?? '';
    final String? photoUrl = user?.photoURL;

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.78,
          height: double.infinity,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // ── En-tête gradient ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[_teal, _tealLight],
                      ),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                    child: Row(
                      children: <Widget>[
                        // Avatar
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          child: photoUrl != null
                              ? ClipOval(
                                  child: Image.network(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _DefaultAvatar(name: name),
                                  ),
                                )
                              : _DefaultAvatar(name: name),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Items ─────────────────────────────────────────────
                  _DrawerItem(
                    icon: Icons.home_rounded,
                    label: 'Accueil',
                    onTap: () => _navigate(context, AppRoutes.home),
                  ),
                  _DrawerDivider(),
                  _DrawerItem(
                    icon: Icons.local_shipping_outlined,
                    label: 'Mes livraisons',
                    subtitle: 'Historique expéditeur',
                    onTap: () =>
                        _navigate(context, AppRoutes.parcelsHistorySender),
                  ),
                  if (isDriver)
                    _DrawerItem(
                      icon: Icons.two_wheeler_rounded,
                      label: 'Mes courses livreur',
                      subtitle: 'Historique conducteur',
                      onTap: () =>
                          _navigate(context, AppRoutes.parcelsHistoryDriver),
                    ),
                  _DrawerItem(
                    icon: Icons.radar_rounded,
                    label: 'GO Radar',
                    subtitle: 'Reporter un voyage en direct',
                    onTap: () =>
                        _navigate(context, AppRoutes.travelGoRadarReporter),
                  ),
                  _DrawerDivider(),
                  _DrawerItem(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Portefeuille',
                    subtitle: 'Solde & transactions',
                    onTap: () => _navigate(context, AppRoutes.wallet),
                  ),
                  _DrawerItem(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Cartes à gratter',
                    subtitle: 'Récompenses & offres',
                    onTap: () => _navigate(context, AppRoutes.scratchCards),
                  ),
                  _DrawerDivider(),
                  _DrawerItem(
                    icon: Icons.person_outline_rounded,
                    label: 'Mon compte',
                    onTap: () => _navigate(context, AppRoutes.userAccount),
                  ),
                  _DrawerItem(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () =>
                        _navigate(context, AppRoutes.userNotifications),
                  ),

                  const Spacer(),

                  // ── Bas : version ou déconnexion ──────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Text(
                      'GVIP',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Composants internes ───────────────────────────────────────────────────────

class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar({required this.name});

  final String name;

  String get _initial =>
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'G';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        _initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF0F766E),
            ),
          ),
          title: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                )
              : null,
          dense: subtitle == null,
        ),
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey[100],
      ),
    );
  }
}
