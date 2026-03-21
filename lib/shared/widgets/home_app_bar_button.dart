import 'dart:io';

import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_routes.dart';

class HomeAppBarButton extends StatelessWidget {
  const HomeAppBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Sur iOS : chevron retour standard (pop)
    if (Platform.isIOS && Navigator.canPop(context)) {
      return IconButton(
        tooltip: 'Retour',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.chevron_left, size: 32),
      );
    }

    // Android / root : bouton maison
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
