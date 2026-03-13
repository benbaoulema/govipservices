import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/travel/data/google_places_service.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

enum _ShipStep { pickup, delivery, recipient }

class _AddressPoint {
  const _AddressPoint({
    this.address = '',
    this.lat,
    this.lng,
    this.placeId,
  });

  final String address;
  final double? lat;
  final double? lng;
  final String? placeId;

  bool get isComplete =>
      address.trim().isNotEmpty && lat != null && lng != null;

  _AddressPoint copyWith({
    String? address,
    double? lat,
    double? lng,
    String? placeId,
    bool clearCoords = false,
  }) {
    return _AddressPoint(
      address: address ?? this.address,
      lat: clearCoords ? null : lat ?? this.lat,
      lng: clearCoords ? null : lng ?? this.lng,
      placeId: clearCoords ? null : placeId ?? this.placeId,
    );
  }
}

class ShipPackagePage extends StatefulWidget {
  const ShipPackagePage({super.key});

  @override
  State<ShipPackagePage> createState() => _ShipPackagePageState();
}

class _ShipPackagePageState extends State<ShipPackagePage> {
  static const String _googleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  final PageController _pageController = PageController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _deliveryController = TextEditingController();
  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _recipientPhoneController =
      TextEditingController();

  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _deliveryFocusNode = FocusNode();
  final FocusNode _recipientNameFocusNode = FocusNode();
  final FocusNode _recipientPhoneFocusNode = FocusNode();

  _ShipStep _currentStep = _ShipStep.pickup;
  _AddressPoint _pickup = const _AddressPoint();
  _AddressPoint _delivery = const _AddressPoint();
  bool _isFetchingPickupLocation = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _recipientNameController.addListener(_handleRecipientChanged);
    _recipientPhoneController.addListener(_handleRecipientChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pickupController.dispose();
    _deliveryController.dispose();
    _recipientNameController
      ..removeListener(_handleRecipientChanged)
      ..dispose();
    _recipientPhoneController
      ..removeListener(_handleRecipientChanged)
      ..dispose();
    _pickupFocusNode.dispose();
    _deliveryFocusNode.dispose();
    _recipientNameFocusNode.dispose();
    _recipientPhoneFocusNode.dispose();
    super.dispose();
  }

  bool get _canContinueFromCurrentStep {
    switch (_currentStep) {
      case _ShipStep.pickup:
        return _pickup.isComplete;
      case _ShipStep.delivery:
        return _delivery.isComplete;
      case _ShipStep.recipient:
        return _recipientNameController.text.trim().isNotEmpty &&
            _recipientPhoneController.text.trim().isNotEmpty &&
            !_isSubmitting;
    }
  }

  int get _currentStepIndex => _ShipStep.values.indexOf(_currentStep);

  void _handleRecipientChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _handleBack() async {
    if (_currentStep == _ShipStep.pickup) return true;
    _goToStep(_ShipStep.values[_currentStepIndex - 1]);
    return false;
  }

  void _handlePickupTextChanged(String value) {
    setState(() {
      _pickup = _pickup.copyWith(address: value, clearCoords: true);
    });
  }

  void _handleDeliveryTextChanged(String value) {
    setState(() {
      _delivery = _delivery.copyWith(address: value, clearCoords: true);
    });
  }

  void _applyPickupDetails(PlaceDetailsResult details) {
    setState(() {
      _pickup = _pickup.copyWith(
        address: details.address,
        lat: details.lat,
        lng: details.lng,
        placeId: details.placeId,
      );
    });
  }

  void _applyDeliveryDetails(PlaceDetailsResult details) {
    setState(() {
      _delivery = _delivery.copyWith(
        address: details.address,
        lat: details.lat,
        lng: details.lng,
        placeId: details.placeId,
      );
    });
  }

  Future<void> _useCurrentLocationForPickup() async {
    if (_isFetchingPickupLocation) return;

    setState(() {
      _isFetchingPickupLocation = true;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage(
          'Activez la localisation pour utiliser votre position actuelle.',
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage(
          'Autorisez la localisation pour pre-remplir le lieu de recuperation.',
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final String resolvedAddress = await _reverseGeocodePosition(position);

      _pickupController.text = resolvedAddress;
      _pickupController.selection = TextSelection.collapsed(
        offset: resolvedAddress.length,
      );

      if (!mounted) return;
      setState(() {
        _pickup = _pickup.copyWith(
          address: resolvedAddress,
          lat: position.latitude,
          lng: position.longitude,
          placeId: null,
        );
      });
      _showMessage('Adresse de recuperation renseignee depuis votre position.');
    } catch (_) {
      _showMessage('Impossible de recuperer votre position actuelle.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isFetchingPickupLocation = false;
      });
    }
  }

  Future<String> _reverseGeocodePosition(Position position) async {
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final Placemark? first = placemarks.isNotEmpty ? placemarks.first : null;
      final String address = <String?>[
        first?.street,
        first?.subLocality,
        first?.locality,
        first?.country,
      ]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(', ');
      if (address.isNotEmpty) return address;
    } catch (_) {
      // Fallback to raw coordinates below.
    }

    return '${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)}';
  }

  Future<void> _continue() async {
    if (!_canContinueFromCurrentStep) return;

    switch (_currentStep) {
      case _ShipStep.pickup:
        _goToStep(_ShipStep.delivery);
        return;
      case _ShipStep.delivery:
        _goToStep(_ShipStep.recipient);
        return;
      case _ShipStep.recipient:
        await _submitDraft();
        return;
    }
  }

  void _goToStep(_ShipStep step) {
    final int targetIndex = _ShipStep.values.indexOf(step);
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      targetIndex,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (step) {
        case _ShipStep.pickup:
          _pickupFocusNode.requestFocus();
          return;
        case _ShipStep.delivery:
          _deliveryFocusNode.requestFocus();
          return;
        case _ShipStep.recipient:
          _recipientNameFocusNode.requestFocus();
          return;
      }
    });
  }

  Future<void> _submitDraft() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recapitulatif',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 16),
                _SummaryRow(
                  icon: Icons.my_location_outlined,
                  title: 'Recuperation',
                  value: _pickup.address,
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  icon: Icons.flag_outlined,
                  title: 'Livraison',
                  value: _delivery.address,
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Destinataire',
                  value:
                      '${_recipientNameController.text.trim()} - ${_recipientPhoneController.text.trim()}',
                ),
                const SizedBox(height: 18),
                Text(
                  'La suite du formulaire peut maintenant brancher la creation Firestore de la demande.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Continuer ensuite'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _currentStep == _ShipStep.pickup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const HomeAppBarButton(),
          title: const Text('Expedier'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _ProgressHeader(currentStep: _currentStep),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildPickupStep(colorScheme),
                    _buildDeliveryStep(colorScheme),
                    _buildRecipientStep(colorScheme),
                  ],
                ),
              ),
              _BottomActionBar(
                canGoBack: _currentStep != _ShipStep.pickup,
                continueLabel: _currentStep == _ShipStep.recipient
                    ? 'Continuer'
                    : 'Suivant',
                onBack: _currentStep == _ShipStep.pickup
                    ? null
                    : () => _goToStep(_ShipStep.values[_currentStepIndex - 1]),
                onContinue: _canContinueFromCurrentStep ? _continue : null,
                isLoading: _isSubmitting,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickupStep(ColorScheme colorScheme) {
    return _StepScaffold(
      accentColor: colorScheme.primary,
      icon: Icons.inventory_2_outlined,
      title: 'Ou recupere-t-on votre colis ?',
      subtitle:
          'Entrez une adresse precise ou utilisez votre position actuelle.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AddressAutocompleteField(
            controller: _pickupController,
            focusNode: _pickupFocusNode,
            labelText: 'Lieu de recuperation',
            hintText: 'Rue, quartier, ville...',
            apiKey: _googleMapsApiKey,
            onChanged: _handlePickupTextChanged,
            onPlaceResolved: _applyPickupDetails,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed:
                _isFetchingPickupLocation ? null : _useCurrentLocationForPickup,
            icon: _isFetchingPickupLocation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: Text(
              _isFetchingPickupLocation
                  ? 'Localisation en cours...'
                  : 'Utiliser ma position',
            ),
          ),
          const SizedBox(height: 18),
          _AddressStatusCard(
            title: 'Adresse retenue',
            icon: Icons.check_circle_outline_rounded,
            isReady: _pickup.isComplete,
            lines: [
              if (_pickup.address.trim().isNotEmpty) _pickup.address,
              if (_pickup.lat != null && _pickup.lng != null)
                'Coordonnees: ${_pickup.lat!.toStringAsFixed(5)}, ${_pickup.lng!.toStringAsFixed(5)}',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStep(ColorScheme colorScheme) {
    return _StepScaffold(
      accentColor: const Color(0xFF0F766E),
      icon: Icons.local_shipping_outlined,
      title: 'Ou doit-on livrer le colis ?',
      subtitle:
          'Choisissez le point d\'arrivee. L\'adresse doit etre selectionnee dans les suggestions.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AddressAutocompleteField(
            controller: _deliveryController,
            focusNode: _deliveryFocusNode,
            labelText: 'Lieu de livraison',
            hintText: 'Adresse du destinataire',
            apiKey: _googleMapsApiKey,
            onChanged: _handleDeliveryTextChanged,
            onPlaceResolved: _applyDeliveryDetails,
          ),
          const SizedBox(height: 18),
          _AddressStatusCard(
            title: 'Destination retenue',
            icon: Icons.flag_circle_outlined,
            isReady: _delivery.isComplete,
            lines: [
              if (_delivery.address.trim().isNotEmpty) _delivery.address,
              if (_delivery.lat != null && _delivery.lng != null)
                'Coordonnees: ${_delivery.lat!.toStringAsFixed(5)}, ${_delivery.lng!.toStringAsFixed(5)}',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientStep(ColorScheme colorScheme) {
    return _StepScaffold(
      accentColor: const Color(0xFF115E59),
      icon: Icons.person_pin_circle_outlined,
      title: 'Qui recoit le colis ?',
      subtitle:
          'Ajoutez le nom et le numero du destinataire avant la suite du formulaire.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _recipientNameController,
            focusNode: _recipientNameFocusNode,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              context,
              label: 'Nom du destinataire',
              hint: 'Ex: Aicha Kone',
              icon: Icons.person_outline_rounded,
            ),
            onSubmitted: (_) => _recipientPhoneFocusNode.requestFocus(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _recipientPhoneController,
            focusNode: _recipientPhoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: _inputDecoration(
              context,
              label: 'Telephone du destinataire',
              hint: 'Ex: +225 07 00 00 00 00',
              icon: Icons.call_outlined,
            ),
          ),
          const SizedBox(height: 18),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF4FBF7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recap rapide',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _SummaryRow(
                    icon: Icons.my_location_outlined,
                    title: 'Recuperation',
                    value: _pickup.address.isEmpty
                        ? 'A definir'
                        : _pickup.address,
                  ),
                  const SizedBox(height: 10),
                  _SummaryRow(
                    icon: Icons.flag_outlined,
                    title: 'Livraison',
                    value: _delivery.address.isEmpty
                        ? 'A definir'
                        : _delivery.address,
                  ),
                  const SizedBox(height: 10),
                  _SummaryRow(
                    icon: Icons.person_outline_rounded,
                    title: 'Destinataire',
                    value: _recipientNameController.text.trim().isEmpty
                        ? 'Nom et telephone a renseigner'
                        : '${_recipientNameController.text.trim()} - ${_recipientPhoneController.text.trim()}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF4FBF7),
      prefixIcon: Icon(icon),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.currentStep});

  final _ShipStep currentStep;

  @override
  Widget build(BuildContext context) {
    const List<String> labels = <String>[
      'Recuperation',
      'Livraison',
      'Destinataire',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nouvel envoi',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Un parcours simple, etape par etape, pour lancer une demande d\'expedition.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Row(
          children: List<Widget>.generate(labels.length, (int index) {
            final bool isActive = index == currentStep.index;
            final bool isDone = index < currentStep.index;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive || isDone
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}',
                        style: TextStyle(
                          color:
                              isActive || isDone ? Colors.white : Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              isActive || isDone ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withOpacity(0.12),
                  accentColor.withOpacity(0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accentColor.withOpacity(0.12)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(icon, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _AddressStatusCard extends StatelessWidget {
  const _AddressStatusCard({
    required this.title,
    required this.icon,
    required this.isReady,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final bool isReady;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isReady ? const Color(0xFFEAF7F1) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isReady ? const Color(0xFF99D3B7) : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isReady ? const Color(0xFF0F766E) : colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  if (lines.isEmpty)
                    Text(
                      'Selectionnez une adresse valide pour continuer.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    )
                  else
                    ...lines.map(
                      (String line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0F766E)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.canGoBack,
    required this.continueLabel,
    required this.onBack,
    required this.onContinue,
    required this.isLoading,
  });

  final bool canGoBack;
  final String continueLabel;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(
            children: [
              if (canGoBack) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: isLoading ? null : onBack,
                    child: const Text('Retour'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: isLoading ? null : onContinue,
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(continueLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
