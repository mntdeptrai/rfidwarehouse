import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../theme/eye_care_theme.dart';

class DesktopUhfStudioView extends StatefulWidget {
  const DesktopUhfStudioView({super.key});

  @override
  State<DesktopUhfStudioView> createState() => _DesktopUhfStudioViewState();
}

class _DesktopUhfStudioViewState extends State<DesktopUhfStudioView> with SingleTickerProviderStateMixin {
  final DesktopUhfTcpService _uhfService = DesktopUhfTcpService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  late TabController _tabController;

  // Controllers
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.116');
  final TextEditingController _portController = TextEditingController(text: '9090');
  final TextEditingController _rs485AddressController = TextEditingController(text: '1');
  final TextEditingController _searchFilterController = TextEditingController();

  // R/W Controllers
  final TextEditingController _rwOffsetController = TextEditingController(text: '2');
  final TextEditingController _rwCountController = TextEditingController(text: '6');
  final TextEditingController _rwPasswordController = TextEditingController(text: '00000000');
  final TextEditingController _rwMatchEpcController = TextEditingController();
  final TextEditingController _rwDataController = TextEditingController();

  // Fast EPC Controllers
  final TextEditingController _fastTargetEpcController = TextEditingController();
  final TextEditingController _fastNewEpcController = TextEditingController();

  // Security Controllers
  final TextEditingController _lockTargetEpcController = TextEditingController();
  final TextEditingController _lockPasswordController = TextEditingController(text: '00000000');
  final TextEditingController _killTargetEpcController = TextEditingController();
  final TextEditingController _killPasswordController = TextEditingController(text: '00000000');

  // Network Config Controllers
  final TextEditingController _netIpController = TextEditingController(text: '192.168.1.116');
  final TextEditingController _netMaskController = TextEditingController(text: '255.255.255.0');
  final TextEditingController _netGatewayController = TextEditingController(text: '192.168.1.1');

  // State flags
  String _selectedConnType = 'RS232'; // 'RS232', 'TCP Client', 'TCP Server', 'USB'
  String _selectedComPort = 'COM3';
  int _selectedBaudRate = 115200;
  int _scanMode = 0; // 0: EPC Only, 1: EPC+TID, 2: Full Memory
  int _rwBank = 1; // 0: Reserved, 1: EPC, 2: TID, 3: User
  int _lockArea = 0;
  int _lockType = 0;

  final List<String> _comPorts = ['COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'COM10'];
  final List<int> _baudRates = [115200, 57600, 38400, 19200, 9600];

  bool _soundEnabled = true;
  bool _autoScrollLog = true;

  final List<String> _logLines = [];
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    _uhfService.addListener(_onServiceUpdate);
    _eyeCare.addListener(_onServiceUpdate);
    _uhfService.onLog.listen((line) {
      if (mounted) {
        setState(() {
          _logLines.add(line);
          if (_logLines.length > 500) _logLines.removeAt(0);
        });
        if (_autoScrollLog && _logScrollController.hasClients) {
          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      }
    });
  }

  @override
  void dispose() {
    _uhfService.removeListener(_onServiceUpdate);
    _eyeCare.removeListener(_onServiceUpdate);
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _rs485AddressController.dispose();
    _searchFilterController.dispose();
    _rwOffsetController.dispose();
    _rwCountController.dispose();
    _rwPasswordController.dispose();
    _rwMatchEpcController.dispose();
    _rwDataController.dispose();
    _fastTargetEpcController.dispose();
    _fastNewEpcController.dispose();
    _lockTargetEpcController.dispose();
    _lockPasswordController.dispose();
    _killTargetEpcController.dispose();
    _killPasswordController.dispose();
    _netIpController.dispose();
    _netMaskController.dispose();
    _netGatewayController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // 1. Connection Toolbar
            _buildConnectionToolbar(c),
            const SizedBox(height: 8),

            // 2. KPI Metrics Bar
            _buildKpiMetrics(c),
            const SizedBox(height: 8),

            // 3. Tab System (4 Tabs)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    _buildTabBar(c),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTabLiveInventory(c),
                          _buildTabMemoryRw(c),
                          _buildTabSecurity(c),
                          _buildTabLanManager(c),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 4. Console Log
            _buildConsoleLog(c),
          ],
        ),
      ),
    );
  }

  // ==================== 1. CONNECTION TOOLBAR (CONNECT READER) ====================
  Widget _buildConnectionToolbar(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          // Section Title: "| Connect Reader"
          Row(
            children: [
              Container(
                width: 3.5,
                height: 16,
                decoration: BoxDecoration(
                  color: c.rfidCyan,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Connect Reader',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),

          // Conn Type
          Text('Conn Type', style: TextStyle(color: c.textSecondary, fontSize: 11)),
          const SizedBox(width: 6),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedConnType,
                dropdownColor: c.bgCard,
                style: TextStyle(color: c.textPrimary, fontSize: 11),
                items: const [
                  DropdownMenuItem(value: 'RS232', child: Text('RS232')),
                  DropdownMenuItem(value: 'TCP Client', child: Text('TCP Client')),
                  DropdownMenuItem(value: 'RS485', child: Text('RS485')),
                  DropdownMenuItem(value: 'USB', child: Text('USB')),
                  DropdownMenuItem(value: 'TCP Server', child: Text('TCP Server')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedConnType = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Param Label
          Text('Param', style: TextStyle(color: c.textSecondary, fontSize: 11)),
          const SizedBox(width: 6),

          // Dynamic Param Controls based on Conn Type
          if (_selectedConnType == 'RS232') ...[
            // COM Port Dropdown
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedComPort,
                  dropdownColor: c.bgCard,
                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                  items: _comPorts.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedComPort = val);
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Baudrate Dropdown
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedBaudRate,
                  dropdownColor: c.bgCard,
                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                  items: _baudRates.map((b) => DropdownMenuItem(value: b, child: Text('$b'))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBaudRate = val);
                  },
                ),
              ),
            ),
          ] else if (_selectedConnType == 'RS485') ...[
            // RS485 Address Input
            SizedBox(
              width: 45,
              height: 30,
              child: TextField(
                controller: _rs485AddressController,
                style: TextStyle(color: c.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Addr',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 10),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  filled: true,
                  fillColor: c.bgCardElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // COM Port Dropdown
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedComPort,
                  dropdownColor: c.bgCard,
                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                  items: _comPorts.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedComPort = val);
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Baudrate Dropdown
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedBaudRate,
                  dropdownColor: c.bgCard,
                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                  items: _baudRates.map((b) => DropdownMenuItem(value: b, child: Text('$b'))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedBaudRate = val);
                  },
                ),
              ),
            ),
          ] else if (_selectedConnType == 'TCP Client') ...[
            // IP Input
            SizedBox(
              width: 120,
              height: 30,
              child: TextField(
                controller: _ipController,
                style: TextStyle(color: c.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  filled: true,
                  fillColor: c.bgCardElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Port Input
            SizedBox(
              width: 60,
              height: 30,
              child: TextField(
                controller: _portController,
                style: TextStyle(color: c.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  filled: true,
                  fillColor: c.bgCardElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                ),
              ),
            ),
          ] else if (_selectedConnType == 'TCP Server') ...[
            // Port Input
            SizedBox(
              width: 80,
              height: 30,
              child: TextField(
                controller: _portController,
                style: TextStyle(color: c.textPrimary, fontSize: 11),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  filled: true,
                  fillColor: c.bgCardElevated,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border)),
                ),
              ),
            ),
          ] else if (_selectedConnType == 'USB') ...[
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.border),
              ),
              child: Text('USB HID Reader (CL7206)', style: TextStyle(color: c.textSecondary, fontSize: 11)),
            ),
          ],

          const SizedBox(width: 14),

          // Connect / Disconnect Button (SDK Style)
          if (_uhfService.isConnecting)
            ElevatedButton.icon(
              onPressed: null,
              icon: const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              label: const Text('Connecting...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.warningAmber,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                elevation: 1,
              ),
            )
          else if (!_uhfService.isConnected)
            ElevatedButton(
              onPressed: () {
                if (_selectedConnType == 'RS232') {
                  _uhfService.connectSerial(_selectedComPort, _selectedBaudRate);
                } else if (_selectedConnType == 'RS485') {
                  final addr = int.tryParse(_rs485AddressController.text) ?? 1;
                  _uhfService.connect485(addr, _selectedComPort, _selectedBaudRate);
                } else if (_selectedConnType == 'TCP Client') {
                  final port = int.tryParse(_portController.text) ?? 9090;
                  _uhfService.connectTcp(_ipController.text.trim(), port);
                } else if (_selectedConnType == 'TCP Server') {
                  final port = int.tryParse(_portController.text) ?? 9090;
                  _uhfService.startTcpServer('0.0.0.0', port);
                } else if (_selectedConnType == 'USB') {
                  _uhfService.connectUsb();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.rfidCyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                elevation: 1,
              ),
              child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            )
          else
            ElevatedButton(
              onPressed: () => _uhfService.disconnect(),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.errorCoral,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                elevation: 1,
              ),
              child: const Text('Disconnect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),

          const Spacer(),

          // Telemetry Chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                const Text('🌡️ ', style: TextStyle(fontSize: 11)),
                Text(
                  _uhfService.isConnected
                      ? '${_uhfService.readerTemp.toStringAsFixed(1)} °C'
                      : '--.- °C',
                  style: TextStyle(
                    color: _uhfService.isConnected ? c.warningAmber : c.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          OutlinedButton.icon(
            onPressed: () {
              _tabController.animateTo(3); // Go to Tab 4 (LAN Manager)
              _uhfService.searchLanReaders();
            },
            icon: Icon(Icons.search, size: 14, color: c.rfidCyan),
            label: Text('TÌM LAN', style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.rfidCyan),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 2. KPI METRICS ====================
  Widget _buildKpiMetrics(EyeCareColors c) {
    String statusText;
    String statusIcon;
    Color statusColor;

    if (_uhfService.isConnecting) {
      statusText = 'ĐANG KẾT NỐI...';
      statusIcon = '🟡';
      statusColor = c.warningAmber;
    } else if (_uhfService.isConnected) {
      statusText = _uhfService.isScanning ? 'ĐANG QUÉT' : 'SẴN SÀNG';
      statusIcon = '🟢';
      statusColor = c.successEmerald;
    } else {
      statusText = 'CHƯA KẾT NỐI';
      statusIcon = '🔴';
      statusColor = c.errorCoral;
    }

    return Row(
      children: [
        _buildKpiCard('THẺ DUY NHẤT', '${_uhfService.uniqueCount}', '🏷️', c.rfidCyan, c),
        const SizedBox(width: 8),
        _buildKpiCard('TỔNG LƯỢT ĐỌC', '${_uhfService.totalReads}', '📊', const Color(0xFF7C3AED), c),
        const SizedBox(width: 8),
        _buildKpiCard('TỐC ĐỘ QUÉT', '${_uhfService.readRate.toInt()} Tags/s', '⚡', c.successEmerald, c),
        const SizedBox(width: 8),
        _buildKpiCard(
          'TRẠNG THÁI',
          statusText,
          statusIcon,
          statusColor,
          c,
        ),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, String icon, Color accentColor, EyeCareColors c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: accentColor, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Consolas')),
              ],
            ),
            Text(icon, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }

  // ==================== 3. TAB BAR ====================
  Widget _buildTabBar(EyeCareColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: c.rfidCyan,
        labelColor: c.rfidCyan,
        unselectedLabelColor: c.textMuted,
        tabs: const [
          Tab(icon: Icon(Icons.radar, size: 15), text: 'Quét Thẻ (Live Inventory)'),
          Tab(icon: Icon(Icons.edit_note, size: 15), text: 'Đọc & Ghi Thẻ (Memory R/W)'),
          Tab(icon: Icon(Icons.lock_outline, size: 15), text: 'Bảo Mật Thẻ (Lock & Kill)'),
          Tab(icon: Icon(Icons.lan_outlined, size: 15), text: 'Tìm Thiết Bị LAN & Cấu Hình'),
        ],
      ),
    );
  }

  // ==================== TAB 1: LIVE INVENTORY ====================
  Widget _buildTabLiveInventory(EyeCareColors c) {
    final query = _searchFilterController.text.trim().toLowerCase();
    final filteredTags = _uhfService.tags.where((t) {
      if (query.isEmpty) return true;
      return t.epc.toLowerCase().contains(query) || t.tid.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          // Antenna matrix & options
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Text('Anten: ', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
                ...List.generate(4, (i) {
                  final antNum = i + 1;
                  final isChecked = _uhfService.activeAntennas.contains(antNum);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: isChecked,
                          activeColor: c.rfidCyan,
                          visualDensity: VisualDensity.compact,
                          onChanged: (val) => _uhfService.setAntenna(antNum, val ?? false),
                        ),
                        Text('ANT $antNum', style: TextStyle(color: isChecked ? c.rfidCyan : c.textPrimary, fontWeight: isChecked ? FontWeight.bold : FontWeight.normal, fontSize: 11)),
                      ],
                    ),
                  );
                }),
                const Spacer(),
                Text('Chế độ: ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: c.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _scanMode,
                      dropdownColor: c.bgCard,
                      style: TextStyle(color: c.textPrimary, fontSize: 11),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Chỉ mã EPC')),
                        DropdownMenuItem(value: 1, child: Text('EPC + TID')),
                        DropdownMenuItem(value: 2, child: Text('EPC + TID + User Data')),
                      ],
                      onChanged: (v) => setState(() => _scanMode = v ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: _soundEnabled,
                  activeColor: c.rfidCyan,
                  visualDensity: VisualDensity.compact,
                  onChanged: (val) => setState(() => _soundEnabled = val ?? true),
                ),
                Text('🔔 Bíp', style: TextStyle(color: c.textPrimary, fontSize: 11)),
                const SizedBox(width: 12),
                Checkbox(
                  value: _uhfService.ignoreAlreadyScanned,
                  activeColor: c.successEmerald,
                  visualDensity: VisualDensity.compact,
                  onChanged: (val) => setState(() => _uhfService.ignoreAlreadyScanned = val ?? true),
                ),
                Text('🚫 Bỏ qua thẻ đã quét', style: TextStyle(color: c.successEmerald, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Action toolbar
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: (!_uhfService.isConnected || _uhfService.isScanning)
                    ? null
                    : () {
                        _uhfService.startInventory(antennas: _uhfService.activeAntennas.toList(), scanMode: _scanMode);
                      },
                icon: const Icon(Icons.play_arrow, size: 14),
                label: const Text('BẮT ĐẦU QUÉT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.successEmerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                onPressed: (!_uhfService.isConnected || !_uhfService.isScanning)
                    ? null
                    : () => _uhfService.stopInventory(),
                icon: const Icon(Icons.stop, size: 14),
                label: const Text('DỪNG QUÉT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.errorCoral,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () => _uhfService.clearTags(),
                icon: const Icon(Icons.clear_all, size: 14),
                label: const Text('Xóa danh sách', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textSecondary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const Spacer(),
              // Search field
              SizedBox(
                width: 200,
                height: 32,
                child: TextField(
                  controller: _searchFilterController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'Tìm EPC / TID...',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                    prefixIcon: Icon(Icons.search, size: 14, color: c.textMuted),
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: c.bgCardElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Tag Data Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: filteredTags.isEmpty
                  ? Center(child: Text('Chưa có thẻ nào được quét. Bấm "BẮT ĐẦU QUÉT" để đọc thẻ.', style: TextStyle(color: c.textMuted, fontSize: 11)))
                  : ListView.builder(
                      itemCount: filteredTags.length,
                      itemBuilder: (context, index) {
                        final tag = filteredTags[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: index.isEven ? c.bgCard : c.bgCardElevated,
                            border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 30, child: Text('${index + 1}', style: TextStyle(color: c.textMuted, fontSize: 10))),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  tag.epc,
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Consolas'),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  tag.tid.isNotEmpty ? tag.tid : '-',
                                  style: TextStyle(color: c.textSecondary, fontSize: 10, fontFamily: 'Consolas'),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: tag.rssiValue >= -60 ? c.successEmerald : (tag.rssiValue >= -75 ? c.warningAmber : c.errorCoral),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('${tag.rssi} dBm', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                                  ],
                                ),
                              ),
                              SizedBox(width: 45, child: Text('ANT ${tag.ant}', style: TextStyle(color: c.rfidCyan, fontSize: 10, fontWeight: FontWeight.bold))),
                              SizedBox(width: 50, child: Text('${tag.count} lần', style: const TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold, fontSize: 10))),
                              SizedBox(
                                width: 75,
                                child: Text(
                                  '${tag.lastSeen.hour.toString().padLeft(2, "0")}:${tag.lastSeen.minute.toString().padLeft(2, "0")}:${tag.lastSeen.second.toString().padLeft(2, "0")}',
                                  style: TextStyle(color: c.textMuted, fontSize: 9),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, size: 14, color: c.textMuted),
                                color: c.bgCard,
                                onSelected: (val) {
                                  if (val == 'copy') {
                                    Clipboard.setData(ClipboardData(text: tag.epc));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép mã EPC')));
                                  } else if (val == 'rw') {
                                    _fastTargetEpcController.text = tag.epc;
                                    _rwMatchEpcController.text = tag.epc;
                                    _tabController.animateTo(1);
                                  } else if (val == 'lock') {
                                    _lockTargetEpcController.text = tag.epc;
                                    _killTargetEpcController.text = tag.epc;
                                    _tabController.animateTo(2);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(value: 'copy', child: Text('📋 Sao chép EPC', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                  PopupMenuItem(value: 'rw', child: Text('✍️ Đọc / Ghi thẻ này', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                  PopupMenuItem(value: 'lock', child: Text('🔒 Khóa / Hủy thẻ này', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 2: MEMORY R/W ====================
  Widget _buildTabMemoryRw(EyeCareColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Bank Read / Write
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ĐỌC & GHI VÙNG NHỚ CHI TIẾT (GEN2)', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('Chọn Vùng nhớ (Memory Bank):', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.border)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _rwBank,
                        isExpanded: true,
                        dropdownColor: c.bgCard,
                        style: TextStyle(color: c.textPrimary, fontSize: 11),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1: EPC (Electronic Product Code)')),
                          DropdownMenuItem(value: 2, child: Text('2: TID (Tag Identifier - Read Only)')),
                          DropdownMenuItem(value: 3, child: Text('3: USER (Bộ nhớ người dùng)')),
                          DropdownMenuItem(value: 0, child: Text('0: RESERVED (Mật khẩu Kill & Access)')),
                        ],
                        onChanged: (v) => setState(() => _rwBank = v ?? 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Word Offset (ptr):', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 34,
                              child: TextField(
                                controller: _rwOffsetController,
                                style: TextStyle(color: c.textPrimary, fontSize: 12),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  filled: true,
                                  fillColor: c.bgCard,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Word Count (cnt):', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 34,
                              child: TextField(
                                controller: _rwCountController,
                                style: TextStyle(color: c.textPrimary, fontSize: 12),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  filled: true,
                                  fillColor: c.bgCard,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Dữ liệu Hex (Kết quả đọc / Dữ liệu ghi):', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _rwDataController,
                    maxLines: 2,
                    style: TextStyle(color: c.rfidCyan, fontSize: 11, fontFamily: 'Consolas'),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(8),
                      filled: true,
                      fillColor: c.bgCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final offset = int.tryParse(_rwOffsetController.text) ?? 2;
                          final count = int.tryParse(_rwCountController.text) ?? 6;
                          final res = await _uhfService.readMemoryBank(bank: _rwBank, offset: offset, count: count, matchEpc: _rwMatchEpcController.text);
                          _rwDataController.text = res;
                        },
                        icon: const Icon(Icons.download, size: 15),
                        label: const Text('ĐỌC DỮ LIỆU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.rfidCyan,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final offset = int.tryParse(_rwOffsetController.text) ?? 2;
                          await _uhfService.writeMemoryBank(bank: _rwBank, offset: offset, hexData: _rwDataController.text.trim(), matchEpc: _rwMatchEpcController.text);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi lệnh ghi thẻ thành công!')));
                        },
                        icon: const Icon(Icons.upload, size: 15),
                        label: const Text('GHI DỮ LIỆU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.successEmerald,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Right: Fast EPC Rewriter
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GHI ĐÈ MÃ EPC SIÊU TỐC (FAST COMMISSIONING)', style: TextStyle(color: c.successEmerald, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('Mã EPC thẻ cần đổi (Chọn từ bảng quét hoặc nhập):', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _fastTargetEpcController,
                      style: TextStyle(color: c.textPrimary, fontSize: 11, fontFamily: 'Consolas'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        filled: true,
                        fillColor: c.bgCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Mã EPC MỚI cần ghi (24 ký tự Hex = 96 bit):', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _fastNewEpcController,
                      style: TextStyle(color: c.successEmerald, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Consolas'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        filled: true,
                        fillColor: c.bgCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      final rnd = Random();
                      final bytes = List.generate(12, (_) => rnd.nextInt(256));
                      _fastNewEpcController.text = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
                    },
                    icon: const Icon(Icons.casino, size: 14),
                    label: const Text('Tạo mã EPC ngẫu nhiên', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (_fastNewEpcController.text.isEmpty) return;
                        await _uhfService.fastWriteEpc(_fastNewEpcController.text.trim(), oldEpc: _fastTargetEpcController.text.trim());
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã ghi đè EPC mới thành công!')));
                      },
                      icon: const Icon(Icons.bolt, size: 16),
                      label: const Text('GHI ĐÈ EPC MỚI NGAY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.successEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 3: SECURITY ====================
  Widget _buildTabSecurity(EyeCareColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lock Panel
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KHÓA VÙNG NHỚ THẺ (TAG MEMORY LOCK)', style: TextStyle(color: c.warningAmber, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('Mã EPC thẻ cần khóa:', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _lockTargetEpcController,
                      style: TextStyle(color: c.textPrimary, fontSize: 11, fontFamily: 'Consolas'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        filled: true,
                        fillColor: c.bgCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Vùng nhớ áp dụng:', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.border)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _lockArea,
                        isExpanded: true,
                        dropdownColor: c.bgCard,
                        style: TextStyle(color: c.textPrimary, fontSize: 11),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('User Memory')),
                          DropdownMenuItem(value: 1, child: Text('TID Memory')),
                          DropdownMenuItem(value: 2, child: Text('EPC Memory')),
                          DropdownMenuItem(value: 3, child: Text('Access Password')),
                          DropdownMenuItem(value: 4, child: Text('Kill Password')),
                        ],
                        onChanged: (v) => setState(() => _lockArea = v ?? 0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Thao tác khóa:', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.border)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _lockType,
                        isExpanded: true,
                        dropdownColor: c.bgCard,
                        style: TextStyle(color: c.textPrimary, fontSize: 11),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('0: Mở khóa (Unlock)')),
                          DropdownMenuItem(value: 1, child: Text('1: Khóa tạm (Lock)')),
                          DropdownMenuItem(value: 2, child: Text('2: Mở khóa vĩnh viễn (Permanent Unlock)')),
                          DropdownMenuItem(value: 3, child: Text('3: Khóa vĩnh viễn (Permanent Lock)')),
                        ],
                        onChanged: (v) => setState(() => _lockType = v ?? 0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _uhfService.lockTag(area: _lockArea, lockType: _lockType, password: _lockPasswordController.text, matchEpc: _lockTargetEpcController.text);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã thiết lập khóa thẻ thành công!')));
                    },
                    icon: const Icon(Icons.lock, size: 15),
                    label: const Text('THIẾT LẬP KHÓA THẺ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.warningAmber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Kill Panel
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HỦY THẺ VĨNH VIỄN (TAG DESTROY / KILL)', style: TextStyle(color: c.errorCoral, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: c.errorCoral.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.errorCoral.withValues(alpha: 0.5))),
                    child: Text('⚠️ CẢNH BÁO: Lệnh Kill sẽ vô hiệu hóa chip RFID vĩnh viễn! Chỉ dùng khi thanh lý tài sản.', style: TextStyle(color: c.errorCoral, fontSize: 10)),
                  ),
                  const SizedBox(height: 8),
                  Text('Mã EPC thẻ cần hủy:', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _killTargetEpcController,
                      style: TextStyle(color: c.textPrimary, fontSize: 11, fontFamily: 'Consolas'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        filled: true,
                        fillColor: c.bgCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Mật khẩu hủy (Kill Password - 8 Hex chars):', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _killPasswordController,
                      style: TextStyle(color: c.textPrimary, fontSize: 11, fontFamily: 'Consolas'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        filled: true,
                        fillColor: c.bgCard,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: c.bgCard,
                          title: Text('XÁC NHẬN HỦY THẺ', style: TextStyle(color: c.errorCoral, fontWeight: FontWeight.bold)),
                          content: Text('Bạn có chắc chắn muốn hủy vĩnh viễn thẻ này không?', style: TextStyle(color: c.textPrimary)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textSecondary))),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral), child: const Text('HỦY THẺ', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold))),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await _uhfService.killTag(killPassword: _killPasswordController.text, matchEpc: _killTargetEpcController.text);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã hủy thẻ vĩnh viễn!')));
                      }
                    },
                    icon: const Icon(Icons.delete_forever, size: 15),
                    label: const Text('💥 HỦY THẺ VĨNH VIỄN (KILL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.errorCoral,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 4: LAN MANAGER ====================
  Widget _buildTabLanManager(EyeCareColors c) {
    final readers = _uhfService.discoveredReaders;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _uhfService.searchLanReaders(),
                icon: const Icon(Icons.search, size: 15),
                label: const Text('TÌM ĐẦU ĐỌC TRONG MẠNG LAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.rfidCyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _uhfService.resetReader(),
                icon: const Icon(Icons.restart_alt, size: 15),
                label: const Text('KHỞI ĐỘNG LẠI TỪ XA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.errorCoral,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Discovered Readers List
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
              child: readers.isEmpty
                  ? Center(child: Text('Chưa tìm thấy thiết bị. Nhấn "TÌM ĐẦU ĐỌC TRONG MẠNG LAN".', style: TextStyle(color: c.textMuted, fontSize: 12)))
                  : ListView.builder(
                      itemCount: readers.length,
                      itemBuilder: (context, idx) {
                        final r = readers[idx];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: c.bgCard, border: Border(bottom: BorderSide(color: c.border))),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: c.rfidCyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                child: Icon(Icons.router, color: c.rfidCyan, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.deviceType, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text('IP: ${r.ip}  |  MAC: ${r.mac}  |  Port: ${r.port}  |  Mode: ${r.workMode}', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  _ipController.text = r.ip;
                                  _portController.text = r.port;
                                  _selectedConnType = 'TCP Client';
                                  _uhfService.connectTcp(r.ip, int.tryParse(r.port) ?? 9090);
                                  _tabController.animateTo(0); // Go back to Live Inventory
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: c.successEmerald,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                child: const Text('KẾT NỐI NGAY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 4. CONSOLE LOG ====================
  Widget _buildConsoleLog(EyeCareColors c) {
    return Container(
      height: 105,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('📋 NHẬT KÝ HOẠT ĐỘNG (SYSTEM LOG):', style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => _autoScrollLog = !_autoScrollLog),
                    child: Row(
                      children: [
                        Icon(_autoScrollLog ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: c.rfidCyan),
                        const SizedBox(width: 4),
                        Text('Tự cuộn', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => setState(() => _logLines.clear()),
                    child: Text('Xóa Log', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border.withValues(alpha: 0.5)),
              ),
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _logLines.length,
                itemBuilder: (context, idx) {
                  final line = _logLines[idx];
                  Color color = c.rfidCyan;
                  if (line.contains('Lỗi') || line.contains('Failed') || line.contains('Error')) {
                    color = c.errorCoral;
                  } else if (line.contains('thành công') || line.contains('Success') || line.contains('BẮT ĐẦU')) {
                    color = c.successEmerald;
                  }
                  return Text(line, style: TextStyle(color: color, fontSize: 10, fontFamily: 'Consolas'));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
