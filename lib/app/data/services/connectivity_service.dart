import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_queue_service.dart';

class ConnectivityService {
  static final _connectivity = Connectivity();
  static StreamSubscription? _subscription;
  static bool _isOnline = true;

  static bool get isOnline => _isOnline;

  static Future<void> init() async {
    // Check current status on app start
    final result = await _connectivity.checkConnectivity();
    _isOnline = _isConnected(result);
    _log('Initial connectivity: ${_isOnline ? 'ONLINE' : 'OFFLINE'}');

    // If online at startup, process any leftover queue from previous session
    if (_isOnline) {
      _log('App started online. Processing any leftover queue...');
      await SyncQueueService.processQueue();
    }

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) async {
      final wasOnline = _isOnline;
      _isOnline = _isConnected(result);

      if (!wasOnline && _isOnline) {
        // Just came back online
        _log('🟢 Back ONLINE. Triggering sync...');
        SyncQueueService.logQueueStatus();
        await SyncQueueService.processQueue();
      } else if (wasOnline && !_isOnline) {
        _log('🔴 Went OFFLINE. Actions will be queued.');
      }
    });
  }

  static bool _isConnected(List<ConnectivityResult> result) {
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  }

  static void dispose() {
    _subscription?.cancel();
  }

  static void _log(String message) {
    // ignore: avoid_print
    print('[ConnectivityService] $message');
  }
}
