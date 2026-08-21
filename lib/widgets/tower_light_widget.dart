import 'package:flutter/material.dart';
import '../services/tower_light_service.dart';

/// Widget hiển thị và mô phỏng Tháp Đèn Tín Hiệu Công Nghiệp CTP50-3T-D-J
class TowerLightWidget extends StatefulWidget {
  final bool compact;
  final bool showControls;

  const TowerLightWidget({
    super.key,
    this.compact = false,
    this.showControls = true,
  });

  @override
  State<TowerLightWidget> createState() => _TowerLightWidgetState();
}

class _TowerLightWidgetState extends State<TowerLightWidget> with SingleTickerProviderStateMixin {
  final TowerLightService _service = TowerLightService();
  late AnimationController _animController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onStatusChanged);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  void _onStatusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onStatusChanged);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _service.currentStatus;

    if (widget.compact) {
      return _buildCompactView(status);
    }

    return _buildFullPanel(status);
  }

  Widget _buildCompactView(TowerLightStatus status) {
    final Color badgeColor = switch (status.color) {
      TowerLightColor.red => const Color(0xFFEF4444),
      TowerLightColor.yellow => const Color(0xFFF59E0B),
      TowerLightColor.green => const Color(0xFF10B981),
      TowerLightColor.off => const Color(0xFF64748B),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMiniLamp(const Color(0xFFEF4444), status.isRed),
          const SizedBox(width: 4),
          _buildMiniLamp(const Color(0xFFF59E0B), status.isYellow),
          const SizedBox(width: 4),
          _buildMiniLamp(const Color(0xFF10B981), status.isGreen),
          const SizedBox(width: 8),
          Text(
            status.reason,
            style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          if (status.isBuzzerOn) ...[
            const SizedBox(width: 6),
            const Icon(Icons.volume_up, color: Color(0xFFEF4444), size: 14),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniLamp(Color color, bool isActive) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final opacity = isActive ? _glowAnimation.value : 0.2;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
        );
      },
    );
  }

  Widget _buildFullPanel(TowerLightStatus status) {
    final Color activeThemeColor = switch (status.color) {
      TowerLightColor.red => const Color(0xFFEF4444),
      TowerLightColor.yellow => const Color(0xFFF59E0B),
      TowerLightColor.green => const Color(0xFF10B981),
      TowerLightColor.off => const Color(0xFF334155),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: activeThemeColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: status.color != TowerLightColor.off
            ? [
                BoxShadow(
                  color: activeThemeColor.withValues(alpha: 0.15),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.traffic, color: Color(0xFF38BDF8), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THÁP ĐÈN TÍN HIỆU CTP50-3T-D-J',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    Text(
                      'Đỏ: Thiếu/Sai hàng | Vàng: Lỗi hệ thống | Xanh: Đủ hàng',
                      style: TextStyle(color: Colors.white54, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sơ đồ đấu dây & Cấu hình GPO',
                icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 18),
                onPressed: _showSettingsAndWiringDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Tower Graphic + Current Status Banner
          Row(
            children: [
              // Visual Tower Light
              _buildRealisticTowerGraphic(status),
              const SizedBox(width: 16),

              // Status Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: activeThemeColor.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: activeThemeColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _getStatusTitle(status.color),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: activeThemeColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (status.isBuzzerOn) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFEF4444)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.volume_up, color: Color(0xFFEF4444), size: 11),
                                      SizedBox(width: 2),
                                      Text('CÒI KÊU', style: TextStyle(color: Color(0xFFEF4444), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            status.reason,
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Control & Test Buttons
          if (widget.showControls) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildTestButton(
                  label: 'Test ĐỎ (Thiếu/Sai)',
                  color: const Color(0xFFEF4444),
                  icon: Icons.error_outline,
                  onTap: () => _service.manualTest(
                    color: TowerLightColor.red,
                    buzzer: true,
                    testReason: 'Thử nghiệm: Thiếu hàng / Sai mã chip',
                  ),
                ),
                _buildTestButton(
                  label: 'Test VÀNG (Lỗi HT)',
                  color: const Color(0xFFF59E0B),
                  icon: Icons.warning_amber_outlined,
                  onTap: () => _service.manualTest(
                    color: TowerLightColor.yellow,
                    buzzer: false,
                    testReason: 'Thử nghiệm: Lỗi hệ thống / Mất kết nối',
                  ),
                ),
                _buildTestButton(
                  label: 'Test XANH (Đủ hàng)',
                  color: const Color(0xFF10B981),
                  icon: Icons.check_circle_outline,
                  onTap: () => _service.manualTest(
                    color: TowerLightColor.green,
                    buzzer: false,
                    testReason: 'Thử nghiệm: Đủ hàng 100% - Thông qua',
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white60,
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.power_settings_new, size: 14),
                  label: const Text('Tắt Tháp Đèn', style: TextStyle(fontSize: 11)),
                  onPressed: () => _service.turnOffAll(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      onPressed: onTap,
    );
  }

  Widget _buildRealisticTowerGraphic(TowerLightStatus status) {
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cap
          Container(
            width: 24,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF475569),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              border: Border.all(color: const Color(0xFF64748B), width: 0.5),
            ),
          ),
          const SizedBox(height: 2),

          // Red Tier (Top)
          _buildTowerTier(
            color: const Color(0xFFEF4444),
            isActive: status.isRed,
            label: '🔴',
          ),
          const SizedBox(height: 2),

          // Yellow Tier (Middle)
          _buildTowerTier(
            color: const Color(0xFFF59E0B),
            isActive: status.isYellow,
            label: '🟡',
          ),
          const SizedBox(height: 2),

          // Green Tier (Bottom)
          _buildTowerTier(
            color: const Color(0xFF10B981),
            isActive: status.isGreen,
            label: '🟢',
          ),
          const SizedBox(height: 2),

          // Buzzer / Base segment
          Container(
            width: 26,
            height: 10,
            decoration: BoxDecoration(
              color: status.isBuzzerOn ? const Color(0xFFEF4444).withValues(alpha: 0.4) : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: status.isBuzzerOn ? const Color(0xFFEF4444) : const Color(0xFF475569), width: 0.5),
            ),
            child: Icon(
              Icons.volume_up,
              size: 8,
              color: status.isBuzzerOn ? const Color(0xFFEF4444) : Colors.white24,
            ),
          ),
          // Pole
          Container(
            width: 8,
            height: 14,
            color: const Color(0xFF64748B),
          ),
          // Base
          Container(
            width: 32,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF475569), width: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTowerTier({
    required Color color,
    required bool isActive,
    required String label,
  }) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final glow = isActive ? _glowAnimation.value : 0.18;
        return Container(
          width: 28,
          height: 18,
          decoration: BoxDecoration(
            color: color.withValues(alpha: glow),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.3),
              width: isActive ? 1.5 : 0.8,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
        );
      },
    );
  }

  String _getStatusTitle(TowerLightColor color) {
    return switch (color) {
      TowerLightColor.red => '🔴 ĐÈN ĐỎ: THIẾU / SAI / THỪA HÀNG',
      TowerLightColor.yellow => '🟡 ĐÈN VÀNG: LỖI HỆ THỐNG',
      TowerLightColor.green => '🟢 ĐÈN XANH: ĐỦ HÀNG THÔNG QUA',
      TowerLightColor.off => '⚪ TRẠNG THÁI CHỜ (STANDBY)',
    };
  }

  void _showSettingsAndWiringDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.electrical_services, color: Color(0xFF38BDF8), size: 24),
              SizedBox(width: 10),
              Text('Cấu Hình & Sơ Đồ Đấu Dây CTP50-3T-D-J', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sơ đồ đấu dây
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🔌 SƠ ĐỒ ĐẤU DÂY THỰC TẾ (CTP50-3T-D-J)', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 8),
                        Table(
                          border: TableBorder.all(color: const Color(0xFF334155)),
                          columnWidths: const {
                            0: FlexColumnWidth(2),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(3),
                          },
                          children: const [
                            TableRow(
                              decoration: BoxDecoration(color: Color(0xFF1E293B)),
                              children: [
                                Padding(padding: EdgeInsets.all(6), child: Text('Màu Dây Tháp Đèn', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Cổng GPO / Rơ-le', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Logic Kích Hoạt Phần Mềm', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: EdgeInsets.all(6), child: Text('🔴 Dây ĐỎ (Red)', style: TextStyle(color: Colors.white, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('GPO 4 (L2 / Relay 4)', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Thiếu hàng, sai hàng, thừa hàng', style: TextStyle(color: Colors.white70, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: EdgeInsets.all(6), child: Text('🟢 Dây XANH (Green)', style: TextStyle(color: Colors.white, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('GPO 3 (L3 / Relay 3)', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Đủ hàng thông qua (100% khớp)', style: TextStyle(color: Colors.white70, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: EdgeInsets.all(6), child: Text('🟡 Dây VÀNG (Yellow)', style: TextStyle(color: Colors.white, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('GPO 2 (L4 / Relay 2)', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Cảnh báo / Lỗi hệ thống', style: TextStyle(color: Colors.white70, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: EdgeInsets.all(6), child: Text('🔊 Dây TÍM / Còi (Buzzer)', style: TextStyle(color: Colors.white, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('GPO 1 (Dự phòng / Rơ-le 1)', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Còi báo động khi đèn đỏ bật', style: TextStyle(color: Colors.white70, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: EdgeInsets.all(6), child: Text('⚡ Dây COM / Nguồn', style: TextStyle(color: Colors.white, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('COM / +24VDC (hoặc -V)', style: TextStyle(color: Colors.white, fontSize: 11))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Nguồn cấp nuôi tháp đèn CTP50', style: TextStyle(color: Colors.white70, fontSize: 11))),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Cấu hình chân GPO
                  const Text('⚙️ TÙY CHỈNH CHÂN CẮM GPO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildPinDropdown('Chân Đèn ĐỎ', _service.config.redPin, (val) => setDlgState(() => _service.config.redPin = val))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPinDropdown('Chân Đèn VÀNG', _service.config.yellowPin, (val) => setDlgState(() => _service.config.yellowPin = val))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPinDropdown('Chân Đèn XANH', _service.config.greenPin, (val) => setDlgState(() => _service.config.greenPin = val))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPinDropdown('Chân CÒI', _service.config.buzzerPin, (val) => setDlgState(() => _service.config.buzzerPin = val))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('Thời gian duy trì tín hiệu (Pulse):', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(width: 10),
                      DropdownButton<int>(
                        value: _service.config.pulseDurationSeconds,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Giữ liên tục (Không tự ngắt)')),
                          DropdownMenuItem(value: 2, child: Text('2 giây')),
                          DropdownMenuItem(value: 3, child: Text('3 giây (Khuyến nghị)')),
                          DropdownMenuItem(value: 5, child: Text('5 giây')),
                          DropdownMenuItem(value: 10, child: Text('10 giây')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => _service.config.pulseDurationSeconds = val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('LƯU & ĐÓNG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinDropdown(String label, int currentVal, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          initialValue: currentVal,
          dropdownColor: const Color(0xFF0F172A),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('GPO 1')),
            DropdownMenuItem(value: 2, child: Text('GPO 2')),
            DropdownMenuItem(value: 3, child: Text('GPO 3')),
            DropdownMenuItem(value: 4, child: Text('GPO 4')),
          ],
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ],
    );
  }
}
