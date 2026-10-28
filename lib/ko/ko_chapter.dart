// 본문(화) 번역
// 번역 버튼을 누르면 그 글 전체를 한 번에 번역한다.
// · AI 번역기: 소설 번역용 지시로, 앞 문단을 참고로 붙여 이름·말투가 이어지게 몇 덩어리로 나눠 보냄
// · 구글 번역: 용어집 적용, 글자 수 제한에 맞춰 나눠 보냄
// · 결과는 글 ID 별로 문단 단위로 저장 → 다시 열면 바로 번역본, 작가가 글을 고치면 바뀐 문단만 다시 번역
// · 직접 고친 문단은 KoTr.overrides 에 저장되어 늘 그걸로 보여줌
import 'dart:convert';

import 'package:loftify/ko/ko_compat.dart';
import 'package:loftify/ko/ko_engines.dart';
import 'package:loftify/ko/ko_translate.dart';

// 본문을 문단(줄)으로 나눈 결과
class KoDoc {
  KoDoc(this.parts);

  // 원문 HTML 조각들. String 이면 그대로, KoLines 면 번역할 줄들
  final List<Object> parts;

  List<String> get lines => [
    for (final p in parts)
      if (p is KoLines) ...p.lines,
  ];

  // 줄 번역(map)을 넣어 HTML 을 다시 만든다. 번역이 없는 줄은 원문 그대로.
  // 번역할 문단들 (순서대로). build(mark: true) 의 data-ko 번호가 이 목록의 위치
  List<KoLines> get blocks => [for (final p in parts) if (p is KoLines) p];

  // mark: 문단마다 data-ko="번호" 를 붙여서 화면에서 눌렀을 때 어느 문단인지 알 수 있게
  String build(String Function(String line) tr, {bool mark = false, String extra = ''}) {
    final sb = StringBuffer();
    var idx = 0;
    for (final p in parts) {
      if (p is String) {
        sb.write(p);
      } else if (p is KoLines) {
        sb.write(
          mark
              ? p.open.replaceFirstMapped(RegExp(r'^<(\w+)'), (m) => '<${m[1]} data-ko="$idx"$extra')
              : p.open,
        );
        idx++;
        for (var i = 0; i < p.lines.length; i++) {
          if (i > 0) sb.write('<br>');
          sb.write(const HtmlEscape(HtmlEscapeMode.element).convert(tr(p.lines[i])));
        }
        sb.write(p.close);
      }
    }
    return sb.toString();
  }
}

class KoLines {
  KoLines(this.open, this.lines, this.close);
  final String open;
  final List<String> lines;
  final String close;
}

class KoChapterResult {
  KoChapterResult(this.map, this.by, this.failed);
  final Map<String, String> map; // 원문 줄 → 번역
  final String by; // 번역한 곳
  final int failed; // 번역 못 한 줄 수
}

abstract final class KoChapter {
  static const kLoadSaved = 'koChLoadSaved'; // 번역한 적 있는 글은 열 때 번역본으로
  static const kTitle = 'koChTitle'; // 글 제목도 같이 번역
  static const _maxSaved = 800; // 저장해 둘 글 수

  static bool get loadSaved => _get(kLoadSaved, true);
  static bool get translateTitle => _get(kTitle, true);
  static const kTapToFix = 'koChTapFix'; // 번역된 문단을 누르면 바로 고치기
  static bool get tapToFix => _get(kTapToFix, true);

  static bool _get(String k, bool def) {
    try {
      final v = GStorage.setting.get(k, defaultValue: def);
      return v is bool ? v : def;
    } catch (_) {
      return def;
    }
  }

  // ── HTML → 문단 ──
  static final _block = RegExp(
    r'<(p|h[1-6]|li)(\s[^>]*)?>([\s\S]*?)</\1>',
    caseSensitive: false,
  );
  static final _br = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final _tag = RegExp(r'<[^>]+>');
  static final _media = RegExp(r'<(img|video|iframe|embed|audio)\b', caseSensitive: false);

  static String unescape(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAll('&amp;', '&');

  static List<String> _splitLines(String inner) => inner
      .split(_br)
      .map((l) => unescape(l.replaceAll(_tag, '')).trim())
      .toList();

  static KoDoc parse(String html) {
    final parts = <Object>[];
    var last = 0;
    var found = false;
    for (final m in _block.allMatches(html)) {
      found = true;
      if (m.start > last) parts.addAll(_loose(html.substring(last, m.start)));
      final inner = m[3] ?? '';
      if (_media.hasMatch(inner) || !KoTr.hasCjk(inner)) {
        // 그림이 든 문단, 번역할 글자가 없는 문단은 그대로
        parts.add(m[0]!);
      } else {
        final tag = m[1]!;
        parts.add(KoLines('<$tag${m[2] ?? ''}>', _splitLines(inner), '</$tag>'));
      }
      last = m.end;
    }
    if (!found) return KoDoc(_loose(html));
    if (last < html.length) parts.addAll(_loose(html.substring(last)));
    return KoDoc(parts);
  }

  // 문단 태그 없이 줄바꿈·<br> 로만 된 글
  static List<Object> _loose(String s) {
    if (!KoTr.hasCjk(s) || _media.hasMatch(s)) return [s];
    final norm = s.replaceAll('\n', '<br>');
    return [KoLines('<p>', _splitLines(norm), '</p>')];
  }

  // ── 저장 ──
  static String _key(Object postId) => 'p:$postId';

  static int hash(String s) {
    // FNV-1a 32비트
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  // 그 글에 쓰인 용어집의 지문 (용어집이 바뀌면 '다시 번역' 안내)
  static int glossarySig(String text) {
    final used = KoTr.glossary.where((e) => text.contains(e.key)).map((e) => '${e.key}=${e.value}').toList()
      ..sort();
    return hash(used.join('\n'));
  }

  static Map? saved(Object postId) {
    try {
      final raw = GStorage.chapters.get(_key(postId));
      if (raw is String && raw.isNotEmpty) return jsonDecode(raw) as Map;
    } catch (_) {}
    return null;
  }

  static Map<String, String> savedMap(Object postId) {
    final m = saved(postId)?['m'];
    if (m is Map) return m.map((k, v) => MapEntry(k.toString(), v.toString()));
    return {};
  }

  static void _save(Object postId, Map<String, String> map, String by, int sig) {
    try {
      final box = GStorage.chapters;
      box.put(
        _key(postId),
        jsonEncode({
          'm': map,
          'by': by,
          'g': sig,
          't': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      if (box.length > _maxSaved) _prune();
    } catch (_) {}
  }

  static void _prune() {
    final box = GStorage.chapters;
    final items = <(dynamic, int)>[];
    for (final k in box.keys) {
      try {
        final t = (jsonDecode(box.get(k) as String) as Map)['t'] as int? ?? 0;
        items.add((k, t));
      } catch (_) {
        items.add((k, 0));
      }
    }
    items.sort((a, b) => a.$2.compareTo(b.$2));
    final drop = items.length - (_maxSaved * 0.9).round();
    for (var i = 0; i < drop; i++) {
      box.delete(items[i].$1);
    }
  }

  // 문단 하나만 다시 번역하려고 저장된 번역에서 뺌
  static void removeLine(Object postId, String line) {
    final sv = saved(postId);
    if (sv == null) return;
    final map = savedMap(postId)..remove(line);
    _save(postId, map, (sv['by'] ?? '').toString(), (sv['g'] as int?) ?? 0);
  }

  static void forget(Object postId) {
    try {
      GStorage.chapters.delete(_key(postId));
    } catch (_) {}
  }

  static int get savedCount {
    try {
      return GStorage.chapters.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearAll() async {
    try {
      await GStorage.chapters.clear();
    } catch (_) {}
  }

  // ── 번역 ──
  // useAi: null 이면 설정(본문에 AI 번역기)을 따름
  static Future<KoChapterResult> translate(
    Object postId,
    List<String> lines, {
    bool? useAi,
    bool fresh = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final map = fresh ? <String, String>{} : savedMap(postId);
    final todo = <String>[];
    final seen = <String>{};
    for (final l in lines) {
      if (l.isEmpty || !KoTr.hasCjk(l) || map.containsKey(l) || !seen.add(l)) continue;
      todo.add(l);
    }
    final ai = (useAi ?? KoTr.aiFor('chapter')) && KoTr.hasAi;
    final sig = glossarySig(lines.join('\n'));
    if (todo.isEmpty) {
      final by = (saved(postId)?['by'] ?? '').toString();
      _save(postId, map, by, sig);
      return KoChapterResult(map, by, 0);
    }
    var done = 0;
    onProgress?.call(0, todo.length);
    final bys = <String>{};
    final chunks = _chunks(todo, ai ? 1200 : 1500, ai ? 40 : 80);
    // 앞 내용 참고용 (이름·말투가 이어지게)
    var prevSrc = <String>[];
    var prevKo = <String>[];
    for (final c in chunks) {
      List<String?> out = List.filled(c.length, null);
      var by = '';
      if (ai) {
        try {
          final (r, slot) = await KoEngines.rotate(
            (s) => _ai(s, c, prevSrc, prevKo),
          );
          out = r;
          by = slot.label;
        } catch (_) {
          // AI 가 다 막힘 → 이 덩어리는 구글로
        }
      }
      // AI 가 못 한 줄(또는 처음부터 구글)은 구글로
      final miss = [for (var i = 0; i < c.length; i++) if (!KoTr.validResult(c[i], out[i])) i];
      if (miss.isNotEmpty && !KoTr.googleBlocked) {
        try {
          final g = await KoTr.googleList([for (final i in miss) c[i]]);
          for (var k = 0; k < miss.length && k < g.length; k++) {
            if (KoTr.validResult(c[miss[k]], g[k])) out[miss[k]] = g[k];
          }
          if (by.isEmpty) by = ai ? '구글 번역 (AI 대신)' : '구글 번역';
        } catch (_) {}
      }
      if (by.isNotEmpty) bys.add(by);
      for (var i = 0; i < c.length; i++) {
        final r = out[i];
        if (r != null && r.trim().isNotEmpty) map[c[i]] = r.trim();
      }
      done += c.length;
      onProgress?.call(done, todo.length);
      // 중간에 앱을 닫아도 된 데까지는 남게
      _save(postId, map, bys.join(', '), sig);
      prevSrc = c.length > 3 ? c.sublist(c.length - 3) : c;
      prevKo = [for (final s in prevSrc) map[s] ?? ''];
    }
    final failed = todo.where((l) => !map.containsKey(l)).length;
    return KoChapterResult(map, bys.join(', '), failed);
  }

  // 줄들을 글자 수·줄 수 한도로 나눔
  static List<List<String>> _chunks(List<String> xs, int maxChars, int maxLines) {
    final out = <List<String>>[];
    var cur = <String>[];
    var n = 0;
    for (final x in xs) {
      if (cur.isNotEmpty && (n + x.length > maxChars || cur.length >= maxLines)) {
        out.add(cur);
        cur = [];
        n = 0;
      }
      cur.add(x);
      n += x.length;
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  static String _stylePrompt(int st) => switch (st) {
    0 => '원문의 문장 구조와 표현을 최대한 살려 옮겨라. 내용을 빼거나 보태지 마라. ',
    1 => '원문의 뜻과 분위기를 그대로 살리되 한국어 소설처럼 자연스럽게 옮겨라. 내용을 빼거나 보태지 마라. ',
    _ => '한국어 웹소설처럼 읽기 편하게 의역하라. 단, 사건·대사의 내용은 바꾸거나 빼지 마라. ',
  };

  static Future<List<String?>> _ai(
    KoSlot slot,
    List<String> xs,
    List<String> prevSrc,
    List<String> prevKo,
  ) async {
    final joined = xs.join('\n');
    final used = KoTr.glossary.where((e) => joined.contains(e.key)).toList();
    final system = StringBuffer()
      ..write('너는 중국어 소설·팬픽(LOFTER)을 한국어로 옮기는 전문 번역가다. ')
      ..write(_stylePrompt(KoTr.style))
      ..write(
        '대사는 인물 관계와 성격에 맞는 한국어 말투(존댓말/반말)로 일관되게 옮겨라. '
        '인명·지명·고유명사는 용어집이 있으면 반드시 그대로 쓰고, 없으면 한국에서 통용되는 표기(없으면 한자음)로 옮겨라. '
        '중국 인터넷 은어·밈은 직역하지 말고 뜻이 바로 통하게 풀어라. '
        '작가의 말·후기·공지 같은 문장도 그대로 번역하라. '
        '모든 항목을 반드시 한국어로 번역하라. 중국어를 그대로 남기지 마라. '
        '입력은 JSON 문자열 배열이고, 각 항목은 소설의 한 문단(또는 한 줄)이다. '
        '입력과 같은 길이·같은 순서의 JSON 문자열 배열 하나로만 답하라. 항목을 합치거나 나누거나 빼지 마라. 설명은 쓰지 마라.',
      );
    final names = KoTr.activeWorks.map((e) => e.name).toList();
    if (names.isNotEmpty) system.write('\n\n[작품] ${names.join(', ')}');
    if (used.isNotEmpty) {
      system.write('\n\n[용어집 - 반드시 이렇게 번역]\n');
      for (final e in used) {
        system.write('${e.key} → ${e.value}\n');
      }
    }
    if (prevSrc.isNotEmpty && prevKo.every((e) => e.isNotEmpty)) {
      system.write('\n\n[바로 앞 내용 - 참고만 하고 번역하지 마라]\n');
      for (var i = 0; i < prevSrc.length; i++) {
        system.write('${prevSrc[i]}\n→ ${prevKo[i]}\n');
      }
    }
    final text = await KoEngines.ask(slot, system.toString(), jsonEncode(xs), json: true);
    final a = text.indexOf('[');
    final b = text.lastIndexOf(']');
    if (a < 0 || b <= a) throw const FormatException('형식');
    final arr = jsonDecode(text.substring(a, b + 1)) as List;
    if (arr.length != xs.length) {
      if (xs.length <= 2) throw const FormatException('줄 수 안 맞음');
      final mid = xs.length ~/ 2;
      return [
        ...await _ai(slot, xs.sublist(0, mid), prevSrc, prevKo),
        ...await _ai(slot, xs.sublist(mid), prevSrc, prevKo),
      ];
    }
    final res = [for (final o in arr) o?.toString()];
    var bad = 0;
    for (var i = 0; i < xs.length; i++) {
      if (!KoTr.validResult(xs[i], res[i])) bad++;
    }
    if (xs.length >= 2 && bad * 2 > xs.length) {
      throw FormatException('원문을 그대로 돌려줌 ($bad/${xs.length})');
    }
    return res;
  }
}
