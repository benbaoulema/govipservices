import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class AjouterTrajetPage extends StatelessWidget {
  const AjouterTrajetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Ajouter un trajet',
      description:
          'Ecran pour publier un trajet de covoiturage: depart, arrivee, date, places, prix.',
    );
  }
}
