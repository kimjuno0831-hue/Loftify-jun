// 인물 말투 화면: 범위 목록(작품 기본 · 연재) + 범위별 편집
import 'package:flutter/material.dart';
import 'package:loftify/ko/ko_compat.dart';
import 'package:loftify/ko/ko_translate.dart';
import 'package:loftify/ko/ko_voice.dart';

const _help = '한 줄에 하나씩.\n'
    "인물:  阿米娅=아미야 | 존댓말, 밝고 다정함\n"
    "관계:  아미야>박사: 존댓말, '박사님'이라고 부름\n"
    "누구에게나:  켈시>*: 하십시오체\n"
    "'(자동)' 으로 시작하는 줄은 AI가 번역하며 정한 것. 고치거나 '(자동)'을 지우면 직접 정한 규칙이 돼서 늘 우선해요.";

class KoVoiceListPage extends StatefulWidget {
  const KoVoiceListPage({super.key});

  @override
  State<KoVoiceListPage> createState() => _KoVoiceListPageState();
}

class _KoVoiceListPageState extends State<KoVoiceListPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scopes = KoVoice.books.keys.toList()
      ..sort((a, b) {
        // 작품 먼저
        final wa = a.startsWith('work:') ? 0 : 1;
        final wb = b.startsWith('work:') ? 0 : 1;
        return wa != wb ? wa - wb : a.compareTo(b);
      });
    final works = KoTr.works.where((w) => !KoVoice.books.containsKey(KoVoice.workScope(w.name))).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('인물 말투')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.auto_fix_high),
            title: const Text('AI가 정한 말투 자동 기록'),
            subtitle: const Text('번역하면서 누가 누구에게 어떤 말투를 썼는지 연재별로 쌓아 두고, 다음 부분·다음 편에서 그대로 따라요'),
            value: KoVoice.autoOn,
            onChanged: (v) {
              GStorage.setting.put(KoVoice.kAuto, v);
              setState(() {});
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '작품 기본은 작품별 용어집처럼 글 제목·태그로 자동 적용되고, 연재(합집)별 말투가 그 위에 덮어써요. '
              '연재별 말투는 글 본문 번역 줄의 ⋮ → 인물 말투에서도 열 수 있어요.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          for (final sc in scopes)
            ListTile(
              leading: Icon(sc.startsWith('work:') ? Icons.collections_bookmark_outlined : Icons.menu_book_outlined),
              title: Text(KoVoice.label(sc, title: KoVoice.titleOf(sc))),
              subtitle: Text(() {
                final b = KoVoice.book(sc);
                final auto = b.rels.where((r) => r.auto).length + b.chars.where((c) => c.auto).length;
                return '인물 ${b.chars.length} · 관계 ${b.rels.length}${auto > 0 ? ' (자동 $auto)' : ''}';
              }()),
              onTap: () async {
                await KoNav.to(() => KoVoiceEditPage(scope: sc, title: KoVoice.titleOf(sc)));
                setState(() {});
              },
            ),
          if (works.isNotEmpty) const Divider(),
          for (final w in works)
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text('작품 기본 만들기: ${w.name}'),
              subtitle: const Text('AI가 웹 검색으로 주요 인물 말투를 채워요 (직접 쓰려면 길게 누르기)'),
              onTap: () async {
                await koVoiceBuildWork(context, w.name);
                if (mounted) setState(() {});
              },
              onLongPress: () async {
                await KoNav.to(() => KoVoiceEditPage(scope: KoVoice.workScope(w.name)));
                if (mounted) setState(() {});
              },
            ),
          if (scopes.isEmpty && works.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '아직 없어요. AI 번역기로 본문을 번역하면 연재별로 자동으로 쌓이고, 작품별 용어집을 만들면 작품 기본 말투도 정할 수 있어요.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class KoVoiceEditPage extends StatefulWidget {
  const KoVoiceEditPage({super.key, required this.scope, this.title});

  final String scope;
  final String? title;

  @override
  State<KoVoiceEditPage> createState() => _KoVoiceEditPageState();
}

class _KoVoiceEditPageState extends State<KoVoiceEditPage> {
  late final _ctrl = TextEditingController(text: KoVoice.text(widget.scope));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    KoVoice.setText(widget.scope, KoVoiceBook.parse(_ctrl.text).format());
    KoDialog.showToast('저장했어요. 이미 번역한 글은 ⋮ → 처음부터 다시 번역하면 반영돼요');
    Navigator.of(context).maybePop();
  }

  // 작품 범위면 그 작품, 연재 범위면 지금 적용 중인 첫 작품
  String? get _work {
    if (widget.scope.startsWith('work:')) return widget.scope.substring(5);
    final w = KoTr.activeWorks;
    return w.isEmpty ? null : w.first.name;
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'auto':
        _clearAuto();
      case 'find':
        // 입력 중인 것부터 저장하고 찾은 걸 더함
        KoVoice.setText(widget.scope, KoVoiceBook.parse(_ctrl.text).format());
        await koVoiceLookup(context, widget.scope);
        if (mounted) setState(() => _ctrl.text = KoVoice.text(widget.scope));
      case 'build':
        KoVoice.setText(widget.scope, KoVoiceBook.parse(_ctrl.text).format());
        await koVoiceBuildWork(context, _work!);
        if (mounted) setState(() => _ctrl.text = KoVoice.text(widget.scope));
        if (!widget.scope.startsWith('work:')) {
          KoDialog.showToast("'$_work' 작품 기본 말투에 넣었어요 (설정 → 인물 말투에서 볼 수 있어요)");
        }
    }
  }

  void _clearAuto() {
    final b = KoVoiceBook.parse(_ctrl.text);
    _ctrl.text = KoVoiceBook(
      b.chars.where((c) => !c.auto).toList(),
      b.rels.where((r) => !r.auto).toList(),
    ).format();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = KoVoice.label(widget.scope, title: widget.title);
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'find', child: Text('인물 찾아서 넣기')),
              if (_work != null) PopupMenuItem(value: 'build', child: Text("AI로 '$_work' 인물 말투 채우기")),
              const PopupMenuItem(value: 'auto', child: Text('자동 기록 줄 모두 지우기')),
            ],
          ),
          TextButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_help, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            minLines: 12,
            maxLines: null,
            style: const TextStyle(fontSize: 14, height: 1.5),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}

// ── AI 로 채우기 (작품 전체 / 인물 한 명) ──

// 찾은 인물·관계를 보여주고 고른 것만 넣기
Future<int> _pickAndAdd(BuildContext context, String scope, KoVoiceBook found) async {
  if (found.isEmpty) {
    KoDialog.showToast('찾은 게 없어요');
    return 0;
  }
  final have = KoVoice.book(scope);
  final haveChars = {for (final c in have.chars) c.ko: c};
  final havePairs = {for (final r in have.rels) r.pairKey: r};
  // 이미 직접 적어 둔 건 기본으로 체크 해제
  final cOn = [for (final c in found.chars) !(haveChars[c.ko]?.auto == false)];
  final rOn = [for (final r in found.rels) !(havePairs[r.pairKey]?.auto == false)];
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('넣을 항목 (틀린 건 체크 해제)'),
        contentPadding: const EdgeInsets.only(top: 8),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < found.chars.length; i++)
                CheckboxListTile(
                  dense: true,
                  value: cOn[i],
                  onChanged: (v) => setState(() => cOn[i] = v ?? false),
                  title: Text(
                    '${found.chars[i].ko}${found.chars[i].zh.isEmpty ? '' : ' (${found.chars[i].zh})'}'
                    '${haveChars.containsKey(found.chars[i].ko) ? '  [이미 있음]' : ''}',
                  ),
                  subtitle: Text('기본: ${found.chars[i].note}'),
                ),
              for (var i = 0; i < found.rels.length; i++)
                CheckboxListTile(
                  dense: true,
                  value: rOn[i],
                  onChanged: (v) => setState(() => rOn[i] = v ?? false),
                  title: Text(
                    '${found.rels[i].from} → ${found.rels[i].to}'
                    '${havePairs.containsKey(found.rels[i].pairKey) ? '  [이미 있음]' : ''}',
                  ),
                  subtitle: Text(found.rels[i].rule),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('넣기')),
        ],
      ),
    ),
  );
  if (ok != true) return 0;
  final add = KoVoiceBook(
    [for (var i = 0; i < found.chars.length; i++) if (cOn[i]) found.chars[i]],
    [for (var i = 0; i < found.rels.length; i++) if (rOn[i]) found.rels[i]],
  );
  KoVoice.addAll(scope, add);
  final n = add.chars.length + add.rels.length;
  KoDialog.showToast('$n개를 넣었어요');
  return n;
}

bool _needAi() {
  if (KoTr.hasAi) return false;
  KoDialog.showToast('AI 번역기가 필요해요 (번역 설정 → AI 번역기)');
  return true;
}

// 작품 전체 인물 말투 초안 → 작품 기본에 넣기
Future<void> koVoiceBuildWork(BuildContext context, String work) async {
  if (_needAi()) return;
  KoDialog.showLoading(msg: "'$work' 인물 말투를 찾는 중…\n(웹 검색 후 AI가 정리해요)");
  KoVoiceBook found;
  try {
    found = await KoVoice.buildWork(work);
  } catch (e) {
    KoDialog.dismiss();
    KoDialog.showToast('실패: $e');
    return;
  }
  KoDialog.dismiss();
  if (!context.mounted) return;
  await _pickAndAdd(context, KoVoice.workScope(work), found);
}

// 인물 이름을 받아 찾아서 넣기
Future<void> koVoiceLookup(BuildContext context, String scope) async {
  if (_needAi()) return;
  final works = KoTr.activeWorks.map((e) => e.name).toList();
  final work = scope.startsWith('work:') ? scope.substring(5) : (works.isEmpty ? null : works.first);
  final ctrl = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('인물 찾아서 넣기'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(work == null ? '작품을 모르면 이름만으로 찾아요.' : '작품: $work', style: const TextStyle(fontSize: 12)),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '인물 이름 (한국어나 중국어)'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('찾기')),
      ],
    ),
  );
  ctrl.dispose();
  if (name == null || name.trim().isEmpty) return;
  KoDialog.showLoading(msg: "'${name.trim()}' 찾는 중…");
  KoVoiceBook found;
  try {
    found = await KoVoice.lookupChar(name.trim(), work: work);
  } catch (e) {
    KoDialog.dismiss();
    KoDialog.showToast('실패: $e');
    return;
  }
  KoDialog.dismiss();
  if (!context.mounted) return;
  await _pickAndAdd(context, scope, found);
}
