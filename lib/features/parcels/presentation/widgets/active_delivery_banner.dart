import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:govipservices/app/navigation/app_navigator.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/parcels/data/parcel_request_service.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';

enum _ActiveDeliveryRole { driver, sender }

class _ActiveDelivery {
  const _ActiveDelivery({required this.request, required this.role});

  final ParcelRequestDocument request;
  final _ActiveDeliveryRole role;
}

class ActiveDeliveryBanner extends StatefulWidget {
  const ActiveDeliveryBanner({required this.child, super.key});

  final Widget child;

  @override
  State<ActiveDeliveryBanner> createState() => _ActiveDeliveryBannerState();
}

class _ActiveDeliveryBannerState extends State<ActiveDeliveryBanner>
    with SingleTickerProviderStateMixin {
  static const Set<String> _hiddenRoutes = <String>{
    AppRoutes.parcelsDeliveryRun,
    AppRoutes.parcelsShipPackage,
  };

  final ParcelRequestService _service = ParcelRequestService();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<ParcelRequestDocument?>? _driverSub;
  StreamSubscription<ParcelRequestDocument?>? _senderSub;

  _ActiveDelivery? _active;
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    _onAuthChanged(FirebaseAuth.instance.currentUser);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _authSub?.cancel();
    _driverSub?.cancel();
    _senderSub?.cancel();
    super.dispose();
  }

  void _onAuthChanged(User? user) {
    _driverSub?.cancel();
    _senderSub?.cancel();
    _setActive(null);

    final String uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    _driverSub = _service.watchActiveDriverDelivery(uid).listen((req) {
      if (req != null) {
        _setActive(
          _ActiveDelivery(request: req, role: _ActiveDeliveryRole.driver),
        );
      } else if (_active?.role == _ActiveDeliveryRole.driver) {
        _setActive(null);
      }
    });

    _senderSub = _service.watchActiveSenderDelivery(uid).listen((req) {
      if (_active?.role == _ActiveDeliveryRole.driver) return;
      if (req != null) {
        _setActive(
          _ActiveDelivery(request: req, role: _ActiveDeliveryRole.sender),
        );
      } else if (_active?.role == _ActiveDeliveryRole.sender) {
        _setActive(null);
      }
    });
  }

  void _setActive(_ActiveDelivery? active) {
    if (!mounted) return;
    setState(() => _active = active);
    if (active != null) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  void _onTap() {
    final _ActiveDelivery? active = _active;
    if (active == null) return;

    final BuildContext? ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;

    if (active.role == _ActiveDeliveryRole.driver) {
      Navigator.of(ctx).pushNamed(
        AppRoutes.parcelsDeliveryRun,
        arguments: active.request,
      );
    } else {
      Navigator.of(ctx).pushNamed(
        AppRoutes.parcelsShipPackage,
        arguments: active.request.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: currentRouteName,
      builder: (BuildContext context, String? routeName, Widget? _) {
        final bool shouldHide = _hiddenRoutes.contains(routeName);
        final bool isHomeRoute =
            routeName == null || routeName == AppRoutes.home;
        final Widget banner = SlideTransition(
          position: _slideAnim,
          child: _active == null
              ? const SizedBox.shrink()
              : _BannerCard(delivery: _active!, onTap: _onTap),
        );
        return Stack(
          children: <Widget>[
            widget.child,
            if (!shouldHide)
              if (isHomeRoute)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 92,
                  child: banner,
                )
              else
                Positioned(
                  left: 16,
                  right: 16,
                  top: MediaQuery.of(context).padding.top + 8,
                  child: banner,
                ),
          ],
        );
      },
    );
  }
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({required this.delivery, required this.onTap});

  final _ActiveDelivery delivery;
  final VoidCallback onTap;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String get _statusLabel {
    switch (widget.delivery.request.status.toLowerCase()) {
      case 'accepted':
        return widget.delivery.role == _ActiveDeliveryRole.driver
            ? 'En route vers le colis'
            : 'Livreur en route';
      case 'en_route_to_pickup':
      case 'en_route':
        return widget.delivery.role == _ActiveDeliveryRole.driver
            ? 'En route vers le point de retrait'
            : 'Livreur en chemin';
      case 'arrived_at_pickup':
        return widget.delivery.role == _ActiveDeliveryRole.driver
            ? 'Arrivé au point de retrait'
            : 'Livreur arrivé au retrait';
      case 'picked_up':
        return widget.delivery.role == _ActiveDeliveryRole.driver
            ? 'Colis récupéré - en livraison'
            : 'Colis récupéré';
      case 'arrived_at_delivery':
        return widget.delivery.role == _ActiveDeliveryRole.driver
            ? 'Arrivé à destination'
            : 'Livreur arrivé à destination';
      default:
        return 'Course en cours';
    }
  }

  String get _destinationLabel {
    final ParcelRequestDocument req = widget.delivery.request;
    final String status = req.status.toLowerCase();
    final bool headingToDelivery = status == 'picked_up' ||
        status == 'arrived_at_delivery' ||
        status == 'delivered';
    return widget.delivery.role == _ActiveDeliveryRole.driver || headingToDelivery
        ? req.deliveryAddress
        : req.pickupAddress;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[Color(0xFF0F766E), Color(0xFF14B8A6)],
                      ),
                    ),
                    child: SvgPicture.asset(
                      'assets/illustrations/delivery_rider_banner.svg',
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[
                          const Color(0xFF042F2E).withValues(alpha: 0.9),
                          const Color(0xFF0F766E).withValues(alpha: 0.64),
                          Colors.transparent,
                        ],
                        stops: const <double>[0.0, 0.56, 1.0],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: <Widget>[
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => Opacity(
                          opacity: _pulseAnim.value,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: Text('🛵', style: TextStyle(fontSize: 22)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              'Course en cours',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _statusLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_destinationLabel.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                _destinationLabel,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Rejoindre',
                          style: TextStyle(
                            color: Color(0xFF0F766E),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
