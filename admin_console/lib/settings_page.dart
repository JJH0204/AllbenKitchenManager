import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models/device_info.dart';

class SettingsPage extends StatefulWidget {
  final bool isServerOn;
  final List<String> logs;
  final List<DeviceInfo> connectedDevices;
  final Function(bool start, int port) onToggleServer;

  const SettingsPage({
    super.key,
    required this.isServerOn,
    required this.logs,
    required this.connectedDevices,
    required this.onToggleServer,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String localIp = "Loading...";
  String tailscaleIp = "Not Found";
  bool isTailscaleOffline = false;
  final TextEditingController _portController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  List<DeviceInfo> connectedDevices = [];

  @override
  void initState() {
    super.initState();
    _loadIps();
    _loadPortSettings();
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length != oldWidget.logs.length) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      String lIp = "Unknown";
      String tIp = "Not Found";
      bool foundTailscale = false;

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          // 로컬 IP (보통 192.168.x.x 또는 10.x.x.x)
          if (addr.address.startsWith("192.168.") ||
              addr.address.startsWith("10.")) {
            lIp = addr.address;
          }
          // Tailscale IP (보통 100.x.x.x)
          if (addr.address.startsWith("100.")) {
            tIp = addr.address;
            foundTailscale = true;
          }
        }
      }

      if (mounted) {
        setState(() {
          localIp = lIp;
          tailscaleIp = tIp;
          // UI에 표시된 IP가 100.x.x.x 인데 실제 인터페이스에 없으면 오프라인으로 간주
          isTailscaleOffline = !foundTailscale;
        });
      }
    } catch (e) {
      if (mounted) setState(() => localIp = "Error: $e");
    }
  }

  Future<void> _loadPortSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final port = prefs.getString('server_port') ?? "8080";
    _portController.text = port;
  }

  Future<void> _savePortSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_port', _portController.text);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('포트 설정이 저장되었습니다.')));
    }
  }

  Future<void> _openFirewallSettings() async {
    var shell = Shell();
    await shell.run('control firewall.cpl');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNetworkSection(),
          const SizedBox(height: 32),
          _buildPortSection(),
          const SizedBox(height: 32),
          _buildFirewallSection(),
          const SizedBox(height: 32),
          _buildLogViewerSection(),
          const SizedBox(height: 32),
          _buildDeviceTableSection(),
        ],
      ),
    );
  }

  Widget _buildNetworkSection() {
    return Column(
      children: [
        if (isTailscaleOffline)
          _buildOfflineWarning("Tailscale 서비스가 오프라인이거나 인터페이스를 찾을 수 없습니다."),
        _buildCard(
          title: "Network Information",
          child: Column(
            children: [
              _buildInfoRow("Local IP", localIp, Icons.lan),
              const Divider(),
              _buildInfoRow(
                "Tailscale IP",
                tailscaleIp,
                Icons.vpn_lock,
                isError: isTailscaleOffline,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineWarning(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortSection() {
    return _buildCard(
      title: "Server Configuration",
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: "Server Port",
                    hintText: "e.g. 8080",
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !widget.isServerOn,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: widget.isServerOn ? null : _savePortSettings,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                ),
                child: const Text("설정 저장"),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                final port = int.tryParse(_portController.text) ?? 8080;
                widget.onToggleServer(!widget.isServerOn, port);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.isServerOn ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                widget.isServerOn ? "SERVER STOP" : "SERVER START",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final appDir = await getApplicationSupportDirectory();
                final dataPath = p.join(appDir.path, 'data');
                // 윈도우 탐색기로 해당 폴더 열기
                var shell = Shell();
                await shell.run('explorer "${dataPath.replaceAll('/', '\\')}"');
              },
              icon: const Icon(Icons.folder_open),
              label: const Text("데이터 폴더 열기 (JSON/Images)"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogViewerSection() {
    return _buildCard(
      title: "Server Logs",
      padding: EdgeInsets.zero,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: ListView.builder(
          controller: _logScrollController,
          itemCount: widget.logs.length,
          itemBuilder: (context, index) {
            return Text(
              widget.logs[index],
              style: const TextStyle(
                color: Color(0xFF3FB950), // Terminal Green
                fontFamily: 'Courier', // Monospace font
                fontSize: 13,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFirewallSection() {
    return _buildCard(
      title: "Windows Security",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("서버 접속이 원활하지 않을 경우 방화벽 설정을 확인하세요."),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _openFirewallSettings,
            icon: const Icon(Icons.security),
            label: const Text("방화벽 설정 열기"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTableSection() {
    return _buildCard(
      title: "Connected Clients",
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          DataTable(
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text("ID")),
              DataColumn(label: Text("Device Name")),
              DataColumn(label: Text("IP Address")),
              DataColumn(label: Text("Status")),
              DataColumn(label: Text("Last Seen")),
            ],
            rows: widget.connectedDevices.map((device) {
              return DataRow(
                cells: [
                  DataCell(Text(device.id)),
                  DataCell(
                    Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataCell(Text(device.ip)),
                  DataCell(
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: device.isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          device.isOnline ? "Online" : "Offline",
                          style: TextStyle(
                            color: device.isOnline ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(device.lastSeen.toString().split('.')[0])),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required Widget child,
    EdgeInsets? padding,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1F2E),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon, {
    bool isError = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: isError ? Colors.red : Colors.blueAccent, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isError ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
