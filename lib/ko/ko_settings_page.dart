// 한국어 번역 설정 화면 (설정 맨 위 '한국어 번역', 본문 번역 줄의 ⋮ → 번역 설정)
import 'package:flutter/material.dart';
import 'package:loftify/ko/ko_chapter.dart';
import 'package:loftify/ko/ko_compat.dart';
import 'package:loftify/ko/ko_engines.dart';
import 'package:loftify/ko/ko_engines_page.dart';
import 'package:loftify/ko/ko_translate.dart';
import 'package:loftify/ko/ko_works.dart';

class KoSettingsPage extends StatefulWidget {
  const KoSettingsPage({super.key});

  @override
  State<KoSettingsPage> createState() => _KoSettingsPageState();
}

class _KoSettingsPageState extends State<KoSettingsPage> {
  bool _get(String k, bool def) {
    final v = GStorage.setting.get(k, defaultValue: def);
    return v is bool ? v : def;
  }

  void _put(String k, Object v) {
    GStorage.setting.put(k, v);
    setState(() {});
  }

  Widget _switch(String key, bool def, String title, {String? subtitle, IconData? icon}) =>
      SwitchListTile(
        secondary: icon == null ? null : Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: _get(key, def),
        onChanged: (v) => _put(key, v),
      );

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      t,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
    ),
  );

  // 목록·제목·태그: 0 끄기, 1 구글만, 2 AI 번역기
  int get _listMode {
    if (!_get(KoTr.kText, true)) return 0;
    return _get(KoTr.kAiText, false) ? 2 : 1;
  }

  void _setListMode(int m) {
    GStorage.setting.put(KoTr.kText, m != 0);
    GStorage.setting.put(KoTr.kAiText, m == 2);
    setState(() {});
  }

  static const _listNames = ['끄기', '구글 번역만', 'AI 번역기'];

  Future<void> _pickListMode() async {
    final r = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('목록·제목·태그 번역'),
        children: [
          for (var i = 0; i < 3; i++)
            RadioListTile<int>(
              value: i,
              groupValue: _listMode,
              title: Text(_listNames[i]),
              subtitle: i == 2 ? const Text('한도를 많이 써요. AI가 막히면 구글로') : null,
              onChanged: (v) => Navigator.pop(context, v),
            ),
        ],
      ),
    );
    if (r != null) _setListMode(r);
  }

  Future<void> _pickStyle() async {
    const notes = [
      '문장 구조와 표현을 최대한 살려서',
      '뜻과 분위기는 그대로, 자연스러운 한국어로 (추천)',
      '한국어 웹소설처럼 읽기 편하게',
    ];
    final r = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('번역 말투'),
        children: [
          for (var i = 0; i < 3; i++)
            RadioListTile<int>(
              value: i,
              groupValue: KoTr.style,
              title: Text(KoTr.styleNames[i]),
              subtitle: Text(notes[i]),
              onChanged: (v) => Navigator.pop(context, v),
            ),
        ],
      ),
    );
    if (r != null) {
      KoTr.setStyle(r);
      setState(() {});
    }
  }

  Future<void> _editCommonGlossary() async {
    final ctrl = TextEditingController(text: KoTr.commonGlossaryText);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("공통 용어집 (한 줄에 하나씩 '중국어=한국어')"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(hintText: '太太=작가님\n同人=2차 창작'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('저장')),
        ],
      ),
    );
    if (ok == true) {
      KoTr.setCommonGlossary(ctrl.text.trim());
      setState(() {});
    }
  }

  Future<void> _test() async {
    KoDialog.showLoading(msg: '번역 중…');
    final r = await KoTr.test();
    KoDialog.dismiss();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('번역 테스트 (목록·제목 설정 기준)'),
        content: Text(r),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
      ),
    );
  }

  Future<void> _clearChapters() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('저장된 본문 번역 지우기'),
        content: const Text('번역해 둔 글을 다시 열면 처음부터 다시 번역해야 해요. 직접 고친 번역과 용어집은 그대로 남아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('지우기')),
        ],
      ),
    );
    if (ok == true) {
      await KoChapter.clearAll();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final engines = KoEngines.list.where((e) => e.usable).toList();
    final err = KoTr.lastAiError;
    final glossaryN = KoTr.parseGlossary(KoTr.commonGlossaryText).length;
    final act = KoTr.activeWorks.map((e) => e.name).join(', ');
    return Scaffold(
      appBar: AppBar(title: const Text('한국어 번역')),
      body: ListView(
        children: [
          _switch(KoTr.kEnable, true, '한국어 번역', subtitle: '끄면 번역 버튼과 목록 번역이 모두 사라져요', icon: Icons.translate),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('번역 말투'),
            subtitle: Text(KoTr.styleNames[KoTr.style]),
            onTap: _pickStyle,
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI 번역기'),
            subtitle: Text(
              engines.isEmpty
                  ? '없음 — 지금은 전부 구글 번역. 제미나이 등 무료 키를 넣으면 소설을 훨씬 자연스럽게 번역해요'
                  : '${engines.map((e) => e.name).join(' → ')} (막히면 다음 것, 다 막히면 구글)'
                        '${err != null ? '\n최근 오류: $err' : ''}',
            ),
            onTap: () async {
              await KoNav.to(() => const KoEnginesPage());
              setState(() {});
            },
          ),
          _header('본문'),
          _switch(
            KoTr.kAiChapter,
            true,
            '본문 번역에 AI 번역기 쓰기',
            subtitle: engines.isEmpty ? 'AI 번역기를 넣으면 적용돼요. 지금은 구글 번역' : '끄면 본문도 구글 번역',
            icon: Icons.menu_book_outlined,
          ),
          _switch(
            KoChapter.kLoadSaved,
            true,
            '번역한 글은 번역본으로 열기',
            subtitle: '한 번 번역한 글은 다시 열 때 버튼 없이 바로 번역본을 보여줘요',
            icon: Icons.history,
          ),
          _switch(KoChapter.kTitle, true, '글 제목도 번역', icon: Icons.title),
          _switch(
            KoChapter.kTapToFix,
            true,
            '문단을 누르면 바로 고치기',
            subtitle: '번역된 본문에서 문단을 누르면 그 문단의 번역 고치기 창이 열려요',
            icon: Icons.touch_app_outlined,
          ),
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: const Text('저장된 본문 번역'),
            subtitle: Text('${KoChapter.savedCount}개 글 · 누르면 비우기'),
            onTap: _clearChapters,
          ),
          _header('목록·검색'),
          ListTile(
            leading: const Icon(Icons.view_list_outlined),
            title: const Text('목록·제목·태그 번역'),
            subtitle: Text('${_listNames[_listMode]} · 글 목록, 검색 결과, 태그 등 짧은 글자'),
            onTap: _pickListMode,
          ),
          _switch(
            KoTr.kDigest,
            false,
            '글 카드 요약도 번역',
            subtitle: '목록에서 제목 아래 보이는 본문 앞부분. 양이 많아 구글 번역이 잠깐 막히기 쉬워요',
            icon: Icons.short_text,
          ),
          _switch(KoTr.kSearchKo, true, '한국어로 검색', subtitle: '검색어에 한국어가 있으면 중국어로 바꿔서 검색해요', icon: Icons.search),
          _header('용어집'),
          ListTile(
            leading: const Icon(Icons.book_outlined),
            title: const Text('공통 용어집'),
            subtitle: Text(glossaryN == 0 ? "작품과 상관없이 늘 쓰는 단어. 한 줄에 하나씩 '중국어=한국어'" : '$glossaryN개'),
            onTap: _editCommonGlossary,
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('작품별 용어집'),
            subtitle: Text(
              KoTr.works.isEmpty
                  ? '작품마다 용어집을 따로 (글 제목·태그로 자동 적용, 자동 만들기 가능)'
                  : '${KoTr.works.length}개${act.isEmpty ? '' : ' · 지금 적용 중: $act'}',
            ),
            onTap: () async {
              await KoNav.to(() => const KoWorksPage());
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('공통 용어집 점검'),
            subtitle: const Text('웹 검색·AI로 표기가 틀린 항목 찾기 (제미나이 키 필요)'),
            onTap: () async {
              await checkGlossary(context, null);
              if (mounted) setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('직접 고친 번역'),
            subtitle: Text('${KoTr.overrides.length}개 · 본문의 [문단 고치기]로 고친 것'),
            onTap: () async {
              await KoNav.to(() => const KoOverridesPage());
              setState(() {});
            },
          ),
          _header('상태'),
          ListTile(
            leading: const Icon(Icons.g_translate),
            title: const Text('구글 번역 상태'),
            subtitle: Text('${KoTr.googleStatus}\n누르면 바로 다시 시도'),
            onTap: () {
              KoTr.resetGoogle();
              KoDialog.showToast('구글 번역을 다시 시도해요');
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('번역 테스트'),
            onTap: _test,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
