import 'package:flutter/material.dart';

class ModuleAction {
  const ModuleAction({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String route;
  final IconData icon;
}

class ModuleCard extends StatelessWidget {
  const ModuleCard({
    required this.title,
    required this.description,
    required this.actions,
    super.key,
  });

  final String title;
  final String description;
  final List<ModuleAction> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(description),
            const SizedBox(height: 12),
            ...actions.map(
              (action) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(action.icon),
                title: Text(action.title),
                subtitle: Text(action.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed(action.route),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
