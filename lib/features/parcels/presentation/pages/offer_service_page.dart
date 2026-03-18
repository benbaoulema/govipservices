import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/parcels/data/vehicle_type_repository.dart';
import 'package:govipservices/features/parcels/domain/models/vehicle_type.dart';
import 'package:govipservices/features/travel/data/google_places_service.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/features/user/data/user_firestore_repository.dart';
import 'package:govipservices/features/user/data/user_availability_service.dart';
import 'package:govipservices/features/user/models/app_user.dart';
import 'package:govipservices/features/user/models/user_phone.dart';
import 'package:govipservices/features/user/models/user_role.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';
import 'package:image_picker/image_picker.dart';

enum _OfferServiceStep {
  vehicleType,
  baseAddress,
  pricing,
  personalInfo,
  vehiclePhoto,
  maxWeight,
  description,
}

enum _PriceUnit { kg, tonne, tricycle, perDelivery }

enum _PriceZoneCurrency { xof, eur }

enum _PersonalInfoStage { contact, details }

class _BaseAddressSelection {
  const _BaseAddressSelection({
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

  _BaseAddressSelection copyWith({
    String? address,
    double? lat,
    double? lng,
    String? placeId,
    bool clearCoordinates = false,
  }) {
    return _BaseAddressSelection(
      address: address ?? this.address,
      lat: clearCoordinates ? null : lat ?? this.lat,
      lng: clearCoordinates ? null : lng ?? this.lng,
      placeId: clearCoordinates ? null : placeId ?? this.placeId,
    );
  }
}

class _PriceZoneDraft {
  const _PriceZoneDraft({
    required this.departZone,
    required this.arrivZone,
    required this.price,
    required this.currency,
  });

  final String departZone;
  final String arrivZone;
  final double price;
  final _PriceZoneCurrency currency;

  bool get isValid =>
      departZone.trim().isNotEmpty &&
      arrivZone.trim().isNotEmpty &&
      price > 0;

  String get duplicateKey =>
      '${departZone.trim().toLowerCase()}|${arrivZone.trim().toLowerCase()}';
}

class OfferServicePage extends StatefulWidget {
  const OfferServicePage({super.key});

  @override
  State<OfferServicePage> createState() => _OfferServicePageState();
}

class _OfferServicePageState extends State<OfferServicePage> {
  String get _googleMapsApiKey => RuntimeAppConfig.googleMapsApiKey;

  final VehicleTypeRepository _vehicleTypeRepository = VehicleTypeRepository();
  final UserFirestoreRepository _userFirestoreRepository =
      UserFirestoreRepository();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _baseAddressController = TextEditingController();
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactPhoneController = TextEditingController();
  final TextEditingController _contactPasswordController =
      TextEditingController();
  final TextEditingController _maxWeightController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _baseAddressFocusNode = FocusNode();
  final FocusNode _contactNameFocusNode = FocusNode();
  final FocusNode _contactPhoneFocusNode = FocusNode();
  final FocusNode _contactPasswordFocusNode = FocusNode();
  final FocusNode _maxWeightFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  late final Future<List<VehicleType>> _vehicleTypesFuture;

  String? _selectedVehicleTypeId;
  _OfferServiceStep _currentStep = _OfferServiceStep.vehicleType;
  _BaseAddressSelection _baseAddress = const _BaseAddressSelection();
  _PriceUnit _priceUnit = _PriceUnit.perDelivery;
  List<_PriceZoneDraft> _priceZones = const <_PriceZoneDraft>[];
  _PersonalInfoStage _personalInfoStage = _PersonalInfoStage.contact;
  String? _existingLightAccountUid;
  XFile? _vehiclePhoto;
  bool _isCheckingLightAccount = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _isResolvingCurrentPosition = false;
  bool _isPickingVehiclePhoto = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _vehicleTypesFuture = _vehicleTypeRepository.fetchActiveVehicleTypes();
    _scrollController.addListener(_updateScrollButtons);
    _contactNameController.addListener(_handlePersonalInfoChanged);
    _contactPhoneController.addListener(_handlePersonalInfoChanged);
    _contactPasswordController.addListener(_handlePersonalInfoChanged);
    _prefillPersonalInfoFromConnectedUser();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollButtons)
      ..dispose();
    _contactNameController.removeListener(_handlePersonalInfoChanged);
    _contactPhoneController.removeListener(_handlePersonalInfoChanged);
    _contactPasswordController.removeListener(_handlePersonalInfoChanged);
    _baseAddressController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactPasswordController.dispose();
    _maxWeightController.dispose();
    _descriptionController.dispose();
    _baseAddressFocusNode.dispose();
    _contactNameFocusNode.dispose();
    _contactPhoneFocusNode.dispose();
    _contactPasswordFocusNode.dispose();
    _maxWeightFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  void _handlePersonalInfoChanged() {
    if (FirebaseAuth.instance.currentUser == null &&
        _currentStep == _OfferServiceStep.personalInfo &&
        _personalInfoStage == _PersonalInfoStage.contact) {
      final String phone = _contactPhoneController.text.trim();
      final bool phoneChanged = _existingLightAccountUid != null ||
          _contactNameController.text.trim().isNotEmpty ||
          _contactPasswordController.text.trim().isNotEmpty;
      if (phoneChanged && phone.isNotEmpty) {
        _existingLightAccountUid = null;
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _checkExistingLightAccount() async {
    final String phone = _contactPhoneController.text.trim();
    if (!_isPhoneValid || _isCheckingLightAccount) return;

    setState(() {
      _isCheckingLightAccount = true;
    });

    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('phone.number', isEqualTo: phone)
              .limit(1)
              .get();

      String? existingUid;
      if (snapshot.docs.isNotEmpty) {
        existingUid = snapshot.docs.first.id;
      }

      if (!mounted) return;
      setState(() {
        _existingLightAccountUid = existingUid;
        _personalInfoStage = _PersonalInfoStage.details;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _contactNameFocusNode.requestFocus();
      });
    } catch (_) {
      if (!mounted) return;
      _showMessage('Impossible de vérifier ce numéro pour le moment.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isCheckingLightAccount = false;
      });
    }
  }

  void _updateScrollButtons() {
    if (!_scrollController.hasClients) return;
    final double offset = _scrollController.offset;
    final double maxOffset = _scrollController.position.maxScrollExtent;
    final bool canScrollLeft = offset > 4;
    final bool canScrollRight = offset < maxOffset - 4;

    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }

    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final double target = (_scrollController.offset + delta).clamp(
      0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  VehicleType? _findSelectedVehicleType(List<VehicleType> items) {
    for (final VehicleType item in items) {
      if (item.id == _selectedVehicleTypeId) return item;
    }
    return null;
  }

  bool get _canContinue {
    final bool isConnected = FirebaseAuth.instance.currentUser != null;
    switch (_currentStep) {
      case _OfferServiceStep.vehicleType:
        return _selectedVehicleTypeId != null;
      case _OfferServiceStep.baseAddress:
        return _baseAddress.isComplete;
      case _OfferServiceStep.pricing:
        return _hasValidPriceZones;
      case _OfferServiceStep.personalInfo:
        if (isConnected) {
          return _contactNameController.text.trim().isNotEmpty &&
              _contactPhoneController.text.trim().isNotEmpty;
        }
        if (_personalInfoStage == _PersonalInfoStage.contact) {
          return _isPhoneValid && !_isCheckingLightAccount;
        }
        final bool requiresPassword = _existingLightAccountUid == null;
        return _contactNameController.text.trim().isNotEmpty &&
            (!requiresPassword ||
                _contactPasswordController.text.trim().length >= 6);
      case _OfferServiceStep.vehiclePhoto:
        return _vehiclePhoto != null && !_isPickingVehiclePhoto;
      case _OfferServiceStep.maxWeight:
        return !_isSaving;
      case _OfferServiceStep.description:
        return !_isSaving;
    }
  }

  bool get _isPhoneValid =>
      RegExp(r'^\d{10}$').hasMatch(_contactPhoneController.text.trim());

  bool get _hasValidPriceZones {
    if (_priceZones.isEmpty) return false;
    final Set<String> seen = <String>{};
    for (final _PriceZoneDraft zone in _priceZones) {
      if (!zone.isValid) return false;
      if (!seen.add(zone.duplicateKey)) return false;
    }
    return true;
  }

  void _goToStep(_OfferServiceStep step) {
    setState(() {
      _currentStep = step;
    });

    if (step == _OfferServiceStep.baseAddress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _baseAddressFocusNode.requestFocus();
      });
    } else if (step == _OfferServiceStep.personalInfo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (FirebaseAuth.instance.currentUser == null &&
            _personalInfoStage == _PersonalInfoStage.contact) {
          _contactPhoneFocusNode.requestFocus();
          return;
        }
        if (_contactNameController.text.trim().isEmpty) {
          _contactNameFocusNode.requestFocus();
          return;
        }
        if (FirebaseAuth.instance.currentUser == null &&
            _existingLightAccountUid == null) {
          _contactPasswordFocusNode.requestFocus();
          return;
        }
        _contactPhoneFocusNode.requestFocus();
      });
    } else if (step == _OfferServiceStep.maxWeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maxWeightFocusNode.requestFocus();
      });
    } else if (step == _OfferServiceStep.description) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _descriptionFocusNode.requestFocus();
      });
    }
  }

  void _handleContinue() {
    final bool isConnected = FirebaseAuth.instance.currentUser != null;
    switch (_currentStep) {
      case _OfferServiceStep.vehicleType:
        return;
      case _OfferServiceStep.baseAddress:
        _goToStep(_OfferServiceStep.pricing);
        return;
      case _OfferServiceStep.pricing:
        _goToStep(_OfferServiceStep.personalInfo);
        return;
      case _OfferServiceStep.personalInfo:
        if (!isConnected && _personalInfoStage == _PersonalInfoStage.contact) {
          _checkExistingLightAccount();
          return;
        }
        _goToStep(_OfferServiceStep.vehiclePhoto);
        return;
      case _OfferServiceStep.vehiclePhoto:
        _goToStep(_OfferServiceStep.maxWeight);
        return;
      case _OfferServiceStep.maxWeight:
        _goToStep(_OfferServiceStep.description);
        return;
      case _OfferServiceStep.description:
        _submitOffer();
        return;
    }
  }

  void _handleBack() {
    switch (_currentStep) {
      case _OfferServiceStep.vehicleType:
        Navigator.of(context).maybePop();
        return;
      case _OfferServiceStep.baseAddress:
        _goToStep(_OfferServiceStep.vehicleType);
        return;
      case _OfferServiceStep.pricing:
        _goToStep(_OfferServiceStep.baseAddress);
        return;
      case _OfferServiceStep.personalInfo:
        if (FirebaseAuth.instance.currentUser == null &&
            _personalInfoStage == _PersonalInfoStage.details) {
          setState(() {
            _personalInfoStage = _PersonalInfoStage.contact;
            _existingLightAccountUid = null;
            _contactNameController.clear();
            _contactPasswordController.clear();
          });
          return;
        }
        _goToStep(_OfferServiceStep.pricing);
        return;
      case _OfferServiceStep.vehiclePhoto:
        _goToStep(_OfferServiceStep.personalInfo);
        return;
      case _OfferServiceStep.maxWeight:
        _goToStep(_OfferServiceStep.vehiclePhoto);
        return;
      case _OfferServiceStep.description:
        _goToStep(_OfferServiceStep.maxWeight);
        return;
    }
  }

  void _handleBaseAddressChanged(String value) {
    setState(() {
      _baseAddress = _baseAddress.copyWith(
        address: value,
        clearCoordinates: true,
      );
    });
  }

  void _handleBaseAddressResolved(PlaceDetailsResult details) {
    setState(() {
      _baseAddress = _baseAddress.copyWith(
        address: details.address,
        lat: details.lat,
        lng: details.lng,
        placeId: details.placeId,
      );
    });
  }

  Future<void> _useCurrentPosition() async {
    if (_isResolvingCurrentPosition) return;

    setState(() {
      _isResolvingCurrentPosition = true;
    });

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage(
          'Activez la localisation pour renseigner votre adresse de base.',
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
          'Autorisez la localisation pour utiliser votre position actuelle.',
        );
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final String resolvedAddress = await _reverseGeocode(position);
      _baseAddressController.text = resolvedAddress;
      _baseAddressController.selection = TextSelection.collapsed(
        offset: resolvedAddress.length,
      );

      if (!mounted) return;
      setState(() {
        _baseAddress = _baseAddress.copyWith(
          address: resolvedAddress,
          lat: position.latitude,
          lng: position.longitude,
          placeId: null,
        );
      });
    } catch (_) {
      _showMessage('Impossible de récupérer votre position actuelle.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isResolvingCurrentPosition = false;
      });
    }
  }

  Future<String> _reverseGeocode(Position position) async {
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
      // Fallback below.
    }

    return '${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)}';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _prefillPersonalInfoFromConnectedUser() async {
    final User? authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(authUser.uid)
              .get();
      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};

      final String name =
          (data['displayName'] as String?)?.trim() ??
          (authUser.displayName?.trim() ?? '');
      final Map<String, dynamic>? phone = data['phone'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(data['phone'] as Map<String, dynamic>)
          : null;
      final String countryCode = (phone?['countryCode'] as String?)?.trim() ?? '';
      final String number = (phone?['number'] as String?)?.trim() ?? '';
      final String fullPhone = [countryCode, number]
          .where((part) => part.isNotEmpty)
          .join(' ')
          .trim();

      if (!mounted) return;
      setState(() {
        if (_contactNameController.text.trim().isEmpty && name.isNotEmpty) {
          _contactNameController.text = name;
        }
        if (_contactPhoneController.text.trim().isEmpty && fullPhone.isNotEmpty) {
          _contactPhoneController.text = fullPhone;
        }
        _personalInfoStage = _PersonalInfoStage.details;
      });
    } catch (_) {
      // Keep the flow resilient if prefill fails.
    }
  }

  Future<void> _openLoginAndPrefill() async {
    final Object? result = await Navigator.of(context).pushNamed(
      AppRoutes.authLogin,
      arguments: <String, dynamic>{'returnToCaller': true},
    );
    if (result == true) {
      await _prefillPersonalInfoFromConnectedUser();
    }
  }

  Future<void> _promptVehiclePhotoSource() async {
    if (_isPickingVehiclePhoto) return;

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir depuis la galerie'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;
    await _pickVehiclePhoto(source);
  }

  Future<void> _pickVehiclePhoto(ImageSource source) async {
    if (_isPickingVehiclePhoto) return;

    setState(() {
      _isPickingVehiclePhoto = true;
    });

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (pickedFile == null || !mounted) return;

      setState(() {
        _vehiclePhoto = pickedFile;
      });
    } catch (_) {
      if (!mounted) return;
      _showMessage('Impossible d ajouter cette photo pour le moment.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isPickingVehiclePhoto = false;
      });
    }
  }

  void _removeVehiclePhoto() {
    setState(() {
      _vehiclePhoto = null;
    });
  }

  String _buildSyntheticEmailFromPhone(String phoneNumber) {
    return '225$phoneNumber@govipuser.local';
  }

  String _priceUnitValue(_PriceUnit unit) {
    switch (unit) {
      case _PriceUnit.kg:
        return 'kg';
      case _PriceUnit.tonne:
        return 'tonne';
      case _PriceUnit.tricycle:
        return 'tricycle';
      case _PriceUnit.perDelivery:
        return 'per_delivery';
    }
  }

  String _currencyValue(_PriceZoneCurrency currency) {
    switch (currency) {
      case _PriceZoneCurrency.xof:
        return 'XOF';
      case _PriceZoneCurrency.eur:
        return 'EUR';
    }
  }

  double? get _maxWeightValue {
    final String raw = _maxWeightController.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  Future<String> _ensureOfferOwnerUid() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String displayName = _contactNameController.text.trim();
    final String phone = _contactPhoneController.text.trim();

    if (currentUser != null) {
      if ((currentUser.displayName ?? '').trim() != displayName &&
          displayName.isNotEmpty) {
        await currentUser.updateDisplayName(displayName);
      }

      await _userFirestoreRepository.update(currentUser.uid, <String, dynamic>{
        'displayName': displayName,
        'role': userRoleToJson(UserRole.pro),
        'phone': <String, dynamic>{
          'countryCode': '+225',
          'number': phone,
        },
        'service': displayName,
        'isServiceProvider': true,
        'capabilities': <String, dynamic>{
          'parcelsProvider': true,
        },
        'meta': <String, dynamic>{
          'offerFlowCompleted': true,
        },
      });
      return currentUser.uid;
    }

    if (_existingLightAccountUid != null) {
      await _userFirestoreRepository.update(_existingLightAccountUid!, <String, dynamic>{
        'displayName': displayName,
        'role': userRoleToJson(UserRole.pro),
        'phone': <String, dynamic>{
          'countryCode': '+225',
          'number': phone,
        },
        'service': displayName,
        'isServiceProvider': true,
        'capabilities': <String, dynamic>{
          'parcelsProvider': true,
        },
        'meta': <String, dynamic>{
          'offerFlowCompleted': true,
          'authEmailSource': 'phone-generated',
        },
      });
      return _existingLightAccountUid!;
    }

    final UserCredential credentials =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: _buildSyntheticEmailFromPhone(phone),
      password: _contactPasswordController.text.trim(),
    );
    final User? authUser = credentials.user;
    if (authUser == null) {
      throw FirebaseAuthException(
        code: 'null-user',
        message: 'Compte leger introuvable apres creation.',
      );
    }

    await authUser.updateDisplayName(displayName);

    final AppUser user = AppUser(
      uid: authUser.uid,
      email: authUser.email,
      displayName: displayName,
      role: UserRole.pro,
      phone: const UserPhone(countryCode: '+225', number: ''),
      photoURL: authUser.photoURL,
      materialPhotoUrl: null,
      service: displayName,
      isServiceProvider: true,
      createdAt: null,
      updatedAt: null,
      archived: false,
      meta: <String, dynamic>{
        'authEmailSource': 'phone-generated',
        'offerFlowCompleted': true,
      },
    ).copyWith(
      phone: UserPhone(countryCode: '+225', number: phone),
    );

    await _userFirestoreRepository.setUser(authUser.uid, user);
    await _userFirestoreRepository.update(authUser.uid, <String, dynamic>{
      'capabilities': <String, dynamic>{
        'parcelsProvider': true,
      },
    });
    return authUser.uid;
  }

  Future<Map<String, String?>> _uploadVehiclePhoto(String ownerUid) async {
    final XFile? photo = _vehiclePhoto;
    if (photo == null) {
      return <String, String?>{
        'photoUrl': null,
        'storagePath': null,
      };
    }

    final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final String storagePath = 'service_materials/$ownerUid/$fileName';
    final Reference ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putFile(File(photo.path));
    final String url = await ref.getDownloadURL();
    return <String, String?>{
      'photoUrl': url,
      'storagePath': storagePath,
    };
  }

  Future<void> _submitOffer() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final String ownerUid = await _ensureOfferOwnerUid();
      final Map<String, String?> photoData = await _uploadVehiclePhoto(ownerUid);
      final VehicleType? selectedVehicleType = await _vehicleTypesFuture.then(
        _findSelectedVehicleType,
      );
      final String title = _contactNameController.text.trim();
      final UserAvailabilitySnapshot availability =
          await UserAvailabilityService().fetchCurrent();
      final String? pickupGeohash =
          _baseAddress.lat != null && _baseAddress.lng != null
              ? UserAvailabilityService.encodeGeohashForCoordinates(
                  _baseAddress.lat!,
                  _baseAddress.lng!,
                )
              : null;
      final bool isSearchable = availability.isOnline &&
          (availability.scope == UserAvailabilityScope.parcels ||
              availability.scope == UserAvailabilityScope.all);

      await FirebaseFirestore.instance.collection('services').add(<String, dynamic>{
        'title': title,
        'name': title,
        'ownerUid': ownerUid,
        'contactName': title,
        'contactPhone': _contactPhoneController.text.trim(),
        'cityName': _baseAddress.address,
        'pickupCityAddress': _baseAddress.address,
        'pickupLatLng': <String, dynamic>{
          'lat': _baseAddress.lat,
          'lng': _baseAddress.lng,
        },
        'pickupGeohash': pickupGeohash,
        'priceUnit': _priceUnitValue(_priceUnit),
        'priceZones': _priceZones
            .map(
              (_PriceZoneDraft zone) => <String, dynamic>{
                'departZone': zone.departZone,
                'arrivZone': zone.arrivZone,
                'price': zone.price,
                'device': _currencyValue(zone.currency),
                'schedules': null,
              },
            )
            .toList(growable: false),
        'maxWeight': _maxWeightValue,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'photoUrl': photoData['photoUrl'],
        'photoStoragePath': photoData['storagePath'],
        'typeVehicule': selectedVehicleType == null
            ? null
            : <String, dynamic>{
                'id': selectedVehicleType.id,
                'name': selectedVehicleType.name,
                'imageUrl': selectedVehicleType.imageUrl,
              },
        'isValidated': false,
        'status': 'active',
        'ownerAvailability': <String, dynamic>{
          'isOnline': availability.isOnline,
          'scope': availability.scope.name,
          'lat': availability.lat,
          'lng': availability.lng,
          'geohash': availability.geohash,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'search': <String, dynamic>{
          'isSearchable': isSearchable,
          'serviceStatus': 'active',
          'isValidated': false,
          'ownerOnline': availability.isOnline,
          'ownerScope': availability.scope.name,
          'ownerLat': availability.lat,
          'ownerLng': availability.lng,
          'ownerGeohash': availability.geohash,
          'ownerAvailabilityUpdatedAt': FieldValue.serverTimestamp(),
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showMessage('Service enregistre avec succes.');
      Navigator.of(context).maybePop(true);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showMessage(error.message ?? 'Impossible de creer le compte leger.');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      _showMessage(error.message ?? 'Impossible d enregistrer le service.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Impossible d enregistrer le service pour le moment.');
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _setPriceUnit(_PriceUnit value) {
    if (_priceUnit == value) return;
    setState(() {
      _priceUnit = value;
    });
  }

  Future<void> _openAddPriceZoneSheet({_PriceZoneDraft? initialZone, int? index}) async {
    final bool isFirstZone = index == null && _priceZones.isEmpty;
    final _PriceZoneDraft? result = await showModalBottomSheet<_PriceZoneDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _PriceZoneEditorSheet(
        apiKey: _googleMapsApiKey,
        priceUnit: _priceUnit,
        initialZone: initialZone,
        defaultDepartZone: _baseAddress.address,
        prefillArrivalWithBaseAddress: isFirstZone,
        duplicateExists: (_PriceZoneDraft draft) {
          return _priceZones.asMap().entries.any((entry) {
            if (index != null && entry.key == index) return false;
            return entry.value.duplicateKey == draft.duplicateKey;
          });
        },
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (index != null) {
        final List<_PriceZoneDraft> next = List<_PriceZoneDraft>.from(
          _priceZones,
        );
        next[index] = result;
        _priceZones = next;
      } else {
        _priceZones = <_PriceZoneDraft>[..._priceZones, result];
      }
    });
  }

  void _removePriceZone(int index) {
    setState(() {
      final List<_PriceZoneDraft> next = List<_PriceZoneDraft>.from(_priceZones);
      next.removeAt(index);
      _priceZones = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Proposer un service'),
      ),
      body: FutureBuilder<List<VehicleType>>(
        future: _vehicleTypesFuture,
        builder: (context, snapshot) {
          final List<VehicleType> items = snapshot.data ?? const <VehicleType>[];

          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate.fixed([
                          if (_currentStep == _OfferServiceStep.vehicleType) ...[
                            _StepBanner(colorScheme: colorScheme),
                            const SizedBox(height: 16),
                          ],
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final Animation<Offset> position = Tween<Offset>(
                                begin: const Offset(0.08, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: position,
                                  child: child,
                                ),
                              );
                            },
                            child: _currentStep == _OfferServiceStep.vehicleType
                                ? _VehicleTypeStep(
                                    key: const ValueKey('vehicle-type-step'),
                                    items: items,
                                    snapshot: snapshot,
                                    selectedVehicleTypeId:
                                        _selectedVehicleTypeId,
                                    selectedVehicleType:
                                        _findSelectedVehicleType(items),
                                    scrollController: _scrollController,
                                    canScrollLeft: _canScrollLeft,
                                    canScrollRight: _canScrollRight,
                                    onScrollLeft: () => _scrollBy(-260),
                                    onScrollRight: () => _scrollBy(260),
                                    onSelect: (VehicleType vehicleType) {
                                      setState(() {
                                        _selectedVehicleTypeId =
                                            vehicleType.id;
                                      });
                                      Future<void>.delayed(
                                        const Duration(milliseconds: 120),
                                        () {
                                          if (!mounted ||
                                              _currentStep !=
                                                  _OfferServiceStep
                                                      .vehicleType) {
                                            return;
                                          }
                                          _goToStep(
                                            _OfferServiceStep.baseAddress,
                                          );
                                        },
                                      );
                                    },
                                  )
                                : _currentStep == _OfferServiceStep.vehiclePhoto
                                    ? _VehiclePhotoStep(
                                        key: const ValueKey(
                                          'vehicle-photo-step',
                                        ),
                                        photo: _vehiclePhoto,
                                        isPicking: _isPickingVehiclePhoto,
                                        onPickPhoto:
                                            _promptVehiclePhotoSource,
                                        onRemovePhoto: _removeVehiclePhoto,
                                      )
                                : _currentStep == _OfferServiceStep.maxWeight
                                    ? _OptionalTextStep(
                                        key: const ValueKey('max-weight-step'),
                                        title: 'Quel poids maximal acceptez-vous ?',
                                        subtitle:
                                            'Vous pouvez renseigner une limite indicative ou passer cette etape.',
                                        controller: _maxWeightController,
                                        focusNode: _maxWeightFocusNode,
                                        hint: 'Ex: 150',
                                        keyboardType: const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        maxLines: 1,
                                        suffixText: 'kg',
                                        skipLabel: 'Ignorer cette information',
                                        onSkip: () {
                                          _maxWeightController.clear();
                                          _handleContinue();
                                        },
                                      )
                                : _currentStep == _OfferServiceStep.description
                                    ? _OptionalTextStep(
                                        key: const ValueKey('description-step'),
                                        title: 'Ajoutez une description',
                                        subtitle:
                                            'Precisez votre service, vos habitudes ou un detail utile. Cette etape peut aussi etre ignoree.',
                                        controller: _descriptionController,
                                        focusNode: _descriptionFocusNode,
                                        hint:
                                            'Ex: Livraisons express, manutention legere, disponibilite 7j/7',
                                        keyboardType: TextInputType.multiline,
                                        maxLines: 5,
                                        skipLabel: 'Ignorer cette etape',
                                        onSkip: () {
                                          _descriptionController.clear();
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          setState(() {});
                                        },
                                      )
                                : _currentStep == _OfferServiceStep.personalInfo
                                    ? _PersonalInfoStep(
                                        key: const ValueKey(
                                          'personal-info-step',
                                        ),
                                        nameController:
                                            _contactNameController,
                                        phoneController:
                                            _contactPhoneController,
                                        passwordController:
                                            _contactPasswordController,
                                        nameFocusNode: _contactNameFocusNode,
                                        phoneFocusNode: _contactPhoneFocusNode,
                                        passwordFocusNode:
                                            _contactPasswordFocusNode,
                                        isConnected:
                                            FirebaseAuth.instance.currentUser !=
                                            null,
                                        stage: _personalInfoStage,
                                        existingLightAccount:
                                            _existingLightAccountUid != null,
                                        isCheckingLightAccount:
                                            _isCheckingLightAccount,
                                        onLoginPressed: _openLoginAndPrefill,
                                      )
                                    : _BaseAddressStep(
                                        key: ValueKey(_currentStep.name),
                                        controller: _baseAddressController,
                                        focusNode: _baseAddressFocusNode,
                                        apiKey: _googleMapsApiKey,
                                        selection: _baseAddress,
                                        onChanged: _handleBaseAddressChanged,
                                        onPlaceResolved:
                                            _handleBaseAddressResolved,
                                        onUseCurrentPosition:
                                            _useCurrentPosition,
                                        isResolvingCurrentPosition:
                                            _isResolvingCurrentPosition,
                                        selectedVehicleType:
                                            _findSelectedVehicleType(items),
                                        priceUnit: _priceUnit,
                                        priceZones: _priceZones,
                                        onPriceUnitChanged: _setPriceUnit,
                                        onAddPriceZone:
                                            _openAddPriceZoneSheet,
                                        onEditPriceZone:
                                            _openAddPriceZoneSheet,
                                        onDeletePriceZone: _removePriceZone,
                                        isPricingStep:
                                            _currentStep ==
                                            _OfferServiceStep.pricing,
                                      ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
              _BottomNavigationBar(
                currentStep: _currentStep,
                canContinue: _canContinue,
                isSaving: _isSaving,
                onBack: _handleBack,
                onContinue: _handleContinue,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StepBanner extends StatelessWidget {
  const _StepBanner({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFFF4FBF8),
            colorScheme.primary.withOpacity(0.08),
            const Color(0xFFFFFFFF),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.14),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    colorScheme.primary,
                    const Color(0xFF0F766E),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.24),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.local_shipping_outlined,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proposer un service',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choisissez votre engin pour construire une annonce claire et bien ciblée.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
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

class _BottomNavigationBar extends StatelessWidget {
  const _BottomNavigationBar({
    required this.currentStep,
    required this.canContinue,
    required this.isSaving,
    required this.onBack,
    required this.onContinue,
  });

  final _OfferServiceStep currentStep;
  final bool canContinue;
  final bool isSaving;
  final VoidCallback onBack;
  final VoidCallback onContinue;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isSaving)
              const LinearProgressIndicator(
                minHeight: 3,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                children: [
                  if (currentStep != _OfferServiceStep.vehicleType) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSaving ? null : onBack,
                        child: const Text('Retour'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: currentStep == _OfferServiceStep.vehicleType
                        ? const SizedBox.shrink()
                        : FilledButton(
                            onPressed:
                                canContinue && !isSaving ? onContinue : null,
                            child: isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    currentStep == _OfferServiceStep.description
                                        ? 'Enregistrer'
                                        : currentStep ==
                                                    _OfferServiceStep
                                                        .baseAddress ||
                                                currentStep ==
                                                    _OfferServiceStep
                                                        .personalInfo ||
                                                currentStep ==
                                                    _OfferServiceStep
                                                        .vehiclePhoto ||
                                                currentStep ==
                                                    _OfferServiceStep.maxWeight
                                        ? 'Continuer'
                                        : 'Continuer ensuite',
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

class _VehiclePhotoStep extends StatelessWidget {
  const _VehiclePhotoStep({
    required super.key,
    required this.photo,
    required this.isPicking,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  final XFile? photo;
  final bool isPicking;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Ajoutez une photo de votre engin',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Prenez une photo nette ou choisissez-en une depuis votre galerie.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF475569),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: photo == null
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  colorScheme.primary.withOpacity(0.10),
                                  const Color(0xFFF8FAFC),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 44,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Aucune photo pour le moment',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF0F172A),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Image.file(
                            File(photo!.path),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isPicking ? null : onPickPhoto,
                    icon: isPicking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            photo == null
                                ? Icons.add_a_photo_outlined
                                : Icons.autorenew_rounded,
                          ),
                    label: Text(
                      photo == null
                          ? 'Prendre ou choisir une photo'
                          : 'Changer la photo',
                    ),
                  ),
                ),
                if (photo != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: isPicking ? null : onRemovePhoto,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Retirer la photo'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionalTextStep extends StatelessWidget {
  const _OptionalTextStep({
    required super.key,
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.keyboardType,
    required this.maxLines,
    required this.skipLabel,
    required this.onSkip,
    this.suffixText,
  });

  final String title;
  final String subtitle;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputType keyboardType;
  final int maxLines;
  final String skipLabel;
  final VoidCallback onSkip;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF475569),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  decoration: _editorInputDecoration(
                    context,
                    label: title,
                    hint: hint,
                    icon: maxLines == 1
                        ? Icons.scale_outlined
                        : Icons.notes_rounded,
                    suffixText: suffixText,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onSkip,
                    child: Text(skipLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VehicleTypeStep extends StatelessWidget {
  const _VehicleTypeStep({
    required super.key,
    required this.items,
    required this.snapshot,
    required this.selectedVehicleTypeId,
    required this.selectedVehicleType,
    required this.scrollController,
    required this.canScrollLeft,
    required this.canScrollRight,
    required this.onScrollLeft,
    required this.onScrollRight,
    required this.onSelect,
  });

  final List<VehicleType> items;
  final AsyncSnapshot<List<VehicleType>> snapshot;
  final String? selectedVehicleTypeId;
  final VehicleType? selectedVehicleType;
  final ScrollController scrollController;
  final bool canScrollLeft;
  final bool canScrollRight;
  final VoidCallback onScrollLeft;
  final VoidCallback onScrollRight;
  final ValueChanged<VehicleType> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choisissez le type d’engin',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sélectionnez l’engin utilisé pour vos livraisons. Les prochaines étapes s’adapteront à sa capacité.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (snapshot.connectionState == ConnectionState.waiting)
          const _VehicleLoadingState()
        else if (snapshot.hasError)
          const _VehicleErrorState(
            onRetryMessage: 'Impossible de charger les types d’engin.',
          )
        else if (items.isEmpty)
          const _VehicleEmptyState()
        else
          _VehicleCarousel(
            items: items,
            selectedId: selectedVehicleTypeId,
            scrollController: scrollController,
            canScrollLeft: canScrollLeft,
            canScrollRight: canScrollRight,
            onScrollLeft: onScrollLeft,
            onScrollRight: onScrollRight,
            onSelect: onSelect,
          ),
        const SizedBox(height: 20),
        _SelectedVehicleSummary(vehicleType: selectedVehicleType),
      ],
    );
  }
}

class _BaseAddressStep extends StatelessWidget {
  const _BaseAddressStep({
    required super.key,
    required this.controller,
    required this.focusNode,
    required this.apiKey,
    required this.selection,
    required this.onChanged,
    required this.onPlaceResolved,
    required this.onUseCurrentPosition,
    required this.isResolvingCurrentPosition,
    required this.selectedVehicleType,
    required this.priceUnit,
    required this.priceZones,
    required this.onPriceUnitChanged,
    required this.onAddPriceZone,
    required this.onEditPriceZone,
    required this.onDeletePriceZone,
    required this.isPricingStep,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String apiKey;
  final _BaseAddressSelection selection;
  final ValueChanged<String> onChanged;
  final ValueChanged<PlaceDetailsResult> onPlaceResolved;
  final VoidCallback onUseCurrentPosition;
  final bool isResolvingCurrentPosition;
  final VehicleType? selectedVehicleType;
  final _PriceUnit priceUnit;
  final List<_PriceZoneDraft> priceZones;
  final ValueChanged<_PriceUnit> onPriceUnitChanged;
  final Future<void> Function({_PriceZoneDraft? initialZone, int? index})
      onAddPriceZone;
  final void Function(int index) onDeletePriceZone;
  final bool isPricingStep;
  final Future<void> Function({_PriceZoneDraft? initialZone, int? index})
      onEditPriceZone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isPricingStep) ...[
        Text(
          'Choisissez votre adresse de base',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'C’est depuis cette adresse que vos courses et livraisons seront rattachées par défaut.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedVehicleType != null) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4FBF8),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFD5ECE2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Engin : ${selectedVehicleType!.name}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF0F766E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  AddressAutocompleteField(
                    controller: controller,
                    focusNode: focusNode,
                    labelText: 'Adresse de base',
                    hintText: 'Rue, quartier, ville...',
                    apiKey: apiKey,
                    onChanged: onChanged,
                    onPlaceResolved: onPlaceResolved,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed:
                        isResolvingCurrentPosition ? null : onUseCurrentPosition,
                    icon: isResolvingCurrentPosition
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(
                      isResolvingCurrentPosition
                          ? 'Localisation en cours...'
                          : 'Utiliser ma position',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _BaseAddressSummary(selection: selection),
        ] else ...[
        Text(
          'Ajoutez vos zones tarifaires',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choisissez une unité globale puis ajoutez vos trajets tarifés. Le départ est prérempli avec votre adresse de base.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          ),
          const SizedBox(height: 16),
          _PriceUnitSection(
            selectedUnit: priceUnit,
            onChanged: onPriceUnitChanged,
          ),
          const SizedBox(height: 18),
          _BaseAddressSummary(
            selection: selection,
            title: 'Adresse de base appliquee',
          ),
          const SizedBox(height: 18),
          _PriceZonesSection(
            zones: priceZones,
            unit: priceUnit,
            onAdd: () => onAddPriceZone(),
            onEdit: onEditPriceZone,
            onDelete: onDeletePriceZone,
          ),
        ],
      ],
    );
  }
}

class _BaseAddressSummary extends StatelessWidget {
  const _BaseAddressSummary({
    required this.selection,
    this.title = 'Adresse retenue',
  });

  final _BaseAddressSelection selection;
  final String title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            selection.isComplete ? const Color(0xFFEAF7F1) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selection.isComplete
              ? const Color(0xFFBDE1CB)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selection.isComplete
                  ? Icons.check_circle_outline_rounded
                  : Icons.place_outlined,
              color: selection.isComplete
                  ? const Color(0xFF15803D)
                  : colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (!selection.isComplete)
                    Text(
                      'Sélectionnez une suggestion ou utilisez votre position pour continuer.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  else ...[
                    Text(
                      selection.address,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Coordonnees : ${selection.lat!.toStringAsFixed(5)}, ${selection.lng!.toStringAsFixed(5)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceUnitSection extends StatelessWidget {
  const _PriceUnitSection({
    required this.selectedUnit,
    required this.onChanged,
  });

  final _PriceUnit selectedUnit;
  final ValueChanged<_PriceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tarif fixe par',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Cette unité s’appliquera à tous les tarifs que vous ajoutez.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _PriceUnit.values.map((unit) {
                return ChoiceChip(
                  label: Text(_priceUnitLabel(unit)),
                  selected: unit == selectedUnit,
                  onSelected: (_) => onChanged(unit),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceZonesSection extends StatelessWidget {
  const _PriceZonesSection({
    required this.zones,
    required this.unit,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<_PriceZoneDraft> zones;
  final _PriceUnit unit;
  final VoidCallback onAdd;
  final Future<void> Function({_PriceZoneDraft? initialZone, int? index}) onEdit;
  final void Function(int index) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tarifs ajoutes',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (zones.isEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Ajoutez votre premier tarif pour ${_priceUnitLabel(unit).toLowerCase()}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...zones.asMap().entries.map((entry) {
            final int index = entry.key;
            final _PriceZoneDraft zone = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: index == zones.length - 1 ? 0 : 12),
              child: _PriceZoneCard(
                index: index,
                zone: zone,
                unit: unit,
                onEdit: () => onEdit(initialZone: zone, index: index),
                onDelete: () => onDelete(index),
              ),
            );
          }),
      ],
    );
  }
}

class _PriceZoneCard extends StatelessWidget {
  const _PriceZoneCard({
    required this.index,
    required this.zone,
    required this.unit,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final _PriceZoneDraft zone;
  final _PriceUnit unit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Tarif ${index + 1}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Modifier',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Supprimer',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${zone.departZone} -> ${zone.arrivZone}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: _currencyLabel(zone.currency)),
                _InfoChip(
                  label:
                      '${_formatPrice(zone.price)} / ${_priceUnitLabel(unit).toLowerCase()}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceZoneEditorSheet extends StatefulWidget {
  const _PriceZoneEditorSheet({
    required this.apiKey,
    required this.priceUnit,
    required this.defaultDepartZone,
    required this.duplicateExists,
    required this.prefillArrivalWithBaseAddress,
    this.initialZone,
  });

  final String apiKey;
  final _PriceUnit priceUnit;
  final _PriceZoneDraft? initialZone;
  final String defaultDepartZone;
  final bool Function(_PriceZoneDraft draft) duplicateExists;
  final bool prefillArrivalWithBaseAddress;

  @override
  State<_PriceZoneEditorSheet> createState() => _PriceZoneEditorSheetState();
}

class _PriceZoneEditorSheetState extends State<_PriceZoneEditorSheet> {
  late final TextEditingController _departController;
  late final TextEditingController _arrivalController;
  late final TextEditingController _priceController;

  late String _departZone;
  late String _arrivZone;
  late _PriceZoneCurrency _currency;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _departController = TextEditingController(
      text: widget.initialZone?.departZone ?? widget.defaultDepartZone,
    );
    _arrivalController = TextEditingController(
      text:
          widget.initialZone?.arrivZone ??
          (widget.prefillArrivalWithBaseAddress ? widget.defaultDepartZone : ''),
    );
    _priceController = TextEditingController(
      text: widget.initialZone == null || widget.initialZone!.price <= 0
          ? ''
          : widget.initialZone!.price.toStringAsFixed(
              widget.initialZone!.price % 1 == 0 ? 0 : 2,
            ),
    );
    _departZone = _departController.text.trim();
    _arrivZone = _arrivalController.text.trim();
    _currency = widget.initialZone?.currency ?? _PriceZoneCurrency.xof;
  }

  @override
  void dispose() {
    _departController.dispose();
    _arrivalController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _save() {
    final double? parsedPrice = double.tryParse(
      _priceController.text.trim().replaceAll(',', '.'),
    );
    final _PriceZoneDraft draft = _PriceZoneDraft(
      departZone: _departZone,
      arrivZone: _arrivZone,
      price: parsedPrice ?? 0,
      currency: _currency,
    );

    if (!draft.isValid) {
      setState(() {
        _errorText = 'Renseignez départ, arrivée et un prix supérieur à 0.';
      });
      return;
    }

    if (widget.duplicateExists(draft)) {
      setState(() {
        _errorText = 'Ce trajet tarifaire existe déjà.';
      });
      return;
    }

    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initialZone == null ? 'Ajouter un tarif' : 'Modifier le tarif',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Définissez un trajet et son prix pour l’unité ${_priceUnitLabel(widget.priceUnit).toLowerCase()}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 18),
            AddressAutocompleteField(
              controller: _departController,
              labelText: 'Départ',
              hintText: 'Adresse ou zone de départ',
              apiKey: widget.apiKey,
              onChanged: (value) {
                setState(() {
                  _departZone = value.trim();
                  _errorText = null;
                });
              },
              onPlaceResolved: (details) {
                setState(() {
                  _departZone = details.address.trim();
                  _errorText = null;
                });
              },
            ),
            const SizedBox(height: 14),
            AddressAutocompleteField(
              controller: _arrivalController,
              labelText: 'Arrivée',
              hintText: 'Adresse ou zone d’arrivée',
              apiKey: widget.apiKey,
              onChanged: (value) {
                setState(() {
                  _arrivZone = value.trim();
                  _errorText = null;
                });
              },
              onPlaceResolved: (details) {
                setState(() {
                  _arrivZone = details.address.trim();
                  _errorText = null;
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Prix',
                hintText: 'Ex: 5000',
                filled: true,
                fillColor: const Color(0xFFF4FBF7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.4,
                  ),
                ),
              ),
              onChanged: (_) {
                setState(() {
                  _errorText = null;
                });
              },
            ),
            const SizedBox(height: 14),
            Text(
              'Devise',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _PriceZoneCurrency.values.map((value) {
                final bool active = _currency == value;
                return ChoiceChip(
                  label: Text(_currencyLabel(value)),
                  selected: active,
                  onSelected: (_) {
                    setState(() {
                      _currency = value;
                      _errorText = null;
                    });
                  },
                );
              }).toList(),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB42318),
                    ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(
                      widget.initialZone == null ? 'Ajouter' : 'Enregistrer',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalInfoStep extends StatelessWidget {
  const _PersonalInfoStep({
    required super.key,
    required this.nameController,
    required this.phoneController,
    required this.passwordController,
    required this.nameFocusNode,
    required this.phoneFocusNode,
    required this.passwordFocusNode,
    required this.isConnected,
    required this.stage,
    required this.existingLightAccount,
    required this.isCheckingLightAccount,
    required this.onLoginPressed,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final FocusNode nameFocusNode;
  final FocusNode phoneFocusNode;
  final FocusNode passwordFocusNode;
  final bool isConnected;
  final _PersonalInfoStage stage;
  final bool existingLightAccount;
  final bool isCheckingLightAccount;
  final VoidCallback onLoginPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vos informations',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isConnected
              ? 'Verifiez les informations de contact qui seront associees a votre annonce.'
              : stage == _PersonalInfoStage.contact
                  ? 'Saisissez votre numero de contact pour retrouver ou preparer votre compte leger.'
                  : existingLightAccount
                      ? 'Ce numero correspond deja a un compte leger. Completez simplement votre nom.'
                      : 'Ce numero ne correspond a aucun compte leger. Ajoutez votre nom et un mot de passe.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (!isConnected)
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connectez-vous pour pre-remplir vos infos',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nom et contact pourront etre recuperes automatiquement depuis votre compte.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: onLoginPressed,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Se connecter'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (!isConnected) const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final Animation<Offset> position = Tween<Offset>(
              begin: const Offset(0.08, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: position, child: child),
            );
          },
          child: isConnected || stage == _PersonalInfoStage.details
              ? DecoratedBox(
                  key: const ValueKey('personal-details'),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameController,
                          focusNode: nameFocusNode,
                          textInputAction:
                              isConnected || existingLightAccount
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                          decoration: _editorInputDecoration(
                            context,
                            label: 'Nom complet',
                            hint: 'Ex: Awa Kone',
                            icon: Icons.person_outline_rounded,
                          ),
                          onSubmitted: (_) {
                            if (!isConnected && !existingLightAccount) {
                              passwordFocusNode.requestFocus();
                            }
                          },
                        ),
                        if (!isConnected && !existingLightAccount) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: passwordController,
                            focusNode: passwordFocusNode,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            decoration: _editorInputDecoration(
                              context,
                              label: 'Mot de passe',
                              hint: '6 caracteres minimum',
                              icon: Icons.lock_outline_rounded,
                            ),
                          ),
                        ],
                        if (isConnected) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: phoneController,
                            focusNode: phoneFocusNode,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            decoration: _editorInputDecoration(
                              context,
                              label: 'Contact',
                              hint: 'Ex: +225 07 00 00 00 00',
                              icon: Icons.call_outlined,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : DecoratedBox(
                  key: const ValueKey('personal-contact'),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Numero de contact',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Saisissez exactement 10 chiffres. Ce numero servira de base pour votre compte leger.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: phoneController,
                          focusNode: phoneFocusNode,
                          keyboardType: TextInputType.number,
                          maxLength: 10,
                          decoration: _editorInputDecoration(
                            context,
                            label: 'Contact',
                            hint: 'Ex: 0700000000',
                            icon: Icons.call_outlined,
                            prefixText: '+225 ',
                            helperText: '10 chiffres exactement',
                          ),
                        ),
                        if (isCheckingLightAccount) ...[
                          const SizedBox(height: 10),
                          const LinearProgressIndicator(minHeight: 3),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

String _priceUnitLabel(_PriceUnit unit) {
  switch (unit) {
    case _PriceUnit.kg:
      return 'Kg';
    case _PriceUnit.tonne:
      return 'Tonne';
    case _PriceUnit.tricycle:
      return 'Tricycle';
    case _PriceUnit.perDelivery:
      return 'Livraison';
  }
}

String _currencyLabel(_PriceZoneCurrency currency) {
  switch (currency) {
    case _PriceZoneCurrency.xof:
      return 'CFA';
    case _PriceZoneCurrency.eur:
      return 'EUR';
  }
}

String _formatPrice(double value) {
  if (value % 1 == 0) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

InputDecoration _editorInputDecoration(
  BuildContext context, {
  required String label,
  required String hint,
  required IconData icon,
  String? prefixText,
  String? helperText,
  String? suffixText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefixText,
    helperText: helperText,
    suffixText: suffixText,
    filled: true,
    fillColor: const Color(0xFFF4FBF7),
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.primary,
        width: 1.4,
      ),
    ),
  );
}

class _VehicleCarousel extends StatelessWidget {
  const _VehicleCarousel({
    required this.items,
    required this.selectedId,
    required this.scrollController,
    required this.canScrollLeft,
    required this.canScrollRight,
    required this.onScrollLeft,
    required this.onScrollRight,
    required this.onSelect,
  });

  final List<VehicleType> items;
  final String? selectedId;
  final ScrollController scrollController;
  final bool canScrollLeft;
  final bool canScrollRight;
  final VoidCallback onScrollLeft;
  final VoidCallback onScrollRight;
  final ValueChanged<VehicleType> onSelect;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (canScrollLeft)
          Positioned(
            left: 0,
            top: 86,
            child: _ScrollArrow(
              icon: Icons.chevron_left_rounded,
              onTap: onScrollLeft,
            ),
          ),
        if (canScrollRight)
          Positioned(
            right: 0,
            top: 86,
            child: _ScrollArrow(
              icon: Icons.chevron_right_rounded,
              onTap: onScrollRight,
            ),
          ),
        SizedBox(
          height: 252,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) => false,
            child: ListView.separated(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final VehicleType item = items[index];
                return _VehicleCard(
                  item: item,
                  isSelected: item.id == selectedId,
                  onTap: () => onSelect(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final VehicleType item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color borderColor =
        isSelected ? const Color(0xFF16A34A) : const Color(0xFFD9E2EC);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(isSelected ? 0.12 : 0.05),
            blurRadius: isSelected ? 22 : 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ColoredBox(
                    color: const Color(0xFFF4F7FB),
                    child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                        ? Image.network(
                            item.imageUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => const _VehicleImageFallback(),
                          )
                        : const _VehicleImageFallback(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFE9F7EF)
                          : const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFBBE4C9)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        item.volume == null
                            ? 'Volume variable'
                            : '${item.volume!.toStringAsFixed(item.volume! % 1 == 0 ? 0 : 1)} m3',
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF15803D)
                              : const Color(0xFF475569),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (item.description != null && item.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleImageFallback extends StatelessWidget {
  const _VehicleImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.local_shipping_outlined,
        size: 44,
        color: Color(0xFF94A3B8),
      ),
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 5,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: const Color(0xFF334155)),
        ),
      ),
    );
  }
}

class _SelectedVehicleSummary extends StatelessWidget {
  const _SelectedVehicleSummary({required this.vehicleType});

  final VehicleType? vehicleType;

  @override
  Widget build(BuildContext context) {
    if (vehicleType == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Sélectionnez un type d’engin pour continuer.'),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBDE1CB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF15803D),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Engin sélectionné : ${vehicleType!.name}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF166534),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleLoadingState extends StatelessWidget {
  const _VehicleLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 220,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _VehicleEmptyState extends StatelessWidget {
  const _VehicleEmptyState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Aucun type d’engin disponible pour le moment.',
        ),
      ),
    );
  }
}

class _VehicleErrorState extends StatelessWidget {
  const _VehicleErrorState({required this.onRetryMessage});

  final String onRetryMessage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5C2C7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          onRetryMessage,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFB42318),
          ),
        ),
      ),
    );
  }
}
