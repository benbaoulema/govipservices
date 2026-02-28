import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class MesTrajetsPage extends StatelessWidget {
  const MesTrajetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Mes trajets',
      description:
          'Ecran de gestion des trajets publies et reserves avec historique et statut.',
    );
  }
}
