import 'package:hive_flutter/hive_flutter.dart';

class HiveService {
  static const String tasksBox = 'tasks_box';
  static const String syncQueueBox = 'sync_queue_box';
  static const String cacheTimestampKey = '__cached_at__';
  static const int cacheTTLHours = 24;

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<Map>(tasksBox);
    await Hive.openBox<Map>(syncQueueBox);
    debugLog('HiveService initialized. Boxes opened: $tasksBox, $syncQueueBox');
  }

  // ── Tasks Box ──────────────────────────────────────────

  static Box<Map> get tasks => Hive.box<Map>(tasksBox);

  static Future<void> saveTasks(List<Map<String, dynamic>> tasks) async {
    final box = Hive.box<Map>(tasksBox);
    await box.clear();
    final Map<String, Map> entries = {
      for (var t in tasks) t['id'] as String: t
    };
    await box.putAll(entries);
    // Save timestamp for TTL check
    await box.put(cacheTimestampKey, {
      'cached_at': DateTime.now().toIso8601String(),
    });
    debugLog('[Hive] Saved ${tasks.length} tasks locally at ${DateTime.now()}');
  }

  static List<Map<String, dynamic>> getTasks() {
    final box = Hive.box<Map>(tasksBox);

    // TTL check — if cache is older than 24 hours, treat as expired
    final meta = box.get(cacheTimestampKey);
    if (meta != null) {
      final cachedAt = DateTime.tryParse(
        Map<String, dynamic>.from(meta)['cached_at'] ?? '',
      );
      if (cachedAt != null) {
        final age = DateTime.now().difference(cachedAt);
        if (age.inHours >= cacheTTLHours) {
          debugLog('[Hive] Cache expired (${age.inHours}h old). Forcing fresh fetch.');
          return []; // empty list forces TaskService to fetch from Supabase
        }
        debugLog('[Hive] Cache is fresh (${age.inMinutes}m old).');
      }
    }

    return box.values
        .where((e) {
          final map = Map<String, dynamic>.from(e);
          return map['id'] != cacheTimestampKey;
        })
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> saveTask(Map<String, dynamic> task) async {
    final box = Hive.box<Map>(tasksBox);
    await box.put(task['id'], task);
    debugLog('[Hive] Saved task: ${task['id']}');
  }

  static Future<void> deleteTask(String id) async {
    final box = Hive.box<Map>(tasksBox);
    await box.delete(id);
    debugLog('[Hive] Deleted task from local: $id');
  }

  // ── Sync Queue Box ─────────────────────────────────────

  static Box<Map> get syncQueue => Hive.box<Map>(syncQueueBox);

  static Future<void> enqueue(Map<String, dynamic> action) async {
    final box = Hive.box<Map>(syncQueueBox);
    await box.put(action['idempotencyKey'], action);
    debugLog('[SyncQueue] Enqueued action: ${action['type']} | key: ${action['idempotencyKey']} | Queue size: ${box.length}');
  }

  static List<Map<String, dynamic>> getQueue() {
    final box = Hive.box<Map>(syncQueueBox);
    return box.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> removeFromQueue(String idempotencyKey) async {
    final box = Hive.box<Map>(syncQueueBox);
    await box.delete(idempotencyKey);
    debugLog('[SyncQueue] Removed key: $idempotencyKey | Queue size: ${box.length}');
  }

  static int get queueSize => Hive.box<Map>(syncQueueBox).length;

  static void debugLog(String message) {
    // ignore: avoid_print
    print('[HiveService] $message');
  }
}
