import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class OfferServicePage extends StatelessWidget {
  const OfferServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Proposer un service',
      description:
          '\u00C9cran pour publier une offre de transport : zone, tarif, capacit\u00E9 et disponibilit\u00E9.',
    );
  }
}
