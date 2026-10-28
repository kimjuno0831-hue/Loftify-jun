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
              leading: const Icon(Icons.add),
              title: Text('작품 기본 만들기: ${w.name}'),
              onTap: () async {
                await KoNav.to(() => KoVoiceEditPage(scope: KoVoice.workScope(w.name)));
                setState(() {});
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
            onSelected: (v) {
              if (v == 'auto') _clearAuto();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'auto', child: Text('자동 기록 줄 모두 지우기'))],
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
