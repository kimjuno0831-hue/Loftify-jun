// "번역 고치기" 화면 (실시간 번역 앱 livetr 의 FixActivity 를 옮겨온 것)
// 본문 문단·제목 길게 누르기에서 열림.
// · 이 문장만 고치기: 고친 번역을 저장해서 같은 문장은 계속 그렇게 보여줌
// · 용어집에 넣기: 단어 하나를 '중국어=한국어'로 저장 → 그 단어가 들어간 모든 번역에 적용
import 'package:loftify/ko/ko_lookup.dart';
import 'package:loftify/ko/ko_translate.dart';
import 'package:loftify/ko/ko_compat.dart';
import 'package:loftify/ko/ko_voice.dart';
import 'package:loftify/ko/ko_voice_page.dart';
import 'package:flutter/material.dart';

abstract final class KoFix {
  // origId: 원문 보기/번역 보기 전환에 쓸 열쇠 (댓글 id, 제목 글자 등). 없으면 전환 버튼 없음.
  // ko: 본문(화) 번역처럼 이 모듈 밖에서 번역한 결과 (있으면 그걸 고침)
  // retranslate: 그 번역을 다시 하는 방법 (본문 문단)
  static Future<void> open(
    String zh, {
    Object? origId,
    String? ko,
    Future<void> Function()? retranslate,
    String? voiceStory,
  }) async {
    if (zh.trim().isEmpty) return;
    if (ko == null) KoTr.want(zh);
    await KoNav.to(
      () => KoFixPage(
        zh: zh,
        origId: origId,
        ko: ko,
        retranslate: retranslate,
        voiceStory: voiceStory,
      ),
    );
  }
}

class KoFixPage extends StatefulWidget {
  const KoFixPage({
    super.key,
    required this.zh,
    this.origId,
    this.ko,
    this.retranslate,
    this.voiceStory,
  });

  // 본문 문단에서 열었을 때: 인물 말투 규칙을 저장할 연재 범위
  final String? voiceStory;
  final String zh;
  final Object? origId;
  final String? ko;
  final Future<void> Function()? retranslate;

  @override
  State<KoFixPage> createState() => _KoFixPageState();
}

class _KoFixPageState extends State<KoFixPage> {
  late final _zhCtrl = TextEditingController(text: widget.zh);
  late final _koViewCtrl = TextEditingController(text: _currentKo);
  late final _sentenceCtrl = TextEditingController(text: _currentKo);
  final _termZh = TextEditingController();
  final _termKo = TextEditingController();
  String _info = '';
  bool _busy = false;
  List<KoCandidate> _cands = [];
  // null = 공통 용어집
  KoWork? _target;

  String get _currentKo {
    final ov = KoTr.overrides[widget.zh];
    if (ov != null) return ov;
    if (widget.ko != null) return widget.ko!;
    return KoTr.isTranslated(widget.zh) ? KoTr.show(widget.zh) : '(아직 번역 안 됨)';
  }

  @override
  void initState() {
    super.initState();
    final act = KoTr.activeWorks;
    if (act.isNotEmpty) _target = act.first;
    KoTr.updates.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (!mounted) return;
    final now = _currentKo;
    if (_koViewCtrl.text != now) {
      _koViewCtrl.text = now;
      if (_sentenceCtrl.text == '(아직 번역 안 됨)') _sentenceCtrl.text = now;
      setState(() {});
    }
  }

  @override
  void dispose() {
    KoTr.updates.removeListener(_onUpdate);
    _zhCtrl.dispose();
    _koViewCtrl.dispose();
    _sentenceCtrl.dispose();
    _termZh.dispose();
    _termKo.dispose();
    _vFrom.dispose();
    _vTo.dispose();
    _vRule.dispose();
    super.dispose();
  }

  String _selected(TextEditingController c) {
    final s = c.selection;
    if (!s.isValid || s.isCollapsed) return '';
    final a = s.start < s.end ? s.start : s.end;
    final b = s.start < s.end ? s.end : s.start;
    if (a < 0 || b > c.text.length) return '';
    return c.text.substring(a, b).trim();
  }

  void _setInfo(String s) {
    if (mounted) setState(() => _info = s);
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      _setInfo('실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 원문에서 고른 부분의 뜻 보기 (키 없이도 됨)
  void _meaning() {
    final sel = _selected(_zhCtrl);
    if (sel.isEmpty) {
      KoDialog.showToast('중국어 원문에서 먼저 글자를 길게 눌러 선택하세요');
      return;
    }
    _run(() async {
      _setInfo("'$sel' 뜻 찾는 중…");
      final r = await KoTr.quick(sel);
      _setInfo("'$sel' = $r\n맞으면 [원문 선택 부분 쓰기]로 아래 칸에 넣으세요.");
    });
  }

  void _useZhSelection() {
    final sel = _selected(_zhCtrl);
    if (sel.isEmpty) {
      KoDialog.showToast('중국어 원문에서 먼저 글자를 길게 눌러 선택하세요');
      return;
    }
    setState(() => _termZh.text = sel);
  }

  // ① 번역에서 고른 단어의 원문 찾기
  void _findSource() {
    final word = _selected(_koViewCtrl);
    if (word.isEmpty) {
      KoDialog.showToast('한국어 번역에서 틀린 단어를 먼저 길게 눌러 선택하세요');
      return;
    }
    if (!KoTr.hasAi) {
      _setInfo('AI 번역기가 없어서 자동으로 찾을 수 없어요. 원문에서 글자를 골라 [선택한 원문 뜻 보기]로 직접 찾아보세요.');
      return;
    }
    _run(() async {
      _setInfo("'$word'의 원문을 찾는 중…");
      final r = await KoLookup.findSource(widget.zh, _koViewCtrl.text, word);
      if (r != null && widget.zh.contains(r)) {
        _termZh.text = r;
        if (_termKo.text.isEmpty) _termKo.text = word;
        _setInfo("'$word' ← 원문 '$r'\n아래 '앞으로 이렇게 번역해줘' 칸을 원하는 말로 고치고 저장하세요.");
      } else {
        _setInfo('정확히 찾지 못했어요${r != null ? ' (AI 답: $r)' : ''}. 원문에서 직접 선택해 주세요.');
      }
    });
  }

  // ② 한국어 이름으로 중국어 표기 찾기
  void _lookup() {
    final k = _termKo.text.trim();
    if (k.isEmpty) {
      KoDialog.showToast("먼저 '앞으로 이렇게 번역해줘' 칸에 한국어 이름을 적어주세요");
      return;
    }
    if (!KoTr.hasAi) {
      _setInfo('AI 번역기가 필요해요. [웹에서 찾아보기]로 직접 확인해 주세요.');
      return;
    }
    final work = _target?.name;
    _run(() async {
      _setInfo(
        work == null
            ? "'$k' 찾는 중… (작품을 고르면 더 정확해요)"
            : "'$work'에서 '$k' 찾는 중… (웹 검색 후 AI가 읽어요)",
      );
      final cs = await KoLookup.find(k, context: widget.zh, work: work);
      setState(() => _cands = cs);
      _setInfo(
        cs.isEmpty
            ? "'$k'의 표기를 찾지 못했어요. [웹에서 찾아보기]로 직접 확인해주세요."
            : "후보를 눌러서 고르세요. 'AI 추측'은 웹 근거가 없는 거라 한 번 더 확인해보세요.",
      );
    });
  }

  void _saveSentence() {
    final t = _sentenceCtrl.text.trim();
    if (t.isEmpty || t == '(아직 번역 안 됨)') {
      KoDialog.showToast('고친 번역을 적어주세요');
      return;
    }
    KoTr.setOverride(widget.zh, t);
    if (widget.origId != null && KoTr.showOrig.contains(widget.origId!)) {
      KoTr.toggleOrig(widget.origId!);
    }
    KoDialog.showToast('이 문장의 번역을 고쳤어요');
    KoNav.back();
  }

  void _saveTerm() {
    final z = _termZh.text.trim();
    final k = _termKo.text.trim();
    if (z.isEmpty || k.isEmpty) {
      KoDialog.showToast('중국어와 한국어를 둘 다 적어주세요');
      return;
    }
    if (z.contains('=') || z.contains('\n')) {
      KoDialog.showToast("중국어에 '='나 줄바꿈은 넣을 수 없어요");
      return;
    }
    // 이 문장을 직접 고쳐둔 게 있으면 용어집이 적용되도록 지움
    if (KoTr.hasOverride(widget.zh)) KoTr.setOverride(widget.zh, null, rewant: widget.ko == null);
    KoTr.addGlossary(z, k, target: _target);
    KoDialog.showToast(
      "${_target == null ? '공통' : _target!.name} 용어집에 '$z=$k' 저장, 다시 번역해요",
    );
    KoNav.back();
  }

  // ── 말투 규칙 ──
  final _vFrom = TextEditingController();
  final _vTo = TextEditingController();
  final _vRule = TextEditingController();
  String? _vScope; // null 이면 이 연재

  bool _vBasic = true; // true: 인물 기본 말투, false: 특정 상대에게

  // 이 연재에 저장된 말투 (이 문단에 나온 인물 먼저)
  Widget _voiceList() {
    final story = widget.voiceStory!;
    final b = KoVoice.book(story);
    final cs = ColorScheme.of(context);
    if (b.isEmpty) {
      return Text('이 연재에 저장된 말투가 아직 없어요.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant));
    }
    final here = '${widget.zh}\n$_currentKo';
    bool hit(String n) => n.isNotEmpty && here.contains(n);
    final chars = [...b.chars]..sort((x, y) => (hit(y.ko) || hit(y.zh) ? 1 : 0) - (hit(x.ko) || hit(x.zh) ? 1 : 0));
    final rels = [...b.rels]..sort((x, y) => (hit(y.from) ? 1 : 0) - (hit(x.from) ? 1 : 0));
    Widget row(String t, bool auto, VoidCallback onDel) => Row(
      children: [
        Expanded(
          child: Text(
            t,
            style: TextStyle(fontSize: 13, color: auto ? cs.onSurfaceVariant : cs.onSurface),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
          tooltip: '지우기',
          onPressed: () => setState(onDel),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in chars.take(8))
          row(
            '${c.auto ? '(자동) ' : ''}${c.ko}${c.zh.isEmpty ? '' : ' (${c.zh})'} · 기본: ${c.note.isEmpty ? '-' : c.note}',
            c.auto,
            () => KoVoice.removeChar(story, c.ko),
          ),
        for (final r in rels.take(10))
          row(
            '${r.auto ? '(자동) ' : ''}${r.from} → ${r.to == '*' ? '누구에게나' : r.to}: ${r.rule}',
            r.auto,
            () => KoVoice.removeRule(story, r.pairKey),
          ),
        if (chars.length > 8 || rels.length > 10)
          Text('… 더 있어요', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _voiceForm(Widget Function(String, VoidCallback?) btn) {
    final story = widget.voiceStory!;
    final names = KoVoice.names(story);
    final works = KoTr.activeWorks;
    Widget pick(TextEditingController c) => names.isEmpty
        ? const SizedBox.shrink()
        : Wrap(
            spacing: 6,
            children: [
              for (final n in names.take(12))
                ActionChip(
                  label: Text(n),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => c.text = n),
                ),
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _voiceList(),
        Align(
          alignment: Alignment.centerLeft,
          child: btn('이 연재 말투 전체 보기·고치기', () async {
            await KoNav.to(() => KoVoiceEditPage(scope: story, title: KoVoice.titleOf(story)));
            if (mounted) setState(() {});
          }),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('인물 기본 말투')),
            ButtonSegment(value: false, label: Text('특정 상대에게')),
          ],
          selected: {_vBasic},
          onSelectionChanged: (v) => setState(() => _vBasic = v.first),
        ),
        TextField(
          controller: _vFrom,
          decoration: InputDecoration(labelText: _vBasic ? '인물 (한국어 이름)' : '말하는 사람 (한국어 이름)'),
        ),
        pick(_vFrom),
        if (!_vBasic) ...[
          TextField(controller: _vTo, decoration: const InputDecoration(labelText: '듣는 사람 (한국어 이름)')),
          pick(_vTo),
        ],
        TextField(
          controller: _vRule,
          decoration: InputDecoration(
            labelText: '말투',
            hintText: _vBasic ? '예) 반말, 무뚝뚝함 / 존댓말, 차분함' : "예) 반말, '박사'라고 부름",
          ),
        ),
        const SizedBox(height: 8),
        DropdownButton<String?>(
          value: _vScope,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('이 연재에만')),
            for (final w in works)
              DropdownMenuItem(value: KoVoice.workScope(w.name), child: Text('작품 기본: ${w.name}')),
          ],
          onChanged: (v) => setState(() => _vScope = v),
        ),
        Wrap(
          children: [
            btn('저장', () => _saveVoice(retranslate: false)),
            if (widget.retranslate != null) btn('저장하고 이 문단 다시 번역', () => _saveVoice(retranslate: true)),
          ],
        ),
      ],
    );
  }

  void _saveVoice({required bool retranslate}) {
    final f = _vFrom.text.trim();
    final t = _vTo.text.trim();
    final r = _vRule.text.trim();
    final scope = _vScope ?? widget.voiceStory!;
    if (_vBasic) {
      if (f.isEmpty || r.isEmpty) {
        KoDialog.showToast('인물과 말투를 적어 주세요');
        return;
      }
      KoVoice.putChar(scope, f, r);
    } else {
      if (f.isEmpty || t.isEmpty || r.isEmpty) {
        KoDialog.showToast('말하는 사람, 듣는 사람, 말투를 모두 적어 주세요');
        return;
      }
      KoVoice.putRule(scope, f, t, r);
    }
    setState(() {});
    if (!retranslate) {
      KoDialog.showToast("저장했어요. 이미 번역한 문단은 ⋮ → 처음부터 다시 번역하면 반영돼요");
      return;
    }
    KoTr.setOverride(widget.zh, null, rewant: false);
    _setInfo('규칙을 저장하고 이 문단을 다시 번역하는 중…');
    widget.retranslate!().then((_) => KoNav.back());
  }

  @override
  Widget build(BuildContext context) {
    final cs = ColorScheme.of(context);
    final label = TextStyle(fontSize: 13, color: cs.primary);
    final hasOv = KoTr.hasOverride(widget.zh);
    Widget btn(String t, VoidCallback? f) => Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: OutlinedButton(onPressed: _busy ? null : f, child: Text(t)),
    );
    Widget gap([double h = 12]) => SizedBox(height: h);
    return Scaffold(
      appBar: AppBar(title: const Text('번역 고치기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('중국어 원문 (길게 눌러 선택 가능)', style: label),
            TextField(
              controller: _zhCtrl,
              readOnly: true,
              maxLines: null,
              style: const TextStyle(fontSize: 16),
            ),
            Wrap(
              children: [
                btn('원문 복사', () => KoUtil.copyText(widget.zh)),
                btn('선택한 원문 뜻 보기', _meaning),
                btn('원문 선택 부분 쓰기', _useZhSelection),
              ],
            ),
            gap(),
            Text(
              '지금 번역${KoTr.byOf(widget.zh) != null ? ' (${KoTr.byOf(widget.zh)})' : ''} — 틀린 단어를 길게 눌러 선택',
              style: label,
            ),
            TextField(
              controller: _koViewCtrl,
              readOnly: true,
              maxLines: null,
              style: const TextStyle(fontSize: 16),
            ),
            Wrap(
              children: [
                btn('번역 복사', () => KoUtil.copyText(_koViewCtrl.text)),
                btn('다시 번역', () {
                  if (widget.retranslate != null) {
                    KoTr.setOverride(widget.zh, null, rewant: false);
                    _setInfo('다시 번역하는 중…');
                    widget.retranslate!().then((_) {
                      KoNav.back();
                    });
                    return;
                  }
                  KoTr.retranslate(widget.zh);
                  _setInfo('다시 번역하는 중… 잠시 뒤 위 번역이 바뀌어요.');
                }),
                if (widget.origId != null)
                  btn(
                    KoTr.showOrig.contains(widget.origId!) ? '번역으로 보기' : '원문으로 보기',
                    () {
                      KoTr.toggleOrig(widget.origId!);
                      KoNav.back();
                    },
                  ),
              ],
            ),
            if (_info.isNotEmpty) ...[
              gap(8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_info, style: TextStyle(color: cs.onSecondaryContainer)),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            const Divider(height: 32),
            Text('방법 1. 이 문장만 고치기', style: label.copyWith(fontSize: 15)),
            const Text('같은 문장이 다시 나오면 계속 이렇게 보여줘요.'),
            TextField(controller: _sentenceCtrl, maxLines: null),
            gap(4),
            Wrap(
              children: [
                btn('이 문장 저장', _saveSentence),
                if (hasOv)
                  btn('고친 번역 지우기', () {
                    KoTr.setOverride(widget.zh, null);
                    KoDialog.showToast('원래 번역으로 돌렸어요');
                    KoNav.back();
                  }),
              ],
            ),
            if (widget.voiceStory != null) ...[
              const Divider(height: 32),
              Text('방법 2. 말투를 규칙으로 저장', style: label.copyWith(fontSize: 15)),
              const Text('누가 누구에게 어떤 말투를 쓰는지 저장하면, 앞으로 번역할 때 계속 그렇게 해요 (AI 번역기).'),
              gap(8),
              _voiceForm(btn),
            ],
            const Divider(height: 32),
            Text('방법 ${widget.voiceStory != null ? 3 : 2}. 단어를 용어집에 넣기', style: label.copyWith(fontSize: 15)),
            const Text('그 단어가 들어간 다른 번역에도 모두 적용돼요.'),
            gap(8),
            btn('① 번역에서 고른 단어의 원문 찾기', _findSource),
            gap(8),
            Text('앞으로 이렇게 번역해줘 (한국어)', style: label),
            TextField(
              controller: _termKo,
              decoration: const InputDecoration(hintText: '예) 페이몬'),
            ),
            gap(8),
            Wrap(
              children: [
                btn('② 한국어 이름으로 중국어 표기 찾기', _lookup),
                btn('웹에서 찾아보기', () {
                  final k = _termKo.text.trim();
                  if (k.isEmpty) {
                    KoDialog.showToast('먼저 한국어 이름을 적어주세요');
                    return;
                  }
                  KoUtil.launchURL(
                    KoLookup.webSearchUrl(k, work: _target?.name),
                  );
                }),
              ],
            ),
            for (final c in _cands)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => setState(() => _termZh.text = c.zh),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${c.zh}  · ${c.source}\n${c.note}${c.evidence.isNotEmpty ? '\n「${c.evidence}」' : ''}',
                    ),
                  ),
                ),
              ),
            gap(8),
            Text('저장할 중국어 단어', style: label),
            TextField(
              controller: _termZh,
              decoration: const InputDecoration(hintText: '예) 派蒙'),
            ),
            gap(12),
            Text('어느 용어집에 저장할까요?', style: label),
            RadioGroup<int>(
              groupValue: _target == null ? -1 : KoTr.works.indexOf(_target!),
              onChanged: (v) => setState(
                () => _target = (v == null || v < 0) ? null : KoTr.works[v],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<int>(
                    value: -1,
                    dense: true,
                    title: const Text('공통 용어집'),
                  ),
                  for (var i = 0; i < KoTr.works.length; i++)
                    RadioListTile<int>(
                      value: i,
                      dense: true,
                      title: Text(
                        '${KoTr.works[i].name} 용어집${KoTr.isActive(KoTr.works[i]) ? ' (지금 적용 중)' : ''}',
                      ),
                    ),
                ],
              ),
            ),
            if (KoTr.works.isEmpty)
              const Text(
                '작품별 용어집은 설정 → 한국어 번역 → 작품별 용어집에서 만들 수 있어요.',
                style: TextStyle(fontSize: 12),
              ),
            gap(8),
            FilledButton(
              onPressed: _busy ? null : _saveTerm,
              child: const Text('③ 저장하고 다시 번역'),
            ),
          ],
        ),
      ),
    );
  }
}
