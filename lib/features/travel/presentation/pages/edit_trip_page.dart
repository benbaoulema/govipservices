import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/data/google_places_service.dart';
import 'package:govipservices/features/travel/data/travel_repository.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

class EditTripPage extends StatefulWidget {
  const EditTripPage({
    required this.tripId,
    super.key,
  });

  final String tripId;

  @override
  State<EditTripPage> createState() => _EditTripPageState();
}

class _EditTripPageState extends State<EditTripPage> {
  static const String _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TravelRepository _travelRepository = TravelRepository();
  final TextEditingController _departureController = TextEditingController();
  final TextEditingController _arrivalController = TextEditingController();
  final TextEditingController _driverController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _seatsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isBus = false;
  bool _hasLuggageSpace = true;
  bool _allowsPets = false;
  String _currency = 'XOF';
  String _tripFrequency = 'none';
  DateTime? _departureDate;
  TimeOfDay? _departureTime;
  _EditableRoutePoint _departurePoint = const _EditableRoutePoint(address: '');
  _EditableRoutePoint _arrivalPoint = const _EditableRoutePoint(address: '');
  List<Map<String, dynamic>> _intermediateStops = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _existingTrip;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  @override
  void dispose() {
    _departureController.dispose();
    _arrivalController.dispose();
    _driverController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _priceController.dispose();
    _seatsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadTrip() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final Map<String, dynamic>? raw = await _travelRepository.getTripRawById(widget.tripId);
      if (raw == null || !mounted) return;

      _existingTrip = raw;
      final String departurePlace = (raw['departurePlace'] as String? ?? '').trim();
      final String arrivalPlace = (raw['arrivalPlace'] as String? ?? '').trim();

      setState(() {
        _departureController.text = departurePlace;
        _arrivalController.text = arrivalPlace;
        _driverController.text = (raw['driverName'] as String? ?? '').trim();
        _phoneController.text = (raw['contactPhone'] as String? ?? '').trim();
        _vehicleController.text = (raw['vehicleModel'] as String? ?? '').trim();
        _priceController.text = (((raw['pricePerSeat'] as num?) ?? 0).toDouble()).toStringAsFixed(0);
        _seatsController.text = (((raw['seats'] as num?) ?? 1).toInt()).toString();
        _notesController.text = (raw['notes'] as String? ?? '').trim();
        _currency = ((raw['currency'] as String?)?.trim().isNotEmpty ?? false)
            ? (raw['currency'] as String).trim().toUpperCase()
            : 'XOF';
        _tripFrequency = ((raw['tripFrequency'] as String?)?.trim().isNotEmpty ?? false)
            ? (raw['tripFrequency'] as String).trim()
            : 'none';
        _isBus = raw['isBus'] == true;
        _hasLuggageSpace = raw['hasLuggageSpace'] != false;
        _allowsPets = raw['allowsPets'] == true;
        _departureDate = _parseDate((raw['departureDate'] as String? ?? '').trim());
        _departureTime = _parseTime((raw['departureTime'] as String? ?? '').trim());
        _departurePoint = _EditableRoutePoint(
          address: departurePlace,
          lat: (raw['departureLat'] as num?)?.toDouble(),
          lng: (raw['departureLng'] as num?)?.toDouble(),
        );
        _arrivalPoint = _EditableRoutePoint(
          address: arrivalPlace,
          lat: (raw['arrivalLat'] as num?)?.toDouble(),
          lng: (raw['arrivalLng'] as num?)?.toDouble(),
        );
        _intermediateStops = (raw['intermediateStops'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  DateTime? _parseDate(String raw) {
    final Match? match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final int? year = int.tryParse(match.group(1)!);
    final int? month = int.tryParse(match.group(2)!);
    final int? day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  TimeOfDay? _parseTime(String raw) {
    final Match? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final int? hour = int.tryParse(match.group(1)!);
    final int? minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatApiDate(DateTime? value) {
    if (value == null) return '';
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _formatTime(TimeOfDay? value) {
    if (value == null) return '';
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickDate() async {
    final DateTime today = DateTime.now();
    final DateTime initial = _departureDate ?? today;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 2),
      locale: const Locale('fr', 'FR'),
    );
    if (picked == null) return;
    setState(() {
      _departureDate = picked;
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay initial = _departureTime ?? TimeOfDay.now();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    setState(() {
      _departureTime = picked;
    });
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? const Color(0xFF991B1B) : const Color(0xFF0F766E),
          content: Text(message),
        ),
      );
  }

  Future<void> _save() async {
    if (_existingTrip == null) return;
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_departureDate == null || _departureTime == null) {
      _showMessage('Renseignez la date et l\'heure du trajet.', error: true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final Map<String, dynamic> existing = _existingTrip!;
      final Map<String, dynamic> payload = <String, dynamic>{
        'departurePlace': _departureController.text.trim(),
        'arrivalPlace': _arrivalController.text.trim(),
        'departureLat': _departurePoint.lat,
        'departureLng': _departurePoint.lng,
        'arrivalLat': _arrivalPoint.lat,
        'arrivalLng': _arrivalPoint.lng,
        'arrivalEstimatedTime': existing['arrivalEstimatedTime'],
        'currency': _currency,
        'vehiclePhotoUrl': existing['vehiclePhotoUrl'],
        'intermediateStops': _intermediateStops,
        'departureDate': _formatApiDate(_departureDate),
        'departureTime': _formatTime(_departureTime),
        'seats': int.tryParse(_seatsController.text.trim()) ?? 1,
        'pricePerSeat': double.tryParse(_priceController.text.trim().replaceAll(',', '.')) ?? 0,
        'vehicleModel': _vehicleController.text.trim(),
        'isBus': _isBus,
        'isFrequentTrip': _tripFrequency != 'none',
        'tripFrequency': _tripFrequency,
        'driverName': _driverController.text.trim(),
        'contactPhone': _phoneController.text.trim(),
        'hasLuggageSpace': _hasLuggageSpace,
        'allowsPets': _allowsPets,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'maxWeightKg': existing['maxWeightKg'],
        'ownerUid': existing['ownerUid'],
        'ownerEmail': existing['ownerEmail'],
        'status': existing['status'] ?? 'published',
      };

      final result = await _travelRepository.updateTrip(widget.tripId, payload);
      if (!mounted) return;
      _showMessage(
        result.alertCount > 0
            ? 'Trajet modifié. Les voyageurs concernés seront informés.'
            : 'Trajet modifié avec succès.',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      _showMessage('Modification impossible: $error', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Modifier le trajet'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _isLoading || _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_isSaving ? 'Enregistrement...' : 'Enregistrer'),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _EditSectionCard(
                    title: 'Trajet',
                    child: Column(
                      children: [
                        AddressAutocompleteField(
                          controller: _departureController,
                          labelText: 'Adresse de départ',
                          hintText: 'Ex: Cocody, Abidjan',
                          apiKey: _googleMapsApiKey,
                          onChanged: (value) {
                            _departurePoint = _EditableRoutePoint(address: value);
                          },
                          onPlaceResolved: (details) {
                            _departurePoint = _EditableRoutePoint(
                              address: details.address,
                              lat: details.lat,
                              lng: details.lng,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        AddressAutocompleteField(
                          controller: _arrivalController,
                          labelText: 'Adresse d\'arrivée',
                          hintText: 'Ex: Yamoussoukro',
                          apiKey: _googleMapsApiKey,
                          onChanged: (value) {
                            _arrivalPoint = _EditableRoutePoint(address: value);
                          },
                          onPlaceResolved: (details) {
                            _arrivalPoint = _EditableRoutePoint(
                              address: details.address,
                              lat: details.lat,
                              lng: details.lng,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditSectionCard(
                    title: 'Date et heure',
                    child: Row(
                      children: [
                        Expanded(
                          child: _PickerTile(
                            label: 'Date',
                            value: _departureDate == null
                                ? 'Choisir'
                                : '${_departureDate!.day.toString().padLeft(2, '0')}/${_departureDate!.month.toString().padLeft(2, '0')}/${_departureDate!.year}',
                            icon: Icons.calendar_today_rounded,
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PickerTile(
                            label: 'Heure',
                            value: _departureTime == null ? 'Choisir' : _formatTime(_departureTime),
                            icon: Icons.schedule_rounded,
                            onTap: _pickTime,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditSectionCard(
                    title: 'Capacité et tarif',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _seatsController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Places',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final int? seats = int.tryParse((value ?? '').trim());
                                  if (seats == null || seats < 1) return 'Invalide';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _priceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Prix par place',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  final double? price =
                                      double.tryParse((value ?? '').trim().replaceAll(',', '.'));
                                  if (price == null || price < 0) return 'Invalide';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _currency,
                          items: const [
                            DropdownMenuItem(value: 'XOF', child: Text('XOF')),
                            DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _currency = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Devise',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditSectionCard(
                    title: 'Conducteur et véhicule',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _driverController,
                          decoration: const InputDecoration(
                            labelText: 'Nom du conducteur',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Contact',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _vehicleController,
                          decoration: const InputDecoration(
                            labelText: 'Véhicule',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Transporteur pro / bus'),
                          value: _isBus,
                          onChanged: (value) => setState(() => _isBus = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditSectionCard(
                    title: 'Options',
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          value: _tripFrequency,
                          items: const [
                            DropdownMenuItem(value: 'none', child: Text('Ponctuel')),
                            DropdownMenuItem(value: 'daily', child: Text('Quotidien')),
                            DropdownMenuItem(value: 'weekly', child: Text('Hebdomadaire')),
                            DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _tripFrequency = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Fréquence',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Bagages autorisés'),
                          value: _hasLuggageSpace,
                          onChanged: (value) => setState(() => _hasLuggageSpace = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Animaux autorisés'),
                          value: _allowsPets,
                          onChanged: (value) => setState(() => _allowsPets = value),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditSectionCard(
                    title: 'Arrêts intermédiaires',
                    child: _intermediateStops.isEmpty
                        ? const Text(
                            'Aucun arrêt intermédiaire configuré pour ce trajet.',
                            style: TextStyle(
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : Column(
                            children: [
                              for (final stop in _intermediateStops) ...[
                                _StopPreviewTile(stop: stop),
                                if (stop != _intermediateStops.last) const SizedBox(height: 8),
                              ],
                              const SizedBox(height: 10),
                              const Text(
                                'Les arrêts intermédiaires actuels sont conservés.',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
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

class _EditableRoutePoint {
  const _EditableRoutePoint({
    required this.address,
    this.lat,
    this.lng,
  });

  final String address;
  final double? lat;
  final double? lng;
}

class _EditSectionCard extends StatelessWidget {
  const _EditSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF10233E),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF0F766E)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF10233E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StopPreviewTile extends StatelessWidget {
  const _StopPreviewTile({
    required this.stop,
  });

  final Map<String, dynamic> stop;

  @override
  Widget build(BuildContext context) {
    final String address = (stop['address'] ?? '').toString().trim();
    final String estimatedTime = (stop['estimatedTime'] ?? '').toString().trim();
    final String price = '${(stop['priceFromDeparture'] ?? 0)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            address.isEmpty ? 'Arrêt sans adresse' : address,
            style: const TextStyle(
              color: Color(0xFF10233E),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Heure: ${estimatedTime.isEmpty ? '--:--' : estimatedTime} • Prix depuis départ: $price',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
