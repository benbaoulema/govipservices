import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class VipShoppingPage extends StatelessWidget {
  const VipShoppingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'VIP Shopping',
      description:
          'Ecran pour demander un achat assiste avec collecte, validation et livraison.',
    );
  }
}
