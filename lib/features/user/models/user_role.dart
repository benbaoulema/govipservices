import 'package:json_annotation/json_annotation.dart';

enum AdminRole {
  @JsonValue('super_admin')
  superAdmin,
  @JsonValue('admin')
  admin,
  @JsonValue('manager')
  manager,
  @JsonValue('moderator')
  moderator,
  @JsonValue('support')
  support,
  @JsonValue('staff')
  staff,
}

enum UserRole {
  @JsonValue('super_admin')
  superAdmin,
  @JsonValue('admin')
  admin,
  @JsonValue('manager')
  manager,
  @JsonValue('moderator')
  moderator,
  @JsonValue('support')
  support,
  @JsonValue('staff')
  staff,
  @JsonValue('pro')
  pro,
  @JsonValue('simpleUser')
  simpleUser,
}

String userRoleToJson(UserRole role) {
  return switch (role) {
    UserRole.superAdmin => 'super_admin',
    UserRole.admin => 'admin',
    UserRole.manager => 'manager',
    UserRole.moderator => 'moderator',
    UserRole.support => 'support',
    UserRole.staff => 'staff',
    UserRole.pro => 'pro',
    UserRole.simpleUser => 'simpleUser',
  };
}
