import 'package:govipservices/features/user/models/app_user.dart';
import 'package:govipservices/features/user/models/user_role.dart';

bool isAdminRole(UserRole? role) {
  return role == UserRole.superAdmin ||
      role == UserRole.admin ||
      role == UserRole.manager ||
      role == UserRole.moderator ||
      role == UserRole.support ||
      role == UserRole.staff;
}

bool canAccessAdminArea(AppUser? user) => isAdminRole(user?.role);

bool isSuperAdmin(AppUser? user) => user?.role == UserRole.superAdmin;

bool isAdmin(AppUser? user) {
  final UserRole? role = user?.role;
  return role == UserRole.admin || role == UserRole.superAdmin;
}

bool isManager(AppUser? user) => user?.role == UserRole.manager;

bool isStaff(AppUser? user) {
  final UserRole? role = user?.role;
  return role == UserRole.staff || role == UserRole.admin || role == UserRole.superAdmin;
}

bool isModerator(AppUser? user) => user?.role == UserRole.moderator;

bool isSupport(AppUser? user) => user?.role == UserRole.support;

bool isPro(AppUser? user) => user?.role == UserRole.pro;

bool isSimpleUser(AppUser? user) => user?.role == UserRole.simpleUser;

bool hasRole(AppUser? user, UserRole role) => user?.role == role;

bool isServiceProvider(AppUser? user) => user?.isServiceProvider == true;
