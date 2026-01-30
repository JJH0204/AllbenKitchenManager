import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/kitchen_provider.dart';

/// 파일명: lib/ui/widgets/settings_dialog.dart
/// 작성의도: 서버 접속 정보를 설정하고 연결 테스트를 수행하는 다이얼로그입니다.
/// 기능 원리: 로컬 폼 상태(IP, Port)를 관리하며, 연결 테스트 시 로딩 상태 및 결과를 시각적으로 보여줍니다.
///          성공 시 `KitchenProvider`를 통해 서버 설정을 영구 저장합니다.

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController ipController;
  late TextEditingController portController;
  String? connectionStatus; // null, "testing", "success", "error"
  String? errorMessage;
  String? syncStatusText;
  bool isTesting = false;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<KitchenProvider>(context, listen: false);
    ipController = TextEditingController(text: provider.serverIp);
    portController = TextEditingController(text: provider.serverPort);
  }

  @override
  void dispose() {
    ipController.dispose();
    portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<KitchenProvider>(
      builder: (context, provider, child) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            "서버 연결 설정",
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: "서버 IP (Tailscale)",
                  hintText: "100.x.x.x",
                  prefixIcon: Icon(Icons.lan),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "포트 번호",
                  hintText: "8080",
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 24),
              if (connectionStatus != null && connectionStatus != "testing")
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: connectionStatus == "success"
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        connectionStatus == "success"
                            ? Icons.check_circle
                            : Icons.error,
                        color: connectionStatus == "success"
                            ? Colors.green
                            : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          connectionStatus == "success"
                              ? "연결 성공!"
                              : (errorMessage ?? "연결 실패"),
                          style: TextStyle(
                            color: connectionStatus == "success"
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (provider.wsConnectionStatus != null)
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: provider.wsConnectionStatus == "success"
                        ? Colors.blue.withValues(alpha: 0.1)
                        : provider.wsConnectionStatus == "connecting"
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      if (provider.wsConnectionStatus == "connecting")
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          provider.wsConnectionStatus == "success"
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                          color: provider.wsConnectionStatus == "success"
                              ? Colors.blue
                              : Colors.red,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider.wsConnectionStatus == "success"
                              ? "실시간 연결 성공!"
                              : provider.wsConnectionStatus == "connecting"
                              ? "연결 시도 중..."
                              : (provider.wsErrorMessage ?? "연결 실패"),
                          style: TextStyle(
                            color: provider.wsConnectionStatus == "success"
                                ? Colors.blue
                                : provider.wsConnectionStatus == "connecting"
                                ? Colors.orange
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소"),
            ),
            ElevatedButton(
              onPressed:
                  provider.wsConnectionStatus == "connecting" ||
                      provider.isSyncing
                  ? null
                  : () async {
                      final success = await provider.connectAndSync(
                        ipController.text.trim(),
                        portController.text.trim(),
                      );
                      if (success && context.mounted) {
                        // 성공적으로 데이터를 받으면 모달 자동 종료
                        Navigator.pop(context);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF141A2E),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: provider.isSyncing
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          provider.wsConnectionStatus == "connecting"
                              ? "연결 시도 중..."
                              : "데이터 동기화 중...",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      "서버 연결",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
