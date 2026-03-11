import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'hive_service.dart';

class SyncQueueService {
  static final _supabase = Supabase.instance.client;
  // static bool simulateFailOnce = true;

  static const _uuid = Uuid();

  static String generateIdempotencyKey({
    required String userId,
    required String actionType,
    required String taskId,
  }) {
    return '${userId}_${actionType}_$taskId';
  }

  static Future<void> enqueueAddTask({
    required String taskId,
    required String userId,
    required String title,
    required DateTime updatedAt,
  }) async {
    final key = generateIdempotencyKey(
      userId: userId,
      actionType: 'add',
      taskId: taskId,
    );
    if (HiveService.syncQueue.containsKey(key)) {
      _log('Duplicate enqueue skipped for key: $key');
      return;
    }
    await HiveService.enqueue({
      'idempotencyKey': key,
      'type': 'add',
      'taskId': taskId,
      'userId': userId,
      'title': title,
      'isCompleted': false,
      'updatedAt': updatedAt.toIso8601String(),
      'retryCount': 0,
    });
  }

  static Future<void> enqueueToggleTask({
    required String taskId,
    required String userId,
    required bool isCompleted,
    required DateTime updatedAt,
  }) async {
    final key = generateIdempotencyKey(
      userId: userId,
      actionType: 'toggle',
      taskId: taskId,
    );
    await HiveService.enqueue({
      'idempotencyKey': key,
      'type': 'toggle',
      'taskId': taskId,
      'userId': userId,
      'isCompleted': isCompleted,
      'updatedAt': updatedAt.toIso8601String(),
      'retryCount': 0,
    });
  }

  static Future<void> enqueueDeleteTask({
    required String taskId,
    required String userId,
  }) async {
    final key = generateIdempotencyKey(
      userId: userId,
      actionType: 'delete',
      taskId: taskId,
    );
    if (HiveService.syncQueue.containsKey(key)) {
      _log('Duplicate enqueue skipped for key: $key');
      return;
    }
    await HiveService.enqueue({
      'idempotencyKey': key,
      'type': 'delete',
      'taskId': taskId,
      'userId': userId,
      'updatedAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    });
  }

  static Future<void> enqueueEditTask({
    required String taskId,
    required String userId,
    required String title,
    required DateTime updatedAt,
  }) async {
    final key = generateIdempotencyKey(
      userId: userId,
      actionType: 'edit',
      taskId: taskId,
    );
    await HiveService.enqueue({
      'idempotencyKey': key,
      'type': 'edit',
      'taskId': taskId,
      'userId': userId,
      'title': title,
      'updatedAt': updatedAt.toIso8601String(),
      'retryCount': 0,
    });
  }

  static Future<void> processQueue() async {
    final queue = HiveService.getQueue();

    if (queue.isEmpty) {
      _log('Queue is empty. Nothing to sync.');
      return;
    }

    _log('Processing queue. Pending items: ${queue.length}');

    for (final action in queue) {
      await _processAction(action);
    }

    _log('Queue processing done. Remaining: ${HiveService.queueSize}');
  }

  static Future<void> _processAction(Map<String, dynamic> action) async {
    final key = action['idempotencyKey'] as String;
    final type = action['type'] as String;
    final retryCount = action['retryCount'] as int? ?? 0;

    _log('Attempting action: $type | key: $key | retry: $retryCount');

    // ── Simulation only — remove before final submission ──

    try {
      // if (simulateFailOnce && retryCount == 0) {
      //   simulateFailOnce = false;
      //   throw Exception('Simulated transient failure for demo');
      // }
      switch (type) {
        case 'add':
          await _supabase.from('tasks').upsert({
            'id': action['taskId'],
            'user_id': action['userId'],
            'title': action['title'],
            'is_completed': action['isCompleted'],
            'updated_at': action['updatedAt'],
          });
          break;

        case 'toggle':
          await _supabase.from('tasks').upsert({
            'id': action['taskId'],
            'user_id': action['userId'],
            'is_completed': action['isCompleted'],
            'updated_at': action['updatedAt'],
          });
          break;

        case 'edit':
          await _supabase.from('tasks').upsert({
            'id': action['taskId'],
            'user_id': action['userId'],
            'title': action['title'],
            'updated_at': action['updatedAt'],
          });
          break;

        case 'delete':
          await _supabase.from('tasks').delete().eq('id', action['taskId']);
          break;
      }

      await HiveService.removeFromQueue(key);
      _log('✅ Synced action: $type | key: $key');
    } catch (e) {
      _log('❌ Failed action: $type | key: $key | error: $e');

      if (retryCount < 2) {
        final delay = Duration(seconds: (retryCount + 1) * 2);
        _log(
          'Retrying in ${delay.inSeconds}s... (attempt ${retryCount + 1}/2)',
        );
        await Future.delayed(delay);

        final updated = Map<String, dynamic>.from(action);
        updated['retryCount'] = retryCount + 1;
        await HiveService.enqueue(updated);

        await _processAction(updated);
      } else {
        _log(
          '🚫 Max retries reached for key: $key. Keeping in queue for next sync.',
        );
      }
    }
  }

  static int get pendingCount => HiveService.queueSize;

  static void logQueueStatus() {
    final queue = HiveService.getQueue();
    _log('=== SYNC QUEUE STATUS ===');
    _log('Pending actions: ${queue.length}');
    for (final action in queue) {
      _log(
        '  → type: ${action['type']} | taskId: ${action['taskId']} | retries: ${action['retryCount']}',
      );
    }
    _log('========================');
  }

  static void _log(String message) {
    // ignore: avoid_print
    print('[SyncQueueService] $message');
  }
}
