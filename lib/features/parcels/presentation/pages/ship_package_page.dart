import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class ShipPackagePage extends StatelessWidget {
  const ShipPackagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Exp\u00E9dier',
      description:
          '\u00C9cran d\u00E9di\u00E9 \u00E0 la cr\u00E9ation d\'un envoi : adresses, colis, prix, paiement et suivi.',
    );
  }
}
