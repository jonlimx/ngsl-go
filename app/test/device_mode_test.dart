import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngsl_go/core/ai/chatgpt_plan_auth_service.dart';
import 'package:ngsl_go/core/ai/story_service.dart';
import 'package:ngsl_go/device_mode.dart';
import 'package:ngsl_go/main.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/network_policy.dart';
import 'package:ngsl_go/store.dart';
import 'memory_learning_test.dart' show MemoryUiFixture;
import 'study_store_test.dart' show words;

class PendingClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  int sent = 0, closed = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent++;
    return response.future;
  }

  @override
  void close() {
    closed++;
  }
}

DeviceModeController controller({
  DeviceIdentity identity = const DeviceIdentity(
    models: ['iReader Ocean 5 Pro'],
  ),
  List<bool>? applied,
}) => DeviceModeController(
  detect: () async => identity,
  applyNative: (offline) async {
    applied?.add(offline);
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => NetworkPolicy.configure(offline: false));

  test(
    'Ocean 5 Pro variants and declared eink hardware are recognised without classifying tablets by size or brand',
    () {
      for (final name in [
        'Ocean5Pro',
        'iReader Ocean 5 Pro',
        'OCEAN_5_PRO',
        'iReader-Ocean5Pro-2025',
      ]) {
        expect(DeviceIdentity(models: [name]).eink, isTrue, reason: name);
      }
      expect(
        const DeviceIdentity(models: ['generic', 'Ocean5 Pro']).eink,
        isTrue,
      );
      expect(
        const DeviceIdentity(brand: 'iReader', models: ['unknown']).eink,
        isFalse,
      );
      expect(const DeviceIdentity(models: ['KPad']).eink, isFalse);
      expect(const DeviceIdentity(models: ['Ocean5 C']).eink, isFalse);
      expect(
        const DeviceIdentity(features: ['android.hardware.epd']).eink,
        isTrue,
      );
    },
  );

  group('device preference persistence', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ngsl_device_');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test(
      'auto starts offline on Ocean and manual choice survives restart and learner changes without rewriting study data',
      () async {
        final store = StudyStore(directory);
        final dad = await store.createLearner('爸爸', false);
        await store.screenWords(
          dad,
          words,
          words.map((w) => w.id),
          keepLearning: {'w0'},
        );
        final child = await store.createLearner('孩子', true);
        await store.ensurePlan(child, words);
        final before = await File(
          '${directory.path}/study.json',
        ).readAsString();
        final applied = <bool>[];
        final mode = controller(applied: applied);
        await mode.load(directory);
        expect(mode.mode, DeviceDisplayMode.automatic);
        expect(mode.eink, isTrue);
        expect(NetworkPolicy.offline, isTrue);
        expect(applied, [true]);
        await mode.setMode(DeviceDisplayMode.standard);
        final restored = controller();
        await restored.load(directory);
        expect(restored.mode, DeviceDisplayMode.standard);
        expect(restored.eink, isFalse);
        expect(
          await File('${directory.path}/study.json').readAsString(),
          before,
        );
        await store.switchLearner(dad);
        expect(restored.eink, isFalse);
        await restored.setMode(DeviceDisplayMode.automatic);
        final again = controller();
        await again.load(directory);
        expect(again.eink, isTrue);
        expect(store.progress(dad)['w0']['status'], 'new');
        expect(store.progress(dad)['w1']['status'], 'known');
        store.dispose();
        mode.dispose();
        restored.dispose();
        again.dispose();
      },
    );

    test(
      'a tablet can opt into offline mode and auto restores tablet mode',
      () async {
        final tablet = controller(
          identity: const DeviceIdentity(models: ['KPad']),
        );
        await tablet.load(directory);
        expect(tablet.eink, isFalse);
        await tablet.setMode(DeviceDisplayMode.eink);
        final restored = controller(
          identity: const DeviceIdentity(models: ['KPad']),
        );
        await restored.load(directory);
        expect(restored.eink, isTrue);
        await restored.setMode(DeviceDisplayMode.automatic);
        expect(restored.eink, isFalse);
        expect(NetworkPolicy.offline, isFalse);
        tablet.dispose();
        restored.dispose();
      },
    );

    test(
      'detection failure remains usable and a failed native change does not save a false preference',
      () async {
        var failNative = false;
        final mode = DeviceModeController(
          detect: () async => throw StateError('unavailable'),
          applyNative: (_) async {
            if (failNative) throw StateError('native failure');
          },
        );
        await mode.load(directory);
        expect(mode.notice, contains('手动选择'));
        failNative = true;
        await expectLater(
          mode.setMode(DeviceDisplayMode.eink),
          throwsA(isA<ContentException>()),
        );
        expect(mode.mode, DeviceDisplayMode.automatic);
        expect(
          await File('${directory.path}/device_settings.json').exists(),
          isFalse,
        );
        failNative = false;
        await mode.setMode(DeviceDisplayMode.eink);
        expect(mode.eink, isTrue);
        mode.dispose();
      },
    );
  });

  group('offline enforcement', () {
    test('requests are refused before any external client is called', () async {
      var calls = 0;
      final client = OfflineAwareClient(
        client: MockClient((request) async {
          calls++;
          return http.Response('online', 200);
        }),
      );
      NetworkPolicy.configure(offline: true);
      await expectLater(
        client.get(Uri.parse('https://example.test/')),
        throwsA(isA<ContentException>()),
      );
      expect(calls, 0);
      NetworkPolicy.configure(offline: false);
      expect(
        (await client.get(Uri.parse('https://example.test/'))).body,
        'online',
      );
      expect(calls, 1);
      client.close();
    });

    test(
      'switching offline aborts transport and rejects an old response even after going online again',
      () async {
        final transport = PendingClient();
        final client = OfflineAwareClient(client: transport);
        final request = client.get(Uri.parse('https://example.test/pending'));
        final rejected = expectLater(request, throwsA(isA<ContentException>()));
        expect(transport.sent, 1);
        NetworkPolicy.configure(offline: true);
        expect(transport.closed, 1);
        NetworkPolicy.configure(offline: false);
        transport.response.complete(
          http.StreamedResponse(Stream.value(utf8.encode('old')), 200),
        );
        await rejected;
        client.close();
      },
    );

    test(
      'auth, token refresh, model discovery and stories cannot access secure storage or HTTP offline',
      () async {
        var storageCalls = 0, httpCalls = 0;
        const storage = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storage, (_) async {
              storageCalls++;
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(storage, null),
        );
        NetworkPolicy.configure(offline: true);
        final auth = ChatGptPlanAuthService(
          client: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );
        expect(await auth.hasSession, isFalse);
        expect(await auth.connectedEmail, isNull);
        await expectLater(auth.signIn(), throwsA(isA<ContentException>()));
        await expectLater(
          auth.getValidAccessToken(),
          throwsA(isA<ContentException>()),
        );
        expect(
          () => auth.getAvailableModels(),
          throwsA(isA<ContentException>()),
        );
        await expectLater(auth.signOut(), throwsA(isA<ContentException>()));
        final story = StoryService(
          auth: auth,
          client: MockClient((_) async {
            httpCalls++;
            return http.Response('{}', 200);
          }),
        );
        await expectLater(
          story.generate(
            learner: Learner.fromJson({
              'id': 'learner',
              'name': '爸爸',
              'child': false,
            }),
            targets: words.take(1).toList(),
            model: 'test',
            knownWords: [],
            recentTitles: [],
          ),
          throwsA(isA<ContentException>()),
        );
        expect(storageCalls, 0);
        expect(httpCalls, 0);
      },
    );
  });

  for (final size in [const Size(420, 700), const Size(632, 840)]) {
    testWidgets('eink navigation, settings and offline study at $size', (
      tester,
    ) async {
      final fixture = await MemoryUiFixture.create(tester, size: size);
      final mode = controller();
      await tester.runAsync(() => mode.load(fixture.directory));
      var authCalls = 0, secureCalls = 0;
      const authChannel = MethodChannel('com.jonlimx.ngsl_go/auth');
      const storageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(authChannel, (_) async {
        authCalls++;
        return null;
      });
      messenger.setMockMethodCallHandler(storageChannel, (_) async {
        secureCalls++;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(authChannel, null);
        messenger.setMockMethodCallHandler(storageChannel, null);
      });
      await tester.pumpWidget(
        VocabularyApp(store: fixture.store, words: words, deviceMode: mode),
      );
      await tester.pumpAndSettle();
      expect(find.text('故事'), findsNothing);
      expect(find.text('把单词放进故事'), findsNothing);
      final ctx = tester.element(find.byType(StudyHome));
      expect(MediaQuery.of(ctx).disableAnimations, isTrue);
      expect(Theme.of(ctx).colorScheme.primary, Colors.black);
      expect(
        Theme.of(ctx).expansionTileTheme.expansionAnimationStyle,
        AnimationStyle.noAnimation,
      );
      await tester.tap(find.text('词库'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('筛选与批量操作'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('筛选与批量操作'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('word0'));
      await tester.tap(find.text('word0'));
      await tester.pumpAndSettle();
      expect(find.text('学习者 · 词卡'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('设备显示模式'), findsOneWidget);
      expect(find.text('ChatGPT 连接'), findsNothing);
      expect(find.text('故事主题'), findsNothing);
      expect(find.text('故事生成模型'), findsNothing);
      final setting = tester.widget<DropdownButtonFormField<DeviceDisplayMode>>(
        find.byType(DropdownButtonFormField<DeviceDisplayMode>),
      );
      expect(setting.initialValue, DeviceDisplayMode.automatic);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('voice-status')),
        350,
      );
      expect(find.text('准备离线语音'), findsOneWidget);
      expect(authCalls, 0);
      expect(secureCalls, 0);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
      mode.dispose();
    });
  }

  testWidgets(
    'manual mode changes keep settings selected, preserve learner data and restore ordinary features',
    (tester) async {
      final fixture = await MemoryUiFixture.create(
        tester,
        size: const Size(632, 840),
      );
      final mode = controller(identity: const DeviceIdentity(models: ['KPad']));
      await tester.runAsync(() => mode.load(fixture.directory));
      final snapshot = jsonEncode(fixture.store.progress(fixture.id));
      await tester.pumpWidget(
        VocabularyApp(store: fixture.store, words: words, deviceMode: mode),
      );
      await tester.pumpAndSettle();
      expect(find.text('故事'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      var setting = tester.widget<DropdownButtonFormField<DeviceDisplayMode>>(
        find.byType(DropdownButtonFormField<DeviceDisplayMode>),
      );
      await tester.runAsync(() async {
        setting.onChanged!(DeviceDisplayMode.eink);
        await mode.setMode(DeviceDisplayMode.eink);
      });
      await tester.pumpAndSettle();
      expect(find.text('学习设置'), findsOneWidget);
      expect(find.text('故事'), findsNothing);
      expect(find.text('ChatGPT 连接'), findsNothing);
      setting = tester.widget<DropdownButtonFormField<DeviceDisplayMode>>(
        find.byType(DropdownButtonFormField<DeviceDisplayMode>),
      );
      expect(setting.initialValue, DeviceDisplayMode.eink);
      await tester.runAsync(() => mode.setMode(DeviceDisplayMode.standard));
      await tester.pumpAndSettle();
      expect(find.text('学习设置'), findsOneWidget);
      expect(find.text('故事'), findsOneWidget);
      expect(jsonEncode(fixture.store.progress(fixture.id)), snapshot);
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
      mode.dispose();
    },
  );
}
