// 로그인 보조 (한국에서 중국 휴대폰 번호 없이 들어가 보기 위한 방법들)
// · 웹으로 로그인: 앱 안에서 LOFTER 공식 웹 로그인 화면을 열고, 로그인되면 쿠키에서 인증 토큰을 꺼내 저장
// · 토큰 직접 넣기: 다른 곳(공식 앱·브라우저)에서 꺼낸 토큰을 붙여넣기
import 'package:awesome_chewie/awesome_chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:loftify/Utils/enums.dart';
import 'package:loftify/Utils/hive_util.dart';

import '../Utils/app_provider.dart';
import '../Utils/request_util.dart';

// 앱이 쓰는 방식으로 토큰을 저장하고 로그인 처리 (LOFTER ID 로그인 성공 때와 같은 순서)
Future<void> koSaveToken(String token, TokenType type) async {
  appProvider.token = token;
  await RequestUtil.clearCookie();
  await ChewieHiveUtil.put(HiveUtil.tokenKey, token);
  await ChewieHiveUtil.put(HiveUtil.tokenTypeKey, type.index);
  mainScreenState?.login();
}

// 웹 쿠키 이름 → 앱 토큰 종류
const _cookieTypes = {
  'LOFTER-PHONE-LOGIN-AUTH': TokenType.password,
  'Authorization': TokenType.lofterID,
};

class KoWebLoginScreen extends StatefulWidget {
  const KoWebLoginScreen({super.key});

  @override
  State<KoWebLoginScreen> createState() => _KoWebLoginScreenState();
}

class _KoWebLoginScreenState extends State<KoWebLoginScreen> {
  static const _start = 'https://www.lofter.com/front/login';
  double _progress = 0;
  String _status = '공식 웹 로그인 화면이에요. 여기서 되는 방법으로 로그인하세요.';
  List<String> _seen = [];
  bool _done = false;

  Future<void> _check() async {
    if (_done) return;
    final names = <String>{};
    for (final host in ['https://www.lofter.com', 'https://lofter.com', 'https://m.lofter.com']) {
      try {
        final cookies = await CookieManager.instance().getCookies(url: WebUri(host));
        for (final c in cookies) {
          names.add(c.name);
          final type = _cookieTypes[c.name];
          final v = c.value?.toString() ?? '';
          if (type != null && v.isNotEmpty) {
            _done = true;
            await koSaveToken(Uri.decodeComponent(v), type);
            IToast.show('로그인했어요');
            if (mounted) Navigator.of(context).maybePop();
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _seen = names.toList()..sort());
  }

  Future<void> _reset() async {
    await CookieManager.instance().deleteAllCookies();
    IToast.show('웹 로그인 기록을 지웠어요. 다시 열어 주세요');
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('웹으로 로그인'),
        actions: [
          IconButton(tooltip: '토큰 확인', onPressed: _check, icon: const Icon(Icons.key)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'reset' ? _reset() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('웹 로그인 기록 지우기'))],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1) LinearProgressIndicator(value: _progress),
          Container(
            width: double.infinity,
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              _seen.isEmpty
                  ? _status
                  : '로그인 토큰을 아직 못 찾았어요. 로그인을 끝냈는데도 그대로면 아래 이름들을 알려 주세요.\n쿠키: ${_seen.join(', ')}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_start)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
              ),
              onProgressChanged: (_, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
              onLoadStop: (_, url) => _check(),
            ),
          ),
        ],
      ),
    );
  }
}

class KoTokenLoginScreen extends StatefulWidget {
  const KoTokenLoginScreen({super.key});

  @override
  State<KoTokenLoginScreen> createState() => _KoTokenLoginScreenState();
}

class _KoTokenLoginScreenState extends State<KoTokenLoginScreen> {
  final _ctrl = TextEditingController();
  TokenType _type = TokenType.password;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var t = _ctrl.text.trim();
    // "이름=값" 으로 붙여넣은 경우 값만
    for (final k in _cookieTypes.keys) {
      if (t.toLowerCase().startsWith('${k.toLowerCase()}=')) {
        _type = _cookieTypes[k]!;
        t = t.substring(k.length + 1).split(';').first.trim();
      }
    }
    if (t.isEmpty) {
      IToast.show('토큰을 넣어 주세요');
      return;
    }
    await koSaveToken(t, _type);
    IToast.show('저장했어요. 내 정보가 안 뜨면 토큰 종류를 바꿔서 다시 해 보세요');
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('토큰 직접 넣기')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '다른 기기의 LOFTER 공식 앱이나 브라우저에 이미 로그인돼 있을 때 쓰는 방법이에요. '
            '브라우저라면 lofter.com 쿠키 중 LOFTER-PHONE-LOGIN-AUTH 값을 넣으세요. '
            "'이름=값' 그대로 붙여넣어도 돼요.\n토큰은 비밀번호와 같으니 다른 사람에게 보여주지 마세요.",
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '토큰'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<TokenType>(
            segments: const [
              ButtonSegment(value: TokenType.password, label: Text('휴대폰 로그인 토큰')),
              ButtonSegment(value: TokenType.lofterID, label: Text('LOFTER ID 토큰')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('저장하고 로그인')),
        ],
      ),
    );
  }
}
