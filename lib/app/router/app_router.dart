import 'package:flutter/material.dart';
import 'package:govipservices/app/presentation/home_page.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/parcels/domain/models/parcel_request_models.dart';
import 'package:govipservices/features/parcels/presentation/pages/offer_service_page.dart';
import 'package:govipservices/features/parcels/presentation/pages/parcel_delivery_run_page.dart';
import 'package:govipservices/features/parcels/presentation/pages/ship_package_page.dart';
import 'package:govipservices/features/parcels/presentation/pages/vip_shopping_page.dart';
import 'package:govipservices/features/notifications/presentation/pages/notifications_page.dart';
import 'package:govipservices/features/travel/presentation/pages/add_trip_page.dart';
import 'package:govipservices/features/travel/presentation/pages/book_trip_page.dart';
import 'package:govipservices/features/travel/presentation/pages/messages_page.dart';
import 'package:govipservices/features/travel/presentation/pages/my_trips_page.dart';
import 'package:govipservices/features/travel/presentation/navigation/trip_detail_route_factory.dart';
import 'package:govipservices/features/user/presentation/pages/create_account_page.dart';
import 'package:govipservices/features/user/presentation/pages/forgot_password_page.dart';
import 'package:govipservices/features/user/presentation/pages/login_page.dart';
import 'package:govipservices/features/user/presentation/pages/account_page.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case AppRoutes.authLogin:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
      case AppRoutes.authSignup:
        return MaterialPageRoute<void>(
          builder: (_) => const CreateAccountPage(),
          settings: settings,
        );
      case AppRoutes.authForgotPassword:
        return MaterialPageRoute<void>(
          builder: (_) => const ForgotPasswordPage(),
          settings: settings,
        );
      case AppRoutes.userAccount:
        return MaterialPageRoute<void>(
          builder: (_) => const AccountPage(),
          settings: settings,
        );
      case AppRoutes.userNotifications:
        return MaterialPageRoute<void>(
          builder: (_) => const NotificationsPage(),
          settings: settings,
        );
      case AppRoutes.parcelsShipPackage:
        return MaterialPageRoute<void>(
          builder: (_) => const ShipPackagePage(),
          settings: settings,
        );
      case AppRoutes.parcelsVipShopping:
        return MaterialPageRoute<void>(
          builder: (_) => const VipShoppingPage(),
          settings: settings,
        );
      case AppRoutes.parcelsOfferService:
        return MaterialPageRoute<void>(
          builder: (_) => const OfferServicePage(),
          settings: settings,
        );
      case AppRoutes.parcelsDeliveryRun:
        final ParcelRequestDocument request =
            settings.arguments! as ParcelRequestDocument;
        return MaterialPageRoute<void>(
          builder: (_) => ParcelDeliveryRunPage(request: request),
          settings: settings,
        );
      case AppRoutes.travelAddTrip:
        return MaterialPageRoute<void>(
          builder: (_) => const AddTripPage(),
          settings: settings,
        );
      case AppRoutes.travelBookTrip:
        return MaterialPageRoute<void>(
          builder: (_) => const BookTripPage(),
          settings: settings,
        );
      case AppRoutes.travelTripDetail:
        return TripDetailRouteFactory.build(settings);
      case AppRoutes.travelMyTrips:
        return MaterialPageRoute<void>(
          builder: (_) => const MyTripsPage(),
          settings: settings,
        );
      case AppRoutes.travelMessages:
        return MaterialPageRoute<void>(
          builder: (_) => const MessagesPage(),
          settings: settings,
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
    }
  }
}
