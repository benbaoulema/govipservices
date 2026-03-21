import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:govipservices/app/navigation/app_navigator.dart';
import 'package:govipservices/app/navigation/parcel_live_activity_deep_link_service.dart';
import 'package:govipservices/app/presentation/intro_page.dart';
import 'package:govipservices/app/router/app_router.dart';
import 'package:govipservices/features/parcels/presentation/widgets/active_delivery_banner.dart';
import 'package:govipservices/features/parcels/presentation/widgets/global_parcel_request_listener.dart';
import 'package:govipservices/features/travel/presentation/widgets/global_booking_request_listener.dart';

class GoVipApp extends StatefulWidget {
  const GoVipApp({super.key});

  @override
  State<GoVipApp> createState() => _GoVipAppState();
}

class _GoVipAppState extends State<GoVipApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ParcelLiveActivityDeepLinkService.instance.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _GoVipAppView();
  }
}

class _GoVipAppView extends StatelessWidget {
  const _GoVipAppView();

  static const Color _turquoise = Color(0xFF14B8A6);
  static const Color _turquoiseDark = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: <NavigatorObserver>[rootRouteObserver],
      title: 'GoVIP Services',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _turquoise),
        appBarTheme: const AppBarTheme(
          backgroundColor: _turquoise,
          foregroundColor: Colors.white,
          centerTitle: true,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _turquoise,
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.8),
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.82),
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
          indicatorColor: _turquoiseDark,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _turquoiseDark,
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          actionTextColor: const Color(0xFFD9FFFA),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        useMaterial3: true,
      ),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => ActiveDeliveryBanner(
        child: GlobalParcelRequestListener(
          child: GlobalBookingRequestListener(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
      home: const IntroGatePage(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
