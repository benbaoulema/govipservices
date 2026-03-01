import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class BookTripPage extends StatelessWidget {
  const BookTripPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Reserver',
      description:
          'Ecran de recherche et reservation des trajets disponibles avec confirmation.',
    );
  }
}
