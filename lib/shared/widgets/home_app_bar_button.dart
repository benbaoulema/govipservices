import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';

class HomeAppBarButton extends StatelessWidget {
  const HomeAppBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Accueil',
      onPressed: () {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => false,
        );
      },
      icon: const Icon(Icons.home_rounded),
    );
  }
}
