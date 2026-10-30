import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'audio.dart';
import 'core/ai/chatgpt_plan_auth_service.dart';
import 'core/ai/story_service.dart';
import 'models.dart';
import 'store.dart';
import 'study_session.dart';
import 'screening.dart';
import 'visuals.dart';
import 'device_mode.dart';
import 'network_policy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'NGSL 1.2',
    ], await rootBundle.loadString('assets/content/NOTICE.txt'));
  });
  runApp(const Bootstrap());
}

ThemeData _normalTheme() => ThemeData(
  useMaterial3: true,
  splashFactory: InkRipple.splashFactory,
  colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: Colors.white)
      .copyWith(
        primary: accent,
        onPrimary: Colors.white,
        secondary: blue,
        secondaryContainer: peach,
        onSecondaryContainer: ink,
        outline: const Color(0xFFADB3BC),
        outlineVariant: line,
        surfaceContainerLow: canvas,
      ),
  scaffoldBackgroundColor: canvas,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 17, height: 1.6, color: ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: ink),
    titleLarge: TextStyle(
      fontSize: 23,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line),
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: Colors.white,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: line),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: peach,
    surfaceTintColor: Colors.transparent,
  ),
  dividerTheme: const DividerThemeData(color: line),
);

class StillPageTransitionsBuilder extends PageTransitionsBuilder {
  const StillPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

ThemeData appTheme({bool eink = false}) {
  final base = _normalTheme();
  if (!eink) return base;
  const border = BorderSide(color: Colors.black, width: 1);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    colorScheme: const ColorScheme.light(
      primary: Colors.black,
      onPrimary: Colors.white,
      secondary: Colors.black,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEEEEEE),
      onSecondaryContainer: Colors.black,
      surface: Colors.white,
      onSurface: Colors.black,
      outline: Colors.black,
      outlineVariant: Colors.black54,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
    ),
    dividerTheme: const DividerThemeData(color: Colors.black54),
    cardTheme: base.cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: border,
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: border,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        animationDuration: Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        side: border,
        animationDuration: Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        animationDuration: Duration.zero,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xFFDDDDDD),
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      expansionAnimationStyle: AnimationStyle.noAnimation,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: StillPageTransitionsBuilder(),
        TargetPlatform.iOS: StillPageTransitionsBuilder(),
        TargetPlatform.linux: StillPageTransitionsBuilder(),
        TargetPlatform.macOS: StillPageTransitionsBuilder(),
        TargetPlatform.windows: StillPageTransitionsBuilder(),
        TargetPlatform.fuchsia: StillPageTransitionsBuilder(),
      },
    ),
  );
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  StudyStore? store;
  List<Vocabulary>? words;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final location = await getApplicationDocumentsDirectory();
      final directory = Directory('${location.path}/ngsl_go');
      await DeviceModeController.instance.load(directory);
      final data = jsonDecode(
        await rootBundle.loadString('assets/content/ngsl.json'),
      );
      final list = (data['words'] as List)
          .map((j) => Vocabulary.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      final loaded = StudyStore(directory);
      await loaded.load();
      if (loaded.activeId != null) {
        await loaded.ensurePlan(loaded.activeId!, list);
      }
      if (mounted) {
        setState(() {
          store = loaded;
          words = list;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ContentException
              ? e.message
              : '暂时无法打开学习记录，请重试。请勿清除应用数据。',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (store != null) return VocabularyApp(store: store!, words: words!);
    return MaterialApp(
      theme: appTheme(eink: DeviceModeController.instance.eink),
      home: Scaffold(
        body: Center(
          child: error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined, size: 36),
                    SizedBox(height: 20),
                    Text('正在准备词库…'),
                  ],
                )
              : SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_off_outlined, size: 42),
                      const SizedBox(height: 20),
                      Text(error!),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () {
                          setState(() => error = null);
                          _load();
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class VocabularyApp extends StatelessWidget {
  const VocabularyApp({
    super.key,
    required this.store,
    required this.words,
    this.deviceMode,
  });
  final StudyStore store;
  final List<Vocabulary> words;
  final DeviceModeController? deviceMode;
  @override
  Widget build(BuildContext context) {
    final controller = deviceMode ?? DeviceModeController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        title: 'NGSL Go',
        debugShowCheckedModeBanner: false,
        theme: appTheme(eink: controller.eink),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => DeviceModeScope(
          controller: controller,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations:
                  controller.eink || MediaQuery.of(context).disableAnimations,
              accessibleNavigation:
                  controller.eink ||
                  MediaQuery.of(context).accessibleNavigation,
              highContrast:
                  controller.eink || MediaQuery.of(context).highContrast,
            ),
            child: controller.eink
                ? ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      .2126,
                      .7152,
                      .0722,
                      0,
                      0,
                      .2126,
                      .7152,
                      .0722,
                      0,
                      0,
                      .2126,
                      .7152,
                      .0722,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
                    child: child!,
                  )
                : child!,
          ),
        ),
        home: StudyHome(store: store, words: words),
      ),
    );
  }
}

class StudyHome extends StatefulWidget {
  const StudyHome({super.key, required this.store, required this.words});
  final StudyStore store;
  final List<Vocabulary> words;
  @override
  State<StudyHome> createState() => _StudyHomeState();
}

class _StudyHomeState extends State<StudyHome> with WidgetsBindingObserver {
  int tab = 0;
  String query = '';
  String filter = 'all';
  int page = 0;
  bool planning = false;
  final selected = <String>{};
  final generating = <String, StoryService>{};
  Timer? timer;
  StudyStore get store => widget.store;
  Map<String, Vocabulary> get byId => {for (final w in widget.words) w.id: w};
  bool get eink => DeviceModeScope.isEink(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (eink) {
      for (final service in generating.values) {
        service.cancel();
      }
      generating.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    store.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 1), (_) => changed());
  }

  @override
  void dispose() {
    timer?.cancel();
    store.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    for (final service in generating.values) {
      service.cancel();
    }
    Speech.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) changed();
  }

  void changed() {
    if (!mounted) return;
    if (store.activeId != null &&
        store.plan(store.activeId!) == null &&
        !planning) {
      planning = true;
      unawaited(
        run(() async {
          await store.ensurePlan(store.activeId!, widget.words);
        }).whenComplete(() {
          planning = false;
          if (mounted) setState(() {});
        }),
      );
    }
    setState(() {});
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> run(
    Future<void> Function() action, {
    bool onlineTask = false,
  }) async {
    try {
      await action();
    } catch (e) {
      if (onlineTask && NetworkPolicy.offline) return;
      message(
        e is ContentException
            ? e.message
            : e is ChatGptPlanAuthException
            ? e.message
            : '操作暂时未完成，请重试。',
      );
    }
  }

  Future<void> profiles() async {
    unawaited(Speech.stop());
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      animationStyle: eink ? AnimationStyle.noAnimation : null,
      builder: (_) => LearnerDialog(store: store),
    );
    selected.clear();
    page = 0;
    changed();
  }

  List<String> taskIds(String id, {bool unfinished = false}) {
    final plan = store.plan(id);
    if (plan == null) return [];
    final p = store.progress(id);
    return List<String>.from(plan['wordIds'])
        .where(
          (w) =>
              p[w]?['status'] != 'known' &&
              (!unfinished || !(plan['done'] as List).contains(w)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: buildLayout);

  Widget buildLayout(BuildContext context, BoxConstraints constraints) {
    final learner = store.active;
    if (learner == null) {
      return Scaffold(
        body: Center(
          child: SizedBox(
            width: 580,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  brand(),
                  const SizedBox(height: 36),
                  const Text(
                    '常用的词，\n慢慢变成自己的话。',
                    style: TextStyle(
                      fontSize: 38,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('先创建一个学习者。你和孩子可以分别学习，进度独立保存。'),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: profiles,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('创建学习者'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final wide = constraints.maxWidth >= 900;
    final selectedTab = eink && tab == 2 ? 0 : tab;
    final pages = <int, Widget>{
      0: today(learner),
      1: wordBank(learner),
      if (!eink) 2: storyLibrary(learner),
      3: SettingsPanel(
        key: ValueKey(learner.id),
        store: store,
        learner: learner,
        words: widget.words,
        onProfiles: profiles,
        onError: message,
      ),
    };
    final destinations = [
      (0, Icons.dashboard_outlined, '今日学习', '今日'),
      (1, Icons.style_outlined, '词库与筛选', '词库'),
      if (!eink) (2, Icons.forum_outlined, '我的故事', '故事'),
      (3, Icons.tune, '设置', '设置'),
    ];
    void selectTab(int value) {
      Speech.stop();
      setState(() => tab = value);
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(wide ? 88 : 72),
        child: SafeArea(
          bottom: false,
          child: Container(
            decoration: const BoxDecoration(
              color: canvas,
              border: Border(bottom: BorderSide(color: line)),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 32 : 20,
              vertical: 14,
            ),
            child: Row(
              children: [
                SizedBox(width: wide ? 190 : 160, child: brand()),
                if (wide) ...[
                  const SizedBox(width: 20),
                  for (final entry in destinations.asMap().entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: selectedTab == entry.value.$1
                              ? ink
                              : muted,
                          backgroundColor: selectedTab == entry.value.$1
                              ? Colors.white
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selectedTab == entry.value.$1
                                  ? line
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        onPressed: () => selectTab(entry.value.$1),
                        child: Text(
                          entry.value.$3,
                          style: TextStyle(
                            fontWeight: selectedTab == entry.value.$1
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: profiles,
                  icon: CircleAvatar(
                    radius: 17,
                    backgroundColor: peach,
                    child: Icon(
                      learner.child
                          ? Icons.face_outlined
                          : Icons.person_outline,
                      size: 20,
                      color: ink,
                    ),
                  ),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Text(
                      learner.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 1240,
            child: Padding(
              padding: EdgeInsets.all(wide ? 32 : 20),
              child: pages[selectedTab],
            ),
          ),
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              animationDuration: eink ? Duration.zero : null,
              selectedIndex: destinations.indexWhere(
                (d) => d.$1 == selectedTab,
              ),
              onDestinationSelected: (index) =>
                  selectTab(destinations[index].$1),
              destinations: [
                for (final item in destinations)
                  NavigationDestination(icon: Icon(item.$2), label: item.$4),
              ],
            ),
    );
  }

  Widget today(Learner learner) {
    final p = store.progress(learner.id);
    final known = p.values.where((v) => v['status'] == 'known').length;
    final learning = p.values.where((v) => v['status'] == 'learning').length;
    final familiar = p.values.where((v) => v['status'] == 'familiar').length;
    final ids = taskIds(learner.id);
    final left = taskIds(learner.id, unfinished: true);
    final plan = store.plan(learner.id);
    final newCount = ids
        .where((id) => (plan?['newIds'] as List? ?? []).contains(id))
        .length;
    final stories = store
        .stories(learner.id)
        .where((s) => s['date'] == store.today)
        .toList();
    final covered = stories
        .expand((s) => (s['words'] as List).map((w) => w['id']))
        .toSet();
    final uncovered = ids.where((id) => !covered.contains(id)).toList();
    final completed = ids.length - left.length;
    final delayed = store
        .practiceLog(learner.id)
        .where(
          (e) =>
              e['kind'] == 'retrieval' &&
              e['delayed'] == true &&
              (e['at'] as String).compareTo(nextDay(store.today, -6)) >= 0 &&
              (e['at'] as String).compareTo(nextDay(store.today, 1)) < 0,
        )
        .toList();
    Widget session() => Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: peach,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                '今日练习',
                style: TextStyle(fontWeight: FontWeight.w700, color: ink),
              ),
              const Spacer(),
              Text(
                '$completed / ${ids.length} 已完成',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                left.length.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontSize: 76,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -4,
                  color: ink,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 14, bottom: 9),
                child: Text('词待练习', style: TextStyle(color: ink)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$newCount 个新词   /   ${ids.length - newCount} 个复习词',
            style: const TextStyle(color: muted),
          ),
          if ((plan?['deferredReviews'] as num? ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '另有 ${plan!['deferredReviews']} 个到期词分批安排，今天优先复习。',
                style: const TextStyle(color: muted),
              ),
            )
          else if (newCount < learner.dailyNew && ids.length >= dailyWordBudget)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('今天复习较多，已减少新词。', style: TextStyle(color: muted)),
            ),
          if (delayed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '近 7 天跨日独立回忆：${delayed.where((e) => e['independent'] == true).length} / ${delayed.length} 次',
                style: const TextStyle(color: muted),
              ),
            ),
          const SizedBox(height: 22),
          LinearProgressIndicator(
            value: ids.isEmpty ? 0 : completed / ids.length,
            minHeight: 5,
            borderRadius: BorderRadius.circular(5),
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 22),
          if (ids.isEmpty)
            Text(
              learner.dailyNew == 0
                  ? '今天没有到期复习词，可在设置中增加新词。'
                  : '今天暂无待学习词，明天会按最新进度安排任务。',
            ),
          if (ids.isNotEmpty)
            FilledButton.icon(
              onPressed: () =>
                  openStudy(learner, ids, plan!['date'], repeat: left.isEmpty),
              icon: Icon(
                left.isEmpty ? Icons.check : Icons.arrow_forward_rounded,
              ),
              label: Text(
                left.isEmpty ? '再练今日单词' : '开始一小组 · 最多 $studyGroupSize 词',
              ),
            ),
        ],
      ),
    );
    Widget todayWords() => Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '今日单词',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${ids.length} 词',
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (ids.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('暂时没有任务，去词库逛逛吧。'),
              ),
            for (final id in ids.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: mist,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    (plan?['done'] as List? ?? []).contains(id)
                        ? Icons.check
                        : Icons.short_text_rounded,
                    size: 18,
                    color: blue,
                  ),
                ),
                title: Text(
                  byId[id]!.word,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  byId[id]!.commonMeaning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.arrow_outward_rounded,
                  size: 16,
                  color: muted,
                ),
                onTap: () => openWord(learner, byId[id]!),
              ),
            if (ids.length > 5)
              Text(
                '其余 ${ids.length - 5} 词在词卡中继续练习',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
          ],
        ),
      ),
    );
    Widget storyPrompt() => Container(
      decoration: BoxDecoration(
        color: mist,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.forum_outlined, color: blue, size: 26),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '把单词放进故事',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text('读一段，想起来，再说出来。', style: TextStyle(color: muted)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: blue,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed:
                          generating.containsKey(learner.id) ||
                              uncovered.isEmpty
                          ? null
                          : () => generate(
                              learner,
                              uncovered.take(6).map((id) => byId[id]!).toList(),
                            ),
                      icon: generating.containsKey(learner.id)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text(
                        generating.containsKey(learner.id)
                            ? '正在编写故事…'
                            : uncovered.isEmpty
                            ? stories.isEmpty
                                  ? '暂无目标词'
                                  : '今日故事已备好'
                            : stories.isEmpty
                            ? '用今日单词生成故事'
                            : '为剩余单词生成故事',
                      ),
                    ),
                    if (generating.containsKey(learner.id))
                      TextButton(
                        onPressed: () => generating[learner.id]?.cancel(),
                        child: const Text('取消生成'),
                      ),
                  ],
                ),
                if (ids.length > 6 && uncovered.isNotEmpty)
                  const Text(
                    '每篇最多串联 6 个词',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return ListView(
      children: [
        eyebrow(store.today.replaceAll('-', ' / ')),
        const SizedBox(height: 8),
        Text(
          '${learner.name}，今天学一点。',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
            color: ink,
          ),
        ),
        const SizedBox(height: 6),
        const Text('从认识一个词，到用它说一句话。', style: TextStyle(color: muted)),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 850
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          session(),
                          if (!eink) ...[
                            const SizedBox(height: 16),
                            storyPrompt(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: todayWords()),
                  ],
                )
              : Column(
                  children: [
                    session(),
                    const SizedBox(height: 16),
                    todayWords(),
                    if (!eink) ...[const SizedBox(height: 16), storyPrompt()],
                  ],
                ),
        ),
        const SizedBox(height: 24),
        if (!eink && stories.isNotEmpty) ...[
          const Text(
            '今日故事',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...stories.map((s) => storyTile(learner, s)),
          const SizedBox(height: 24),
        ],
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: line),
          ),
          child: Wrap(
            spacing: 32,
            runSpacing: 18,
            children: [
              metric('$known', '已排除熟词'),
              metric('$learning', '正在学习'),
              metric('$familiar', '已熟悉 · 低频抽查'),
              metric(
                '${widget.words.length - known - learning - familiar}',
                '待学习',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 10,
            ),
            leading: const Icon(Icons.fact_check_outlined, color: accent),
            title: Text(known == 0 && learning == 0 ? '快速筛掉已经熟练的词' : '继续快速筛词'),
            subtitle: const Text('每批 100 词，只点不熟的。'),
            trailing: const Icon(Icons.arrow_forward_rounded, color: muted),
            onTap: () => openScreening(learner),
          ),
        ),
        if (store.recoveryNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(store.recoveryNotice!),
          ),
      ],
    );
  }

  Widget wordBank(Learner learner) {
    final progress = store.progress(learner.id);
    final found = widget.words
        .where(
          (w) =>
              w.matchesQuery(query) &&
              switch (filter) {
                'known' => progress[w.id]?['status'] == 'known',
                'familiar' => progress[w.id]?['status'] == 'familiar',
                'learning' => progress[w.id]?['status'] == 'learning',
                'new' =>
                  progress[w.id] == null || progress[w.id]?['status'] == 'new',
                _ => true,
              },
        )
        .toList();
    final pages = (found.length / 24).ceil();
    final current = page.clamp(0, pages > 0 ? pages - 1 : 0);
    final visible = found.skip(current * 24).take(24).toList();
    Widget filters() => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in [
          ('all', '全部'),
          ('new', '待学习'),
          ('learning', '学习中'),
          ('known', '已筛除熟词'),
          ('familiar', '已熟悉'),
        ])
          ChoiceChip(
            label: Text(f.$2),
            selected: filter == f.$1,
            onSelected: (_) => setState(() {
              filter = f.$1;
              page = 0;
              selected.clear();
            }),
          ),
      ],
    );
    Widget batchActions() => Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: visible.isEmpty
              ? null
              : () => setState(() {
                  if (visible.every((w) => selected.contains(w.id))) {
                    selected.clear();
                  } else {
                    selected.addAll(visible.map((w) => w.id));
                  }
                }),
          icon: const Icon(Icons.checklist),
          label: const Text('选择本页'),
        ),
        FilledButton.tonal(
          onPressed: selected.isEmpty ? null : () => mark(learner.id, true),
          child: Text(
            '已熟练，跳过${selected.isEmpty ? '' : ' · ${selected.length}'}',
          ),
        ),
        TextButton(
          onPressed: selected.isEmpty ? null : () => mark(learner.id, false),
          child: const Text('恢复学习'),
        ),
      ],
    );
    final header = <Widget>[
      const Text(
        '词库与熟词筛选',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        '${learner.name} 的标记 · NGSL 1.2 · ${widget.words.length} 词',
        style: const TextStyle(color: Colors.black54),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: () => openScreening(learner),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('快速筛词 · 每批 100 词'),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '搜索单词、释义或短语',
        ),
        onChanged: (value) => setState(() {
          query = value;
          page = 0;
          selected.clear();
        }),
      ),
      const SizedBox(height: 14),
      if (eink)
        ExpansionTile(
          key: const ValueKey('word-bank-tools'),
          tilePadding: EdgeInsets.zero,
          title: const Text('筛选与批量操作'),
          children: [filters(), const SizedBox(height: 12), batchActions()],
        )
      else ...[
        filters(),
        const SizedBox(height: 12),
        batchActions(),
      ],
      const SizedBox(height: 10),
    ];
    final grid = found.isEmpty
        ? empty(Icons.search_off, '没有找到匹配的词')
        : GridView.builder(
            shrinkWrap: eink,
            physics: eink ? const NeverScrollableScrollPhysics() : null,
            itemCount: visible.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 330,
              mainAxisExtent: 174,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemBuilder: (_, index) {
              final w = visible[index];
              final status = progress[w.id]?['status'];
              final checked = selected.contains(w.id);
              return Material(
                color: checked ? peach : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: eink
                        ? Colors.black
                        : checked
                        ? accent
                        : line,
                    width: eink && checked ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => openWord(learner, w),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 10, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${w.rank.toString().padLeft(4, '0')}',
                              style: const TextStyle(
                                fontSize: 11,
                                letterSpacing: 1,
                                color: muted,
                              ),
                            ),
                            const Spacer(),
                            Checkbox(
                              value: checked,
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  selected.add(w.id);
                                } else {
                                  selected.remove(w.id);
                                }
                              }),
                            ),
                          ],
                        ),
                        Text(
                          w.word,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.6,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          w.commonMeaning,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: muted),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Text(
                              w.pos,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              status == 'known'
                                  ? '已熟练'
                                  : status == 'learning'
                                  ? '学习中'
                                  : '待学习',
                              style: TextStyle(
                                color: status == 'learning' ? blue : muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_outward_rounded,
                              size: 15,
                              color: muted,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
    final footer = Row(
      children: [
        Text('${found.length} 个词'),
        const Spacer(),
        IconButton(
          onPressed: current == 0
              ? null
              : () => setState(() {
                  page = current - 1;
                  selected.clear();
                }),
          icon: const Icon(Icons.chevron_left),
        ),
        Text('${pages == 0 ? 0 : current + 1} / $pages'),
        IconButton(
          onPressed: current + 1 >= pages
              ? null
              : () => setState(() {
                  page = current + 1;
                  selected.clear();
                }),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
    if (eink) {
      return ListView(
        children: [
          ...header,
          if (found.isEmpty) SizedBox(height: 200, child: grid) else grid,
          footer,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...header,
        Expanded(child: grid),
        footer,
      ],
    );
  }

  Future<void> openScreening(Learner learner) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ScreeningPage(store: store, learner: learner, words: widget.words),
      ),
    );
    if (!mounted) return;
    setState(() {
      selected.clear();
      page = 0;
    });
  }

  Future<void> mark(String id, bool known) => run(() async {
    final ids = Set<String>.from(selected);
    await store.markKnown(id, ids, known, words: widget.words);
    if (!mounted) return;
    setState(selected.clear);
    message(known ? '已跳过 ${ids.length} 个熟词' : '已恢复选中词的学习状态');
  });
  Widget storyLibrary(Learner learner) {
    final stories = store.stories(learner.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我的故事',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '${learner.name} 的故事 · 保存后可离线阅读',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: stories.isEmpty
              ? empty(
                  Icons.auto_stories_outlined,
                  '还没有故事',
                  '到今日学习，用自己的目标词生成第一篇。',
                )
              : ListView(
                  children: stories.map((s) => storyTile(learner, s)).toList(),
                ),
        ),
      ],
    );
  }

  Widget storyTile(Learner learner, Map<String, dynamic> story) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 12,
        ),
        leading: const Icon(Icons.auto_stories_outlined, color: accent),
        title: Text(story['title']),
        subtitle: Text(
          '${story['date']} · ${(story['words'] as List).length} 个目标词 · 已练习 ${(story['practiced'] as List? ?? []).length} 个',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StoryPage(
              store: store,
              learner: learner,
              storyId: story['id'],
              words: byId,
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> generate(Learner learner, List<Vocabulary> targets) async {
    if (eink || NetworkPolicy.offline) return;
    final revision = NetworkPolicy.revision;
    final id = learner.id;
    if (generating.containsKey(id) || targets.isEmpty) return;
    final service = StoryService();
    final date = store.today;
    setState(() => generating[id] = service);
    await run(() async {
      if (!await ChatGptPlanAuthService.instance.hasSession) {
        throw const ContentException('请先在设置中连接 ChatGPT，再生成故事。');
      }
      final models = await ChatGptPlanAuthService.instance.getAvailableModels();
      final model = models.contains(store.model)
          ? store.model
          : models.contains('gpt-6-luna')
          ? 'gpt-6-luna'
          : models.where((m) => m.startsWith('gpt-')).firstOrNull;
      if (model == null) {
        throw const ContentException('当前账号没有可用的文字模型，请重新连接 ChatGPT。');
      }
      final progress = store.progress(id);
      final known = widget.words
          .where(
            (w) =>
                progress[w.id]?['status'] == 'known' ||
                progress[w.id]?['status'] == 'familiar' ||
                (progress[w.id]?['interval'] as num? ?? 0) >= 7,
          )
          .map((w) => w.word);
      final story = await service.generate(
        learner: learner,
        targets: targets,
        model: model,
        knownWords: known,
        recentTitles: store.stories(id).map((s) => s['title'] as String),
      );
      NetworkPolicy.requireOnline(revision);
      await store.saveStory(id, date, story);
      message('${learner.name} 的故事已保存，可在“我的故事”中阅读。');
    }, onlineTask: true);
    if (identical(generating[id], service)) generating.remove(id);
    if (mounted) setState(() {});
  }

  void openWord(Learner learner, Vocabulary word) {
    showDialog<void>(
      context: context,
      animationStyle: eink ? AnimationStyle.noAnimation : null,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                child: Row(
                  children: [
                    Text('${learner.name} · 词卡'),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: WordCard(
                    word: word,
                    content: store.content(learner.id, word),
                    store: store,
                    learnerId: learner.id,
                    accent: learner.accent,
                    onError: message,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => Speech.stop());
  }

  void openStudy(
    Learner learner,
    List<String> ids,
    String date, {
    bool repeat = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewPage(
          store: store,
          learner: learner,
          words: ids.map((id) => byId[id]!).toList(),
          date: date,
          repeat: repeat,
        ),
      ),
    );
  }
}

Widget brand() => const Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    BrandMark(size: 40),
    SizedBox(width: 10),
    Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NGSL Go',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 21,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
              color: ink,
            ),
          ),
          Text(
            'WORDS INTO LIFE',
            style: TextStyle(
              fontSize: 8,
              height: 1.2,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ],
      ),
    ),
  ],
);
Widget eyebrow(String text) => Text(
  text,
  style: const TextStyle(
    fontSize: 12,
    color: accent,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w600,
  ),
);
Widget metric(String value, String label) => SizedBox(
  width: 140,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 31,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
    ],
  ),
);
Widget empty(IconData icon, String title, [String? description]) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 46, color: muted),
      const SizedBox(height: 18),
      Text(title, style: const TextStyle(fontSize: 19)),
      if (description != null) ...[
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    ],
  ),
);

class LearnerDialog extends StatefulWidget {
  const LearnerDialog({super.key, required this.store});
  final StudyStore store;
  @override
  State<LearnerDialog> createState() => _LearnerDialogState();
}

class _LearnerDialogState extends State<LearnerDialog> {
  final name = TextEditingController();
  bool child = false, creating = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    setState(() {
      creating = true;
      error = null;
    });
    try {
      await widget.store.createLearner(name.text, child);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ContentException ? e.message : '暂时无法保存，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('谁来学习？'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in widget.store.learners)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  p.child ? Icons.face_outlined : Icons.person_outline,
                ),
                title: Text(p.name),
                subtitle: Text(p.child ? '儿童' : '成人'),
                trailing: p.id == widget.store.activeId
                    ? const Icon(Icons.check, color: accent)
                    : null,
                onTap: creating
                    ? null
                    : () async {
                        try {
                          await widget.store.switchLearner(p.id);
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (mounted) setState(() => error = '切换未完成，请重试。');
                        }
                      },
              ),
            if (widget.store.learners.isNotEmpty) const Divider(height: 32),
            TextField(
              controller: name,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: '新学习者的名字',
                hintText: '例如：爸爸、小雨',
              ),
              onSubmitted: (_) => creating ? null : create(),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('成人'),
                  icon: Icon(Icons.person_outline),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('儿童'),
                  icon: Icon(Icons.face_outlined),
                ),
              ],
              selected: {child},
              onSelectionChanged: creating
                  ? null
                  : (value) => setState(() => child = value.first),
            ),
            const SizedBox(height: 14),
            const Text(
              '学习进度分别保存在这台平板上。',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: creating ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: creating ? null : create,
        child: Text(creating ? '正在保存…' : '创建学习者'),
      ),
    ],
  );
}

class WordCard extends StatefulWidget {
  const WordCard({
    super.key,
    required this.word,
    required this.content,
    required this.accent,
    required this.onError,
    required this.store,
    required this.learnerId,
    this.onProgressChanged,
  });
  final StudyStore store;
  final String learnerId;
  final VoidCallback? onProgressChanged;
  final Vocabulary word;
  final Map<String, dynamic> content;
  final String accent;
  final void Function(String) onError;
  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  bool playing = false, marking = false, formationShown = false;

  Future<void> setFamiliar(bool familiar) async {
    if (marking) return;
    final store = widget.store;
    final learnerId = widget.learnerId;
    final wordId = widget.word.id;
    setState(() => marking = true);
    try {
      await store.markFamiliar(learnerId, wordId, familiar);
      await Speech.stop();
      if (mounted) {
        setState(() {});
        widget.onProgressChanged?.call();
      }
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => marking = false);
    }
  }

  Future<void> speak(String text, String accent, [String? asset]) async {
    if (playing) return;
    setState(() => playing = true);
    try {
      await Speech.play(text, accent, asset: asset);
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => playing = false);
    }
  }

  Future<void> speakSense(
    WordSense sense,
    String accent, {
    bool wordOnly = false,
  }) async {
    if (playing) return;
    setState(() => playing = true);
    try {
      await Speech.play(
        wordOnly ? widget.word.word : sense.exampleEnglish,
        accent,
        asset: wordOnly
            ? (accent == 'us' ? sense.usWordAudio : sense.ukWordAudio)
            : (accent == 'us' ? sense.usAudio : sense.ukAudio),
      );
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    final c = {...w.content, ...widget.content};
    final progress =
        widget.store.progress(widget.learnerId)[w.id] as Map? ?? {};
    final familiar = progress['status'] == 'familiar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow(
          '${w.senses.isEmpty ? w.pos : w.senses.map((sense) => partOfSpeechLabel(sense.pos)).toSet().join(' / ')}    ·    NGSL #${w.rank}',
        ),
        const SizedBox(height: 12),
        Text(
          w.word,
          style: const TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            for (final a in [('uk', '英'), ('us', '美')])
              OutlinedButton.icon(
                onPressed: playing
                    ? null
                    : () => speak(w.word, a.$1, c['${a.$1}Audio']),
                icon: const Icon(Icons.volume_up_outlined, size: 19),
                label: Text('${a.$2} ${c['${a.$1}Ipa'] ?? w.referenceIpa}'),
              ),
          ],
        ),
        if (c['ukIpa'] == null || c['usIpa'] == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '当前显示参考音标；不同词性的读音差异可在常见义项中查看。',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: ValueKey('familiar-${w.id}'),
              onPressed: marking ? null : () => setFamiliar(!familiar),
              icon: Icon(familiar ? Icons.replay : Icons.check_circle_outline),
              label: Text(
                marking
                    ? '正在保存…'
                    : familiar
                    ? '恢复常规学习'
                    : '标记已熟悉',
              ),
            ),
            if (familiar)
              Text(
                '已熟悉 · ${progress['due']} 低频抽查',
                style: const TextStyle(color: muted),
              ),
          ],
        ),
        const SizedBox(height: 26),
        if (w.senses.isNotEmpty) ...[
          eyebrow('常见义项'),
          const SizedBox(height: 10),
          for (final sense in w.senses)
            ExpansionTile(
              key: ValueKey('sense-${w.id}-${sense.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 18),
              title: Text(
                '${partOfSpeechLabel(sense.pos)}  ${sense.chinese}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  sense.english,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
              children: [
                if (sense.ukIpa != null || sense.usIpa != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '英 ${sense.ukIpa ?? '—'}    美 ${sense.usIpa ?? '—'}',
                      style: const TextStyle(color: muted),
                    ),
                  ),
                if (sense.hasAudioVariant)
                  Wrap(
                    spacing: 12,
                    children: [
                      for (final accent in [('uk', '英音'), ('us', '美音')])
                        TextButton.icon(
                          onPressed: playing
                              ? null
                              : () => speakSense(
                                  sense,
                                  accent.$1,
                                  wordOnly: true,
                                ),
                          icon: const Icon(Icons.volume_up_outlined, size: 18),
                          label: Text('${accent.$2} · 本义项读音'),
                        ),
                    ],
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        sense.exampleEnglish,
                        style: const TextStyle(fontSize: 18, height: 1.6),
                      ),
                    ),
                    IconButton(
                      onPressed: playing
                          ? null
                          : () => speakSense(sense, widget.accent),
                      tooltip: '听本义项例句',
                      icon: const Icon(Icons.volume_up_outlined),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    sense.exampleChinese,
                    style: const TextStyle(color: muted, height: 1.6),
                  ),
                ),
                const SizedBox(height: 12),
                for (final pattern in sense.collocations)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${pattern['english']}  ·  ${pattern['chinese']}',
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                    ),
                  ),
                for (final inflection in sense.inflections)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${inflection['label']}：${(inflection['forms'] as List).join(' / ')}',
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                    ),
                  ),
                for (final note in sense.usageNotes)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        note,
                        style: const TextStyle(color: muted, height: 1.6),
                      ),
                    ),
                  ),
              ],
            ),
          if (w.phrases.isNotEmpty) ...[
            const SizedBox(height: 22),
            eyebrow('常用短语'),
            const SizedBox(height: 8),
            for (final phrase in w.phrases)
              ExpansionTile(
                key: ValueKey(
                  'phrase-${w.id}-${phrase.phrase}-${phrase.chinese}',
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 18),
                title: Text(
                  '${phrase.phrase}  ·  ${phrase.chinese}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  phrase.english,
                  style: const TextStyle(height: 1.5),
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          phrase.exampleEnglish,
                          style: const TextStyle(fontSize: 18, height: 1.6),
                        ),
                      ),
                      IconButton(
                        onPressed: playing
                            ? null
                            : () => speak(
                                phrase.exampleEnglish,
                                widget.accent,
                                widget.accent == 'us'
                                    ? phrase.usAudio
                                    : phrase.ukAudio,
                              ),
                        tooltip: '听短语例句',
                        icon: const Icon(Icons.volume_up_outlined),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      phrase.exampleChinese,
                      style: const TextStyle(color: muted, height: 1.6),
                    ),
                  ),
                ],
              ),
          ],
        ] else ...[
          eyebrow('中文释义'),
          const SizedBox(height: 10),
          Text(
            c['chinese'] ?? w.chinese,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          eyebrow('英文释义'),
          const SizedBox(height: 10),
          Text(
            c['english'] ?? w.english,
            style: const TextStyle(fontSize: 18, height: 1.6),
          ),
        ],
        if ((c['collocations'] as List? ?? []).isNotEmpty) ...[
          const SizedBox(height: 28),
          eyebrow('常见搭配'),
          const SizedBox(height: 10),
          for (final phrase in c['collocations'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phrase['english'],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          phrase['chinese'],
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: playing
                        ? null
                        : () => speak(phrase['english'], widget.accent),
                    icon: const Icon(Icons.volume_up_outlined, size: 21),
                  ),
                ],
              ),
            ),
        ],
        if (c['exampleEnglish'] != null) ...[
          const SizedBox(height: 24),
          eyebrow('例句'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  c['exampleEnglish'],
                  style: const TextStyle(fontSize: 20, height: 1.7),
                ),
              ),
              IconButton(
                onPressed: playing
                    ? null
                    : () => speak(c['exampleEnglish'], widget.accent),
                icon: const Icon(Icons.volume_up_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            c['exampleChinese'],
            style: const TextStyle(color: Colors.black54),
          ),
        ] else ...[
          const SizedBox(height: 24),
          const Text(
            '完整词库已随应用提供，单词释义、搭配和例句均可离线查看。',
            style: TextStyle(color: muted, fontSize: 14),
          ),
        ],
        if (c['inflections'] != null ||
            c['wordFamily'] != null ||
            c['antonyms'] != null ||
            c['usageNotes'] != null ||
            c['wordFormation'] != null) ...[
          const SizedBox(height: 24),
          ExpansionTile(
            key: ValueKey('fce-${w.id}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.symmetric(vertical: 16),
            title: const Text(
              '词形与用法',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            children: [
              if (c['inflections'] != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: eyebrow('时态与比较形式'),
                ),
                for (final item in c['inflections'])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text((item['forms'] as List).join(' / ')),
                    subtitle: Text(item['label']),
                  ),
              ],
              if (c['wordFamily'] != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: eyebrow('同根词 · 按语境选择词性和词义'),
                ),
                for (final item in c['wordFamily'])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item['word']}  ·  ${item['pos']}'),
                    subtitle: Text(item['chinese']),
                  ),
              ],
              if (c['antonyms'] != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: eyebrow('反义词与对照用法'),
                ),
                for (final item in c['antonyms'])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${item['word']} · ${item['chinese']}'),
                    subtitle: Text(item['note']),
                  ),
              ],
              if (c['usageNotes'] != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: eyebrow('搭配、结构与易错点'),
                ),
                for (final note in c['usageNotes'])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        note,
                        style: const TextStyle(fontSize: 16, height: 1.6),
                      ),
                    ),
                  ),
              ],
              if (c['wordFormation'] != null) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: eyebrow('词形填空 · 原创练习'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${c['wordFormation']['prompt']}  (${(c['wordFormation']['stem'] as String).toUpperCase()})',
                    style: const TextStyle(fontSize: 19, height: 1.6),
                  ),
                ),
                if (formationShown) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '答案：${c['wordFormation']['answer']}',
                      style: const TextStyle(
                        color: blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(c['wordFormation']['chinese']),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      c['wordFormation']['explanation'],
                      style: const TextStyle(height: 1.6),
                    ),
                  ),
                ] else
                  TextButton(
                    onPressed: () => setState(() => formationShown = true),
                    child: const Text('查看词形答案'),
                  ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.store,
    required this.learner,
    required this.words,
    required this.date,
    this.repeat = false,
  });
  final StudyStore store;
  final Learner learner;
  final List<Vocabulary> words;
  final String date;
  final bool repeat;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late StudyGroup group;
  Map<String, dynamic>? repeatPlan;
  Map<String, dynamic> get scheduledPlan =>
      widget.store.plan(widget.learner.id, widget.date)!;
  bool get repeating => repeatPlan != null;
  final answer = TextEditingController();
  String? currentId;
  bool revealed = false, hinted = false, saving = false, playing = false;
  bool? spellingCorrect;

  Map<String, dynamic> get plan => repeatPlan ?? scheduledPlan;
  Map<String, dynamic> get progress => widget.store.progress(widget.learner.id);
  Vocabulary get word => widget.words.firstWhere((w) => w.id == currentId);
  Map<String, dynamic> get wordProgress =>
      Map<String, dynamic>.from(progress[currentId] ?? {});
  MemorySkill get skill =>
      plannedMemorySkill(plan, wordProgress, currentId!, widget.store.today);

  @override
  void initState() {
    super.initState();
    if (widget.repeat) prepareRepeat();
    startGroup();
  }

  void prepareRepeat() {
    repeatPlan = {
      'date': widget.date,
      'wordIds': [
        for (final w in widget.words)
          if ((scheduledPlan['done'] as List).contains(w.id)) w.id,
      ],
      'done': <String>[],
      'practice': {
        for (final w in widget.words)
          w.id: {
            'skill': nextMemorySkill(
              Map<String, dynamic>.from(progress[w.id] ?? {}),
              widget.store.today,
            ).name,
            'attempts': 0,
          },
      },
    };
  }

  List<String> get unfinished => widget.words
      .where(
        (w) =>
            progress[w.id]?['status'] != 'known' &&
            (plan['wordIds'] as List).contains(w.id) &&
            !(plan['done'] as List).contains(w.id),
      )
      .map((w) => w.id)
      .toList();

  bool ready(String id) {
    final at = practiceReadyAt(plan, id, progress);
    return at == null || !widget.store.clock().isBefore(at);
  }

  void startGroup() {
    final remaining = unfinished;
    // Continue with available words before offering words still in cooldown.
    group = StudyGroup([
      ...remaining.where(ready),
      ...remaining.where((id) => !ready(id)),
    ]);
    advance();
  }

  void advance() {
    currentId = group.next(widget.store.clock(), plan, progress);
    revealed = false;
    hinted = false;
    playing = false;
    spellingCorrect = null;
    answer.clear();
  }

  @override
  void dispose() {
    answer.dispose();
    Speech.stop();
    super.dispose();
  }

  void error(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> playCue() async {
    if (playing || saving) return;
    final target = word;
    final accent = widget.learner.accent;
    setState(() => playing = true);
    try {
      await Speech.play(
        target.word,
        accent,
        asset: widget.store.content(
          widget.learner.id,
          target,
        )['${accent}Audio'],
      );
    } catch (e) {
      error(e.toString());
    } finally {
      if (mounted && currentId == target.id) setState(() => playing = false);
    }
  }

  Future<void> introduce() async {
    if (saving) return;
    final id = currentId!;
    setState(() => saving = true);
    try {
      await widget.store.introduce(widget.learner.id, id, widget.date);
      await Speech.stop();
      if (mounted && currentId == id) {
        setState(() {
          group.record(id, exposure: true);
          advance();
        });
      }
    } catch (e) {
      error(e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> grade(Recall recall) async {
    if (saving) return;
    final id = currentId!;
    final direction = skill;
    final effective = hinted && recall != Recall.again ? Recall.hard : recall;
    setState(() => saving = true);
    try {
      var recorded = true;
      if (repeating) {
        await widget.store.repeatToday(
          widget.learner.id,
          id,
          effective,
          skill: direction,
          planDay: widget.date,
          hinted: hinted,
        );
        final independent =
            effective == Recall.good || effective == Recall.easy;
        if (independent) {
          (plan['done'] as List).add(id);
        } else {
          plan['practice'][id]['readyAt'] = widget.store.progress(
            widget.learner.id,
          )[id]['readyAt'];
        }
      } else {
        recorded = await widget.store.review(
          widget.learner.id,
          id,
          effective,
          widget.date,
          skill: direction,
          hinted: hinted,
          response: direction == MemorySkill.spelling
              ? answer.text.trim()
              : null,
        );
      }
      await Speech.stop();
      if (mounted && currentId == id) {
        if (!recorded) {
          setState(advance);
          return;
        }
        setState(() {
          group.record(
            id,
            complete: effective == Recall.good || effective == Recall.easy,
          );
          advance();
        });
      }
    } catch (e) {
      error(e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget card(Vocabulary target) => WordCard(
    key: ValueKey('study-answer-${target.id}'),
    word: target,
    content: widget.store.content(widget.learner.id, target),
    store: widget.store,
    learnerId: widget.learner.id,
    onProgressChanged: () {
      if (mounted) setState(advance);
    },
    accent: widget.learner.accent,
    onError: error,
  );

  Widget prompt() {
    final target = word;
    final content = widget.store.content(widget.learner.id, target);
    final direction = skill;
    final hint = switch (direction) {
      MemorySkill.meaning => content['english'] ?? target.english,
      MemorySkill.listening => content['chinese'] ?? target.chinese,
      MemorySkill.production || MemorySkill.spelling =>
        '首字母 ${target.word.substring(0, 1)} · ${target.word.length} 个字符',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        eyebrow('${direction.label} · 先回忆，再查看'),
        const SizedBox(height: 28),
        if (direction == MemorySkill.listening)
          FilledButton.tonalIcon(
            key: const ValueKey('listen-cue'),
            onPressed: playing ? null : playCue,
            icon: const Icon(Icons.volume_up_outlined),
            label: Text(playing ? '正在播放…' : '听单词'),
          )
        else
          Text(
            direction == MemorySkill.meaning
                ? target.word
                : content['chinese'] ?? target.chinese,
            style: TextStyle(
              fontSize: direction == MemorySkill.meaning ? 48 : 28,
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 22),
        Text(switch (direction) {
          MemorySkill.meaning => '说出这个词的意思。',
          MemorySkill.listening => '听发音，说出它的意思。',
          MemorySkill.production => '说出对应的英文，再试着用它说一句话。',
          MemorySkill.spelling => '根据释义，拼写词条原形。',
        }, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 20),
        if (direction == MemorySkill.spelling)
          TextField(
            key: const ValueKey('spelling-answer'),
            controller: answer,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: '输入英文单词',
              border: OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 16),
        if (hinted)
          Text(
            '提示：$hint',
            key: const ValueKey('memory-hint'),
            style: const TextStyle(color: blue, fontSize: 18),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('memory-hint-button'),
              onPressed: () => setState(() => hinted = true),
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('给我提示'),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.tonal(
          key: const ValueKey('reveal-memory-answer'),
          onPressed: () async {
            await Speech.stop();
            if (!mounted) return;
            setState(() {
              if (direction == MemorySkill.spelling) {
                spellingCorrect =
                    normalizeSpelling(answer.text) ==
                    normalizeSpelling(target.word);
              }
              revealed = true;
            });
          },
          child: Text(direction == MemorySkill.spelling ? '检查拼写' : '我已尝试，查看答案'),
        ),
        const SizedBox(height: 12),
        const Text(
          '先自己回答，再对照答案记录；想不起来也可以直接查看。',
          style: TextStyle(color: muted),
        ),
      ],
    );
  }

  Widget summary() {
    final waiting = unfinished;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            waiting.isEmpty
                ? Icons.check_circle_outline
                : Icons.pause_circle_outline,
            size: 56,
            color: accent,
          ),
          const SizedBox(height: 20),
          const Text('这一小组先到这里。', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 14),
          Text('新学 ${group.introduced} 词 · 独立回忆 ${group.recalled} 词'),
          const SizedBox(height: 12),
          Text(
            waiting.isEmpty
                ? (repeating
                      ? '这一轮今日单词已练完。重新练习会单独记录，后续仍按计划复习。'
                      : '今日词卡已完成，可以再练今日单词。')
                : '还有 ${waiting.length} 词待练习。需要重学的词已保存，隔一会儿再回忆。',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (waiting.any(ready))
                FilledButton(
                  onPressed: () => setState(startGroup),
                  child: const Text('再练一小组'),
                ),
              if (waiting.isEmpty && widget.date == widget.store.today)
                FilledButton.icon(
                  onPressed: () => setState(() {
                    prepareRepeat();
                    startGroup();
                  }),
                  icon: const Icon(Icons.replay),
                  label: const Text('再练今日单词'),
                ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('回到今日学习'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = currentId == null ? null : word;
    final initial = target != null && isUnlearned(wordProgress);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.learner.name} · ${repeating ? '再练今日单词' : '词卡学习'}',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SizedBox(
            width: 800,
            child: target == null
                ? summary()
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Text(
                          '每组最多 $studyGroupSize 词 · ${group.recalled} 词已独立回忆',
                          style: const TextStyle(color: muted),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          key: ValueKey('study-scroll-${target.id}-$revealed'),
                          padding: const EdgeInsets.all(28),
                          child: initial
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    eyebrow('新词 · 先理解，再回忆'),
                                    const SizedBox(height: 16),
                                    card(target),
                                  ],
                                )
                              : revealed
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (spellingCorrect != null) ...[
                                      Text(
                                        spellingCorrect!
                                            ? '拼写正确'
                                            : '正确拼写：${target.word}',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          color: blue,
                                        ),
                                      ),
                                      if (!spellingCorrect!)
                                        Text(
                                          '你的答案：${answer.text.trim().isEmpty ? '未填写' : answer.text.trim()}',
                                        ),
                                      const SizedBox(height: 16),
                                    ],
                                    if (hinted)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 16),
                                        child: Text(
                                          '本次使用过提示，稍后会再安排回忆。',
                                          style: TextStyle(color: muted),
                                        ),
                                      ),
                                    card(target),
                                  ],
                                )
                              : prompt(),
                        ),
                      ),
                      if (initial || revealed)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (initial)
                                FilledButton(
                                  onPressed: saving ? null : introduce,
                                  child: const Text('学好了，稍后回忆'),
                                )
                              else if (spellingCorrect != null)
                                FilledButton(
                                  onPressed: saving
                                      ? null
                                      : () => grade(
                                          spellingCorrect!
                                              ? Recall.good
                                              : Recall.again,
                                        ),
                                  child: Text(
                                    spellingCorrect! && !hinted
                                        ? '记录并继续'
                                        : '记下了，稍后再练',
                                  ),
                                )
                              else ...[
                                OutlinedButton(
                                  onPressed: saving
                                      ? null
                                      : () => grade(Recall.again),
                                  child: const Text('没想起来'),
                                ),
                                OutlinedButton(
                                  onPressed: saving
                                      ? null
                                      : () => grade(Recall.hard),
                                  child: const Text('提示后想起'),
                                ),
                                FilledButton(
                                  onPressed: saving || hinted
                                      ? null
                                      : () => grade(Recall.good),
                                  child: const Text('独立想起'),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class StoryPage extends StatefulWidget {
  const StoryPage({
    super.key,
    required this.store,
    required this.learner,
    required this.storyId,
    required this.words,
  });
  final StudyStore store;
  final Learner learner;
  final String storyId;
  final Map<String, Vocabulary> words;
  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  bool translation = false, slow = false, playing = false;
  final shown = <String>{};
  @override
  void dispose() {
    Speech.stop();
    super.dispose();
  }

  void error(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> speak(String text) async {
    setState(() => playing = true);
    try {
      await Speech.play(text, widget.learner.accent, speed: slow ? 0.8 : 1);
    } catch (e) {
      error(e.toString());
    } finally {
      if (mounted) setState(() => playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.store
        .stories(widget.learner.id)
        .firstWhere((s) => s['id'] == widget.storyId);
    final words = List<Map<String, dynamic>>.from(
      (story['words'] as List).map((w) => Map<String, dynamic>.from(w)),
    );
    final surfaces = words.map((w) => RegExp.escape(w['surface'])).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final matcher = RegExp(
      '(?<![a-z])(${surfaces.join('|')})(?![a-z])',
      caseSensitive: false,
    );
    TextSpan rich(String text) {
      final spans = <TextSpan>[];
      var start = 0;
      for (final m in matcher.allMatches(text)) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
        spans.add(
          TextSpan(
            text: m.group(0),
            style: const TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              backgroundColor: peach,
            ),
          ),
        );
        start = m.end;
      }
      spans.add(TextSpan(text: text.substring(start)));
      return TextSpan(children: spans);
    }

    return Scaffold(
      appBar: AppBar(title: Text('${widget.learner.name} · 每日故事')),
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 900,
          child: ListView(
            padding: const EdgeInsets.all(32),
            children: [
              eyebrow(story['date']),
              const SizedBox(height: 12),
              Text(
                story['title'],
                style: const TextStyle(
                  fontSize: 32,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: playing
                        ? null
                        : () => speak(
                            (story['paragraphs'] as List)
                                .map((p) => p['english'])
                                .join('\n'),
                          ),
                    icon: const Icon(Icons.volume_up_outlined),
                    label: Text(playing ? '正在准备朗读…' : '播放全文'),
                  ),
                  TextButton.icon(
                    onPressed: Speech.stop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('停止'),
                  ),
                  FilterChip(
                    label: const Text('慢速'),
                    selected: slow,
                    onSelected: (v) => setState(() => slow = v),
                  ),
                  FilterChip(
                    label: const Text('显示中文'),
                    selected: translation,
                    onSelected: (v) => setState(() => translation = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              for (final p in story['paragraphs'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        rich(p['english']),
                        style: const TextStyle(
                          fontSize: 23,
                          height: 1.9,
                          color: ink,
                        ),
                      ),
                      if (translation)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            p['chinese'],
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                              height: 1.7,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 40),
              const Text(
                '故事里的用法',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              for (final w in words)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ExpansionTile(
                      key: ValueKey('${widget.storyId}:${w['id']}'),
                      title: Text(
                        widget.words[w['id']]!.word,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(w['chinese']),
                      childrenPadding: const EdgeInsets.all(24),
                      children: [
                        WordCard(
                          word: widget.words[w['id']]!,
                          content: w,
                          store: widget.store,
                          learnerId: widget.learner.id,
                          accent: widget.learner.accent,
                          onError: error,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              const Text(
                '遮住单词，回忆一下',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '先自己说出或写下答案，再查看并记录回忆表现；故事练习与词卡复习分别记录。',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              for (final w in words)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w['exercise']['prompt'],
                            style: const TextStyle(fontSize: 20, height: 1.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            w['exercise']['chinese'],
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 14),
                          if (shown.contains(w['id']))
                            Text(
                              w['exercise']['answer'],
                              style: const TextStyle(
                                fontSize: 22,
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => shown.add(w['id'])),
                              child: const Text('查看答案'),
                            ),
                          if (shown.contains(w['id'])) ...[
                            const SizedBox(height: 12),
                            if (story['practiceResults']?[w['id']] != null)
                              Text(
                                switch (story['practiceResults'][w['id']]['recall']) {
                                  'good' || 'easy' => '已记录：独立想起',
                                  'hard' => '已记录：提示后想起',
                                  _ => '已记录：没想起来，建议再读例句',
                                },
                                style: const TextStyle(color: blue),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final result in [
                                    (Recall.again, '没想起来'),
                                    (Recall.hard, '提示后想起'),
                                    (Recall.good, '独立想起'),
                                  ])
                                    OutlinedButton(
                                      onPressed: () async {
                                        try {
                                          await widget.store.recordStoryRecall(
                                            widget.learner.id,
                                            widget.storyId,
                                            w['id'],
                                            result.$1,
                                          );
                                          if (mounted) setState(() {});
                                        } catch (_) {
                                          error('练习记录未保存，请重试。');
                                        }
                                      },
                                      child: Text(result.$2),
                                    ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              eyebrow('试着表达'),
              const SizedBox(height: 10),
              Text(
                story['speakingPrompt'],
                style: const TextStyle(fontSize: 20, height: 1.7),
              ),
              const SizedBox(height: 24),
              const Text(
                'AI 生成的学习材料，如有不自然或不准确的内容，请以可靠词典为准。',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.store,
    required this.learner,
    required this.words,
    required this.onProfiles,
    required this.onError,
  });
  final StudyStore store;
  final Learner learner;
  final List<Vocabulary> words;
  final VoidCallback onProfiles;
  final void Function(String) onError;
  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  ChatGptPlanAuthService get auth => ChatGptPlanAuthService.instance;
  bool? _lastEink;
  int _loadRevision = 0;
  int _connectSequence = 0;
  bool get eink => DeviceModeScope.isEink(context);
  bool connecting = false,
      loading = true,
      checkingVoices = false,
      preparingVoices = false;
  Map<String, dynamic>? voices;
  String? voiceError;
  String? voiceNotice;
  bool previewingVoice = false;
  String? previewStatus;
  String? email;
  List<String> models = [];
  @override
  void initState() {
    super.initState();
    checkVoices();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lastEink == eink) return;
    _lastEink = eink;
    ++_loadRevision;
    ++_connectSequence;
    email = null;
    models = [];
    loading = !eink;
    connecting = false;
    if (!eink) unawaited(load());
  }

  Future<void> checkVoices({bool refresh = false}) async {
    if (checkingVoices) return;
    setState(() {
      checkingVoices = true;
      voiceError = null;
      voiceNotice = null;
    });
    try {
      final status = await Speech.voiceStatus(refresh: refresh);
      if (mounted) {
        setState(() {
          voices = status;
          if (refresh) {
            voiceNotice = status['bundled'] != true
                ? '检查完成：安装包缺少离线模型。'
                : status['ready'] == true
                ? '检查完成：离线模型已就绪，可以试听。'
                : '检查完成：模型已随安装包提供，请先准备离线语音。';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => voiceError = e.toString());
    } finally {
      if (mounted) setState(() => checkingVoices = false);
    }
  }

  Future<void> prepareVoices() async {
    if (preparingVoices) return;
    setState(() {
      preparingVoices = true;
      voiceError = null;
      voiceNotice = null;
    });
    try {
      await Speech.prepareVoices();
      if (!mounted) return;
      await checkVoices();
      if (mounted && voiceError == null) {
        setState(() => voiceNotice = '离线语音准备完成，可以点击“试听英语例句”。');
      }
    } catch (e) {
      if (mounted) setState(() => voiceError = e.toString());
    } finally {
      if (mounted) setState(() => preparingVoices = false);
    }
  }

  Future<void> previewVoice() async {
    if (previewingVoice || preparingVoices || checkingVoices) return;
    final accent = widget.learner.accent;
    setState(() {
      previewingVoice = true;
      previewStatus = '正在准备试听，首次加载可能需要一点时间…';
      voiceError = null;
      voiceNotice = null;
    });
    try {
      await Speech.play(
        'Although the weather changed, we continued our walk around the lake.',
        accent,
        onProgress: (message) {
          if (mounted) setState(() => previewStatus = message);
        },
      );
      if (mounted) setState(() => voiceNotice = '试听已开始播放。');
    } catch (e) {
      if (mounted) {
        setState(
          () => voiceError = e is ContentException ? e.message : '试听失败，请重试。',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          previewingVoice = false;
          previewStatus = null;
        });
      }
    }
  }

  String voiceDescription(String accent) {
    if (preparingVoices) return '正在解包并校验 Kokoro 模型，首次准备需要一点时间…';
    if (checkingVoices) return '正在检查 Kokoro 离线语音…';
    if (voiceError != null) return voiceError!;
    if (voices == null) return '点击检查 Kokoro 离线语音。';
    if (voices!['bundled'] != true) return '安装包缺少 Kokoro 模型，请重新运行安装脚本构建。';
    if (voices!['ready'] != true) {
      return 'Kokoro 已随应用提供，准备后约占用 ${(voices!["bytes"] as num? ?? 384000000) ~/ (1024 * 1024)} MB 额外空间。首次朗读会自动准备，也可以先点“准备离线语音”；无需联网下载语音包。';
    }
    return eink
        ? 'Kokoro 离线模型已准备 · 英音 Emma / 美音 Heart。例句和短语均在本机生成并缓存。'
        : 'Kokoro 离线模型已准备 · 英音 Emma / 美音 Heart。例句、短语和故事均在本机生成并缓存。';
  }

  Future<void> load() async {
    if (eink || NetworkPolicy.offline) return;
    final revision = ++_loadRevision;
    try {
      final e = await auth.connectedEmail;
      final m = await auth.hasSession
          ? await auth.getAvailableModels()
          : <String>[];
      if (mounted && !eink && revision == _loadRevision) {
        setState(() {
          email = e;
          models = m.where((s) => s.startsWith('gpt-')).toList();
        });
      }
    } catch (_) {
      if (mounted && !eink && revision == _loadRevision) {
        widget.onError('暂时无法读取 ChatGPT 连接。已保存的内容仍可学习。');
      }
    } finally {
      if (mounted && revision == _loadRevision) setState(() => loading = false);
    }
  }

  Future<void> connect() async {
    if (eink || NetworkPolicy.offline) return;
    final attempt = ++_connectSequence;
    setState(() => connecting = true);
    try {
      await auth.signIn();
      await load();
    } catch (e) {
      if (mounted && !eink && attempt == _connectSequence) {
        widget.onError(
          e is ChatGptPlanAuthException ? e.message : '连接未完成，请重试。',
        );
      }
    } finally {
      if (mounted && attempt == _connectSequence) {
        setState(() => connecting = false);
      }
    }
  }

  Future<void> change(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        widget.onError(e is ContentException ? e.message : '设置保存失败，请重试。');
      }
    }
  }

  Widget deviceSettings() {
    final device = DeviceModeScope.of(context);
    return Card(
      key: const ValueKey('device-mode-card'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '设备显示模式',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<DeviceDisplayMode>(
              key: ValueKey('device-mode-${device.mode.name}'),
              initialValue: device.mode,
              decoration: const InputDecoration(labelText: '自动 / 普通 / 墨水屏'),
              items: const [
                DropdownMenuItem(
                  value: DeviceDisplayMode.automatic,
                  child: Text('自动识别设备'),
                ),
                DropdownMenuItem(
                  value: DeviceDisplayMode.standard,
                  child: Text('普通模式'),
                ),
                DropdownMenuItem(
                  value: DeviceDisplayMode.eink,
                  child: Text('墨水屏模式 · 完全离线'),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) unawaited(change(() => device.setMode(mode)));
              },
            ),
            const SizedBox(height: 12),
            Text(
              '${device.identity.description} · ${device.eink ? '墨水屏模式，完全离线' : '普通模式'}',
              key: const ValueKey('device-mode-status'),
            ),
            const SizedBox(height: 8),
            const Text(
              '此设置只影响当前设备，切换学习者后保持不变。自动识别不正确时可手动选择。',
              style: TextStyle(color: muted, height: 1.5),
            ),
            if (device.notice != null)
              Text(device.notice!, style: const TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }

  Future<void> copyScreening() async {
    final sourceId = widget.learner.id;
    final sourceName = widget.learner.name;
    final targets = widget.store.learners
        .where((l) => l.id != sourceId)
        .toList();
    if (targets.isEmpty) {
      widget.onError('请先创建另一个学习者，再复制筛词结果。');
      return;
    }
    var targetId = targets.first.id;
    final chosen = await showDialog<String>(
      context: context,
      animationStyle: eink ? AnimationStyle.noAnimation : null,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text('复制 $sourceName 的筛词结果'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('仅复制熟词、生词筛选标记。接收者已经筛选或学习过的词、复习记录和故事都会保留。'),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: targetId,
                  decoration: const InputDecoration(labelText: '复制给'),
                  items: targets
                      .map(
                        (l) =>
                            DropdownMenuItem(value: l.id, child: Text(l.name)),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id != null) update(() => targetId = id);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, targetId),
              child: const Text('复制筛词结果'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      final result = await widget.store.copyScreening(
        sourceId,
        chosen,
        widget.words,
      );
      if (mounted) {
        widget.onError(
          '已复制 ${result.known} 个熟词、${result.learning} 个生词；保留接收者已有记录 ${result.skipped} 词。',
        );
      }
    } catch (e) {
      if (mounted) widget.onError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final learner = widget.store.learners.firstWhere(
      (p) => p.id == widget.learner.id,
    );
    final forecast = learningForecast(
      widget.words,
      widget.store.progress(learner.id),
      widget.store.plan(learner.id),
      learner.dailyNew,
      widget.store.today,
    );
    return ListView(
      children: [
        const Text(
          '学习设置',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        deviceSettings(),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${learner.name} 的学习偏好',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<int>(
                  initialValue: learner.dailyNew,
                  decoration: const InputDecoration(
                    labelText: '每日新词 · 增加时补入今日',
                  ),
                  items:
                      {0, 3, 5, 8, 10, 15, 20, 30, 40, 50, 60, learner.dailyNew}
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text(n == 0 ? '只复习，不加新词' : '$n 个新词'),
                            ),
                          )
                          .toList(),
                  onChanged: (n) => change(
                    () => widget.store.configure(
                      learner.id,
                      dailyNew: n,
                      words: widget.words,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  forecast.remaining == 0
                      ? '全部单词已进入学习或标为熟悉，继续按计划复习即可。'
                      : forecast.days == null
                      ? '还有 ${forecast.remaining} 个新词；当前只复习，暂无学完日期。'
                      : '还有 ${forecast.remaining} 个新词，按当前数量约 ${forecast.days} 天，预计 ${forecast.finish} 学完首轮新词。',
                  key: const ValueKey('learning-forecast'),
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 6),
                const Text(
                  '今日已学记录保留；调大数量会追加新词，调小数量从后续计划生效。预计日期不含后续复习，复习较多时会顺延。',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                if (!eink) ...[
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: learner.topic,
                    decoration: const InputDecoration(labelText: '故事主题'),
                    items: [
                      for (final pair in [
                        ('mixed', '日常与工作混合'),
                        ('daily', '日常生活'),
                        ('travel', '旅行与探索'),
                        ('work', '职场交流'),
                        ('adventure', '温和的小冒险'),
                      ])
                        DropdownMenuItem(value: pair.$1, child: Text(pair.$2)),
                    ],
                    onChanged: (value) => change(
                      () => widget.store.configure(learner.id, topic: value),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: learner.accent,
                  decoration: InputDecoration(
                    labelText: eink ? '离线发音 · 搭配与例句' : '搭配、例句和故事的默认发音',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'uk', child: Text('英音')),
                    DropdownMenuItem(value: 'us', child: Text('美音')),
                  ],
                  onChanged: (value) => change(
                    () => widget.store.configure(learner.id, accent: value),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: widget.onProfiles,
                  icon: const Icon(Icons.switch_account_outlined),
                  label: const Text('切换或创建学习者'),
                ),
                TextButton.icon(
                  key: const ValueKey('copy-screening'),
                  onPressed: copyScreening,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('把我的筛词结果复制给其他学习者'),
                ),
              ],
            ),
          ),
        ),
        if (!eink) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ChatGPT 连接',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '这台平板上的学习者共用连接。各自的故事与学习进度独立保存。',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    loading
                        ? '正在读取连接…'
                        : email == null
                        ? '尚未连接'
                        : '已连接 · $email',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: connecting || loading ? null : connect,
                        icon: connecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.link),
                        label: Text(
                          connecting
                              ? '等待浏览器授权…'
                              : email == null
                              ? '连接 ChatGPT'
                              : '重新连接',
                        ),
                      ),
                      if (connecting)
                        TextButton(
                          onPressed: auth.cancelSignIn,
                          child: const Text('取消'),
                        ),
                      if (email != null && !connecting)
                        TextButton(
                          onPressed: () => change(() async {
                            final revoked = await auth.signOut();
                            if (mounted) {
                              setState(() {
                                email = null;
                                models = [];
                              });
                              if (!revoked) {
                                widget.onError(
                                  '已退出本机连接。如需撤销授权，可在 ChatGPT 连接设置中处理。',
                                );
                              }
                            }
                          }),
                          child: const Text('退出连接'),
                        ),
                    ],
                  ),
                  if (connecting)
                    TextButton(
                      onPressed: () async {
                        final input = TextEditingController();
                        final link = await showDialog<String>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('粘贴浏览器返回链接'),
                            content: SizedBox(
                              width: 500,
                              child: TextField(
                                controller: input,
                                decoration: const InputDecoration(
                                  hintText: '浏览器最终跳转的完整链接',
                                ),
                                maxLines: 3,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, input.text),
                                child: const Text('继续'),
                              ),
                            ],
                          ),
                        );
                        input.dispose();
                        if (link != null) {
                          try {
                            auth.submitCallbackLink(link);
                          } catch (e) {
                            widget.onError(e.toString());
                          }
                        }
                      },
                      child: const Text('授权后未自动返回？'),
                    ),
                  if (models.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: models.contains(widget.store.model)
                          ? widget.store.model
                          : models.contains('gpt-6-luna')
                          ? 'gpt-6-luna'
                          : models.first,
                      decoration: const InputDecoration(labelText: '故事生成模型'),
                      items: models
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (value) =>
                          change(() => widget.store.setModel(value!)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发音与离线使用',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  eink
                      ? '单词、搭配和例句使用随应用提供的 Kokoro，在本机朗读，无需联网或系统语音包。'
                      : '单词、搭配、例句和故事统一使用 Kokoro。模型随安装包提供；首次准备需要额外存储空间，之后可完全离线朗读。',
                ),
                const SizedBox(height: 12),
                Text(
                  voiceDescription(learner.accent),
                  key: const ValueKey('voice-status'),
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          preparingVoices || checkingVoices || previewingVoice
                          ? null
                          : prepareVoices,
                      icon: const Icon(Icons.record_voice_over_outlined),
                      label: Text(preparingVoices ? '正在准备…' : '准备离线语音'),
                    ),
                    TextButton.icon(
                      onPressed:
                          checkingVoices || preparingVoices || previewingVoice
                          ? null
                          : () => checkVoices(refresh: true),
                      icon: const Icon(Icons.refresh),
                      label: Text(checkingVoices ? '正在检查…' : '检查 Kokoro 模型'),
                    ),
                    TextButton.icon(
                      onPressed:
                          previewingVoice || preparingVoices || checkingVoices
                          ? null
                          : previewVoice,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: Text(previewingVoice ? '正在准备试听…' : '试听英语例句'),
                    ),
                  ],
                ),
                if (preparingVoices || checkingVoices || previewingVoice) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (previewStatus != null) ...[
                  const SizedBox(height: 12),
                  Text(previewStatus!),
                ],
                if (voiceNotice != null) ...[
                  const SizedBox(height: 12),
                  Text(voiceNotice!, key: const ValueKey('voice-result')),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '关于 NGSL Go',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  '0.1.0 · NGSL 1.2 · 2,809 个词条\n全量双语例句与搭配由大模型原创生成并预置，学习时可离线查看。\n学习记录只保存在这台平板。请勿清除应用数据或卸载应用。\n学习者档案用于分开学习进度，不提供密码或隐私保护。',
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'NGSL Go',
                    applicationVersion: '0.1.0',
                  ),
                  child: const Text('开源许可与词库来源'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
