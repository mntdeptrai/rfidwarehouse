import 'package:flutter/material.dart';
import '../services/tower_light_service.dart';
import '../theme/eye_care_theme.dart';

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
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  late AnimationController _animController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onStatusChanged);
    _eyeCare.addListener(_onStatusChanged);

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
    _eyeCare.removeListener(_onStatusChanged);
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _service.currentStatus;
    final c = _eyeCare.colors;

    if (widget.compact) {
      return _buildCompactView(status, c);
    }

    return _buildFullPanel(status, c);
  }

  Widget _buildCompactView(TowerLightStatus status, EyeCareColors c) {
    final Color badgeColor = switch (status.color) {
      TowerLightColor.red => const Color(0xFFEF4444),
      TowerLightColor.yellow => const Color(0xFFF59E0B),
      TowerLightColor.green => const Color(0xFF10B981),
      TowerLightColor.off => c.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
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

  Widget _buildFullPanel(TowerLightStatus status, EyeCareColors c) {
    final Color activeThemeColor = switch (status.color) {
      TowerLightColor.red => const Color(0xFFEF4444),
      TowerLightColor.yellow => const Color(0xFFF59E0B),
      TowerLightColor.green => const Color(0xFF10B981),
      TowerLightColor.off => c.border,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgCard,
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
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.traffic, color: c.rfidCyan, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THÁP ĐÈN TÍN HIỆU CTP50-3T-D-J',
                      style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    Text(
                      'Đỏ: Thiếu/Sai hàng | Vàng: Lỗi hệ thống | Xanh: Đủ hàng',
                      style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sơ đồ đấu dây & Cấu hình GPO',
                icon: Icon(Icons.settings_outlined, color: c.textSecondary, size: 18),
                onPressed: () => _showSettingsAndWiringDialog(c),
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
                        color: c.bgCardElevated,
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
                            style: TextStyle(color: c.textPrimary, fontSize: 11.5, height: 1.3),
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
            Divider(color: c.border, height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildTestButton(
                  label: 'Test ĐỎ - Thiếu/Sai',
                  color: const Color(0xFFEF4444),
                  icon: Icons.error_outline,
                  onTap: () => _service.manualTest(
                    color: TowerLightColor.red,
                    buzzer: true,
                    testReason: 'Thử nghiệm: Thiếu hàng / Sai mã chip',
                  ),
                ),
                _buildTestButton(
                  label: 'Test VÀNG - Lỗi HT',
                  color: const Color(0xFFF59E0B),
                  icon: Icons.warning_amber_outlined,
                  onTap: () => _service.manualTest(
                    color: TowerLightColor.yellow,
                    buzzer: false,
                    testReason: 'Thử nghiệm: Lỗi hệ thống / Mất kết nối',
                  ),
                ),
                _buildTestButton(
                  label: 'Test XANH - Đủ hàng',
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
                    foregroundColor: c.textSecondary,
                    side: BorderSide(color: c.border),
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

  Widget _buildRealisticTowerGraphic(TowerLightStatus status) {
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFE6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC7BDAF)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cap đỉnh tháp
          Container(
            width: 32,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFFB5A999),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              border: Border.all(color: const Color(0xFF64748B), width: 0.5),
            ),
          ),

          // Đèn ĐỎ
          _buildTowerLampSection(
            color: const Color(0xFFEF4444),
            isActive: status.isRed,
            isBlinking: status.isRedBlinking,
            tag: 'RED',
          ),

          // Khớp nối đen
          _buildCoupler(),

          // Đèn VÀNG
          _buildTowerLampSection(
            color: const Color(0xFFF59E0B),
            isActive: status.isYellow,
            isBlinking: status.isYellowBlinking,
            tag: 'YEL',
          ),

          // Khớp nối đen
          _buildCoupler(),

          // Đèn XANH
          _buildTowerLampSection(
            color: const Color(0xFF10B981),
            isActive: status.isGreen,
            isBlinking: status.isGreenBlinking,
            tag: 'GRN',
          ),

          // Khớp nối đen
          _buildCoupler(),

          // Đế còi Buzzer
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE9E2D5),
              border: Border.all(color: const Color(0xFFB5A999)),
            ),
            child: Icon(
              Icons.volume_up,
              size: 14,
              color: status.isBuzzerOn ? const Color(0xFFEF4444) : Colors.white30,
            ),
          ),

          // Thân trụ nhôm (Aluminum pole)
          Container(
            width: 8,
            height: 14,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF94A3B8), Color(0xFFCBD5E1), Color(0xFF64748B)],
              ),
            ),
          ),

          // Đế kim loại bắt ốc (Mounting base)
          Container(
            width: 34,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFFC7BDAF),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoupler() {
    return Container(
      width: 38,
      height: 3,
      color: const Color(0xFFF4EFE6),
    );
  }

  Widget _buildTowerLampSection({
    required Color color,
    required bool isActive,
    required bool isBlinking,
    required String tag,
  }) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final double opacity = isActive
            ? (isBlinking ? _glowAnimation.value : 0.95)
            : 0.22;

        return Container(
          width: 36,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(4),
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
          child: Center(
            child: Container(
              width: 18,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: isActive ? 0.7 : 0.1),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      },
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
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
      ),
      icon: Icon(icon, size: 13, color: color),
      label: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
      ),
      onPressed: onTap,
    );
  }

  String _getStatusTitle(TowerLightColor color) {
    return switch (color) {
      TowerLightColor.red => '🔴 ĐÈN ĐỎ: THIẾU / SAI / THỪA HÀNG',
      TowerLightColor.yellow => '🟡 ĐÈN VÀNG: LỖI HỆ THỐNG',
      TowerLightColor.green => '🟢 ĐÈN XANH: ĐỦ HÀNG THÔNG QUA',
      TowerLightColor.off => '⚪ TRẠNG THÁI CHỜ - STANDBY',
    };
  }

  void _showSettingsAndWiringDialog(EyeCareColors c) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.electrical_services, color: c.rfidCyan, size: 24),
              const SizedBox(width: 10),
              Text('Cấu Hình & Sơ Đồ Đấu Dây CTP50-3T-D-J', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
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
                      color: c.bgCardElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🔌 SƠ ĐỒ ĐẤU DÂY THỰC TẾ CTP50-3T-D-J', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 8),
                        Table(
                          border: TableBorder.all(color: c.border),
                          columnWidths: const {
                            0: FlexColumnWidth(2),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(3),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: c.bgCard),
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text('Màu Dây Tháp Đèn', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('Cổng GPO / Rơ-le', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('Logic Kích Hoạt Phần Mềm', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text('🔴 Dây ĐỎ - Red', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                const Padding(padding: EdgeInsets.all(6), child: Text('GPO 4 - L2 / Relay 4', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('Thiếu hàng, sai hàng, thừa hàng', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text('🟢 Dây XANH - Green', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                const Padding(padding: EdgeInsets.all(6), child: Text('GPO 3 - L3 / Relay 3', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('Đủ hàng thông qua - 100% khớp', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text('🟡 Dây VÀNG - Yellow', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                const Padding(padding: EdgeInsets.all(6), child: Text('GPO 2 - L4 / Relay 2', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('Cảnh báo / Lỗi hệ thống', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text('🔊 Dây TÍM - Còi Buzzer', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('GPO 1 - Dự phòng / Rơ-le 1', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('Còi báo động khi đèn đỏ bật', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                              ],
                            ),
                            TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text('⚡ Dây COM / Nguồn', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('COM / +24VDC', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('Nguồn cấp nuôi tháp đèn CTP50', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Cấu hình chân GPO
                  Text('⚙️ TÙY CHỈNH CHÂN CẮM GPO', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildPinDropdown('Chân Đèn ĐỎ', _service.config.redPin, (val) => setDlgState(() => _service.config.redPin = val), c)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPinDropdown('Chân Đèn VÀNG', _service.config.yellowPin, (val) => setDlgState(() => _service.config.yellowPin = val), c)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPinDropdown('Chân Đèn XANH', _service.config.greenPin, (val) => setDlgState(() => _service.config.greenPin = val), c)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPinDropdown('Chân CÒI', _service.config.buzzerPin, (val) => setDlgState(() => _service.config.buzzerPin = val), c)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Thời gian duy trì tín hiệu:', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                      const SizedBox(width: 10),
                      DropdownButton<int>(
                        value: _service.config.pulseDurationSeconds,
                        dropdownColor: c.bgCardElevated,
                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Giữ liên tục - Không tự ngắt')),
                          DropdownMenuItem(value: 2, child: Text('2 giây')),
                          DropdownMenuItem(value: 3, child: Text('3 giây - Khuyến nghị')),
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
              child: const Text('LƯU & ĐÓNG', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinDropdown(String label, int currentVal, ValueChanged<int> onChanged, EyeCareColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          initialValue: currentVal,
          dropdownColor: c.bgCardElevated,
          style: TextStyle(color: c.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            filled: true,
            fillColor: c.bgCardElevated,
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
