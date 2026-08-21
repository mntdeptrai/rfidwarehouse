import 'package:flutter/material.dart';
import '../services/uhf_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UhfService _uhfService = UhfService();
  late double _currentPower;
  late int _selectedRegion;
  bool _isSaving = false;

  final List<Map<String, dynamic>> _regions = [
    {'id': 1, 'name': 'China (920 - 925 MHz)'},
    {'id': 2, 'name': 'USA / FCC (902 - 928 MHz)'},
    {'id': 3, 'name': 'Europe / ETSI (865 - 868 MHz)'},
    {'id': 4, 'name': 'Korea (917 - 923.5 MHz)'},
    {'id': 5, 'name': 'Japan (916.8 - 920.8 MHz)'},
  ];

  @override
  void initState() {
    super.initState();
    _currentPower = _uhfService.rfPower.toDouble().clamp(1.0, 33.0);
    _selectedRegion = _uhfService.frequencyMode > 0 ? _uhfService.frequencyMode : 1;
    _uhfService.addListener(_onUhfUpdate);
  }

  @override
  void dispose() {
    _uhfService.removeListener(_onUhfUpdate);
    super.dispose();
  }

  void _onUhfUpdate() {
    if (mounted) {
      setState(() {
        _currentPower = _uhfService.rfPower.toDouble().clamp(1.0, 33.0);
      });
    }
  }

  Future<void> _applyRfPower() async {
    setState(() => _isSaving = true);
    final success = await _uhfService.setRfPower(_currentPower.toInt());
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Đã lưu công suất RF: ${_currentPower.toInt()} dBm' : 'Lỗi cài đặt công suất!'),
          backgroundColor: success ? const Color(0xFF059669) : const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _applyRegion(int regionId) async {
    setState(() {
      _selectedRegion = regionId;
      _isSaving = true;
    });
    final success = await _uhfService.setFrequencyRegion(regionId);
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Đã đổi khu vực tần số thành công!' : 'Lỗi đổi khu vực tần số!'),
          backgroundColor: success ? const Color(0xFF059669) : const Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Cài Đặt Phần Cứng UHF',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // RF Power Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt, color: Color(0xFFF59E0B), size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Công suất phát sóng (RF Power)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${_currentPower.toInt()} dBm',
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFF59E0B),
                      inactiveTrackColor: const Color(0xFF334155),
                      thumbColor: const Color(0xFFF59E0B),
                      overlayColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _currentPower,
                      min: 1,
                      max: 33,
                      divisions: 32,
                      label: '${_currentPower.toInt()} dBm',
                      onChanged: (val) => setState(() => _currentPower = val),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('1 dBm - Gần ~10cm', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      Text('30/33 dBm - Xa ~5-10m', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('ÁP DỤNG CÔNG SUẤT RF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isSaving ? null : _applyRfPower,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Frequency Region Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.public, color: Color(0xFF38BDF8), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Khu vực tần số (Frequency Region)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E293B),
                        value: _selectedRegion,
                        items: _regions.map((r) {
                          return DropdownMenuItem<int>(
                            value: r['id'] as int,
                            child: Text(
                              r['name'] as String,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _applyRegion(val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Sound & Haptic Feedback
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Âm thanh & Phản hồi',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Âm thanh Beep khi quét thẻ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      value: _uhfService.soundEnabled,
                      activeThumbColor: const Color(0xFF38BDF8),
                      onChanged: (val) => setState(() => _uhfService.soundEnabled = val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rung phản hồi', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      value: _uhfService.hapticEnabled,
                      activeThumbColor: const Color(0xFF38BDF8),
                      onChanged: (val) => setState(() => _uhfService.hapticEnabled = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Device Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF34D399), size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Thông tin phần cứng RFID',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Color(0xFF38BDF8), size: 20),
                        tooltip: 'Làm mới',
                        onPressed: () async {
                          await _uhfService.refreshDeviceInfo();
                          setState(() {});
                        },
                      )
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  _buildInfoRow('Trạng thái khởi tạo', _uhfService.isInitialized ? '🟢 ĐÃ KẾT NỐI' : '🔴 CHƯA KẾT NỐI'),
                  _buildInfoRow('Phần cứng', _uhfService.hardwareVersion),
                  _buildInfoRow('Firmware module', _uhfService.firmwareVersion),
                  _buildInfoRow('Nhiệt độ chip RFID', '${_uhfService.temperature} °C'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('KHỞI TẠO LẠI PHẦN CỨNG'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await _uhfService.init();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
