import 'package:flutter_test/flutter_test.dart';
import 'package:just_task_it/app/data/services/sync_queue_service.dart';

void main() {
  group('SyncQueueService', () {

    group('generateIdempotencyKey', () {
      test('same inputs always produce same key', () {
        final key1 = SyncQueueService.generateIdempotencyKey(
          userId: 'user123',
          actionType: 'toggle',
          taskId: 'task456',
        );
        final key2 = SyncQueueService.generateIdempotencyKey(
          userId: 'user123',
          actionType: 'toggle',
          taskId: 'task456',
        );

        expect(key1, equals(key2));
      });

      test('different actionTypes produce different keys', () {
        final addKey = SyncQueueService.generateIdempotencyKey(
          userId: 'user123',
          actionType: 'add',
          taskId: 'task456',
        );
        final toggleKey = SyncQueueService.generateIdempotencyKey(
          userId: 'user123',
          actionType: 'toggle',
          taskId: 'task456',
        );

        expect(addKey, isNot(equals(toggleKey)));
      });

      test('different taskIds produce different keys', () {
        final key1 = SyncQueueService.generateIdempotencyKey(
          userId: 'user123',
          actionType: 'add',
          taskId: 'task001',
        );
        final key2 = SyncQueueService.generateIdempotencyKey(
          userId: 'user123',
          actionType: 'add',
          taskId: 'task002',
        );

        expect(key1, isNot(equals(key2)));
      });

      test('key format is userId_actionType_taskId', () {
        final key = SyncQueueService.generateIdempotencyKey(
          userId: 'user123',
          actionType: 'add',
          taskId: 'task456',
        );

        expect(key, equals('user123_add_task456'));
      });
    });

  });
}
