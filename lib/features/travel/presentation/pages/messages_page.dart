import 'package:flutter/material.dart';
import 'package:govipservices/shared/widgets/feature_placeholder_page.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholderPage(
      title: 'Messages',
      description:
          '\u00C9cran de messagerie entre conducteurs et passagers autour d\'un trajet.',
    );
  }
}
