import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:govipservices/features/travel/data/go_radar_repository.dart';
import 'package:govipservices/features/travel/presentation/services/go_radar_reminder_service.dart';

// ─── Couleurs ─────────────────────────────────────────────────────────────────

const Color _accent = Color(0xFF14B8A6);
const Color _accentDark = Color(0xFF0F766E);
const Color _bg = Color(0xFFF2FFFC);
const Color _surface = Color(0xFFFFFFFF);
const Color _border = Color(0xFFD8F3EE);

// ─── Page ─────────────────────────────────────────────────────────────────────

class GoRadarUpdatePage extends StatefulWidget {
  const GoRadarUpdatePage({super.key, required this.args});

  final GoRadarSessionArgs args;

  @override
  State<GoRadarUpdatePage> createState() => _GoRadarUpdatePageState();
}

class _GoRadarUpdatePageState extends State<GoRadarUpdatePage> {
  final GoRadarRepository _repo = GoRadarRepository();

  GoRadarSession? _session;
  bool _loadingSession = true;

  GoRadarStatus _status = GoRadarStatus.chargement;
  int _availableSeats = 0;

  Position? _position;
  bool _fetchingLocation = false;
  String _locationLabel = 'Position non capturée';

  bool _sending = false;
  String? _lastSentAt;

  // Rappel périodique
  bool _reminderActive = false;
  int _reminderMinutes = 10;

  @override
  void initState() {
    super.initState();
    _openSession();
    _fetchLocation();
  }

  @override
  void dispose() {
    // Annule les notifications si l'écran est fermé
    if (_reminderActive) {
      GoRadarReminderService.instance.cancelAll();
    }
    super.dispose();
  }

  // ── Session ────────────────────────────────────────────────────────────────

  Future<void> _openSession() async {
    try {
      final session = await _repo.openSession(widget.args);
      if (!mounted) return;
      setState(() {
        _session = session;
        _status = session.status;
        _availableSeats = session.availableSeats;
        _loadingSession = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSession = false);
      _showError('Impossible d\'ouvrir la session GO Radar');
    }
  }

  // ── GPS ────────────────────────────────────────────────────────────────────

  Future<void> _fetchLocation() async {
    setState(() => _fetchingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _locationLabel = 'Permission GPS refusée';
          _fetchingLocation = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _position = pos;
        _locationLabel =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
        _fetchingLocation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationLabel = 'Position indisponible';
        _fetchingLocation = false;
      });
    }
  }

  // ── Envoi ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    if (_session == null || _sending) return;
    setState(() => _sending = true);

    // Rafraîchit la position avant d'envoyer
    await _fetchLocation();

    final now = TimeOfDay.now();
    final departureRealTime =
        _status == GoRadarStatus.enRoute && _session!.departureRealTime == null
            ? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
            : null;

    try {
      await _repo.pushUpdate(
        sessionId: _session!.id,
        status: _status,
        availableSeats: _availableSeats,
        lat: _position?.latitude,
        lng: _position?.longitude,
        departureRealTime: departureRealTime,
      );

      if (!mounted) return;
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      setState(() {
        _lastSentAt = '$h:$m';
        _sending = false;
        if (departureRealTime != null) {
          _session = GoRadarSession(
            id: _session!.id,
            tripId: _session!.tripId,
            companyId: _session!.companyId,
            companyName: _session!.companyName,
            departure: _session!.departure,
            arrival: _session!.arrival,
            scheduledTime: _session!.scheduledTime,
            slotNumber: _session!.slotNumber,
            date: _session!.date,
            status: _status,
            availableSeats: _availableSeats,
            reporterUid: _session!.reporterUid,
            lastUpdatedAt: DateTime.now(),
            lastLat: _position?.latitude,
            lastLng: _position?.longitude,
            departureRealTime: departureRealTime,
          );
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mise à jour envoyée'),
          backgroundColor: _accentDark,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      _showError('Erreur lors de l\'envoi');
    }
  }

  // ── Rappel ─────────────────────────────────────────────────────────────────

  Future<void> _toggleReminder(bool active) async {
    setState(() => _reminderActive = active);
    if (active) {
      await GoRadarReminderService.instance
          .start(intervalMinutes: _reminderMinutes);
    } else {
      await GoRadarReminderService.instance.cancelAll();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'GO Radar — Reporter',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: _loadingSession
          ? const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TripSummaryCard(args: widget.args),
                const SizedBox(height: 16),
                _StatusSelector(
                  selected: _status,
                  onSelect: (s) => setState(() => _status = s),
                ),
                const SizedBox(height: 16),
                _SeatsSelector(
                  value: _availableSeats,
                  onChanged: (v) => setState(() => _availableSeats = v),
                ),
                const SizedBox(height: 16),
                _LocationCard(
                  label: _locationLabel,
                  loading: _fetchingLocation,
                  onRefresh: _fetchLocation,
                ),
                const SizedBox(height: 16),
                _ReminderCard(
                  active: _reminderActive,
                  minutes: _reminderMinutes,
                  onToggle: _toggleReminder,
                  onMinutesChanged: (m) {
                    setState(() => _reminderMinutes = m);
                    if (_reminderActive) _toggleReminder(true); // replanifie
                  },
                ),
                if (_lastSentAt != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Dernière mise à jour envoyée à $_lastSentAt',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accentDark,
                      disabledBackgroundColor: Colors.grey.shade200,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _sending ? 'Envoi...' : 'Envoyer la mise à jour',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

// ─── Récapitulatif du voyage ──────────────────────────────────────────────────

class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({required this.args});
  final GoRadarSessionArgs args;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _accentDark,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                args.companyName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Départ ${args.slotNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  args.departure,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white70, size: 18),
              Expanded(
                child: Text(
                  args.arrival,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Départ prévu : ${args.scheduledTime}  •  ${args.date}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sélecteur de statut ─────────────────────────────────────────────────────

class _StatusSelector extends StatelessWidget {
  const _StatusSelector({required this.selected, required this.onSelect});
  final GoRadarStatus selected;
  final void Function(GoRadarStatus) onSelect;

  static const _statuses = GoRadarStatus.values;

  static IconData _icon(GoRadarStatus s) => switch (s) {
        GoRadarStatus.chargement => Icons.hourglass_top_rounded,
        GoRadarStatus.enRoute => Icons.directions_bus_rounded,
        GoRadarStatus.arrive => Icons.location_on_rounded,
        GoRadarStatus.termine => Icons.flag_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Statut du voyage',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(_statuses.length, (i) {
            final s = _statuses[i];
            final bool isSelected = s == selected;
            return GestureDetector(
              onTap: () => onSelect(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.only(bottom: i < _statuses.length - 1 ? 8 : 0),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _accent.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _accent : Colors.grey.shade200,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      _icon(s),
                      size: 20,
                      color: isSelected ? _accentDark : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? _accentDark
                              : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: _accent,
                        size: 18,
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Stepper places ───────────────────────────────────────────────────────────

class _SeatsSelector extends StatelessWidget {
  const _SeatsSelector({required this.value, required this.onChanged});
  final int value;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.event_seat_outlined, color: _accentDark, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Places disponibles',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            onTap: value > 0 ? () => onChanged(value - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$value',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? _accent.withValues(alpha: 0.10)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? _accentDark : Colors.grey.shade300,
        ),
      ),
    );
  }
}

// ─── Carte position GPS ──────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.label,
    required this.loading,
    required this.onRefresh,
  });
  final String label;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            Icons.my_location_rounded,
            color: loading ? Colors.grey.shade400 : _accentDark,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Position GPS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading ? 'Localisation...' : label,
                  style: TextStyle(
                    fontSize: 12,
                    color: loading
                        ? Colors.grey.shade400
                        : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: _accent,
                strokeWidth: 2,
              ),
            )
          else
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: _accentDark,
              tooltip: 'Rafraîchir la position',
            ),
        ],
      ),
    );
  }
}

// ─── Carte rappel ─────────────────────────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.active,
    required this.minutes,
    required this.onToggle,
    required this.onMinutesChanged,
  });
  final bool active;
  final int minutes;
  final void Function(bool) onToggle;
  final void Function(int) onMinutesChanged;

  static const _options = [5, 10, 15, 20, 30];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                color: _accentDark,
                size: 22,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Rappel de mise à jour',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Switch(
                value: active,
                onChanged: onToggle,
                activeColor: _accentDark,
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _options.map((m) {
                  final bool sel = m == minutes;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => onMinutesChanged(m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? _accentDark
                              : _accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${m}min',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : _accentDark,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
