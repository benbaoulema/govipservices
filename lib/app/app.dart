import 'package:flutter/material.dart';
import 'package:govipservices/app/router/app_router.dart';
import 'package:govipservices/app/router/app_routes.dart';

class GoVipApp extends StatelessWidget {
  const GoVipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoVIP Services',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A5C36)),
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
