import 'package:flutter/material.dart';
import 'package:govipservices/app/config/runtime_app_config.dart';
import 'package:govipservices/features/travel/domain/models/additional_service_models.dart';
import 'package:govipservices/features/travel/presentation/widgets/address_autocomplete_field.dart';
import 'package:govipservices/shared/services/location_service.dart';

const Color _travelAccent = Color(0xFF14B8A6);
const Color _travelAccentDark = Color(0xFF0F766E);
const Color _travelAccentSoft = Color(0xFFD9FFFA);

// ── Comfort option model ─────────────────────────────────────────────────────

class ConfortOption {
  const ConfortOption({
    required this.id,
    required this.label,
    required this.icon,
    this.price,
  });
  final String id;
  final String label;
  final IconData icon;
  final int? price;
}

const List<ConfortOption> kConfortOptions = <ConfortOption>[
  ConfortOption(
      id: 'depot_gare',
      label: 'Me déposer à la gare',
      icon: Icons.directions_car_rounded),
  ConfortOption(
      id: 'gare_maison',
      label: 'De la gare à la maison',
      icon: Icons.home_rounded),
  ConfortOption(
      id: 'smart_food',
      label: 'Smart food (eau + sandwich)',
      icon: Icons.lunch_dining_rounded,
      price: 500),
];

// Maps ConfortOption.id → (AdditionalServiceType firestoreId, uses segmentFrom?)
const Map<String, (String, bool)> kOptionCoverageMap = <String, (String, bool)>{
  'depot_gare': ('domicile_gare', true),
  'gare_maison': ('gare_maison', false),
  'smart_food': ('kit_alimentaire', true),
};

// ── ConfortOptionsSheet ──────────────────────────────────────────────────────

class ConfortOptionsSheet extends StatefulWidget {
  const ConfortOptionsSheet({
    this.segmentFrom = '',
    this.segmentTo = '',
    this.additionalServices = const <AdditionalServiceDocument>[],
    super.key,
  });

  final String segmentFrom;
  final String segmentTo;
  final List<AdditionalServiceDocument> additionalServices;

  @override
  State<ConfortOptionsSheet> createState() => _ConfortOptionsSheetState();
}

class _ConfortOptionsSheetState extends State<ConfortOptionsSheet> {
  final Set<String> _selected = <String>{};
  String? _homeAddress;

  bool _isCovered(ConfortOption opt) {
    if (widget.additionalServices.isEmpty) return true;
    final (String firestoreId, bool useFrom) =
        kOptionCoverageMap[opt.id] ?? ('', true);
    if (firestoreId.isEmpty) return true;
    final AdditionalServiceDocument? svc = widget.additionalServices
        .cast<AdditionalServiceDocument?>()
        .firstWhere((s) => s!.type.firestoreId == firestoreId, orElse: () => null);
    if (svc == null) return false;
    final String address = useFrom ? widget.segmentFrom : widget.segmentTo;
    return svc.coversAddress(address);
  }

  Future<void> _handleOptionTap(ConfortOption opt) async {
    final bool wasSelected = _selected.contains(opt.id);
    if (opt.id == 'gare_maison') {
      if (wasSelected) {
        setState(() {
          _selected.remove(opt.id);
          _homeAddress = null;
        });
      } else {
        final double topOffset =
            kToolbarHeight + MediaQuery.of(context).padding.top;
        final String? address = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          useSafeArea: false,
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(context).size.height - topOffset),
          builder: (_) => const _HomeAddressSheet(),
        );
        if (!mounted) return;
        if (address != null && address.trim().isNotEmpty) {
          setState(() {
            _selected.add(opt.id);
            _homeAddress = address.trim();
          });
        }
      }
    } else {
      setState(() {
        if (wasSelected) {
          _selected.remove(opt.id);
        } else {
          _selected.add(opt.id);
        }
      });
    }
  }

  List<String> buildResult() {
    return _selected.map((id) {
      if (id == 'gare_maison' && _homeAddress != null) {
        return 'gare_maison:$_homeAddress';
      }
      return id;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFD1D9E6),
                borderRadius: BorderRadius.circular(99)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: _travelAccentSoft,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.stars_rounded,
                    color: _travelAccentDark, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Services Confort',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10233E))),
                    Text('Optionnels · Sélectionnez ce dont vous avez besoin',
                        style: TextStyle(fontSize: 12, color: Color(0xFF7A8CA8))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(kConfortOptions.length, (i) {
            final ConfortOption opt = kConfortOptions[i];
            final bool selected = _selected.contains(opt.id);
            final bool isGareMaison = opt.id == 'gare_maison';
            final bool covered = _isCovered(opt);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: covered ? 1.0 : 0.45,
                child: GestureDetector(
                  onTap: covered ? () => _handleOptionTap(opt) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? _travelAccentSoft : const Color(0xFFF8FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: selected
                              ? _travelAccentDark
                              : const Color(0xFFE2E8F0),
                          width: selected ? 1.5 : 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: selected
                                    ? _travelAccentDark
                                    : const Color(0xFFE8EDF5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(opt.icon,
                                  size: 18,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF5B647A)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(opt.label,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: selected
                                              ? _travelAccentDark
                                              : const Color(0xFF10233E))),
                                  if (!covered)
                                    const Text(
                                        'Non disponible dans votre ville',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9AA5B4)))
                                  else if (opt.price != null)
                                    Text('${opt.price} XOF',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: selected
                                                ? _travelAccentDark
                                                : const Color(0xFF7A8CA8)))
                                  else if (!selected && isGareMaison)
                                    const Text('Adresse requise',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9AA5B4))),
                                ],
                              ),
                            ),
                            if (covered)
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: selected
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: _travelAccentDark,
                                        key: ValueKey('checked'))
                                    : const Icon(
                                        Icons.radio_button_unchecked_rounded,
                                        color: Color(0xFFD1D9E6),
                                        key: ValueKey('unchecked')),
                              ),
                          ],
                        ),
                        if (isGareMaison && selected && _homeAddress != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      _travelAccentDark.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on_rounded,
                                    size: 14, color: _travelAccentDark),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _homeAddress!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF10233E)),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _handleOptionTap(opt),
                                  child: const Icon(Icons.edit_rounded,
                                      size: 14, color: Color(0xFF7A8CA8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _travelAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(buildResult()),
              child: Text(_selected.isEmpty
                  ? 'Réserver sans option'
                  : 'Réserver (${_selected.length} option${_selected.length > 1 ? "s" : ""})'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── HomeAddressSheet ─────────────────────────────────────────────────────────

class _HomeAddressSheet extends StatefulWidget {
  const _HomeAddressSheet();

  @override
  State<_HomeAddressSheet> createState() => _HomeAddressSheetState();
}

class _HomeAddressSheetState extends State<_HomeAddressSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _fetchingGps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _fetchingGps = true);
    try {
      final LocationResult? result = await LocationService.instance.getCurrent();
      if (!mounted) return;
      if (result != null && result.address.isNotEmpty) {
        _controller.text = result.address;
        Navigator.of(context).pop(result.address);
      }
    } finally {
      if (mounted) setState(() => _fetchingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD1D9E6),
                      borderRadius: BorderRadius.circular(99)),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: _travelAccentSoft,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.home_rounded,
                        color: _travelAccentDark, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Adresse de la maison',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF10233E))),
                        Text('Où souhaitez-vous être déposé ?',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF7A8CA8))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AddressAutocompleteField(
                controller: _controller,
                focusNode: _focus,
                labelText: 'Adresse',
                hintText: 'Ex: Rue de la Paix, Quartier...',
                apiKey: RuntimeAppConfig.googleMapsApiKey,
                onChanged: (_) {},
                onSuggestionSelected: (suggestion) {
                  Navigator.of(context).pop(suggestion.description);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _travelAccentDark,
                    side: const BorderSide(color: Color(0xFFD8F3EE)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _fetchingGps ? null : _useGps,
                  icon: _fetchingGps
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(_fetchingGps
                      ? 'Localisation...'
                      : 'Utiliser ma position actuelle'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _travelAccentDark,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _controller.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_controller.text.trim()),
                  child: const Text('Valider cette adresse'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
