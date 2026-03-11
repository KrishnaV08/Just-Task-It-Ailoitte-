import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_task_it/app/modules/dashboard/widgets/edit_task_sheet.dart';
import 'package:just_task_it/app/modules/theme/theme_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:just_task_it/app/data/models/task_model.dart';
import 'package:just_task_it/app/data/services/task_service.dart';
import 'package:just_task_it/app/data/services/connectivity_service.dart';
import 'package:just_task_it/app/data/services/sync_queue_service.dart';
import 'package:just_task_it/app/routes/app_pages.dart';

class DashboardController extends GetxController {
  final _taskService = TaskService();

  final allTasks = <TaskModel>[].obs;
  final isLoading = false.obs;
  final isOnline = true.obs;
  final pendingQueueCount = 0.obs;

  List<TaskModel> get pendingTasks =>
      allTasks.where((t) => !t.isCompleted).toList();
  List<TaskModel> get completedTasks =>
      allTasks.where((t) => t.isCompleted).toList();

  double get progress =>
      allTasks.isEmpty ? 0 : completedTasks.length / allTasks.length;

  String get progressText => allTasks.isEmpty
      ? 'No tasks yet'
      : '${completedTasks.length} of ${allTasks.length} completed';

  @override
  void onInit() {
    super.onInit();
    Get.put(ThemeController());

    // Step 1: Load from Hive instantly — no waiting for network
    _loadFromCache();

    // Step 2: If online, refresh from Supabase in background
    _refreshFromRemote();

    // Step 3: Keep isOnline + queue count in sync for UI
    _observeConnectivity();
  }

  // ── Load from cache instantly ──────────────────────────

  void _loadFromCache() {
    final cached = _taskService.getLocalTasks();
    if (cached.isNotEmpty) {
      allTasks.value = cached;
      _log('Loaded ${cached.length} tasks from cache instantly.');
    }
    _updateQueueCount();
  }

  // ── Refresh from Supabase silently ─────────────────────

  Future<void> _refreshFromRemote() async {
    if (!ConnectivityService.isOnline) {
      _log('Offline — skipping remote refresh.');
      return;
    }
    try {
      final remote = await _taskService.fetchTasks();
      allTasks.value = remote;
      _log('Background refresh done. ${remote.length} tasks loaded.');
    } catch (e) {
      _log('Background refresh failed: $e');
    }
    _updateQueueCount();
  }

  // ── Observe connectivity for UI badge ─────────────────

  void _observeConnectivity() {
    isOnline.value = ConnectivityService.isOnline;
    // Poll every 3 seconds to keep UI badge fresh
    // ConnectivityService already handles actual sync triggering
    ever(isOnline, (_) => _updateQueueCount());
    _startConnectivityPolling();
  }

  void _startConnectivityPolling() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      final current = ConnectivityService.isOnline;
      if (isOnline.value != current) {
        isOnline.value = current;
        if (current) {
          // Just came online — refresh UI after sync
          await Future.delayed(const Duration(seconds: 2));
          await _refreshFromRemote();
        }
      }
      _updateQueueCount();
      return true; // keep polling
    });
  }

  void _updateQueueCount() {
    pendingQueueCount.value = SyncQueueService.pendingCount;
  }

  // ── Fetch (pull to refresh) ────────────────────────────

  void fetchTasks() async {
    isLoading.value = true;
    try {
      allTasks.value = await _taskService.fetchTasks();
    } catch (e) {
      Get.snackbar('Error', 'Could not load tasks.',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
      _updateQueueCount();
    }
  }

  // ── Add Task ───────────────────────────────────────────

  void addTask(String title) async {
    if (title.trim().isEmpty) return;

    // taskService returns the real task with proper UUID immediately
    final task = await _taskService.addTask(title.trim());
    allTasks.insert(0, task);
    _updateQueueCount();

    if (!ConnectivityService.isOnline) {
      Get.snackbar(
        'Saved Offline',
        'Task will sync when you\'re back online.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  // ── Edit Task ──────────────────────────────────────────

  void editTask(String id, String newTitle) async {
    if (newTitle.trim().isEmpty) return;

    final index = allTasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    // Optimistic update
    allTasks[index] = allTasks[index].copyWith(title: newTitle.trim());
    allTasks.refresh();

    await _taskService.updateTaskTitle(id, newTitle.trim());
    _updateQueueCount();

    if (!ConnectivityService.isOnline) {
      Get.snackbar(
        'Saved Offline',
        'Edit will sync when you\'re back online.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  void showEditSheet(TaskModel task) {
    showModalBottomSheet(
      context: Get.context!,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditTaskSheet(
        task: task,
        onEdit: (newTitle) => editTask(task.id, newTitle),
      ),
    );
  }

  // ── Toggle Task ────────────────────────────────────────

  void toggleTask(String id, bool current) async {
    final index = allTasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    // Optimistic update
    allTasks[index] = allTasks[index].copyWith(isCompleted: !current);
    allTasks.refresh();

    await _taskService.toggleTask(id, current);
    _updateQueueCount();

    if (!ConnectivityService.isOnline) {
      Get.snackbar(
        'Saved Offline',
        'Will sync when you\'re back online.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  // ── Delete Task ────────────────────────────────────────

  void deleteTask(String id) async {
    allTasks.removeWhere((t) => t.id == id);
    await _taskService.deleteTask(id);
    _updateQueueCount();

    if (!ConnectivityService.isOnline) {
      Get.snackbar(
        'Deleted Offline',
        'Will sync when you\'re back online.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  // ── Theme + Auth ───────────────────────────────────────

  void toggleTheme() {
    Get.find<ThemeController>().toggleTheme();
    isDarkMode.value = Get.find<ThemeController>().isDarkMode;
  }

  RxBool isDarkMode = Get.find<ThemeController>().isDarkMode.obs;

  void signOut() async {
    await Supabase.instance.client.auth.signOut();
    Get.offAllNamed(Routes.GET_STARTED);
  }

  // ── Helpers ────────────────────────────────────────────

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get userName =>
      Supabase.instance.client.auth.currentUser?.userMetadata?['name'] ??
      'there';

  void _log(String message) {
    // ignore: avoid_print
    print('[DashboardController] $message');
  }
}
