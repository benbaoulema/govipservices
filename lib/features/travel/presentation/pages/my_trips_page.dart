import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class MyTripsPage extends StatelessWidget {
  const MyTripsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Mes trajets',
      description:
          '\u00C9cran de gestion des trajets publi\u00E9s et r\u00E9serv\u00E9s avec historique et statut.',
    );
  }
}
