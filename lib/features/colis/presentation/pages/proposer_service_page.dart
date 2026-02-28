import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class ProposerServicePage extends StatelessWidget {
  const ProposerServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Proposer un service',
      description:
          'Ecran pour publier une offre de transport: zone, tarif, capacite et disponibilite.',
    );
  }
}
