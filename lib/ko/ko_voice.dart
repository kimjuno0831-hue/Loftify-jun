// 인물 말투 (소설 번역에서 인물마다 말투가 흔들리지 않게)
// 한국어 말투는 '누가 누구에게' 말하느냐로 정해지므로 두 가지를 적어 둔다.
//   인물 카드:  阿米娅=아미야 | 존댓말, 밝고 다정함
//   관계 규칙:  아미야>박사: 존댓말, '박사님'이라고 부름
// 범위는 두 층: 작품 기본(작품별 용어집처럼 제목·태그로 자동 적용) + 이 합집(연재) 덮어쓰기.
// AI 가 번역하며 정한 말투는 '(자동)' 으로 합집(없으면 그 글)에 쌓이고, 직접 적은 줄이 늘 우선한다.
import 'dart:convert';

import 'package:loftify/ko/ko_compat.dart';
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
    final sb = StringBuffer('\n\n[인물 말투 - 반드시 지켜라. 한국어 말투는 말하는 사람과 듣는 사람의 관계로 정한다]\n');
    for (final c in chars.take(20)) {
      sb.writeln('· ${c.zh.isEmpty ? c.ko : '${c.zh}(${c.ko})'}${c.note.isEmpty ? '' : ': ${c.note}'}');
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
