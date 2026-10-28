// Headless visual QA without a VM service or a local socket.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:ngsl_go/main.dart';
import 'package:ngsl_go/models.dart';
import 'package:ngsl_go/store.dart';

class PreviewBinding extends WidgetsFlutterBinding {
  Size viewport = const Size(1280, 800);
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) =>
      ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(viewport),
        physicalConstraints: BoxConstraints.tight(viewport),
        devicePixelRatio: 1,
      );
}

Future<void> main() async {
  final binding = PreviewBinding();
  var failures = 0;
  FlutterError.onError = (details) {
    failures++;
    stderr.writeln(details.toString());
  };
  final icons = File(
    '/tmp/ngsl-flutter-sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (await icons.exists()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
  }
  final root = '/Users/jonathanlin/Workspace/OPC/ngsl/app';
  final json = jsonDecode(
    await File('$root/assets/content/ngsl.json').readAsString(),
  );
  final words = (json['words'] as List)
      .map((w) => Vocabulary.fromJson(Map<String, dynamic>.from(w)))
      .toList();
  final directory = await Directory.systemTemp.createTemp('ngsl_preview_');
  final store = StudyStore(directory);
  await store.load();
  final adult = await store.createLearner('爸爸', false);
  await store.markKnown(
    adult,
    words.take(800).map((w) => w.id),
    true,
    words: words,
  );
  await store.createLearner('小雨', true);
  await store.switchLearner(adult);
  await store.ensurePlan(adult, words);
  final key = GlobalKey();
  runApp(
    RepaintBoundary(
      key: key,
      child: VocabularyApp(store: store, words: words),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final output = Directory('/tmp/ngsl-qa');
  await output.create(recursive: true);
  Future<void> snapshot(String name) async {
    binding.scheduleFrame();
    await binding.endOfFrame;
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
    stdout.writeln('Rendered $name');
  }

  bool tapTile(String title) {
    VoidCallback? callback;
    bool containsTitle(Element element) {
      if (element.widget is Text && (element.widget as Text).data == title) {
        return true;
      }
      var found = false;
      element.visitChildren((child) {
        if (containsTitle(child)) found = true;
      });
      return found;
    }

    void visit(Element element) {
      final w = element.widget;
      if (w is ListTile && w.title is Text && (w.title as Text).data == title) {
        callback = w.onTap;
      }
      if (w is TextButton && containsTitle(element)) callback = w.onPressed;
      if (w is NavigationBar) {
        for (var i = 0; i < w.destinations.length; i++) {
          if ((w.destinations[i] as NavigationDestination).label == title) {
            callback = () => w.onDestinationSelected?.call(i);
          }
        }
      }
      element.visitChildren(visit);
    }

    binding.rootElement!.visitChildren(visit);
    callback?.call();
    return callback != null;
  }

  await snapshot('today');
  if (!tapTile('词库与筛选')) throw StateError('Missing word bank navigation');
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await snapshot('words');
  if (!tapTile('我的故事')) throw StateError('Missing story navigation');
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await snapshot('stories');
  if (!tapTile('爸爸')) throw StateError('Missing learner switcher');
  await Future<void>.delayed(const Duration(milliseconds: 350));
  await snapshot('profiles');
  if (!tapTile('关闭')) throw StateError('Missing profile close button');
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!tapTile('今日学习')) throw StateError('Missing today navigation');
  binding.viewport = const Size(800, 1280);
  binding.handleMetricsChanged();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await snapshot('today-portrait');
  if (!tapTile('词库')) throw StateError('Missing portrait word bank navigation');
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await snapshot('words-portrait');
  store.dispose();
  await directory.delete(recursive: true);
  stdout.writeln('Visual QA errors: $failures');
  exit(failures == 0 ? 0 : 1);
}
