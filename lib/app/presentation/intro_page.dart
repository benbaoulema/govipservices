import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:govipservices/app/presentation/home_page.dart';
import 'package:govipservices/app/router/app_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _introSeenKey = 'app_intro_seen_v1';
const Color _introTurquoise = Color(0xFF14B8A6);
const Color _introTurquoiseDark = Color(0xFF0F766E);
const Color _introCream = Color(0xFFF8FFFE);

class IntroGatePage extends StatefulWidget {
  const IntroGatePage({super.key});

  @override
  State<IntroGatePage> createState() => _IntroGatePageState();
}

class _IntroGatePageState extends State<IntroGatePage> {
  late final Future<bool> _introSeenFuture = _readIntroSeen();

  Future<bool> _readIntroSeen() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_introSeenKey) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _introSeenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: _introCream,
            body: Center(
              child: CircularProgressIndicator(color: _introTurquoise),
            ),
          );
        }

        if (snapshot.data == true) {
          return const HomePage();
        }

        return const IntroPage();
      },
    );
  }
}

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isCompleting = false;

  static const List<_IntroSlideData> _slides = [
    _IntroSlideData(
      title: 'Voyagez et expédiez plus simplement',
      description: 'Une seule app pour réserver un trajet, publier un départ ou suivre vos services de transport.',
      assetPath: 'assets/illustrations/departure.svg',
    ),
    _IntroSlideData(
      title: 'Choisissez votre segment en toute liberté',
      description: 'Départ, arrivée, points intermédiaires et réservation passagers sont gérés dans un parcours clair.',
      assetPath: 'assets/illustrations/stops.svg',
    ),
    _IntroSlideData(
      title: 'Une expérience premium, du départ à l’arrivée',
      description: 'Messagerie, suivi, références de réservation et services VIP sont réunis dans une interface élégante.',
      assetPath: 'assets/illustrations/review.svg',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeIntro() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Future<void> _skipIntro() async {
    await _completeIntro();
  }

  Future<void> _goNext() async {
    if (_currentIndex == _slides.length - 1) {
      await _completeIntro();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLast = _currentIndex == _slides.length - 1;
    final _IntroSlideData slide = _slides[_currentIndex];

    return Scaffold(
      backgroundColor: _introCream,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFEFFFFC),
                      Colors.white,
                      Color.lerp(_introTurquoise, Colors.white, 0.86)!,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -40,
              right: -20,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _introTurquoise.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              bottom: 200,
              left: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _introTurquoiseDark.withOpacity(0.08),
                ),
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.84),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFDDF4EE)),
                        ),
                        child: const Text(
                          'GoVIP Services',
                          style: TextStyle(
                            color: _introTurquoiseDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _isCompleting ? null : _skipIntro,
                        child: const Text('Passer'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (index) => setState(() => _currentIndex = index),
                    itemBuilder: (context, index) {
                      final _IntroSlideData data = _slides[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                        child: Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white,
                                        Color.lerp(_introTurquoise, Colors.white, 0.88)!,
                                      ],
                                    ),
                                    border: Border.all(color: const Color(0xFFDDF4EE)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _introTurquoise.withOpacity(0.10),
                                        blurRadius: 28,
                                        offset: const Offset(0, 16),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 92,
                                        height: 92,
                                        decoration: BoxDecoration(
                                          color: _introTurquoise.withOpacity(0.10),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      SizedBox(
                                        height: 220,
                                        child: SvgPicture.asset(data.assetPath),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              data.title,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color: const Color(0xFF10233E),
                                    fontWeight: FontWeight.w900,
                                  ),
                            )
                                .animate(key: ValueKey('title-$index'))
                                .fadeIn(duration: 240.ms)
                                .slideY(begin: 0.10, end: 0),
                            const SizedBox(height: 12),
                            Text(
                              data.description,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: const Color(0xFF5B6472),
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                  ),
                            )
                                .animate(key: ValueKey('desc-$index'))
                                .fadeIn(delay: 90.ms, duration: 240.ms)
                                .slideY(begin: 0.10, end: 0),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List<Widget>.generate(
                          _slides.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: _currentIndex == index ? 28 : 9,
                            height: 9,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: _currentIndex == index
                                  ? _introTurquoise
                                  : _introTurquoise.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _introTurquoise,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: _isCompleting ? null : _goNext,
                          child: Text(isLast ? 'Commencer' : 'Suivant'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        slide.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroSlideData {
  const _IntroSlideData({
    required this.title,
    required this.description,
    required this.assetPath,
  });

  final String title;
  final String description;
  final String assetPath;
}
