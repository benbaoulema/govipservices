import 'package:flutter/foundation.dart';
import 'package:govipservices/features/scratch/data/scratch_service.dart';
import 'package:govipservices/features/scratch/domain/models/scratch_models.dart';

class ScratchCubit extends ChangeNotifier {
  ScratchCubit() {
    load();
  }

  final ScratchService _service = ScratchService.instance;

  List<UserScratchCard> _pendingCards = [];
  List<UserScratchCard> _revealedCards = [];
  List<UserReward> _availableRewards = [];
  bool _isLoading = true;
  String? _error;
  bool _isRevealing = false;
  bool _isRedeeming = false;

  List<UserScratchCard> get pendingCards => _pendingCards;
  List<UserScratchCard> get revealedCards => _revealedCards;
  List<UserReward> get availableRewards => _availableRewards;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isRevealing => _isRevealing;
  bool get isRedeeming => _isRedeeming;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.registerAppLaunch();
      await _refresh();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<RevealResult?> revealCard(String cardId) async {
    _isRevealing = true;
    _error = null;
    notifyListeners();
    try {
      final RevealResult result = await _service.revealCard(cardId);
      return result;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    } finally {
      _isRevealing = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await _refresh();
    notifyListeners();
  }

  Future<bool> redeemReward(String rewardId) async {
    _isRedeeming = true;
    _error = null;
    notifyListeners();
    try {
      await _service.redeemReward(rewardId);
      await _refresh();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isRedeeming = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    final results = await Future.wait(<Future<dynamic>>[
      _service.fetchPendingCards(),
      _service.fetchRevealedCards(),
      _service.fetchAvailableRewards(),
    ]);
    _pendingCards = results[0] as List<UserScratchCard>;
    _revealedCards = results[1] as List<UserScratchCard>;
    _availableRewards = results[2] as List<UserReward>;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
