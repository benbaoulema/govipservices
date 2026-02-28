import 'package:flutter/material.dart';
import 'package:govipservices/app/presentation/home_page.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:govipservices/features/colis/presentation/pages/expedier_page.dart';
import 'package:govipservices/features/colis/presentation/pages/proposer_service_page.dart';
import 'package:govipservices/features/colis/presentation/pages/vip_shopping_page.dart';
import 'package:govipservices/features/voyager/presentation/pages/ajouter_trajet_page.dart';
import 'package:govipservices/features/voyager/presentation/pages/messages_page.dart';
import 'package:govipservices/features/voyager/presentation/pages/mes_trajets_page.dart';
import 'package:govipservices/features/voyager/presentation/pages/reserver_page.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case AppRoutes.colisExpedier:
        return MaterialPageRoute<void>(
          builder: (_) => const ExpedierPage(),
          settings: settings,
        );
      case AppRoutes.colisVipShopping:
        return MaterialPageRoute<void>(
          builder: (_) => const VipShoppingPage(),
          settings: settings,
        );
      case AppRoutes.colisProposerService:
        return MaterialPageRoute<void>(
          builder: (_) => const ProposerServicePage(),
          settings: settings,
        );
      case AppRoutes.voyagerAjouterTrajet:
        return MaterialPageRoute<void>(
          builder: (_) => const AjouterTrajetPage(),
          settings: settings,
        );
      case AppRoutes.voyagerReserver:
        return MaterialPageRoute<void>(
          builder: (_) => const ReserverPage(),
          settings: settings,
        );
      case AppRoutes.voyagerMesTrajets:
        return MaterialPageRoute<void>(
          builder: (_) => const MesTrajetsPage(),
          settings: settings,
        );
      case AppRoutes.voyagerMessages:
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
