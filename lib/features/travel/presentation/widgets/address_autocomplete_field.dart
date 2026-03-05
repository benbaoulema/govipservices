import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/data/google_places_service.dart';

class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.apiKey,
    this.onChanged,
    this.onSuggestionSelected,
    this.onPlaceResolved,
    this.focusNode,
    this.countries = const <String>['ci', 'fr'],
    super.key,
  });

  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final String apiKey;
  final ValueChanged<String>? onChanged;
  final ValueChanged<PlaceSuggestion>? onSuggestionSelected;
  final ValueChanged<PlaceDetailsResult>? onPlaceResolved;
  final FocusNode? focusNode;
  final List<String> countries;

  @override
  State<AddressAutocompleteField> createState() => _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField>
    with WidgetsBindingObserver {
  final FocusNode _internalFocusNode = FocusNode();
  final Random _random = Random();
  late final GooglePlacesAutocompleteService _service;
  late String _sessionToken;
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const <PlaceSuggestion>[];
  bool _isLoading = false;
  String? _errorText;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _service = GooglePlacesAutocompleteService(apiKey: widget.apiKey);
    _sessionToken = _nextSessionToken();
    _effectiveFocusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    _effectiveFocusNode.removeListener(_onFocusChanged);
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _nextSessionToken() {
    final int timestamp = DateTime.now().microsecondsSinceEpoch;
    final int nonce = _random.nextInt(1 << 31);
    return '$timestamp-$nonce';
  }

  void _onFocusChanged() {
    if (!_effectiveFocusNode.hasFocus) {
      setState(() {
        _suggestions = const <PlaceSuggestion>[];
        _errorText = null;
      });
    } else {
      _sessionToken = _nextSessionToken();
    }
  }

  Future<void> _search(String value) async {
    final String query = value.trim();
    if (query.length < 3) {
      setState(() {
        _isLoading = false;
        _suggestions = const <PlaceSuggestion>[];
        _errorText = null;
      });
      return;
    }

    if (widget.apiKey.isEmpty) {
      setState(() {
        _isLoading = false;
        _suggestions = const <PlaceSuggestion>[];
        _errorText = 'Cle Google Maps absente. Lancez l app avec --dart-define=GOOGLE_MAPS_API_KEY=...';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final List<PlaceSuggestion> result = await _service.getSuggestions(
        input: query,
        sessionToken: _sessionToken,
        countries: widget.countries,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = result;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _suggestions = const <PlaceSuggestion>[];
        _errorText = 'Impossible de recuperer les suggestions.';
      });
    }
  }

  void _onTextChanged(String value) {
    widget.onChanged?.call(value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  void _selectSuggestion(PlaceSuggestion suggestion) {
    widget.controller.text = suggestion.description;
    widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    widget.onChanged?.call(widget.controller.text);
    widget.onSuggestionSelected?.call(suggestion);
    setState(() {
      _suggestions = const <PlaceSuggestion>[];
      _errorText = null;
    });
    _effectiveFocusNode.unfocus();
    _resolveSelectionDetails(suggestion);
  }

  Future<void> _resolveSelectionDetails(PlaceSuggestion suggestion) async {
    if (widget.onPlaceResolved == null || widget.apiKey.isEmpty) return;
    try {
      final PlaceDetailsResult? details = await _service.getPlaceDetails(
        placeId: suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (details == null || !mounted) return;

      final String resolvedAddress = details.address.trim().isEmpty ? suggestion.description : details.address;
      if (resolvedAddress != widget.controller.text) {
        widget.controller.text = resolvedAddress;
        widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
        widget.onChanged?.call(widget.controller.text);
      }
      widget.onPlaceResolved?.call(details);
    } catch (_) {
      // Keep autocomplete responsive even if details request fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _effectiveFocusNode,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            filled: true,
            fillColor: const Color(0xFFF4FBF7),
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
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : widget.controller.text.trim().isNotEmpty
                    ? IconButton(
                        tooltip: 'Effacer',
                        onPressed: () {
                          widget.controller.clear();
                          widget.onChanged?.call('');
                          setState(() {
                            _suggestions = const <PlaceSuggestion>[];
                            _errorText = null;
                          });
                          _effectiveFocusNode.requestFocus();
                        },
                        icon: const Icon(Icons.close_rounded),
                      )
                    : const Icon(Icons.location_on_outlined),
          ),
          onChanged: _onTextChanged,
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red.shade700),
          ),
        ],
        if (_effectiveFocusNode.hasFocus && _suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Material(
            elevation: 8,
            color: Colors.white,
            shadowColor: Colors.black.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final PlaceSuggestion suggestion = _suggestions[index];
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFE7F6ED),
                      child: Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      suggestion.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                    onTap: () => _selectSuggestion(suggestion),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
