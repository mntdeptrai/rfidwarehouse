import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/uhf_connection_config.dart';
import '../../services/auth_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../theme/eye_care_theme.dart';

class DesktopConnectionConfigView extends StatefulWidget {
  const DesktopConnectionConfigView({super.key});

  @override
  State<DesktopConnectionConfigView> createState() => _DesktopConnectionConfigViewState();
}

class _DesktopConnectionConfigViewState extends State<DesktopConnectionConfigView> {
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final DesktopUhfTcpService _desktopUhf = DesktopUhfTcpService();
  final AuthService _auth = AuthService();

  // Controllers & Form State
  late String _connectionType;
  late TextEditingController _tcpIpController;
  late TextEditingController _tcpPortController;
  late TextEditingController _comPortController;
  late int _selectedBaudRate;
  late TextEditingController _rs485AddressController;

  late bool _autoConnectOnStartup;
  late bool _autoReconnect;
  late bool _autoConnectOnScan;

  late Set<int> _activeAntennas;
  late int _rfPower;

  // Real-time console logs
  final List<String> _consoleLogs = [];
  StreamSubscription<String>? _logSub;
  final ScrollController _logScrollController = ScrollController();

  bool _isSaving = false;
  bool _isSearchingLan = false;
  String? _feedbackMessage;
  bool _isFeedbackSuccess = true;

  final List<int> _baudRates = [9600, 19200, 38400, 57600, 115200];
  final List<String> _commonComPorts = [
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'COM10'
  ];

  @override
  void initState() {
    super.initState();
    _loadFromCurrentConfig();

    _eyeCare.addListener(_onStateUpdate);
    _desktopUhf.addListener(_onStateUpdate);
    _auth.addListener(_onStateUpdate);

    _logSub = _desktopUhf.onLog.listen((log) {
      if (!mounted) return;
      setState(() {
        _consoleLogs.add(log);
        if (_consoleLogs.length > 200) {
          _consoleLogs.removeAt(0);
        }
      });
      _scrollToBottom();
    });
  }

  void _loadFromCurrentConfig() {
    final cfg = _desktopUhf.config;
    _connectionType = cfg.connectionType;
    _tcpIpController = TextEditingController(text: cfg.tcpIp);
    _tcpPortController = TextEditingController(text: cfg.tcpPort.toString());
    _comPortController = TextEditingController(text: cfg.comPort);
    _selectedBaudRate = cfg.baudRate;
    _rs485AddressController = TextEditingController(text: cfg.rs485Address.toString());

    _autoConnectOnStartup = cfg.autoConnectOnStartup;
    _autoReconnect = cfg.autoReconnect;
    _autoConnectOnScan = cfg.autoConnectOnScan;

    _activeAntennas = Set<int>.from(cfg.activeAntennas);
    if (_activeAntennas.isEmpty) {
      _activeAntennas = {1};
    }
    _rfPower = cfg.rfPower;
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _logScrollController.dispose();
    _tcpIpController.dispose();
    _tcpPortController.dispose();
    _comPortController.dispose();
    _rs485AddressController.dispose();

    _eyeCare.removeListener(_onStateUpdate);
    _desktopUhf.removeListener(_onStateUpdate);
    _auth.removeListener(_onStateUpdate);
    super.dispose();
  }

  UhfConnectionConfig _buildConfigFromInputs() {
    return UhfConnectionConfig(
      connectionType: _connectionType,
      tcpIp: _tcpIpController.text.trim().isEmpty ? '192.168.1.116' : _tcpIpController.text.trim(),
      tcpPort: int.tryParse(_tcpPortController.text.trim()) ?? 9090,
      comPort: _comPortController.text.trim().isEmpty ? 'COM3' : _comPortController.text.trim().toUpperCase(),
      baudRate: _selectedBaudRate,
      rs485Address: int.tryParse(_rs485AddressController.text.trim()) ?? 1,
      autoConnectOnStartup: _autoConnectOnStartup,
      autoReconnect: _autoReconnect,
      autoConnectOnScan: _autoConnectOnScan,
      activeAntennas: _activeAntennas.toList()..sort(),
      rfPower: _rfPower,
    );
  }

  Future<void> _handleSaveConfig({bool connectImmediately = false}) async {
    setState(() {
      _isSaving = true;
      _feedbackMessage = null;
    });

    final newConfig = _buildConfigFromInputs();
    final saved = await _desktopUhf.saveConfig(newConfig);

    if (!saved) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _feedbackMessage = 'Lưu cấu hình thất bại!';
          _isFeedbackSuccess = false;
        });
      }
      return;
    }

    if (connectImmediately) {
      setState(() {
        _feedbackMessage = 'Đã lưu cấu hình! Đang kết nối tới ${newConfig.connectionSummary}...';
        _isFeedbackSuccess = true;
      });

      final ok = await _desktopUhf.connectWithSavedConfig(timeout: const Duration(seconds: 7));
      if (mounted) {
        setState(() {
          _isSaving = false;
          if (ok) {
            _feedbackMessage = 'Kết nối thành công tới ${newConfig.connectionSummary}!';
            _isFeedbackSuccess = true;
          } else {
            _feedbackMessage = 'Đã lưu cấu hình nhưng chưa thể kết nối tới đầu đọc. Vui lòng kiểm tra cáp/mạng!';
            _isFeedbackSuccess = false;
          }
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _feedbackMessage = 'Đã lưu cấu hình kết nối thành công!';
          _isFeedbackSuccess = true;
        });
      }
    }

    // Tự ẩn thông báo sau 4 giây
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _feedbackMessage != null) {
        setState(() => _feedbackMessage = null);
      }
    });
  }

  Future<void> _handleDisconnect() async {
    await _desktopUhf.disconnect(isManual: true);
    if (mounted) {
      setState(() {
        _feedbackMessage = 'Đã ngắt kết nối đầu đọc RFID.';
        _isFeedbackSuccess = true;
      });
    }
  }

  Future<void> _handleSearchLan() async {
    setState(() {
      _isSearchingLan = true;
      _feedbackMessage = 'Đang phát sóng UDP tìm kiếm đầu đọc RFID trong mạng nội bộ...';
      _isFeedbackSuccess = true;
    });

    await _desktopUhf.searchLanDevices();

    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() {
        _isSearchingLan = false;
        final count = _desktopUhf.discoveredReaders.length;
        if (count > 0) {
          _feedbackMessage = 'Tìm thấy $count thiết bị RFID trong mạng LAN!';
          _isFeedbackSuccess = true;
        } else {
          _feedbackMessage = 'Không tìm thấy thiết bị qua UDP broadcast. Hãy nhập IP thủ công.';
          _isFeedbackSuccess = false;
        }
      });
    }
  }

  void _applyDiscoveredDevice(DiscoveredLanReader device) {
    setState(() {
      _connectionType = 'TCP Client';
      _tcpIpController.text = device.ip;
      _tcpPortController.text = device.port;
      _feedbackMessage = 'Đã chọn thiết bị: ${device.ip}:${device.port} (${device.deviceType})';
      _isFeedbackSuccess = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final isConnected = _desktopUhf.isConnected;
    final isConnecting = _desktopUhf.isConnecting;
    final user = _auth.currentUser;
    final canConfig = user?.canConfigureHardware ?? true;

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // ==================== TOP HEADER BAR ====================
          _buildHeaderBar(c, isConnected, isConnecting, canConfig),

          // ==================== FEEDBACK BANNER ====================
          if (_feedbackMessage != null) _buildFeedbackBanner(c),

          // ==================== MAIN CONTENT SCROLL ====================
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. LIVE STATUS HERO CARD
                  _buildLiveStatusHero(c, isConnected, isConnecting),
                  const SizedBox(height: 18),

                  // 2. TWO-COLUMN CONFIGURATION SECTION
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 950;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _buildProtocolConfigCard(c)),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  _buildAutomationCard(c),
                                  const SizedBox(height: 18),
                                  _buildAntennaRfCard(c),
                                ],
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildProtocolConfigCard(c),
                            const SizedBox(height: 18),
                            _buildAutomationCard(c),
                            const SizedBox(height: 18),
                            _buildAntennaRfCard(c),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 18),

                  // 3. LAN DISCOVERY RESULTS (IF AVAILABLE)
                  if (_desktopUhf.discoveredReaders.isNotEmpty) ...[
                    _buildDiscoveredLanDevicesCard(c),
                    const SizedBox(height: 18),
                  ],

                  // 4. LIVE HARDWARE LOG TERMINAL
                  _buildHardwareConsoleCard(c),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // WIDGET BUILDERS
  // ==========================================================================

  Widget _buildHeaderBar(EyeCareColors c, bool isConnected, bool isConnecting, bool canConfig) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.rfidCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.rfidCyan, width: 1.2),
            ),
            child: Icon(Icons.settings_input_antenna_rounded, color: c.rfidCyan, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'CẤU HÌNH KẾT NỐI ĐẦU ĐỌC RFID',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.rfidCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.rfidCyan, width: 0.8),
                      ),
                      child: Text('QUẢN TRỊ HỆ THỐNG', style: TextStyle(color: c.rfidCyan, fontSize: 9.5, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isConnected ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444), width: 0.8),
                      ),
                      child: Text(
                        isConnected ? 'ONLINE • ĐÃ KẾT NỐI' : 'OFFLINE • CHƯA KẾT NỐI',
                        style: TextStyle(
                          color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Thiết lập thông số kết nối TCP/IP LAN, Cổng COM RS232/485 và tự động kết nối khi khởi động phần mềm.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),

          // Action Buttons
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('TẢI LẠI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: () {
                  setState(() {
                    _loadFromCurrentConfig();
                    _feedbackMessage = 'Đã nạp lại cấu hình đang lưu.';
                    _isFeedbackSuccess = true;
                  });
                },
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.rfidCyan,
                  side: BorderSide(color: c.rfidCyan.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isSaving
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.rfidCyan))
                    : const Icon(Icons.save_rounded, size: 16),
                label: const Text('LƯU CẤU HÌNH', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _isSaving ? null : () => _handleSaveConfig(connectImmediately: false),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('LƯU & KẾT NỐI NGAY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _isSaving ? null : () => _handleSaveConfig(connectImmediately: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackBanner(EyeCareColors c) {
    final isSuccess = _isFeedbackSuccess;
    final color = isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _feedbackMessage ?? '',
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: color, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _feedbackMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusHero(EyeCareColors c, bool isConnected, bool isConnecting) {
    final statusColor = isConnected
        ? const Color(0xFF10B981)
        : (isConnecting ? const Color(0xFFF59E0B) : c.textMuted);

    final statusText = isConnected
        ? 'ĐÃ KẾT NỐI VỚI ĐẦU ĐỌC'
        : (isConnecting ? 'ĐANG KẾT NỐI THIẾT BỊ...' : 'CHƯA KẾT NỐI ĐẦU ĐỌC');

    final summary = _desktopUhf.config.connectionSummary;
    final currentId = _desktopUhf.currentConnId.isNotEmpty ? _desktopUhf.currentConnId : summary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected ? const Color(0xFF10B981).withValues(alpha: 0.4) : c.border,
          width: isConnected ? 1.5 : 1,
        ),
        boxShadow: [
          if (isConnected)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Live Pulse Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor, width: 2),
            ),
            child: Center(
              child: Icon(
                isConnected
                    ? Icons.sensors_rounded
                    : (isConnecting ? Icons.sync_rounded : Icons.sensors_off_rounded),
                color: statusColor,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 18),

          // Status Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Text(
                        'Driver: Hopeland HF340 / C# Bridge',
                        style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isConnected
                      ? 'Thiết bị hoạt động tại: $currentId • Công suất: ${_desktopUhf.config.rfPower} dBm • Anten mở: [${_desktopUhf.config.activeAntennas.join(", ")}]'
                      : (isConnecting
                          ? 'Đang phát tín hiệu kết nối tới $summary... Xin chờ giây lát.'
                          : 'Cổng quét RFID chưa sẵn sàng. Bấm "Kết Nối Thử" hoặc chọn lưu & kích hoạt.'),
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),

          // Control Buttons
          Wrap(
            spacing: 10,
            children: [
              if (isConnected)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFFEF4444),
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                  label: const Text('NGẮT KẾT NỐI', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  onPressed: _handleDisconnect,
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: isConnecting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(
                    isConnecting ? 'ĐANG KẾT NỐI...' : 'KẾT NỐI THỬ',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: isConnecting ? null : () => _handleSaveConfig(connectImmediately: true),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.rfidCyan,
                  side: BorderSide(color: c.rfidCyan.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isSearchingLan
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.rfidCyan))
                    : const Icon(Icons.wifi_find_rounded, size: 16),
                label: Text(
                  _isSearchingLan ? 'ĐANG QUÉT LAN...' : 'TÌM TRONG LAN',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSearchingLan ? null : _handleSearchLan,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProtocolConfigCard(EyeCareColors c) {
    final protocols = ['TCP Client', 'RS232', 'RS485', 'USB'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, color: c.rfidCyan, size: 20),
              const SizedBox(width: 10),
              Text(
                'PHƯƠNG THỨC KẾT NỐI VẬT LÝ',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Protocol Choice Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.bgDeep,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: protocols.map((proto) {
                final isSelected = _connectionType == proto;
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _connectionType = proto),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? c.rfidCyan : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        proto,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF0F172A) : c.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          // Specific Settings by Protocol
          if (_connectionType == 'TCP Client') ...[
            _buildTcpSettings(c),
          ] else if (_connectionType == 'RS232') ...[
            _buildRs232Settings(c),
          ] else if (_connectionType == 'RS485') ...[
            _buildRs485Settings(c),
          ] else ...[
            _buildUsbSettings(c),
          ],
        ],
      ),
    );
  }

  Widget _buildTcpSettings(EyeCareColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Địa chỉ IP đầu đọc *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _tcpIpController,
                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: '192.168.1.116',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.lan_rounded, color: c.rfidCyan, size: 18),
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.rfidCyan)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cổng Port (Mặc định 9090) *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _tcpPortController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: '9090',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.numbers_rounded, color: c.rfidCyan, size: 18),
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.rfidCyan)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Helper Box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: const Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Khuyên dùng cho Cổng RFID cố định (Hopeland CL7206C / HZ540):',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '1. Nối dây mạng LAN từ đầu đọc vào Switch / Router của kho.\n2. Đặt IP máy tính cùng lớp mạng với đầu đọc (ví dụ: 192.168.1.xxx).\n3. Bấm "TÌM TRONG LAN" để hệ thống tự động quét và dò IP của đầu đọc.',
                      style: TextStyle(color: c.textSecondary, fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRs232Settings(EyeCareColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cổng COM (Serial Port) *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _comPortController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            hintText: 'COM3',
                            hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                            prefixIcon: Icon(Icons.cable_rounded, color: c.rfidCyan, size: 18),
                            filled: true,
                            fillColor: c.bgDeep,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.rfidCyan)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Chọn cổng COM nhanh',
                        icon: Icon(Icons.arrow_drop_down_circle_outlined, color: c.rfidCyan),
                        color: c.bgCard,
                        onSelected: (val) => setState(() => _comPortController.text = val),
                        itemBuilder: (ctx) => _commonComPorts.map((port) {
                          return PopupMenuItem<String>(
                            value: port,
                            child: Text(port, style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace')),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tốc độ Baud Rate *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedBaudRate,
                        isExpanded: true,
                        dropdownColor: c.bgCard,
                        items: _baudRates.map((baud) {
                          return DropdownMenuItem<int>(
                            value: baud,
                            child: Text('$baud bps', style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace')),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedBaudRate = v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: c.rfidCyan, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sử dụng khi nối trực tiếp cáp DB9 RS232 hoặc cáp USB-to-Serial từ đầu đọc vào cổng USB của máy tính Windows. Tốc độ tiêu chuẩn cho Hopeland là 115200 bps.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRs485Settings(EyeCareColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cổng COM RS485 *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _comPortController,
                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'COM3',
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Địa chỉ Bus (1-254) *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _rs485AddressController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: '1',
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Text(
            'Chế độ RS485 bus cho phép nối nhiều đầu đọc trên cùng 1 đường truyền cáp xoắn đôi 2 dây.',
            style: TextStyle(color: c.textSecondary, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildUsbSettings(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.usb_rounded, color: c.rfidCyan, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kết Nối Cổng USB Trực Tiếp (HID / Virtual COM)', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(
                  'Cắm cáp USB Type-B hoặc Micro-USB từ đầu đọc vào máy tính. Driver sẽ tự động nhận diện và kết nối.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomationCard(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_mode_rounded, color: const Color(0xFF10B981), size: 20),
              const SizedBox(width: 10),
              Text(
                'TỰ ĐỘNG HÓA & PHỤC HỒI KẾT NỐI',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Switch 1: Auto-connect on startup
          _buildSwitchRow(
            title: 'Tự động kết nối khi mở ứng dụng',
            subtitle: 'Tự kết nối với đầu đọc ngay khi ứng dụng khởi động hoặc chuyển vào màn hình quét.',
            value: _autoConnectOnStartup,
            onChanged: (val) => setState(() => _autoConnectOnStartup = val),
            c: c,
          ),
          const Divider(height: 16),

          // Switch 2: Auto reconnect
          _buildSwitchRow(
            title: 'Tự động kết nối lại khi mất tín hiệu',
            subtitle: 'Thử kết nối lại mỗi 5 giây nếu cáp bị lỏng hoặc mạng LAN bị ngắt quãng.',
            value: _autoReconnect,
            onChanged: (val) => setState(() => _autoReconnect = val),
            c: c,
          ),
          const Divider(height: 16),

          // Switch 3: Auto-connect on scan
          _buildSwitchRow(
            title: 'Tự động kích hoạt khi bấm quét hàng',
            subtitle: 'Khi bấm "Bắt Đầu Quét", nếu đầu đọc đang ngắt kết nối sẽ tự động kết nối trước khi quét.',
            value: _autoConnectOnScan,
            onChanged: (val) => setState(() => _autoConnectOnScan = val),
            c: c,
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required EyeCareColors c,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _buildAntennaRfCard(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: const Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 10),
              Text(
                'ANTEN & CÔNG SUẤT PHÁT SÓNG RF',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Antennas Choice
          Text('Cổng Anten đang kích hoạt:', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [1, 2, 3, 4].map((ant) {
              final isEnabled = _activeAntennas.contains(ant);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        if (isEnabled) {
                          if (_activeAntennas.length > 1) {
                            _activeAntennas.remove(ant);
                          }
                        } else {
                          _activeAntennas.add(ant);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isEnabled ? c.rfidCyan.withValues(alpha: 0.2) : c.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isEnabled ? c.rfidCyan : c.border,
                          width: isEnabled ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        'Anten $ant',
                        style: TextStyle(
                          color: isEnabled ? c.rfidCyan : c.textMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // RF Power Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Công suất phát sóng (Power):', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                ),
                child: Text(
                  '$_rfPower dBm',
                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFF59E0B),
              thumbColor: const Color(0xFFF59E0B),
              overlayColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _rfPower.toDouble(),
              min: 0,
              max: 33,
              divisions: 33,
              onChanged: (val) => setState(() => _rfPower = val.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0 dBm (Tắt sóng)', style: TextStyle(color: c.textMuted, fontSize: 10)),
              Text('20 dBm (Kho nhỏ 2m)', style: TextStyle(color: c.textMuted, fontSize: 10)),
              Text('30-33 dBm (Cổng kho lớn 6m-8m)', style: TextStyle(color: c.textMuted, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveredLanDevicesCard(EyeCareColors c) {
    final devices = _desktopUhf.discoveredReaders;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_find_rounded, color: c.rfidCyan, size: 20),
              const SizedBox(width: 10),
              Text(
                'THIẾT BỊ PHÁT HIỆN QUA MẠNG LAN (${devices.length})',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: devices.length,
            separatorBuilder: (ctx, i) => const Divider(height: 12),
            itemBuilder: (ctx, idx) {
              final dev = devices[idx];
              final isCurrent = _tcpIpController.text == dev.ip;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCurrent ? c.rfidCyan.withValues(alpha: 0.08) : c.bgDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCurrent ? c.rfidCyan : c.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.rfidCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.router_rounded, color: c.rfidCyan, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${dev.ip}:${dev.port}',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: c.bgCard,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: c.border),
                                ),
                                child: Text(dev.deviceType, style: TextStyle(color: c.textSecondary, fontSize: 10)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MAC: ${dev.mac} • Gateway: ${dev.gateway} • Subnet: ${dev.mask}',
                            style: TextStyle(color: c.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCurrent ? const Color(0xFF10B981) : c.rfidCyan,
                        foregroundColor: isCurrent ? Colors.white : const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        elevation: 0,
                      ),
                      onPressed: () => _applyDiscoveredDevice(dev),
                      child: Text(
                        isCurrent ? 'ĐANG CHỌN' : 'CHỌN ĐẦU ĐỌC NÀY',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareConsoleCard(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NHẬT KÝ KẾT NỐI PHẦN CỨNG (REAL-TIME CONSOLE)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 24)),
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.grey, size: 16),
                label: const Text('XÓA LOG', style: TextStyle(color: Colors.grey, fontSize: 11)),
                onPressed: () => setState(() => _consoleLogs.clear()),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: _consoleLogs.isEmpty
                ? Center(
                    child: Text(
                      'Chưa có log mới từ thiết bị. Nhấn "KẾT NỐI THỬ" để kiểm tra đường truyền phần cứng.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    itemCount: _consoleLogs.length,
                    itemBuilder: (ctx, i) {
                      final line = _consoleLogs[i];
                      Color logColor = const Color(0xFF94A3B8);
                      if (line.contains('✅') || line.contains('thành công')) {
                        logColor = const Color(0xFF34D399);
                      } else if (line.contains('❌') || line.contains('lỗi') || line.contains('Không thể')) {
                        logColor = const Color(0xFFF87171);
                      } else if (line.contains('⚠️') || line.contains('Timeout')) {
                        logColor = const Color(0xFFFBBF24);
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Text(
                          line,
                          style: TextStyle(color: logColor, fontSize: 11, fontFamily: 'monospace', height: 1.3),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
