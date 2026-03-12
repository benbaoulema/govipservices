import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/notifications/data/firestore_notifications_repository.dart';

class NotificationsAppBarButton extends StatefulWidget {
  const NotificationsAppBarButton({super.key});

  @override
  State<NotificationsAppBarButton> createState() =>
      _NotificationsAppBarButtonState();
}

class _NotificationsAppBarButtonState extends State<NotificationsAppBarButton> {
  final FirestoreNotificationsRepository _repository =
      FirestoreNotificationsRepository();

  late Future<int> _unreadCountFuture;

  @override
  void initState() {
    super.initState();
    _unreadCountFuture = _loadUnreadCount();
  }

  Future<int> _loadUnreadCount() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return Future<int>.value(0);
    return _repository.fetchUnreadCount(user.uid);
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).pushNamed(AppRoutes.userNotifications);
    if (!mounted) return;
    setState(() {
      _unreadCountFuture = _loadUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        tooltip: 'Notifications',
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.authLogin),
        icon: const Icon(Icons.notifications_none_rounded),
      );
    }

    return FutureBuilder<int>(
      future: _unreadCountFuture,
      initialData: 0,
      builder: (context, snapshot) {
        final int unreadCount = snapshot.data ?? 0;
        return IconButton(
          tooltip: 'Notifications',
          onPressed: _openNotifications,
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}
