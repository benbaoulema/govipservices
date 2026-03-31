import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:govipservices/features/app_version/data/app_version_service.dart';
import 'package:govipservices/features/app_version/domain/entities/app_version.dart';

// ── Vérification + affichage ──────────────────────────────────────────────────

Future<void> checkAndShowAppUpdate(BuildContext context) async {
  try {
    final AppVersion? remote = await AppVersionService.instance.fetchCurrent();
    if (remote == null) return;

    final PackageInfo info = await PackageInfo.fromPlatform();
    final bool isOutdated = info.version != remote.version;
    if (!isOutdated) return;

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !remote.forceMajeure,
      builder: (_) => _AppUpdateDialog(version: remote),
    );
  } catch (_) {}
}

// ── Dialog ────────────────────────────────────────────────────────────────────

class _AppUpdateDialog extends StatelessWidget {
  const _AppUpdateDialog({required this.version});

  final AppVersion version;

  static const Color _teal = Color(0xFF0F766E);
  static const Color _tealLight = Color(0xFF14B8A6);

  Future<void> _openStore() async {
    final Uri uri = Uri.parse(version.storeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Bloque le retour arrière si forceMajeure
      canPop: !version.forceMajeure,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── En-tête gradient ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_teal, _tealLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    version.forceMajeure
                        ? 'Mise à jour requise'
                        : 'Mise à jour disponible',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version ${version.version}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // ── Corps ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                children: [
                  Text(
                    version.forceMajeure
                        ? 'Une nouvelle version est disponible. Vous devez mettre à jour l\'app pour continuer à l\'utiliser.'
                        : 'Une nouvelle version de GVIP est disponible. Installez-la pour profiter des dernières améliorations.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4A5568),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: _openStore,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Installer'),
                    ),
                  ),
                  if (!version.forceMajeure) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6B7A90),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Plus tard',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
