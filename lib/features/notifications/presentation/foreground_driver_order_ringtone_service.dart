import 'package:audioplayers/audioplayers.dart';

class ForegroundDriverOrderRingtoneService {
  ForegroundDriverOrderRingtoneService._();

  static final ForegroundDriverOrderRingtoneService instance =
      ForegroundDriverOrderRingtoneService._();

  static const String _assetPath = 'audio/driver_order_alert.wav';

  AudioPlayer? _player;
  bool _isPlaying = false;

  Future<void> start() async {
    if (_isPlaying) return;

    final AudioPlayer player = AudioPlayer();
    _player = player;
    try {
      _isPlaying = true;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(1.0);
      await player.play(AssetSource(_assetPath));
    } catch (_) {
      _player = null;
      _isPlaying = false;
      await player.dispose();
    }
  }

  Future<void> stop() async {
    final AudioPlayer? player = _player;
    _player = null;
    _isPlaying = false;
    if (player == null) return;

    await player.stop();
    await player.dispose();
  }
}
