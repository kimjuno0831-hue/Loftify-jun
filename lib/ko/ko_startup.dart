// 앱 시작 안전장치 (Loftify-jun)
// 시작 단계 하나가 오류를 내거나 멈춰도 로고 화면에서 영원히 멈추지 않게 하고,
// 무엇이 잘못됐는지 화면에 보여준다. 깨진 저장소는 비우고 새로 연다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final List<String> koStartupErrors = [];

// 시작 단계 하나 실행. 오류·시간 초과면 기록하고 recover 가 있으면 한 번 더.
Future<void> koStep(
  String name,
  Future<void> Function() run, {
  Duration timeout = const Duration(seconds: 25),
  Future<void> Function()? recover,
}) async {
  try {
    await run().timeout(timeout);
  } catch (e) {
    if (recover == null) {
      koStartupErrors.add('$name: $e');
      return;
    }
    try {
      await recover().timeout(timeout);
      koStartupErrors.add('$name: 오류가 나서 이 저장소를 비우고 새로 열었어요 ($e)');
    } catch (e2) {
      koStartupErrors.add('$name: $e / 복구도 실패: $e2');
    }
  }
}

// 시작 오류가 있으면 앱 위에 알림 줄을 띄움 (내용 복사 가능)
class KoStartupGuard extends StatefulWidget {
  const KoStartupGuard({super.key, required this.child});
  final Widget child;

  @override
  State<KoStartupGuard> createState() => _KoStartupGuardState();
}

class _KoStartupGuardState extends State<KoStartupGuard> {
  bool _hide = false;

  @override
  Widget build(BuildContext context) {
    if (koStartupErrors.isEmpty || _hide) return widget.child;
    final text = koStartupErrors.join('\n');
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          bottom: 24,
          child: Material(
            elevation: 6,
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('시작할 때 문제가 있었어요', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(
                      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                        child: const Text('내용 복사'),
                      ),
                      TextButton(onPressed: () => setState(() => _hide = true), child: const Text('닫기')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
