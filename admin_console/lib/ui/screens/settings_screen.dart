/**
 * 작성의도: 서버 네트워크 정보 및 보안 설정을 관리하는 화면 위젯입니다.
 * 기능 원리: 로컬 및 가상 네트워크(Tailscale) IP 확인, 서버 포트 변경, 방화벽 설정 접근 및 연결된 기기 상세 정보를 제공합니다.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../providers/server_provider.dart';
import '../../models/device_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String localIp = "Loading...";
  String tailscaleIp = "Not Found";
  bool isTailscaleOffline = false;
  final TextEditingController _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadIps();
    _loadPortSettings();
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
          if (addr.address.startsWith("192.168.") ||
              addr.address.startsWith("10.")) {
            lIp = addr.address;
          }
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
    return Consumer<ServerProvider>(
      builder: (context, serverProvider, child) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildNetworkSection(),
              const SizedBox(height: 32),
              _buildPortSection(serverProvider),
              const SizedBox(height: 32),
              _buildFirewallSection(),
              const SizedBox(height: 32),
              _buildDeviceTableSection(serverProvider.connectedClients),
            ],
          ),
        );
      },
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

  Widget _buildPortSection(ServerProvider serverProvider) {
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
                  enabled: !serverProvider.isServerOn,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: serverProvider.isServerOn ? null : _savePortSettings,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                ),
                child: const Text("포트 저장"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final appDir = await getApplicationSupportDirectory();
                final dataPath = p.join(appDir.path, 'data');
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

  Widget _buildDeviceTableSection(List<DeviceModel> connectedDevices) {
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
            rows: connectedDevices.map((device) {
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
