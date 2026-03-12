import 'package:govipservices/features/notifications/domain/models/app_notification.dart';

abstract class NotificationsRepository {
  Future<void> createNotification(CreateAppNotificationInput input);

  Future<void> createNotifications(List<CreateAppNotificationInput> inputs);

  Future<List<AppNotification>> fetchNotifications(
    String userId, {
    int limit = 50,
  });

  Future<int> fetchUnreadCount(String userId);

  Future<void> markAsRead(String notificationId);

  Future<void> markAsUnread(String notificationId);

  Future<void> markAllAsRead(String userId);
}
