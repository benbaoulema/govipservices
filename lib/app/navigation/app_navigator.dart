import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<String?> currentRouteName = ValueNotifier<String?>(null);

class RootRouteObserver extends NavigatorObserver {
  void _sync(Route<dynamic>? route) {
    final String? nextRouteName = route?.settings.name;
    if (currentRouteName.value == nextRouteName) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (currentRouteName.value != nextRouteName) {
        currentRouteName.value = nextRouteName;
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _sync(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _sync(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _sync(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _sync(previousRoute);
  }
}

final RootRouteObserver rootRouteObserver = RootRouteObserver();
