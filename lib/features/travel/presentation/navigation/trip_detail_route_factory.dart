import 'package:flutter/material.dart';
import 'package:govipservices/features/travel/domain/models/trip_detail_models.dart';
import 'package:govipservices/features/travel/presentation/pages/trip_detail_page.dart';
import 'package:govipservices/shared/widgets/home_app_bar_button.dart';

class TripDetailRouteFactory {
  static Route<dynamic> build(RouteSettings settings) {
    final Object? args = settings.arguments;
    if (args is! TripDetailArgs) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const _TripDetailInvalidArgsPage(),
      );
    }

    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => TripDetailPage(args: args),
    );
  }
}

class _TripDetailInvalidArgsPage extends StatelessWidget {
  const _TripDetailInvalidArgsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const HomeAppBarButton(),
        title: const Text('Detail trajet'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 44),
              const SizedBox(height: 12),
              const Text('Arguments de navigation invalides.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Retour'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
