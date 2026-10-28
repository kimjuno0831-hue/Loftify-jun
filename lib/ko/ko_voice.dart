// 인물 말투 (소설 번역에서 인물마다 말투가 흔들리지 않게)
// 한국어 말투는 '누가 누구에게' 말하느냐로 정해지므로 두 가지를 적어 둔다.
//   인물 카드:  阿米娅=아미야 | 존댓말, 밝고 다정함
//   관계 규칙:  아미야>박사: 존댓말, '박사님'이라고 부름
// 범위는 두 층: 작품 기본(작품별 용어집처럼 제목·태그로 자동 적용) + 이 합집(연재) 덮어쓰기.
// AI 가 번역하며 정한 말투는 '(자동)' 으로 합집(없으면 그 글)에 쌓이고, 직접 적은 줄이 늘 우선한다.
import 'dart:convert';

import 'package:loftify/ko/ko_compat.dart';
import 'package:loftify/ko/ko_lookup.dart';
import 'package:loftify/ko/ko_translate.dart';

class KoChar {
  KoChar(this.zh, this.ko, this.note, {this.auto = false});
  final String zh; // 중국어 이름 (없으면 빈칸)
  final String ko; // 한국어 이름
  final String note; // 말투·성격
  final bool auto;
}

class KoRel {
  KoRel(this.from, this.to, this.rule, {this.auto = false});
  final String from; // 말하는 사람 (한국어 이름 또는 중국어 이름)
  final String to; // 듣는 사람 ('*' 이면 누구에게나)
  final String rule;
  final bool auto;

  String get pairKey => '${from.trim()}>${to.trim()}';
}

class KoVoiceBook {
  KoVoiceBook(this.chars, this.rels);
  final List<KoChar> chars;
  final List<KoRel> rels;

  bool get isEmpty => chars.isEmpty && rels.isEmpty;

  static const autoMark = '(자동) ';

  // 줄 글 → 책. 인물: '중국어=한국어 | 말투', 관계: '말하는 사람>듣는 사람: 말투'
  static KoVoiceBook parse(String text) {
    final chars = <KoChar>[];
    final rels = <KoRel>[];
    for (var l in text.split('\n')) {
      l = l.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      var auto = false;
      if (l.startsWith(autoMark.trim())) {
        auto = true;
        l = l.substring(autoMark.trim().length).trim();
      }
      final gt = l.indexOf('>');
      final colon = l.indexOf(RegExp(r'[:：]'));
      if (gt > 0 && colon > gt) {
        final from = l.substring(0, gt).trim();
        final to = l.substring(gt + 1, colon).trim();
        final rule = l.substring(colon + 1).trim();
        if (from.isNotEmpty && to.isNotEmpty && rule.isNotEmpty) {
          rels.add(KoRel(from, to, rule, auto: auto));
        }
        continue;
      }
      final eq = l.indexOf('=');
      if (eq >= 0) {
        final zh = l.substring(0, eq).trim();
        final rest = l.substring(eq + 1);
        final bar = rest.indexOf('|');
        final ko = (bar >= 0 ? rest.substring(0, bar) : rest).trim();
        final note = bar >= 0 ? rest.substring(bar + 1).trim() : '';
        if (ko.isNotEmpty) chars.add(KoChar(zh, ko, note, auto: auto));
      }
    }
    return KoVoiceBook(chars, rels);
  }

  String format() {
    final sb = StringBuffer();
    for (final c in chars) {
      sb.writeln('${c.auto ? autoMark : ''}${c.zh}=${c.ko}${c.note.isEmpty ? '' : ' | ${c.note}'}');
    }
    if (chars.isNotEmpty && rels.isNotEmpty) sb.writeln();
    for (final r in rels) {
      sb.writeln('${r.auto ? autoMark : ''}${r.from}>${r.to}: ${r.rule}');
    }
    return sb.toString().trimRight();
  }
}

abstract final class KoVoice {
  static const _k = 'koVoiceBooks'; // {범위: 줄 글}
  static const kAuto = 'koVoiceAuto'; // AI 가 정한 말투를 자동 기록할지

  static bool get autoOn {
    final v = GStorage.setting.get(kAuto, defaultValue: true);
    return v is bool ? v : true;
  }

  static Map<String, String>? _books;

  static Map<String, String> get books {
    if (_books != null) return _books!;
    try {
      final raw = GStorage.setting.get(_k, defaultValue: '');
      if (raw is String && raw.isNotEmpty) {
        _books = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return _books ??= {};
  }

  static void _save() {
    try {
      GStorage.setting.put(_k, jsonEncode(books));
    } catch (_) {}
  }

  // 범위 이름
  static String workScope(String workName) => 'work:$workName';
  static String colScope(int collectionId) => 'col:$collectionId';
  static String postScope(Object postId) => 'post:$postId';

  // 글이 속한 연재 범위 (합집이 없으면 그 글 하나)
  static String storyScope(Object postId, int? collectionId) =>
      (collectionId != null && collectionId > 0) ? colScope(collectionId) : postScope(postId);

  static String text(String scope) => books[scope] ?? '';
  static KoVoiceBook book(String scope) => KoVoiceBook.parse(text(scope));

  static void setText(String scope, String t) {
    if (t.trim().isEmpty) {
      books.remove(scope);
    } else {
      books[scope] = t.trim();
    }
    _save();
  }

  // 화면에 보여줄 범위 이름
  static String label(String scope, {String? title}) {
    if (scope.startsWith('work:')) return '작품: ${scope.substring(5)}';
    if (scope.startsWith('col:')) return title == null ? '합집 ${scope.substring(4)}' : '합집: $title';
    if (scope.startsWith('post:')) return title == null ? '글 ${scope.substring(5)}' : '글: $title';
    return scope;
  }

  // 합집 이름 기억 (목록 화면에 번호 대신 이름으로)
  static const _kTitles = 'koVoiceTitles';
  static void rememberTitle(String scope, String title) {
    if (title.trim().isEmpty) return;
    try {
      final raw = GStorage.setting.get(_kTitles, defaultValue: '');
      final m = raw is String && raw.isNotEmpty ? (jsonDecode(raw) as Map) : {};
      if (m[scope] == title) return;
      m[scope] = title;
      GStorage.setting.put(_kTitles, jsonEncode(m));
    } catch (_) {}
  }

  static String? titleOf(String scope) {
    try {
      final raw = GStorage.setting.get(_kTitles, defaultValue: '');
      if (raw is String && raw.isNotEmpty) return (jsonDecode(raw) as Map)[scope]?.toString();
    } catch (_) {}
    return null;
  }

  // 이 글에 적용할 책: 작품 기본들 + 연재 범위 (나중 것이 같은 인물·같은 관계를 덮어씀)
  static KoVoiceBook merged(String story) {
    final chars = <String, KoChar>{};
    final rels = <String, KoRel>{};
    void add(KoVoiceBook b) {
      for (final c in b.chars) {
        final key = c.ko;
        final old = chars[key];
        if (old != null && !old.auto && c.auto) continue; // 직접 적은 게 우선
        chars[key] = c;
      }
      for (final r in b.rels) {
        final old = rels[r.pairKey];
        if (old != null && !old.auto && r.auto) continue;
        rels[r.pairKey] = r;
      }
    }

    for (final w in KoTr.activeWorks) {
      add(book(workScope(w.name)));
    }
    add(book(story));
    return KoVoiceBook(chars.values.toList(), rels.values.toList());
  }

  // 번역 지시에 넣을 부분: 이 덩어리에 나오는 인물 위주로 (없으면 빈 글)
  static String promptFor(KoVoiceBook b, String chunk) {
    if (b.isEmpty) return '';
    bool appears(String name) => name.isNotEmpty && name != '*' && chunk.contains(name);
    // 중국어 이름 → 한국어 이름 (관계 규칙은 한국어 이름으로 적는 경우가 많음)
    final zhOf = {for (final c in b.chars) c.ko: c.zh};
    bool inChunk(String n) => appears(n) || appears(zhOf[n] ?? '');
    final chars = b.chars.where((c) => appears(c.zh) || appears(c.ko)).toList();
    final names = {for (final c in chars) c.ko};
    final rels = b.rels.where((r) {
      final f = inChunk(r.from) || names.contains(r.from);
      final t = r.to == '*' || inChunk(r.to) || names.contains(r.to);
      return f && t;
    }).toList();
    if (chars.isEmpty && rels.isEmpty) return '';
    final sb = StringBuffer(
      '\n\n[인물 말투 - 반드시 지켜라. 그 인물의 대사는 말투 단계·어미·자칭을 그대로 쓰고 예시 대사와 같은 느낌으로 옮겨라. '
      '아래 관계 규칙이 있는 상대에게는 관계 규칙이 우선한다]\n',
    );
    for (final c in chars.take(20)) {
      sb.writeln('· ${c.zh.isEmpty ? c.ko : '${c.zh}(${c.ko})'}${c.note.isEmpty ? '' : ' — ${c.note}'}');
    }
    for (final r in rels.take(30)) {
      sb.writeln('· ${r.from} → ${r.to == '*' ? '누구에게나' : r.to}: ${r.rule}');
    }
    return sb.toString();
  }

  // AI 가 돌려준 말투 기록을 연재 범위에 '(자동)' 으로 쌓음. 직접 적은 규칙은 건드리지 않음.
  static void record(String story, List rels, List chars) {
    if (!autoOn) return;
    final b = book(story);
    final relMap = {for (final r in b.rels) r.pairKey: r};
    final charMap = {for (final c in b.chars) c.ko: c};
    var changed = false;
    for (final v in rels) {
      if (v is! Map) continue;
      final from = (v['from'] ?? '').toString().trim();
      final to = (v['to'] ?? '').toString().trim();
      final rule = (v['rule'] ?? '').toString().trim();
      if (from.isEmpty || to.isEmpty || rule.isEmpty || rule.length > 60) continue;
      final key = '$from>$to';
      final old = relMap[key];
      if (old != null && (!old.auto || old.rule == rule)) continue;
      relMap[key] = KoRel(from, to, rule, auto: true);
      changed = true;
    }
    for (final v in chars) {
      if (v is! Map) continue;
      final zh = (v['zh'] ?? '').toString().trim();
      final ko = (v['ko'] ?? '').toString().trim();
      final note = (v['note'] ?? '').toString().trim();
      if (ko.isEmpty || note.length > 60) continue;
      final old = charMap[ko];
      if (old != null && (!old.auto || old.note == note || note.isEmpty)) continue;
      charMap[ko] = KoChar(zh.isNotEmpty ? zh : (old?.zh ?? ''), ko, note, auto: true);
      changed = true;
    }
    if (!changed) return;
    // 자동 기록이 너무 쌓이지 않게 (오래된 자동 줄부터 버림)
    final rl = relMap.values.toList();
    final autoRels = rl.where((r) => r.auto).toList();
    if (autoRels.length > 60) {
      final drop = autoRels.take(autoRels.length - 60).toSet();
      rl.removeWhere(drop.contains);
    }
    setText(story, KoVoiceBook(charMap.values.toList(), rl).format());
  }

  // 사용자가 직접 정한 관계 규칙 저장 (같은 관계는 바꿈)
  static void putRule(String scope, String from, String to, String rule) {
    final b = book(scope);
    final rels = b.rels.where((r) => r.pairKey != '${from.trim()}>${to.trim()}').toList()
      ..add(KoRel(from.trim(), to.trim(), rule.trim()));
    setText(scope, KoVoiceBook(b.chars, rels).format());
  }

  // 인물 기본 말투 저장 (누구에게 말하든 기본으로). 같은 인물이면 바꿈
  static void putChar(String scope, String ko, String note, {String zh = ''}) {
    final b = book(scope);
    final old = b.chars.where((c) => c.ko == ko.trim()).toList();
    final chars = b.chars.where((c) => c.ko != ko.trim()).toList()
      ..add(KoChar(zh.isNotEmpty ? zh : (old.isEmpty ? '' : old.first.zh), ko.trim(), note.trim()));
    setText(scope, KoVoiceBook(chars, b.rels).format());
  }

  // 한 줄 지우기 (목록에서 바로 지울 때)
  static void removeChar(String scope, String ko) {
    final b = book(scope);
    setText(scope, KoVoiceBook(b.chars.where((c) => c.ko != ko).toList(), b.rels).format());
  }

  static void removeRule(String scope, String pairKey) {
    final b = book(scope);
    setText(scope, KoVoiceBook(b.chars, b.rels.where((r) => r.pairKey != pairKey).toList()).format());
  }

  // ── AI 로 채우기 ──
  static String _glossaryHint(String? work) {
    if (work == null) return '';
    final w = KoTr.works.where((e) => e.name == work).toList();
    if (w.isEmpty) return '';
    final g = KoTr.parseGlossary(w.first.glossary).take(60).map((e) => '${e.key}=${e.value}').join('\n');
    return g.isEmpty ? '' : '\n\n[이 작품 용어집 - 이름 표기는 이걸 따르라]\n$g';
  }

  static const _system =
      '너는 중국 작품의 팬픽·소설을 한국어로 번역할 때 쓸 "인물 말투표"를 만든다. 번역가가 이것만 보고 그 인물의 대사를 똑같은 말투로 쓸 수 있을 만큼 구체적이어야 한다. '
      '인물마다 다음을 적어라. '
      'level: 한국어 말투 단계를 뉘앙스까지 구체적으로 (예: "고풍스러운 하오체(일제강점기 문인 느낌)", "딱딱한 하십시오체", "부드러운 해요체", "거친 반말", "능글맞은 반말"). '
      'endings: 그 인물이 자주 쓰는 어미·말끝 3~6개 (예: "~하오", "~구료", "~소", "~지 않소"). '
      'self: 자기를 부르는 말 (예: "나", "저", "소생", 자기 이름으로 3인칭이면 "파우스트는(3인칭)"). '
      'desc: 말하는 방식과 성격을 2~3문장으로 (말의 길이, 감정 표현, 자주 하는 말버릇, 다른 사람을 부르는 방식). '
      'examples: 그 말투가 바로 드러나는 한국어 예시 대사 2~3개 (원작 한국어판 대사를 알면 그걸, 모르면 그 말투로 지어서). '
      '그리고 기본 말투와 다른 말투를 쓰는 중요한 관계(누가 누구에게, 말투와 호칭)도 적어라. '
      '원작 한국어판(정식 한국어 서비스나 원작이 한국어인 경우 원문)에서의 실제 말투를 최우선 근거로 삼고, 그다음 원작 설정, 웹 검색 결과 순으로. '
      '이름의 중국어는 중국어판(간체) 실제 표기, 한국어는 한국어판 실제 표기로. 확신 없는 인물은 빼라. '
      'JSON 객체 하나로만 답하라: {"c":[{"zh":"중국어 이름","ko":"한국어 이름","level":"...","endings":["~하오","~구료"],"self":"...","desc":"...","examples":["...","..."]}],'
      ' "v":[{"from":"말하는 사람 한국어 이름","to":"듣는 사람 한국어 이름","rule":"말투와 호칭 (60자 이내)"}]}';

  // 인물 카드 설명 칸을 정해진 순서로 이어 붙임 (한 줄에 저장)
  static String composeNote({
    String level = '',
    String endings = '',
    String self = '',
    String desc = '',
    List<String> examples = const [],
  }) {
    final parts = <String>[
      if (level.trim().isNotEmpty) '말투: ${level.trim()}',
      if (endings.trim().isNotEmpty) '어미: ${endings.trim()}',
      if (self.trim().isNotEmpty) '자칭: ${self.trim()}',
      if (desc.trim().isNotEmpty) '설명: ${desc.trim().replaceAll('\n', ' ')}',
      if (examples.any((e) => e.trim().isNotEmpty))
        '예: ${examples.where((e) => e.trim().isNotEmpty).map((e) => '"${e.trim().replaceAll('"', "'")}"').join(' ')}',
    ];
    return parts.join(' | ');
  }

  // 저장된 설명 칸을 다시 나눔 (편집 화면용). 형식이 아니면 전부 설명으로
  static Map<String, String> splitNote(String note) {
    final out = <String, String>{};
    for (final p in note.split('|')) {
      final t = p.trim();
      final m = RegExp(r'^(말투|어미|자칭|설명|예)\s*[:：]\s*([\s\S]*)$').firstMatch(t);
      if (m != null) {
        out[m[1]!] = m[2]!.trim();
      } else if (t.isNotEmpty) {
        out['설명'] = [if (out['설명'] != null) out['설명']!, t].join(' ');
      }
    }
    return out;
  }

  static KoVoiceBook _fromJson(Map? o) {
    final chars = <KoChar>[];
    final rels = <KoRel>[];
    if (o == null) return KoVoiceBook(chars, rels);
    for (final c in (o['c'] is List ? o['c'] as List : const []).whereType<Map>()) {
      final ko = (c['ko'] ?? '').toString().trim();
      if (ko.isEmpty || chars.any((e) => e.ko == ko)) continue;
      String str(String k) => (c[k] ?? '').toString().trim();
      final endings = c['endings'] is List ? (c['endings'] as List).map((e) => e.toString()).join(', ') : str('endings');
      final examples = c['examples'] is List
          ? (c['examples'] as List).map((e) => e.toString()).toList()
          : [if (str('examples').isNotEmpty) str('examples')];
      var note = composeNote(
        level: str('level'),
        endings: endings,
        self: str('self'),
        desc: str('desc'),
        examples: examples,
      );
      if (note.isEmpty) note = str('note');
      chars.add(KoChar(str('zh'), ko, note));
    }
    for (final v in (o['v'] is List ? o['v'] as List : const []).whereType<Map>()) {
      final f = (v['from'] ?? '').toString().trim();
      final t = (v['to'] ?? '').toString().trim();
      final r = (v['rule'] ?? '').toString().trim();
      if (f.isEmpty || t.isEmpty || r.isEmpty) continue;
      rels.add(KoRel(f, t, r));
    }
    return KoVoiceBook(chars, rels);
  }

  static Map? _obj(String raw) {
    final a = raw.indexOf('{');
    final b = raw.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      final o = jsonDecode(raw.substring(a, b + 1));
      return o is Map ? o : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _web(List<String> queries) async {
    final web = StringBuffer();
    for (final q in queries) {
      final r = await KoLookup.search(q, maxChars: 2500);
      if (r.isNotEmpty) web.write('### 검색어: $q\n$r\n\n');
    }
    return web.isEmpty ? '(검색 결과를 가져오지 못함 — 네 지식으로만, 확신 있는 것만)' : web.toString();
  }

  // 작품 전체 인물 말투표 초안
  static Future<KoVoiceBook> buildWork(String work) async {
    final web = await _web(['$work 등장인물 말투 성격', '$work 角色 性格 说话 口癖', '$work 캐릭터 관계']);
    final user = '[작품]\n$work${_glossaryHint(work)}\n\n[웹 검색 결과]\n$web\n\n'
        '주요 인물 최대 15명, 중요한 관계 최대 20개.';
    return _fromJson(_obj(await KoTr.ask(_system, user, json: true)));
  }

  // 인물 한 명 찾아서 채우기 (이름은 한국어든 중국어든)
  static Future<KoVoiceBook> lookupChar(String name, {String? work}) async {
    final w = work ?? '';
    final web = await _web(['$w $name 캐릭터 말투 성격', '$w $name 角色 性格 说话', '$w $name 관계']);
    final user = '[작품]\n${w.isEmpty ? '(모름 — 이름으로 판단)' : w}${_glossaryHint(work)}\n\n[찾을 인물]\n$name\n\n'
        '[웹 검색 결과]\n$web\n\n이 인물 한 명의 c 항목과, 이 인물이 말하는 쪽(from)인 중요한 관계 최대 6개만.';
    return _fromJson(_obj(await KoTr.ask(_system, user, json: true)));
  }

  // 찾은 걸 범위에 넣기 (같은 인물·같은 관계는 바꿈)
  static void addAll(String scope, KoVoiceBook add) {
    final b = book(scope);
    final names = {for (final c in add.chars) c.ko};
    final pairs = {for (final r in add.rels) r.pairKey};
    setText(
      scope,
      KoVoiceBook(
        [...b.chars.where((c) => !names.contains(c.ko)), ...add.chars],
        [...b.rels.where((r) => !pairs.contains(r.pairKey)), ...add.rels],
      ).format(),
    );
  }

  // 고칠 때 고를 수 있는 인물 이름들
  static List<String> names(String story) {
    final b = merged(story);
    final out = <String>{for (final c in b.chars) c.ko};
    for (final r in b.rels) {
      out.add(r.from);
      if (r.to != '*') out.add(r.to);
    }
    return out.where((e) => e.isNotEmpty).toList();
  }
}
