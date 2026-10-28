// 글 상세 화면의 본문 번역 줄 + 번역된 본문
// 원래 본문 위젯(builder)은 그대로 두고, 넘겨주는 제목·본문 HTML 만 번역본으로 바꿔 준다.
import 'package:flutter/material.dart';
import 'package:loftify/ko/ko_chapter.dart';
import 'package:loftify/ko/ko_compat.dart';
import 'package:loftify/ko/ko_fix.dart';
import 'package:loftify/ko/ko_settings_page.dart';
import 'package:loftify/ko/ko_translate.dart';

class KoPostBody extends StatefulWidget {
  const KoPostBody({
    super.key,
    required this.postId,
    required this.title,
    required this.content,
    this.tags = const [],
    required this.builder,
  });

  final Object postId;
  final String title;
  final String content;
  final List<String> tags;
  final Widget Function(String title, String content) builder;

  @override
  State<KoPostBody> createState() => _KoPostBodyState();
}

class _KoPostBodyState extends State<KoPostBody> {
  late KoDoc _doc;
  late List<String> _lines; // 번역할 줄 (제목 포함)
  Map<String, String> _map = {};
  bool _showKo = false;
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String _by = '';
  int _failed = 0;
  bool _glossaryChanged = false;
  String? _error;

  bool get _hasText => _lines.any(KoTr.hasCjk);
  int get _missing => _lines.where((l) => KoTr.hasCjk(l) && !_map.containsKey(l)).toSet().length;

  @override
  void initState() {
    super.initState();
    _prepare();
    KoTr.updates.addListener(_onUpdate);
  }

  @override
  void didUpdateWidget(covariant KoPostBody old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId || old.content != widget.content || old.title != widget.title) {
      _prepare();
    }
  }

  @override
  void dispose() {
    KoTr.updates.removeListener(_onUpdate);
    super.dispose();
  }

  // 직접 고친 번역이 바뀌면 다시 그림
  int _ovCount = -1;
  void _onUpdate() {
    if (!mounted || !_showKo) return;
    final n = KoTr.overrides.length;
    if (n != _ovCount) {
      _ovCount = n;
      setState(() {});
    }
  }

  void _prepare() {
    // 작품별 용어집 자동 적용: 제목·태그로 판단
    KoTr.addContext('post:${widget.postId}', '${widget.title}\n${widget.tags.join('\n')}');
    _doc = KoChapter.parse(widget.content);
    _lines = [
      if (KoChapter.translateTitle && KoTr.hasCjk(widget.title)) widget.title.trim(),
      ..._doc.lines,
    ];
    _map = KoChapter.savedMap(widget.postId);
    final sv = KoChapter.saved(widget.postId);
    _by = (sv?['by'] ?? '').toString();
    _glossaryChanged = sv != null &&
        sv['g'] is int &&
        sv['g'] != KoChapter.glossarySig(_lines.join('\n'));
    _showKo = KoTr.enabled && KoChapter.loadSaved && _map.isNotEmpty;
    _failed = 0;
    _error = null;
  }

  String _tr(String line) {
    final t = line.trim();
    return KoTr.overrides[t] ?? _map[t] ?? KoTr.overrides[line] ?? _map[line] ?? line;
  }

  Future<void> _translate({bool? useAi, bool fresh = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _done = 0;
      _total = 0;
      _error = null;
    });
    try {
      final r = await KoChapter.translate(
        widget.postId,
        _lines,
        useAi: useAi,
        fresh: fresh,
        onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _map = r.map;
        _by = r.by;
        _failed = r.failed;
        _showKo = true;
        _glossaryChanged = false;
      });
      if (r.failed > 0) {
        KoDialog.showToast('${r.failed}개 문단은 번역하지 못했어요. 잠시 뒤 [번역]을 다시 누르면 그것만 다시 해요');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retranslateLine(String line) async {
    KoChapter.removeLine(widget.postId, line);
    _map.remove(line);
    final r = await KoChapter.translate(widget.postId, [line]);
    if (mounted) setState(() => _map = KoChapter.savedMap(widget.postId)..addAll(r.map));
  }

  Future<void> _openParagraphs() async {
    await KoNav.to(
      () => _KoParagraphsPage(
        lines: _lines.where(KoTr.hasCjk).toSet().toList(),
        tr: _tr,
        retranslate: _retranslateLine,
      ),
    );
    if (!mounted) return;
    final sv = KoChapter.saved(widget.postId);
    setState(() {
      _map = KoChapter.savedMap(widget.postId);
      _glossaryChanged = sv != null &&
          sv['g'] is int &&
          sv['g'] != KoChapter.glossarySig(_lines.join('\n'));
    });
  }

  void _menu(String v) {
    switch (v) {
      case 'ai':
        _translate(useAi: true, fresh: true);
      case 'google':
        _translate(useAi: false, fresh: true);
      case 'forget':
        KoChapter.forget(widget.postId);
        setState(() {
          _map = {};
          _showKo = false;
          _by = '';
        });
      case 'settings':
        KoNav.to(() => const KoSettingsPage()).then((_) {
          if (mounted) setState(_prepare);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _showKo
        ? widget.builder(
            KoChapter.translateTitle ? _tr(widget.title.trim()) : widget.title,
            _doc.build(_tr),
          )
        : widget.builder(widget.title, widget.content);
    if (!KoTr.enabled || !_hasText) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [_bar(context), body],
    );
  }

  Widget _bar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final aiNow = KoTr.aiFor('chapter');
    final translated = _map.isNotEmpty;
    final missing = _missing;

    String info;
    if (_busy) {
      info = _total == 0 ? '번역 준비 중…' : '번역 중 $_done/$_total 문단';
    } else if (_error != null) {
      info = '번역 실패: $_error';
    } else if (translated) {
      final parts = <String>[
        if (_by.isNotEmpty) _by,
        if (missing > 0) '번역 안 된 문단 $missing개',
        if (_glossaryChanged) '용어집이 바뀌었어요 · ⋮ 에서 다시 번역',
      ];
      info = parts.join(' · ');
    } else {
      info = aiNow ? 'AI 번역기로 이 글 전체를 번역해요' : '구글 번역으로 이 글 전체를 번역해요';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (!translated || missing > 0)
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _translate(),
                  icon: const Icon(Icons.translate, size: 18),
                  label: Text(translated ? '나머지 번역' : '한국어로 번역'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => setState(() => _showKo = !_showKo),
                  icon: Icon(_showKo ? Icons.notes : Icons.translate, size: 18),
                  label: Text(_showKo ? '원문 보기' : '번역 보기'),
                ),
              const SizedBox(width: 8),
              if (translated && _showKo)
                TextButton(
                  onPressed: _busy ? null : _openParagraphs,
                  child: const Text('문단 고치기'),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                enabled: !_busy,
                icon: const Icon(Icons.more_vert),
                onSelected: _menu,
                itemBuilder: (_) => [
                  if (KoTr.hasAi) const PopupMenuItem(value: 'ai', child: Text('AI 번역기로 처음부터 다시')),
                  const PopupMenuItem(value: 'google', child: Text('구글 번역으로 처음부터 다시')),
                  if (translated) const PopupMenuItem(value: 'forget', child: Text('저장된 번역 지우기')),
                  const PopupMenuItem(value: 'settings', child: Text('번역 설정')),
                ],
              ),
            ],
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            ),
          if (info.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(info, style: small),
            ),
          if (_failed > 0 && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text('이번에 $_failed개 문단을 번역하지 못했어요', style: small.copyWith(color: cs.error)),
            ),
        ],
      ),
    );
  }
}

// 문단별 원문·번역 목록. 누르면 번역 고치기 창
class _KoParagraphsPage extends StatefulWidget {
  const _KoParagraphsPage({required this.lines, required this.tr, required this.retranslate});

  final List<String> lines;
  final String Function(String) tr;
  final Future<void> Function(String) retranslate;

  @override
  State<_KoParagraphsPage> createState() => _KoParagraphsPageState();
}

class _KoParagraphsPageState extends State<_KoParagraphsPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('문단 고치기')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.lines.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '고칠 문단을 누르세요. 문단 번역을 직접 고치거나, 단어를 용어집에 넣으면 같은 단어가 나오는 다른 글에도 적용돼요.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            );
          }
          final zh = widget.lines[i - 1];
          final ko = widget.tr(zh);
          final fixed = KoTr.hasOverride(zh);
          return ListTile(
            title: Text(ko == zh ? '(번역 안 됨)' : ko),
            subtitle: Text(zh, style: TextStyle(color: cs.onSurfaceVariant)),
            trailing: fixed ? Icon(Icons.edit, size: 16, color: cs.primary) : null,
            onTap: () async {
              await KoFix.open(
                zh,
                ko: ko == zh ? null : ko,
                retranslate: () => widget.retranslate(zh),
              );
              if (mounted) setState(() {});
            },
          );
        },
      ),
    );
  }
}
