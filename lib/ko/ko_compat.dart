// pili-ko(PiliPlus) 번역 모듈을 Loftify에서 그대로 쓰기 위한 연결 부분.
// PiliPlus의 저장소·화면 이동·알림 창 대신 Loftify에 있는 것들로 이어 줌.
import 'package:awesome_chewie/awesome_chewie.dart' show chewieProvider, IToast;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

// 번역 설정 저장소 (Loftify 설정과 섞이지 않게 상자를 따로 씀)
abstract final class GStorage {
  static const settingBox = 'ko_settings';
  static const chapterBox = 'ko_chapters';

  static Box get setting => Hive.box(settingBox);
  static Box get chapters => Hive.box(chapterBox);

  // main.dart 에서 HiveUtil.initBox() 다음에 부름
  static Future<void> init(String path) async {
    await Hive.openBox(settingBox, path: path);
    await Hive.openBox(chapterBox, path: path);
  }
}

// 화면 이동
abstract final class KoNav {
  static NavigatorState? get _nav => chewieProvider.globalNavigatorKey.currentState;

  static Future<T?> to<T>(Widget Function() page) async =>
      _nav?.push<T>(MaterialPageRoute(builder: (_) => page()));

  static void back({Object? result}) => _nav?.maybePop(result);
}

// 알림·로딩 창
abstract final class KoDialog {
  static OverlayEntry? _loading;

  static void showToast(String msg) => IToast.show(msg);

  static void showLoading({String msg = '잠시만요…'}) {
    dismiss();
    final overlay = chewieProvider.globalNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _loading = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black38,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(msg, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(_loading!);
  }

  static void dismiss() {
    _loading?.remove();
    _loading = null;
  }
}

abstract final class KoUtil {
  static Future<void> launchURL(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      KoDialog.showToast('링크를 열 수 없어요');
    }
  }

  static Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    KoDialog.showToast('복사했어요');
  }
}
