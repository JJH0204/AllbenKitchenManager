import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/kitchen_provider.dart';

/// 파일명: lib/ui/screens/settings_screen.dart
/// 작성의도: 서버 접속 정보 설정 및 앱 구성을 관리하는 독립된 설정 페이지입니다.
/// 기능 원리: `KitchenProvider`의 서버 설정을 읽고 쓰며, 연결 테스트 및 동기화 기능을 제공합니다.

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController ipController;
  late TextEditingController portController;

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
        return Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "SETTINGS",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF0F172A),
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Server Connection
                    Expanded(
                      child: _buildSectionCard(
                        title: "서버 연결 설정",
                        icon: Icons.lan,
                        children: [
                          _buildTextField(
                            controller: ipController,
                            label: "서버 IP (Tailscale)",
                            hint: "100.x.x.x",
                            icon: Icons.computer,
                          ),
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: portController,
                            label: "포트 번호",
                            hint: "8080",
                            icon: Icons.numbers,
                            isNumber: true,
                          ),
                          const SizedBox(height: 32),
                          _buildConnectionStatus(provider),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Right Column: App Information & Actions
                    Expanded(
                      child: Column(
                        children: [
                          _buildSectionCard(
                            title: "앱 정보",
                            icon: Icons.info_outline,
                            children: [
                              _buildInfoRow("버전", "v1.2.0 (Build 341)"),
                              _buildInfoRow(
                                "상태",
                                provider.wsConnectionStatus == "success"
                                    ? "연결됨"
                                    : "연결 안 됨",
                              ),
                              _buildInfoRow(
                                "동기화",
                                provider.isSyncing ? "동기화 중..." : "최신 상태",
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildActionCard(
                            title: "서버 설정 적용 및 동기화",
                            description: "입력된 IP와 포트로 접속을 시도하고 최신 데이터를 가져옵니다.",
                            buttonLabel: provider.isSyncing
                                ? "동기화 중..."
                                : "설정 적용하기",
                            icon: Icons.sync,
                            isLoading: provider.isSyncing,
                            onPressed: () async {
                              await provider.connectAndSync(
                                ipController.text.trim(),
                                portController.text.trim(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0F172A), size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String description,
    required String buttonLabel,
    required IconData icon,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          buttonLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(KitchenProvider provider) {
    bool isSuccess = provider.wsConnectionStatus == "success";
    bool isError = provider.wsConnectionStatus == "error";
    bool isConnecting = provider.wsConnectionStatus == "connecting";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSuccess
            ? Colors.green.withOpacity(0.08)
            : (isError
                  ? Colors.red.withOpacity(0.08)
                  : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (isConnecting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(
              isSuccess
                  ? Icons.check_circle
                  : (isError ? Icons.error : Icons.cloud_off),
              color: isSuccess
                  ? Colors.green
                  : (isError ? Colors.red : const Color(0xFF94A3B8)),
              size: 20,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isSuccess
                  ? "서버와 정상적으로 연결되었습니다."
                  : (isError
                        ? (provider.wsErrorMessage ?? "연결 오류가 발생했습니다.")
                        : "서버 연결이 필요합니다."),
              style: TextStyle(
                color: isSuccess
                    ? Colors.green
                    : (isError ? Colors.red : const Color(0xFF64748B)),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
