import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';
import 'hive_service.dart';
import 'connectivity_service.dart';
import 'sync_queue_service.dart';

class TaskService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const _uuid = Uuid();

  String get _userId => _supabase.auth.currentUser!.id;

  // ── Fetch ──────────────────────────────────────────────
  // Always returns local cache instantly.
  // If online, fetches from Supabase in background and updates cache.

  List<TaskModel> getLocalTasks() {
    final raw = HiveService.getTasks();
    final tasks = raw.map((e) => TaskModel.fromLocalJson(e)).toList();
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _log('Loaded ${tasks.length} tasks from local cache.');
    return tasks;
  }

  Future<List<TaskModel>> fetchTasks() async {
    if (!ConnectivityService.isOnline) {
      _log('Offline — returning cached tasks.');
      return getLocalTasks();
    }

    try {
      final response = await _supabase
          .from('tasks')
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false);

      final tasks = (response as List)
          .map((e) => TaskModel.fromJson(e))
          .toList();

      // Save fresh data to Hive
      await HiveService.saveTasks(
        tasks.map((t) => t.copyWith(isSynced: true).toLocalJson()).toList(),
      );

      _log('Fetched ${tasks.length} tasks from Supabase and cached locally.');
      return tasks;
    } catch (e) {
      _log('Supabase fetch failed. Falling back to cache. Error: $e');
      return getLocalTasks();
    }
  }

  // ── Add Task ───────────────────────────────────────────

  Future<TaskModel> addTask(String title) async {
    final id = _uuid.v4(); // client-generated UUID — safe for upsert
    final now = DateTime.now();

    final task = TaskModel(
      id: id,
      userId: _userId,
      title: title.trim(),
      isCompleted: false,
      createdAt: now,
      updatedAt: now,
      isSynced: false,
    );

    // 1. Save to Hive immediately
    await HiveService.saveTask(task.toLocalJson());

    if (ConnectivityService.isOnline) {
      try {
        await _supabase.from('tasks').upsert(task.toJson());
        // Mark as synced in Hive
        await HiveService.saveTask(task.copyWith(isSynced: true).toLocalJson());
        _log('✅ Task added and synced: $id');
        return task.copyWith(isSynced: true);
      } catch (e) {
        _log('Supabase add failed. Queuing for sync. Error: $e');
        await _enqueueAdd(task);
      }
    } else {
      _log('Offline — task saved locally and queued: $id');
      await _enqueueAdd(task);
    }

    return task;
  }

  Future<void> _enqueueAdd(TaskModel task) async {
    await SyncQueueService.enqueueAddTask(
      taskId: task.id,
      userId: task.userId,
      title: task.title,
      updatedAt: task.updatedAt,
    );
  }

  // ── Toggle Task ────────────────────────────────────────

  Future<void> toggleTask(String id, bool current) async {
    final newValue = !current;
    final now = DateTime.now();

    // Update Hive immediately
    final raw = HiveService.getTasks();
    final existing = raw.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (existing.isNotEmpty) {
      final updated = Map<String, dynamic>.from(existing);
      updated['is_completed'] = newValue;
      updated['updated_at'] = now.toIso8601String();
      updated['is_synced'] = false;
      await HiveService.saveTask(updated);
    }

    if (ConnectivityService.isOnline) {
      try {
        await _supabase.from('tasks').upsert({
          'id': id,
          'user_id': _userId,
          'is_completed': newValue,
          'updated_at': now.toIso8601String(),
        });
        if (existing.isNotEmpty) {
          final synced = Map<String, dynamic>.from(existing);
          synced['is_completed'] = newValue;
          synced['updated_at'] = now.toIso8601String();
          synced['is_synced'] = true;
          await HiveService.saveTask(synced);
        }
        _log('✅ Task toggled and synced: $id');
      } catch (e) {
        _log('Supabase toggle failed. Queuing. Error: $e');
        await SyncQueueService.enqueueToggleTask(
          taskId: id,
          userId: _userId,
          isCompleted: newValue,
          updatedAt: now,
        );
      }
    } else {
      _log('Offline — toggle queued for: $id');
      await SyncQueueService.enqueueToggleTask(
        taskId: id,
        userId: _userId,
        isCompleted: newValue,
        updatedAt: now,
      );
    }
  }

  // ── Delete Task ────────────────────────────────────────

  Future<void> deleteTask(String id) async {
    // Remove from Hive immediately
    await HiveService.deleteTask(id);

    if (ConnectivityService.isOnline) {
      try {
        await _supabase.from('tasks').delete().eq('id', id);
        _log('✅ Task deleted and synced: $id');
      } catch (e) {
        _log('Supabase delete failed. Queuing. Error: $e');
        await SyncQueueService.enqueueDeleteTask(
          taskId: id,
          userId: _userId,
        );
      }
    } else {
      _log('Offline — delete queued for: $id');
      await SyncQueueService.enqueueDeleteTask(
        taskId: id,
        userId: _userId,
      );
    }
  }

  // ── Edit Task ──────────────────────────────────────────

  Future<void> updateTaskTitle(String id, String newTitle) async {
    final now = DateTime.now();

    // Update Hive immediately
    final raw = HiveService.getTasks();
    final existing = raw.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (existing.isNotEmpty) {
      final updated = Map<String, dynamic>.from(existing);
      updated['title'] = newTitle;
      updated['updated_at'] = now.toIso8601String();
      updated['is_synced'] = false;
      await HiveService.saveTask(updated);
    }

    if (ConnectivityService.isOnline) {
      try {
        await _supabase.from('tasks').upsert({
          'id': id,
          'user_id': _userId,
          'title': newTitle,
          'updated_at': now.toIso8601String(),
        });
        if (existing.isNotEmpty) {
          final synced = Map<String, dynamic>.from(existing);
          synced['title'] = newTitle;
          synced['updated_at'] = now.toIso8601String();
          synced['is_synced'] = true;
          await HiveService.saveTask(synced);
        }
        _log('✅ Task edited and synced: $id');
      } catch (e) {
        _log('Supabase edit failed. Queuing. Error: $e');
        await SyncQueueService.enqueueEditTask(
          taskId: id,
          userId: _userId,
          title: newTitle,
          updatedAt: now,
        );
      }
    } else {
      _log('Offline — edit queued for: $id');
      await SyncQueueService.enqueueEditTask(
        taskId: id,
        userId: _userId,
        title: newTitle,
        updatedAt: now,
      );
    }
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[TaskService] $message');
  }
}
