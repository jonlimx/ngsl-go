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
import 'screening.dart';
import 'visuals.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'NGSL 1.2',
    ], await rootBundle.loadString('assets/content/NOTICE.txt'));
  });
  runApp(const Bootstrap());
}

ThemeData appTheme() => ThemeData(
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
      final data = jsonDecode(
        await rootBundle.loadString('assets/content/ngsl.json'),
      );
      final list = (data['words'] as List)
          .map((j) => Vocabulary.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      final location = await getApplicationDocumentsDirectory();
      final loaded = StudyStore(Directory('${location.path}/ngsl_go'));
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
      theme: appTheme(),
      home: Scaffold(
        body: Center(
          child: error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
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
  const VocabularyApp({super.key, required this.store, required this.words});
  final StudyStore store;
  final List<Vocabulary> words;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NGSL Go',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: StudyHome(store: store, words: words),
  );
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

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
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
    final pages = [
      today(learner),
      wordBank(learner),
      storyLibrary(learner),
      SettingsPanel(
        key: ValueKey(learner.id),
        store: store,
        learner: learner,
        onProfiles: profiles,
        onError: message,
      ),
    ];
    const destinations = [
      (Icons.dashboard_outlined, '今日学习', '今日'),
      (Icons.style_outlined, '词库与筛选', '词库'),
      (Icons.forum_outlined, '我的故事', '故事'),
      (Icons.tune, '设置', '设置'),
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
                          foregroundColor: tab == entry.key ? ink : muted,
                          backgroundColor: tab == entry.key
                              ? Colors.white
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: tab == entry.key
                                  ? line
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        onPressed: () => selectTab(entry.key),
                        child: Text(
                          entry.value.$2,
                          style: TextStyle(
                            fontWeight: tab == entry.key
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
              child: pages[tab],
            ),
          ),
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: selectTab,
              destinations: [
                for (final item in destinations)
                  NavigationDestination(icon: Icon(item.$1), label: item.$3),
              ],
            ),
    );
  }

  Widget today(Learner learner) {
    final p = store.progress(learner.id);
    final known = p.values.where((v) => v['status'] == 'known').length;
    final learning = p.values.where((v) => v['status'] == 'learning').length;
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
              onPressed: left.isEmpty
                  ? null
                  : () => openStudy(learner, left, plan!['date']),
              icon: Icon(
                left.isEmpty ? Icons.check : Icons.arrow_forward_rounded,
              ),
              label: Text(left.isEmpty ? '今日词卡已完成' : '开始词卡 · ${left.length} 词'),
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
                  byId[id]!.chinese,
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
                          const SizedBox(height: 16),
                          storyPrompt(),
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
                    const SizedBox(height: 16),
                    storyPrompt(),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        if (stories.isNotEmpty) ...[
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
              metric('${widget.words.length - known - learning}', '待学习'),
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
              (query.isEmpty ||
                  w.word.toLowerCase().contains(query.toLowerCase()) ||
                  w.chinese.contains(query)) &&
              switch (filter) {
                'known' => progress[w.id]?['status'] == 'known',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            hintText: '搜索单词或中文释义',
          ),
          onChanged: (value) => setState(() {
            query = value;
            page = 0;
            selected.clear();
          }),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in [
              ('all', '全部'),
              ('new', '待学习'),
              ('learning', '学习中'),
              ('known', '已熟练'),
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
        ),
        const SizedBox(height: 12),
        Wrap(
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
              onPressed: selected.isEmpty
                  ? null
                  : () => mark(learner.id, false),
              child: const Text('恢复学习'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: found.isEmpty
              ? empty(Icons.search_off, '没有找到匹配的词')
              : GridView.builder(
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
                        side: BorderSide(color: checked ? accent : line),
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
                                w.chinese,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: muted,
                                ),
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
                                      color: status == 'learning'
                                          ? blue
                                          : muted,
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
                ),
        ),
        Row(
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
        ),
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
      await store.saveStory(id, date, story);
      message('${learner.name} 的故事已保存，可在“我的故事”中阅读。');
    });
    generating.remove(id);
    if (mounted) setState(() {});
  }

  void openWord(Learner learner, Vocabulary word) {
    showDialog<void>(
      context: context,
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
                    loadContent: () => enrichWord(store, learner, word),
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

  void openStudy(Learner learner, List<String> ids, String date) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewPage(
          store: store,
          learner: learner,
          words: ids.map((id) => byId[id]!).toList(),
          date: date,
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

Future<Map<String, dynamic>> enrichWord(
  StudyStore store,
  Learner learner,
  Vocabulary word,
) async {
  final auth = ChatGptPlanAuthService.instance;
  if (!await auth.hasSession) throw const ContentException('请先在设置中连接 ChatGPT。');
  final models = await auth.getAvailableModels();
  final model = models.contains(store.model)
      ? store.model
      : models.contains('gpt-6-luna')
      ? 'gpt-6-luna'
      : models.where((m) => m.startsWith('gpt-')).firstOrNull;
  if (model == null) throw const ContentException('当前没有可用模型，请检查 ChatGPT 连接。');
  // Reuse the validated generation pipeline; only the requested word card is
  // cached here, without adding an unsolicited story to the learner's library.
  final story = await StoryService().generate(
    learner: learner,
    targets: [word],
    model: model,
    knownWords: const [],
    recentTitles: const [],
  );
  await store.saveWordContent(
    learner.id,
    word.id,
    Map<String, dynamic>.from((story['words'] as List).single),
  );
  return store.content(learner.id, word);
}

class WordCard extends StatefulWidget {
  const WordCard({
    super.key,
    required this.word,
    required this.content,
    required this.accent,
    required this.onError,
    this.loadContent,
  });
  final Vocabulary word;
  final Map<String, dynamic> content;
  final String accent;
  final void Function(String) onError;
  final Future<Map<String, dynamic>> Function()? loadContent;
  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  bool playing = false, enriching = false;
  Map<String, dynamic> extra = {};
  Future<void> enrich() async {
    if (enriching || widget.loadContent == null) return;
    setState(() => enriching = true);
    try {
      final data = await widget.loadContent!();
      if (mounted) setState(() => extra = data);
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => enriching = false);
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

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    final c = {...widget.content, ...extra};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow('${w.pos}    ·    NGSL #${w.rank}'),
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
              '当前显示官方参考音标；故事学习内容会补充英美读音差异。',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ),
        const SizedBox(height: 26),
        Text(
          c['chinese'] ?? w.chinese,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Text(
          c['english'] ?? w.english,
          style: const TextStyle(fontSize: 18, height: 1.6),
        ),
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
            '可通过 ChatGPT 补充搭配与例句，保存后可离线查看。',
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
          if (widget.loadContent != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: enriching ? null : enrich,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(enriching ? '正在补充学习内容…' : '补充搭配与例句'),
              ),
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
  });
  final StudyStore store;
  final Learner learner;
  final List<Vocabulary> words;
  final String date;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final List<Vocabulary> queue = List.of(widget.words);
  int index = 0;
  bool revealed = false, saving = false;
  @override
  void dispose() {
    Speech.stop();
    super.dispose();
  }

  void error(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> grade(Recall recall) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.store.review(
        widget.learner.id,
        queue[index].id,
        recall,
        widget.date,
      );
      await Speech.stop();
      if (mounted) {
        setState(() {
          if (recall == Recall.again) queue.add(queue[index]);
          index++;
          revealed = false;
        });
      }
    } catch (_) {
      if (mounted) error('学习记录保存失败，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = index >= queue.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.learner.name} · 词卡学习'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('$index / ${queue.length}'),
          ),
        ],
      ),
      body: Center(
        child: SizedBox(
          width: 800,
          child: done
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 56,
                      color: accent,
                    ),
                    const SizedBox(height: 20),
                    const Text('这一组完成了。', style: TextStyle(fontSize: 28)),
                    const SizedBox(height: 12),
                    const Text('接下来可以读故事，试着在新的情境中使用这些词。'),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('回到今日学习'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    LinearProgressIndicator(
                      value: index / queue.length,
                      minHeight: 4,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(36),
                        child: revealed
                            ? WordCard(
                                key: ValueKey(index),
                                word: queue[index],
                                content: widget.store.content(
                                  widget.learner.id,
                                  queue[index],
                                ),
                                loadContent: () => enrichWord(
                                  widget.store,
                                  widget.learner,
                                  queue[index],
                                ),
                                accent: widget.learner.accent,
                                onError: error,
                              )
                            : SizedBox(
                                height: 340,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    eyebrow('先回忆，再查看'),
                                    const SizedBox(height: 30),
                                    Text(
                                      queue[index].word,
                                      style: const TextStyle(
                                        fontSize: 48,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text('想想它的意思，或者用它说一句话。'),
                                    const SizedBox(height: 24),
                                    FilledButton.tonal(
                                      onPressed: () =>
                                          setState(() => revealed = true),
                                      child: const Text('查看释义与用法'),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    if (revealed)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final value in [
                              (Recall.again, '没想起来'),
                              (Recall.hard, '有点吃力'),
                              (Recall.good, '记得'),
                              (Recall.easy, '很熟悉'),
                            ])
                              OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => grade(value.$1),
                                child: Text(value.$2),
                              ),
                          ],
                        ),
                      ),
                  ],
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
                '先自己说出或写下答案，再查看。完成后会记录这篇故事的练习进度。',
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
                          if (shown.contains(w['id']))
                            TextButton.icon(
                              onPressed:
                                  (story['practiced'] as List).contains(w['id'])
                                  ? null
                                  : () async {
                                      try {
                                        await widget.store.markStoryPractice(
                                          widget.learner.id,
                                          widget.storyId,
                                          w['id'],
                                        );
                                        if (mounted) setState(() {});
                                      } catch (_) {
                                        error('练习记录未保存，请重试。');
                                      }
                                    },
                              icon: const Icon(Icons.check),
                              label: Text(
                                (story['practiced'] as List).contains(w['id'])
                                    ? '已练习'
                                    : '我已完成这道练习',
                              ),
                            ),
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
    required this.onProfiles,
    required this.onError,
  });
  final StudyStore store;
  final Learner learner;
  final VoidCallback onProfiles;
  final void Function(String) onError;
  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final auth = ChatGptPlanAuthService.instance;
  bool connecting = false, loading = true;
  String? email;
  List<String> models = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final e = await auth.connectedEmail;
      final m = await auth.hasSession
          ? await auth.getAvailableModels()
          : <String>[];
      if (mounted) {
        setState(() {
          email = e;
          models = m.where((s) => s.startsWith('gpt-')).toList();
        });
      }
    } catch (_) {
      if (mounted) widget.onError('暂时无法读取 ChatGPT 连接。已保存的内容仍可学习。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> connect() async {
    setState(() => connecting = true);
    try {
      await auth.signIn();
      await load();
    } catch (e) {
      if (mounted) {
        widget.onError(
          e is ChatGptPlanAuthException ? e.message : '连接未完成，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> change(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) widget.onError('设置保存失败，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final learner = widget.store.learners.firstWhere(
      (p) => p.id == widget.learner.id,
    );
    return ListView(
      children: [
        const Text(
          '学习设置',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
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
                    labelText: '每日新词 · 下次安排任务时生效',
                  ),
                  items: {0, 3, 5, 8, 10, 15, 20, learner.dailyNew}
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(n == 0 ? '只复习，不加新词' : '$n 个新词'),
                        ),
                      )
                      .toList(),
                  onChanged: (n) => change(
                    () => widget.store.configure(learner.id, dailyNew: n),
                  ),
                ),
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
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: learner.accent,
                  decoration: const InputDecoration(labelText: '搭配、例句和故事的默认发音'),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        change(() => widget.store.setModel(value!)),
                  ),
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
                  '发音与离线使用',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  '词库和已保存的故事可离线阅读。配套音频优先离线播放；动态内容使用平板上已安装的英音或美音语音包，合成后缓存。',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => change(() async {
                    await Speech.channel.invokeMethod('installVoices');
                  }),
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: const Text('安装或检查英语语音包'),
                ),
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
                  '0.1.0 · NGSL 1.2 · 2,809 个词条\n学习记录只保存在这台平板。请勿清除应用数据或卸载应用。\n学习者档案用于分开学习进度，不提供密码或隐私保护。',
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
