import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/mysql_sync_service.dart';
import '../../theme/eye_care_theme.dart';

class PdaMySqlSyncScreen extends StatefulWidget {
  const PdaMySqlSyncScreen({super.key});

  @override
  State<PdaMySqlSyncScreen> createState() => _PdaMySqlSyncScreenState();
}

class _PdaMySqlSyncScreenState extends State<PdaMySqlSyncScreen> {
  final _syncService = MySqlSyncService();
  final _eyeCare = EyeCareThemeService();

  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _dbController;
  late TextEditingController _userController;
  late TextEditingController _passController;

  bool _isTesting = false;
  bool _isSyncing = false;
  bool _obscurePass = true;
  String? _testMessage;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: _syncService.config.host);
    _portController = TextEditingController(text: _syncService.config.port.toString());
    _dbController = TextEditingController(text: _syncService.config.database);
    _userController = TextEditingController(text: _syncService.config.username);
    _passController = TextEditingController(text: _syncService.config.password);

    _syncService.addListener(_onSyncUpdate);
    _eyeCare.addListener(_onSyncUpdate);
  }

  void _onSyncUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncService.removeListener(_onSyncUpdate);
    _eyeCare.removeListener(_onSyncUpdate);
    _hostController.dispose();
    _portController.dispose();
    _dbController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final port = int.tryParse(_portController.text.trim()) ?? 3306;
    await _syncService.updateConfig(
      host: _hostController.text.trim(),
      port: port,
      database: _dbController.text.trim(),
      username: _userController.text.trim(),
      password: _passController.text,
      isAutoSync: _syncService.config.isAutoSync,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('Đã lưu cấu hình máy chủ MySQL thành công!'),
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testMessage = null;
      _testSuccess = null;
    });

    await _saveConfig();
    final res = await _syncService.testConnection();

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testSuccess = res['success'] as bool;
      _testMessage = res['message'] as String;
    });
  }

  Future<void> _triggerSync() async {
    setState(() => _isSyncing = true);
    final success = await _syncService.syncNow();
    if (!mounted) return;
    setState(() => _isSyncing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        content: Text(
          success
              ? 'Đồng bộ dữ liệu SQLite <-> MySQL thành công!'
              : 'Mất kết nối MySQL. Dữ liệu đang được lưu tạm an toàn trong SQLite.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final isOnline = _syncService.isOnline;
    final pendingCount = _syncService.pendingCount;
    final lastSync = _syncService.lastSyncTime;
    final timeStr = lastSync != null ? DateFormat('HH:mm:ss dd/MM').format(lastSync) : 'Chưa đồng bộ';

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: AppBar(
        backgroundColor: c.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Đồng Bộ SQLite <-> MySQL',
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới kết nối',
            icon: Icon(Icons.refresh, color: c.textSecondary),
            onPressed: () => _syncService.checkConnectivity(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Status Banner Card
            Builder(
              builder: (context) {
                final isWifi = _syncService.isWifiConnected;
                final pdaIp = _syncService.pdaIpAddress;
                final Color statusColor = isOnline
                    ? c.successEmerald
                    : (isWifi ? c.rfidCyan : c.warningAmber);

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isOnline
                                  ? Icons.cloud_done
                                  : (isWifi ? Icons.wifi : Icons.cloud_off),
                              color: statusColor,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isOnline
                                      ? 'CHẾ ĐỘ ONLINE (ĐÃ KẾT NỐI MYSQL)'
                                      : (isWifi
                                          ? 'ĐÃ KẾT NỐI WI-FI (IP: ${pdaIp.isNotEmpty ? pdaIp : "OK"})'
                                          : 'CHẾ ĐỘ OFFLINE (LƯU TẠM SQLITE)'),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isOnline
                                      ? 'Sẵn sàng đẩy dữ liệu lên máy chủ MySQL trung tâm'
                                      : (isWifi
                                          ? 'Đã có Wi-Fi nhưng chưa kết nối tới MySQL ${_syncService.config.host}:${_syncService.config.port}. Hãy nhập đúng IP máy tính bên dưới.'
                                          : 'Mọi thao tác quét kho được lưu trong SQLite cục bộ'),
                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Divider(color: c.border, height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Chờ đồng bộ:', style: TextStyle(color: c.textMuted, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                '$pendingCount bản ghi',
                                style: TextStyle(
                                  color: pendingCount > 0 ? c.warningAmber : c.successEmerald,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Đồng bộ gần nhất:', style: TextStyle(color: c.textMuted, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(timeStr, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.rfidCyan,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: _isSyncing || _syncService.isSyncing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.sync, color: Colors.white, size: 20),
                          label: Text(
                            _isSyncing || _syncService.isSyncing ? 'ĐANG ĐỒNG BỘ...' : 'ĐỒNG BỘ NGAY (SQLITE ⇋ MYSQL)',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: (_isSyncing || _syncService.isSyncing) ? null : _triggerSync,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // 2. MySQL Configuration Panel
            Container(
              padding: const EdgeInsets.all(16),
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
                      Icon(Icons.settings, color: c.rfidCyan, size: 18),
                      const SizedBox(width: 8),
                      Text('CẤU HÌNH MÁY CHỦ MYSQL', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  if (_syncService.isWifiConnected && _syncService.pdaIpAddress.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: c.rfidCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi, color: c.rfidCyan, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'IP Wi-Fi của tay cầm PDA: ${_syncService.pdaIpAddress}\n(Nhập IP máy tính cùng mạng Wi-Fi này vào ô bên dưới)',
                              style: TextStyle(color: c.rfidCyan, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildTextField(
                          controller: _hostController,
                          label: 'Địa chỉ IP / Host Máy chủ',
                          hint: '192.168.1.104',
                          icon: Icons.dns,
                          colors: c,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: _portController,
                          label: 'Cổng (Port)',
                          hint: '3306',
                          icon: Icons.numbers,
                          isNumber: true,
                          colors: c,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _dbController,
                    label: 'Tên Database MySQL',
                    hint: 'rfidwarehouse',
                    icon: Icons.storage,
                    colors: c,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _userController,
                          label: 'Tài khoản (User)',
                          hint: 'root',
                          icon: Icons.person,
                          colors: c,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildTextField(
                          controller: _passController,
                          label: 'Mật khẩu (Password)',
                          hint: '••••••',
                          icon: Icons.lock,
                          obscure: _obscurePass,
                          colors: c,
                          suffix: GestureDetector(
                            onTap: () => setState(() => _obscurePass = !_obscurePass),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(
                                _obscurePass ? Icons.visibility : Icons.visibility_off,
                                color: c.textMuted,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tự động đồng bộ khi có Wi-Fi', style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                            Text('Tự động nhận diện Wi-Fi & đồng bộ ngay không cần ấn nút', style: TextStyle(color: c.textMuted, fontSize: 10)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _syncService.config.isAutoSync,
                        activeTrackColor: c.successEmerald,
                        activeThumbColor: Colors.white,
                        onChanged: (val) {
                          setState(() {
                            _syncService.config.isAutoSync = val;
                          });
                          _saveConfig();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.rfidCyan,
                            side: BorderSide(color: c.rfidCyan),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: _isTesting
                              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: c.rfidCyan, strokeWidth: 2))
                              : const Icon(Icons.network_ping, size: 18),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_isTesting ? 'ĐANG THỬ...' : 'KIỂM TRA KẾT NỐI', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          onPressed: _isTesting ? null : _testConnection,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.successEmerald,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.save, color: Colors.white, size: 18),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('LƯU CẤU HÌNH', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          onPressed: _saveConfig,
                        ),
                      ),
                    ],
                  ),
                  if (_testMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _testSuccess == true ? c.successEmerald.withValues(alpha: 0.15) : c.errorCoral.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _testSuccess == true ? c.successEmerald : c.errorCoral),
                      ),
                      child: Row(
                        children: [
                          Icon(_testSuccess == true ? Icons.check_circle : Icons.error, color: _testSuccess == true ? c.successEmerald : c.errorCoral, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testMessage!,
                              style: TextStyle(color: _testSuccess == true ? c.successEmerald : c.errorCoral, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Live Sync Logs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('NHẬT KÝ ĐỒNG BỘ (SYNC LOGS)', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
                if (_syncService.logs.isNotEmpty)
                  TextButton(
                    onPressed: () => _syncService.clearLogs(),
                    child: Text('Xóa nhật ký', style: TextStyle(color: c.errorCoral, fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_syncService.logs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Center(
                  child: Text('Chưa có lịch sử đồng bộ', style: TextStyle(color: c.textMuted, fontSize: 12)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _syncService.logs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (ctx, idx) {
                  final log = _syncService.logs[idx];
                  Color tagColor = c.rfidCyan;
                  if (log.action == 'PUSH') tagColor = c.successEmerald;
                  if (log.action == 'ERROR') tagColor = c.errorCoral;
                  if (log.action == 'CONNECT') tagColor = c.warningAmber;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: tagColor),
                          ),
                          child: Text(log.action, style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log.message, style: TextStyle(color: c.textPrimary, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('HH:mm:ss dd/MM').format(log.timestamp),
                                style: TextStyle(color: c.textMuted, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required EyeCareColors colors,
    bool isNumber = false,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
            prefixIcon: Icon(icon, color: colors.rfidCyan, size: 16),
            prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 24),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            filled: true,
            fillColor: colors.bgCardElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.rfidCyan, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

