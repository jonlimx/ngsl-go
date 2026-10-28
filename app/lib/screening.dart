import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'visuals.dart';

/// The learner is fixed when this route opens, including all asynchronous saves.
class ScreeningPage extends StatefulWidget {
  const ScreeningPage({
    super.key,
    required this.store,
    required this.learner,
    required this.words,
  });
  final StudyStore store;
  final Learner learner;
  final List<Vocabulary> words;

  @override
  State<ScreeningPage> createState() => _ScreeningPageState();
}

class _ScreeningPageState extends State<ScreeningPage> {
  List<Vocabulary> batch = [];
  final keep = <String>{};
  final scroll = ScrollController();
  bool meanings = false, busy = false;
  bool reachedEnd = false;
  ScreeningUndo? undo;
  String? notice;

  @override
  void initState() {
    super.initState();
    scroll.addListener(checkEnd);
    loadBatch();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  List<Vocabulary> get remaining => screeningCandidates(
    widget.words,
    widget.store.progress(widget.learner.id),
  );

  void loadBatch() {
    batch = remaining.take(100).toList();
    keep.clear();
    if (scroll.hasClients) scroll.jumpTo(0);
    reachedEnd = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => checkEnd());
  }

  void checkEnd() {
    if (mounted &&
        !reachedEnd &&
        scroll.hasClients &&
        scroll.position.pixels >= scroll.position.maxScrollExtent - 1) {
      setState(() => reachedEnd = true);
    }
  }

  Future<void> save() async {
    if (busy || !reachedEnd || batch.isEmpty) return;
    setState(() => busy = true);
    try {
      final result = await widget.store.screenWords(
        widget.learner.id,
        widget.words,
        batch.map((w) => w.id),
        keepLearning: keep,
      );
      if (!mounted) return;
      setState(() {
        undo = result;
        notice =
            '上一批：跳过 ${result.count - result.keptCount} 词，保留 ${result.keptCount} 词待学习';
        loadBatch();
      });
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e is ContentException ? e.message : '筛选暂时未保存，请重试。'),
      ),
    );
  }

  Future<void> undoLast() async {
    final previous = undo;
    if (previous == null) return;
    setState(() => busy = true);
    try {
      await widget.store.undoScreening(previous, widget.words);
      if (!mounted) return;
      setState(() {
        undo = null;
        notice = '已撤销上一批筛选';
        loadBatch();
      });
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = remaining.length;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.learner.name} · 快速筛词')),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '只点不熟或不确定的词，其余整批跳过。',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text('每批最多 100 词 · 还有 $left 词未筛 · 不必筛完，可随时返回开始学习'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('显示释义'),
                      selected: meanings,
                      onSelected: busy
                          ? null
                          : (value) => setState(() => meanings = value),
                    ),
                    TextButton(
                      onPressed: busy || batch.isEmpty
                          ? null
                          : () => setState(() {
                              keep.addAll(batch.map((w) => w.id));
                            }),
                      child: const Text('本批都不熟'),
                    ),
                    TextButton(
                      onPressed: busy || keep.isEmpty
                          ? null
                          : () => setState(keep.clear),
                      child: const Text('清空选择'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: batch.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_outline, size: 48),
                              const SizedBox(height: 16),
                              const Text('未筛的词已经处理完了'),
                              const Text('保留的生词会继续进入每日学习计划。'),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: busy
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text('返回学习'),
                              ),
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = (constraints.maxWidth / 170)
                                .floor()
                                .clamp(2, 8);
                            return GridView.builder(
                              key: const ValueKey('screening-grid'),
                              controller: scroll,
                              itemCount: batch.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    mainAxisExtent: meanings ? 112 : 64,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemBuilder: (context, index) {
                                final word = batch[index];
                                final selected = keep.contains(word.id);
                                return Semantics(
                                  selected: selected,
                                  button: true,
                                  label:
                                      '${word.word}，${selected ? '保留学习' : '将跳过'}',
                                  child: Material(
                                    color: selected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.secondaryContainer
                                        : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: selected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : line,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: ValueKey('screen-${word.id}'),
                                      onTap: busy
                                          ? null
                                          : () => setState(() {
                                              if (!keep.add(word.id)) {
                                                keep.remove(word.id);
                                              }
                                            }),
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    word.word,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                if (selected)
                                                  const Icon(
                                                    Icons.check_circle,
                                                    size: 18,
                                                  ),
                                              ],
                                            ),
                                            if (meanings)
                                              Text(
                                                word.chinese,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                if (batch.isNotEmpty && !reachedEnd)
                  const Text('向下浏览到本批末尾后即可提交', style: TextStyle(fontSize: 13)),
                if (notice != null)
                  Text(notice!, style: const TextStyle(fontSize: 13)),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (batch.isNotEmpty)
                      FilledButton(
                        onPressed: busy || !reachedEnd ? null : save,
                        child: Text(
                          busy
                              ? '正在保存…'
                              : '跳过 ${batch.length - keep.length} 词，保留 ${keep.length} 词 · 下一批',
                        ),
                      ),
                    if (undo != null)
                      TextButton.icon(
                        onPressed: busy ? null : undoLast,
                        icon: const Icon(Icons.undo),
                        label: const Text('撤销上一批'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
