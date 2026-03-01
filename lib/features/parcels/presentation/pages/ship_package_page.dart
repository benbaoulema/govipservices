import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class ShipPackagePage extends StatelessWidget {
  const ShipPackagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Expedier',
      description:
          'Ecran dedie a la creation dun envoi: adresses, colis, prix, paiement et suivi.',
    );
  }
}
