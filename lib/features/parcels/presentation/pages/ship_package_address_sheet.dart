part of 'ship_package_page.dart';

class _AddressSearchSheetRoute extends StatefulWidget {
  const _AddressSearchSheetRoute({required this.child});

  final Widget child;

  @override
  State<_AddressSearchSheetRoute> createState() => _AddressSearchSheetRouteState();
}

class _AddressSearchSheetRouteState extends State<_AddressSearchSheetRoute> {
  double _dragOffset = 0;

  void _handleDragUpdate(DragUpdateDetails details) {
    final double nextOffset = (_dragOffset + details.delta.dy).clamp(0, 220);
    if (nextOffset == _dragOffset) return;
    setState(() {
      _dragOffset = nextOffset;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 120 || velocity > 900) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _dragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        final double maxHeight =
            constraints.maxHeight - mediaQuery.padding.top - 6;

        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.36, end: 1),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double value, Widget? child) {
                  final double height = maxHeight * value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(
                      0,
                      ((1 - value) * 24) + _dragOffset,
                      0,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragUpdate: _handleDragUpdate,
                        onVerticalDragEnd: _handleDragEnd,
                        child: child,
                      ),
                    ),
                  );
                },
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AddressSheetCompanionConfig {
  const _AddressSheetCompanionConfig({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
}

class _AddressSearchSheet extends StatefulWidget {
  const _AddressSearchSheet({
    required this.title,
    required this.apiKey,
    required this.initialAddress,
    required this.labelText,
    required this.hintText,
    required this.onResolved,
  });

  static _AddressSheetCompanionConfig? companionConfig;

  final String title;
  final String apiKey;
  final String initialAddress;
  final String labelText;
  final String hintText;
  final ValueChanged<PlaceDetailsResult> onResolved;

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _entered = true;
        });
      }
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _AddressSheetCompanionConfig? companionConfig =
        _AddressSearchSheet.companionConfig;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: _entered ? 1 : 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFF9FBFA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DBE4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 220.ms)
                    .slideY(begin: -0.8, end: 0, duration: 320.ms),
              ),
              const SizedBox(height: 16),
                Row(
                  children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Fermer',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 40.ms, duration: 220.ms)
                      .slideX(begin: -0.2, end: 0, duration: 280.ms),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                    )
                        .animate()
                        .fadeIn(delay: 80.ms, duration: 240.ms)
                        .slideY(begin: 0.15, end: 0, duration: 320.ms),
                  ),
                ],
              ),
              if (companionConfig != null) ...[
                const SizedBox(height: 14),
                InkWell(
                  onTap: companionConfig.onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: _SlimAddressBar(
                    icon: Icons.swap_horiz_rounded,
                    iconColor: const Color(0xFF0F766E),
                    label: companionConfig.label,
                    value: companionConfig.value,
                    trailingIcon: Icons.chevron_right_rounded,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 145.ms, duration: 250.ms)
                    .slideY(begin: 0.2, end: 0, duration: 340.ms),
              ],
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      blurRadius: 22,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.labelText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF0F172A),
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Recherchez un lieu précis pour continuer.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF667085),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: InputDecorationTheme(
                            labelStyle: const TextStyle(
                              color: Color(0xFF475467),
                              fontWeight: FontWeight.w700,
                            ),
                            hintStyle: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontWeight: FontWeight.w500,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFF0F766E),
                                width: 1.8,
                              ),
                            ),
                          ),
                        ),
                        child: AddressAutocompleteField(
                          controller: _controller,
                          focusNode: _focusNode,
                          labelText: widget.labelText,
                          hintText: widget.hintText,
                          apiKey: widget.apiKey,
                          countries: const <String>['ci', 'fr'],
                          suggestionTypes: null,
                          onPlaceResolved: widget.onResolved,
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  .animate()
                  .fadeIn(delay: 160.ms, duration: 260.ms)
                  .slideY(begin: 0.22, end: 0, duration: 360.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlimAddressBar extends StatelessWidget {
  const _SlimAddressBar({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.trailingIcon,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Text(
              '$label :',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                  ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 8),
              Icon(
                trailingIcon,
                color: const Color(0xFF94A3B8),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
