// 글 상세 화면의 본문 번역 줄 + 번역된 본문
// 원래 본문 위젯(builder)은 그대로 두고, 넘겨주는 제목·본문 HTML 만 번역본으로 바꿔 준다.
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:loftify/ko/ko_chapter.dart';
import 'package:loftify/ko/ko_compat.dart';
import 'package:loftify/ko/ko_fix.dart';
import 'package:loftify/ko/ko_settings_page.dart';
import 'package:loftify/ko/ko_translate.dart';
import 'package:loftify/ko/ko_voice.dart';
import 'package:loftify/ko/ko_voice_page.dart';

class KoPostBody extends StatefulWidget {
  const KoPostBody({
    super.key,
    required this.postId,
    required this.title,
    required this.content,
    this.tags = const [],
    this.collectionId,
    this.collectionTitle,
    required this.builder,
  });

  final Object postId;
  final String title;
  final String content;
  final List<String> tags;
  final int? collectionId; // 합집(연재) 번호: 인물 말투를 연재 단위로 기억
  final String? collectionTitle;
  String get story => KoVoice.storyScope(postId, collectionId);
  // blockBuilder: 번역된 문단을 직접 그려서 누르면 고칠 수 있게 (본문 위젯에 넘겨줌)
  final Widget Function(
    String title,
    String content,
    Widget? Function(dom.Element element, TextStyle? style)? blockBuilder,
  ) builder;

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
    KoTr.glossaryChanged.addListener(_onGlossary);
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
    KoTr.glossaryChanged.removeListener(_onGlossary);
    super.dispose();
  }

  // 이 글의 문단을 직접 고친 번역이 바뀌면 다시 그림 (개수뿐 아니라 내용까지 비교)
  int _ovSig = 0;
  void _onUpdate() {
    if (!mounted || !_showKo) return;
    final sig = Object.hashAll(_lines.map((l) => KoTr.overrides[l.trim()]));
    if (sig != _ovSig) {
      _ovSig = sig;
      setState(() {});
    }
  }

  // 용어집이 바뀌면 그 단어가 든 문단만 바로 다시 번역
  bool _glossaryBusy = false;
  Future<void> _onGlossary() async {
    final keys = KoTr.glossaryChanged.value;
    if (!mounted || keys.isEmpty || _map.isEmpty || _glossaryBusy) return;
    final redo = _lines
        .where((l) => _map.containsKey(l) && !KoTr.hasOverride(l) && keys.any(l.contains))
        .toSet()
        .toList();
    if (redo.isEmpty) return;
    _glossaryBusy = true;
    try {
      for (final l in redo) {
        KoChapter.removeLine(widget.postId, l);
      }
      setState(() {
        for (final l in redo) {
          _map.remove(l);
        }
      });
      await KoChapter.translate(widget.postId, _lines, story: widget.story);
      if (!mounted) return;
      setState(() {
        _map = KoChapter.savedMap(widget.postId);
        _glossaryChanged = false;
      });
      KoDialog.showToast('용어집에 맞춰 문단 ${redo.length}개를 다시 번역했어요');
    } catch (_) {
    } finally {
      _glossaryBusy = false;
    }
  }

  String get _storyTitle =>
      (widget.collectionId ?? 0) > 0 ? (widget.collectionTitle ?? '') : widget.title;

  void _prepare() {
    KoVoice.rememberTitle(widget.story, _storyTitle);
    // 작품별 용어집 자동 적용: 제목·태그로 판단
    // (화면을 그리는 중에 다른 위젯을 바꾸지 않게 다음 순간에)
    final key = 'post:${widget.postId}';
    final ctx = '${widget.title}\n${widget.tags.join('\n')}';
    final body = widget.content.length > 20000 ? widget.content.substring(0, 20000) : widget.content;
    Future.microtask(() => KoTr.addContext(key, ctx, body: KoChapter.unescape(body.replaceAll(RegExp(r'<[^>]+>'), ' '))));
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
        story: widget.story,
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
    final r = await KoChapter.translate(widget.postId, [line], story: widget.story);
    if (mounted) setState(() => _map = KoChapter.savedMap(widget.postId)..addAll(r.map));
  }

  Future<void> _openParagraphs() async {
    await KoNav.to(
      () => _KoParagraphsPage(
        lines: _lines.where(KoTr.hasCjk).toSet().toList(),
        tr: _tr,
        retranslate: _retranslateLine,
        story: widget.story,
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

  // 번역된 문단: 기본 그리기 대신 글자를 직접 그리고, 누르면 그 문단 번역 고치기
  Widget? _blockBuilder(dom.Element element, TextStyle? style) {
    final k = element.attributes['data-ko'];
    if (k == null) return null;
    final i = int.tryParse(k);
    final blocks = _doc.blocks;
    if (i == null || i < 0 || i >= blocks.length) return null;
    final b = blocks[i];
    final text = Text(b.lines.map(_tr).join('\n'), style: style);
    final gap = (style?.fontSize ?? 16) * 0.5;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap),
      child: KoChapter.tapToFix
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _fixBlock(b),
              child: text,
            )
          : text,
    );
  }

  Future<void> _fixBlock(KoLines b) async {
    final lines = b.lines.where(KoTr.hasCjk).toList();
    if (lines.isEmpty) return;
    var zh = lines.first;
    if (lines.length > 1) {
      // 줄바꿈으로 나뉜 문단: 고칠 줄 고르기
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final l in lines)
                ListTile(
                  title: Text(_tr(l), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, l),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      zh = picked;
    }
    final ko = _tr(zh);
    await KoFix.open(
      zh,
      ko: ko == zh ? null : ko,
      retranslate: () => _retranslateLine(zh),
      voiceStory: widget.story,
    );
    if (mounted) setState(() {});
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
      case 'voice':
        KoNav.to(() => KoVoiceEditPage(scope: widget.story, title: _storyTitle));
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
            _doc.build(_tr, mark: true),
            _blockBuilder,
          )
        : widget.builder(widget.title, widget.content, null);
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
                  const PopupMenuItem(value: 'voice', child: Text('인물 말투 (이 연재)')),
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
  const _KoParagraphsPage({
    required this.lines,
    required this.tr,
    required this.retranslate,
    required this.story,
  });

  final String story;
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
        separatorBuilder: (_, __) => const Divider(height: 1),
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
                voiceStory: widget.story,
              );
              if (mounted) setState(() {});
            },
          );
        },
      ),
    );
  }
}
