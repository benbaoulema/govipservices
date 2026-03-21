import 'dart:async';
import 'dart:collection';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/app/navigation/app_navigator.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/parcels/data/parcel_request_service.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';

const Color _parcelAccentDark = Color(0xFF0F766E);

class GlobalParcelRequestListener extends StatefulWidget {
  const GlobalParcelRequestListener({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<GlobalParcelRequestListener> createState() =>
      _GlobalParcelRequestListenerState();
}

class _GlobalParcelRequestListenerState
    extends State<GlobalParcelRequestListener> {
  final ParcelRequestService _requestService = ParcelRequestService();
  final Queue<ParcelRequestDocument> _pendingQueue = Queue<ParcelRequestDocument>();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<ParcelRequestDocument>>? _requestSubscription;
  Set<String> _knownRequestIds = <String>{};
  bool _hasPrimedRequests = false;
  bool _isDialogVisible = false;
  // ID de la demande actuellement affichée dans le popup
  String? _activePopupRequestId;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChanged,
    );
    _handleAuthChanged(FirebaseAuth.instance.currentUser);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _requestSubscription?.cancel();
    super.dispose();
  }

  void _handleAuthChanged(User? user) {
    _requestSubscription?.cancel();
    _knownRequestIds = <String>{};
    _hasPrimedRequests = false;
    _pendingQueue.clear();
    _activePopupRequestId = null;

    final String uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    _requestSubscription = _requestService
        .watchPendingRequestsForProviderUid(uid)
        .listen(_handlePendingRequestsChanged);
  }

  void _handlePendingRequestsChanged(List<ParcelRequestDocument> requests) {
    final Set<String> currentIds = requests.map((r) => r.id).toSet();

    // Si le popup actif a été traité sur un autre appareil → le fermer
    if (_activePopupRequestId != null &&
        !currentIds.contains(_activePopupRequestId) &&
        _isDialogVisible) {
      final BuildContext? ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        Navigator.of(ctx, rootNavigator: true).maybePop();
      }
      _isDialogVisible = false;
      _activePopupRequestId = null;
    }

    // Nettoyer la queue des demandes déjà traitées ailleurs
    _pendingQueue.removeWhere((r) => !currentIds.contains(r.id));

    final List<ParcelRequestDocument> newRequests = _hasPrimedRequests
        ? requests
            .where((request) => !_knownRequestIds.contains(request.id))
            .toList(growable: false)
        : const <ParcelRequestDocument>[];

    _knownRequestIds = currentIds;
    _hasPrimedRequests = true;

    if (newRequests.isEmpty) return;

    for (final ParcelRequestDocument request in newRequests) {
      _pendingQueue.add(request);
    }
    _showNextPopupIfIdle();
  }

  void _showNextPopupIfIdle() {
    if (_isDialogVisible || _pendingQueue.isEmpty) return;

    final BuildContext? dialogContext = rootNavigatorKey.currentContext;
    if (dialogContext == null) return;

    final ParcelRequestDocument request = _pendingQueue.removeFirst();
    _isDialogVisible = true;
    _activePopupRequestId = request.id;

    showParcelRequestPopup(
      context: dialogContext,
      request: request,
      requestService: _requestService,
    ).whenComplete(() {
      _isDialogVisible = false;
      _activePopupRequestId = null;
      _showNextPopupIfIdle();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

Future<void> showParcelRequestPopup({
  required BuildContext context,
  required ParcelRequestDocument request,
  ParcelRequestService? requestService,
}) {
  final ParcelRequestService service = requestService ?? ParcelRequestService();

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (modalContext) {
      return _GlobalParcelRequestPopup(
        request: request,
        onAccept: () => _handleParcelRequestAction(
          modalContext,
          service,
          request,
          'accepted',
        ),
        onReject: () => _handleParcelRequestAction(
          modalContext,
          service,
          request,
          'rejected',
        ),
      );
    },
  );
}

Future<void> _handleParcelRequestAction(
  BuildContext modalContext,
  ParcelRequestService requestService,
  ParcelRequestDocument request,
  String status,
) async {
  Navigator.of(modalContext).pop();

  final BuildContext? appContext = rootNavigatorKey.currentContext;
  try {
    if (status == 'accepted') {
      // Transaction atomique : n'accepte que si encore en attente
      final bool accepted = await requestService.acceptRequest(request.id);
      if (!accepted) {
        // Déjà acceptée sur un autre appareil — ignorer silencieusement
        return;
      }
      if (appContext == null || !appContext.mounted) return;
      await Navigator.of(appContext).pushNamed(
        AppRoutes.parcelsDeliveryRun,
        arguments: ParcelRequestDocument(
          id: request.id,
          trackNum: request.trackNum,
          serviceId: request.serviceId,
          providerUid: request.providerUid,
          providerName: request.providerName,
          requesterUid: request.requesterUid,
          requesterName: request.requesterName,
          requesterContact: request.requesterContact,
          pickupAddress: request.pickupAddress,
          deliveryAddress: request.deliveryAddress,
          price: request.price,
          currency: request.currency,
          vehicleLabel: request.vehicleLabel,
          status: 'accepted',
          pickupLat: request.pickupLat,
          pickupLng: request.pickupLng,
          deliveryLat: request.deliveryLat,
          deliveryLng: request.deliveryLng,
          receiverName: request.receiverName,
          receiverContactPhone: request.receiverContactPhone,
          createdAt: request.createdAt,
        ),
      );
      return;
    }

    // Refus : notifie le sender
    await requestService.updateRequestStatusAndNotify(
      requestId: request.id,
      status: status,
      requesterUid: request.requesterUid,
      providerName: request.providerName,
      trackNum: request.trackNum,
    );

    if (appContext == null || !appContext.mounted) return;
    ScaffoldMessenger.of(appContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Demande colis refusée.'),
        ),
      );
  } catch (_) {
    if (appContext == null || !appContext.mounted) return;
    ScaffoldMessenger.of(appContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF991B1B),
          content: Text('Mise à jour impossible pour le moment.'),
        ),
      );
  }
}

class _GlobalParcelRequestPopup extends StatefulWidget {
  const _GlobalParcelRequestPopup({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final ParcelRequestDocument request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  State<_GlobalParcelRequestPopup> createState() =>
      _GlobalParcelRequestPopupState();
}

class _GlobalParcelRequestPopupState extends State<_GlobalParcelRequestPopup>
    with SingleTickerProviderStateMixin {
  static const int _totalSeconds = 90;

  late final AnimationController _timerCtrl;
  late final Timer _ticker;
  int _remaining = _totalSeconds;
  bool _acted = false;

  @override
  void initState() {
    super.initState();
    _timerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _totalSeconds),
    )..forward();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _onTimeout();
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _timerCtrl.dispose();
    super.dispose();
  }

  void _onTimeout() {
    if (_acted) return;
    _acted = true;
    _ticker.cancel();
    widget.onReject();
  }

  void _safeAccept() {
    if (_acted) return;
    _acted = true;
    _ticker.cancel();
    widget.onAccept();
  }

  void _safeReject() {
    if (_acted) return;
    _acted = true;
    _ticker.cancel();
    widget.onReject();
  }

  Color get _timerColor {
    if (_remaining > 30) return Colors.white;
    if (_remaining > 10) return const Color(0xFFFBBF24);
    return const Color(0xFFF87171);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF0F766E), Color(0xFF14B8A6)],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 32,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── En-tête + timer ──────────────────────────────────────
              Row(
                children: <Widget>[
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Nouvelle demande colis',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Timer circulaire
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        AnimatedBuilder(
                          animation: _timerCtrl,
                          builder: (_, __) => CircularProgressIndicator(
                            value: 1 - _timerCtrl.value,
                            strokeWidth: 3,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_timerColor),
                          ),
                        ),
                        Center(
                          child: Text(
                            '$_remaining',
                            style: TextStyle(
                              color: _timerColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.request.requesterName.isEmpty
                    ? 'Un client attend votre réponse.'
                    : '${widget.request.requesterName} attend votre réponse.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              // Prix
              SizedBox(
                width: double.infinity,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_formatPrice(widget.request.price)} ${widget.request.currency}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _parcelAccentDark,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Détails
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Ref: ${widget.request.trackNum}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    _ParcelPopupRow(
                      icon: Icons.my_location_outlined,
                      label: widget.request.pickupAddress,
                    ),
                    const SizedBox(height: 8),
                    _ParcelPopupRow(
                      icon: Icons.flag_outlined,
                      label: widget.request.deliveryAddress,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        if (widget.request.vehicleLabel.isNotEmpty)
                          _ParcelPopupPill(
                            icon: Icons.two_wheeler_outlined,
                            label: widget.request.vehicleLabel,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _safeReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.46)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      child: const Text('Refuser'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _safeAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _parcelAccentDark,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      child: const Text('Accepter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParcelPopupRow extends StatelessWidget {
  const _ParcelPopupRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ParcelPopupPill extends StatelessWidget {
  const _ParcelPopupPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPrice(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(0);
}
