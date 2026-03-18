import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/features/notifications/data/firestore_notifications_repository.dart';
import 'package:govipservices/features/notifications/domain/models/app_notification.dart';
import 'package:govipservices/features/notifications/presentation/notification_navigation.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

enum _NotificationsFilter { all, unread }

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirestoreNotificationsRepository _repository =
      FirestoreNotificationsRepository();
  final NotificationNavigation _notificationNavigation = NotificationNavigation();

  _NotificationsFilter _filter = _NotificationsFilter.all;
  late Future<List<AppNotification>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _loadNotifications();
  }

  Future<List<AppNotification>> _loadNotifications() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Future<List<AppNotification>>.value(const <AppNotification>[]);
    }
    return _repository.fetchNotifications(user.uid);
  }

  Future<void> _refreshNotifications() async {
    final Future<List<AppNotification>> next = _loadNotifications();
    setState(() {
      _notificationsFuture = next;
    });
    await next;
  }

  Future<void> _handleNotificationTap(AppNotification notification) async {
    if (notification.isUnread) {
      await _repository.markAsRead(notification.id);
      await _refreshNotifications();
    }
    if (!mounted) return;

    final String? info = await _notificationNavigation.openFromAppNotification(
      context,
      notification,
    );
    if (info != null && mounted) {
      _showMessage(info);
    }
  }

  Future<void> _toggleRead(AppNotification notification) async {
    if (notification.isUnread) {
      await _repository.markAsRead(notification.id);
    } else {
      await _repository.markAsUnread(notification.id);
    }
    await _refreshNotifications();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Notifications'),
        actions: [
          if (user != null)
            TextButton(
              onPressed: () async {
                await _repository.markAllAsRead(user.uid);
                await _refreshNotifications();
              },
              child: const Text('Tout lire'),
            ),
        ],
      ),
      body: user == null
          ? const _NotificationsGuestState()
          : FutureBuilder<List<AppNotification>>(
              future: _notificationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<AppNotification> notifications =
                    snapshot.data ?? const <AppNotification>[];
                final List<AppNotification> visibleNotifications =
                    _filter == _NotificationsFilter.unread
                        ? notifications.where((n) => n.isUnread).toList(growable: false)
                        : notifications;

                if (notifications.isEmpty) {
                  return const _NotificationsEmptyState();
                }

                return RefreshIndicator(
                  onRefresh: _refreshNotifications,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      _NotificationsFilterBar(
                        filter: _filter,
                        unreadCount: notifications.where((n) => n.isUnread).length,
                        onChanged: (next) {
                          setState(() {
                            _filter = next;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (visibleNotifications.isEmpty)
                        const _NotificationsFilteredEmptyState()
                      else
                        for (int i = 0; i < visibleNotifications.length; i++) ...[
                          _NotificationCard(
                            notification: visibleNotifications[i],
                            onTap: () => _handleNotificationTap(visibleNotifications[i]),
                            onToggleRead: () => _toggleRead(visibleNotifications[i]),
                          ),
                          if (i < visibleNotifications.length - 1)
                            const SizedBox(height: 12),
                        ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _NotificationsGuestState extends StatelessWidget {
  const _NotificationsGuestState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Connectez-vous pour retrouver vos notifications.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475467),
          ),
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: Color(0xFF98A2B3),
            ),
            SizedBox(height: 14),
            Text(
              'Aucune notification pour le moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475467),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsFilteredEmptyState extends StatelessWidget {
  const _NotificationsFilteredEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Aucune notification non lue.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475467),
        ),
      ),
    );
  }
}

class _NotificationsFilterBar extends StatelessWidget {
  const _NotificationsFilterBar({
    required this.filter,
    required this.unreadCount,
    required this.onChanged,
  });

  final _NotificationsFilter filter;
  final int unreadCount;
  final ValueChanged<_NotificationsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Toutes'),
          selected: filter == _NotificationsFilter.all,
          onSelected: (_) => onChanged(_NotificationsFilter.all),
        ),
        const SizedBox(width: 10),
        ChoiceChip(
          label: Text(unreadCount > 0 ? 'Non lues ($unreadCount)' : 'Non lues'),
          selected: filter == _NotificationsFilter.unread,
          onSelected: (_) => onChanged(_NotificationsFilter.unread),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onToggleRead,
  });

  final AppNotification notification;
  final Future<void> Function() onTap;
  final Future<void> Function() onToggleRead;

  @override
  Widget build(BuildContext context) {
    final DateTime? createdAt = notification.createdAt?.toDate();
    final String subtitle = createdAt == null
        ? notification.body
        : '${notification.body}\n${_formatNotificationTime(createdAt)}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onToggleRead,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: notification.isUnread
                ? const Color(0xFFF8FAFC)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: notification.isUnread
                  ? const Color(0xFFBFDBFE)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _iconBackground(notification.domain),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _iconForType(notification.type),
                  color: _iconColor(notification.domain),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10233E),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: notification.isUnread
                              ? 'Marquer comme lue'
                              : 'Marquer comme non lue',
                          onPressed: onToggleRead,
                          icon: Icon(
                            notification.isUnread
                                ? Icons.mark_email_read_outlined
                                : Icons.mark_email_unread_outlined,
                            size: 20,
                            color: notification.isUnread
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        height: 1.4,
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _ctaLabel(notification),
                      style: TextStyle(
                        color: _iconColor(notification.domain),
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

String _ctaLabel(AppNotification notification) {
  switch (notification.type.trim()) {
    case 'parcel_request_created':
      return 'Voir la demande colis';
    case 'booking_created':
      return 'Voir les réservations du trajet';
    case 'booking_status_updated':
      return 'Voir la réservation';
    case 'booking_cancelled':
      return 'Voir le trajet';
    case 'trip_updated':
      return 'Voir les changements';
    case 'trip_cancelled':
      return 'Voir le trajet annulé';
    default:
      return 'Ouvrir';
  }
}

Color _iconBackground(String domain) {
  switch (domain.trim()) {
    case 'parcel':
      return const Color(0xFFECFDF3);
    case 'travel':
    default:
      return const Color(0xFFDBEAFE);
  }
}

Color _iconColor(String domain) {
  switch (domain.trim()) {
    case 'parcel':
      return const Color(0xFF027A48);
    case 'travel':
    default:
      return const Color(0xFF1D4ED8);
  }
}

IconData _iconForType(String type) {
  switch (type.trim()) {
    case 'parcel_request_created':
      return Icons.local_shipping_outlined;
    case 'booking_created':
      return Icons.confirmation_number_outlined;
    case 'booking_status_updated':
      return Icons.verified_outlined;
    case 'booking_cancelled':
      return Icons.person_off_outlined;
    case 'trip_updated':
      return Icons.route_outlined;
    case 'trip_cancelled':
      return Icons.event_busy_outlined;
    default:
      return Icons.notifications_none_rounded;
  }
}

String _formatNotificationTime(DateTime value) {
  final Duration diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'À l\'instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
  return 'Il y a ${diff.inDays} j';
}
