import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';

/// Bản ghi lịch sử gộp pallet trong phiên làm việc của PDA
class PalletMergeRecord {
  final String sourcePalletCode;
  final String targetPalletCode;
  final int itemCount;
  final String targetLocationName;
  final DateTime timestamp;

  PalletMergeRecord({
    required this.sourcePalletCode,
    required this.targetPalletCode,
    required this.itemCount,
    required this.targetLocationName,
    required this.timestamp,
  });
}

class PdaMergePalletsScreen extends StatefulWidget {
  final Pallet? initialSourcePallet;

  const PdaMergePalletsScreen({
    super.key,
    this.initialSourcePallet,
  });

  @override
  State<PdaMergePalletsScreen> createState() => PdaMergePalletsScreenState();
}

class PdaMergePalletsScreenState extends State<PdaMergePalletsScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final AuthService _auth = AuthService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  Pallet? _sourcePallet;
  Pallet? _targetPallet;
  bool _deleteSourcePallet = false;
  bool _isProcessing = false;

  Timer? _resetTimer;
  PalletMergeRecord? _lastMergedRecord;
  final List<PalletMergeRecord> _recentMerges = [];

  StreamSubscription<String>? _barcodeSub;
  StreamSubscription<TagInfo>? _rfidSub;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);

    if (widget.initialSourcePallet != null) {
      _sourcePallet = widget.initialSourcePallet;
    }

    // Đặt chế độ quét kết hợp Barcode & RFID trên PDA
    _uhf.setScanMode(PdaScanMode.auto);

    // Lắng nghe súng quét Barcode PDA
    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      _handleIncomingScan(barcode);
    });

    // Lắng nghe đầu đọc RFID PDA
    _rfidSub = _uhf.onTagRead.listen((tag) {
      _handleIncomingScan(tag.epc);
    });
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _barcodeSub?.cancel();
    _rfidSub?.cancel();
    super.dispose();
  }

  @visibleForTesting
  Future<void> handleIncomingScan(String rawCode) => _handleIncomingScan(rawCode);

  /// Xử lý mã Barcode hoặc RFID quét được từ PDA
  Future<void> _handleIncomingScan(String rawCode) async {
    if (_isProcessing) return; // Đang chạy gộp thì không nhận thêm

    final clean = rawCode.trim().toUpperCase();
    if (clean.isEmpty) return;

    // Nếu vừa gộp xong và đang chạy hẹn giờ dọn màn hình, hủy hẹn giờ để quét cặp mới ngay
    if (_resetTimer != null && _resetTimer!.isActive) {
      _resetTimer?.cancel();
      _resetTimer = null;
      setState(() {
        _sourcePallet = null;
        _targetPallet = null;
      });
    }

    // Tìm kiếm Pallet theo mã Pallet, ID hoặc RFID EPC trong kho
    final found = _repo.pallets.where((p) {
      return p.palletCode.toUpperCase() == clean ||
          p.palletId.toUpperCase() == clean ||
          (p.rfidEpc != null && p.rfidEpc!.toUpperCase() == clean);
    }).firstOrNull;

    if (found == null) {
      _showFeedbackSnackBar('Không tìm thấy Pallet nào khớp với mã: $clean', isError: true);
      HapticFeedback.vibrate();
      return;
    }

    // 1. NẾU CHƯA CÓ PALLET NGUỒN -> GÁN LÀM PALLET NGUỒN
    if (_sourcePallet == null) {
      final items = _repo.items.where((it) => it.palletId == found.palletId).length;
      if (items == 0) {
        _showFeedbackSnackBar('Pallet [${found.palletCode}] đang rỗng, không thể làm Pallet nguồn để gộp!', isError: true);
        HapticFeedback.vibrate();
        return;
      }
      setState(() {
        _sourcePallet = found;
        _targetPallet = null;
      });
      HapticFeedback.lightImpact();
      _showFeedbackSnackBar('Đã nhận Nguồn: ${found.palletCode} ($items SP). MỜI QUÉT PALLET ĐÍCH ĐỂ TỰ ĐỘNG GỘP ⚡');
      return;
    }

    // 2. NẾU ĐÃ CÓ PALLET NGUỒN -> GÁN LÀM PALLET ĐÍCH VÀ TỰ ĐỘNG GỘP NGAY
    if (found.palletId == _sourcePallet!.palletId) {
      _showFeedbackSnackBar('Pallet đích không thể trùng với Pallet nguồn!', isError: true);
      HapticFeedback.vibrate();
      return;
    }

    setState(() {
      _targetPallet = found;
    });
    HapticFeedback.mediumImpact();

    // ⚡ TỰ ĐỘNG GỘP NGAY LẬP TỨC KHÔNG CẦN THAO TÁC BẤM NÚT
    await _executeAutoMerge();
  }

  /// Tự động thực hiện gộp dữ liệu hàng hóa từ Pallet nguồn sang Pallet đích
  Future<void> _executeAutoMerge() async {
    if (_sourcePallet == null || _targetPallet == null || _isProcessing) return;

    final sourcePallet = _sourcePallet!;
    final targetPallet = _targetPallet!;
    final sourceCode = sourcePallet.palletCode;
    final targetCode = targetPallet.palletCode;
    final targetLocName = _getLocationName(targetPallet.locationId);
    final sourceItemsCount = _repo.items.where((it) => it.palletId == sourcePallet.palletId).length;

    setState(() => _isProcessing = true);
    final user = _auth.currentUser;
    final performedBy = user?.fullName ?? user?.username ?? 'Thủ kho PDA';

    try {
      final success = await _repo.mergePallets(
        sourcePalletId: sourcePallet.palletId,
        targetPalletId: targetPallet.palletId,
        performedBy: performedBy,
        deleteSourcePallet: _deleteSourcePallet,
      );

      if (success && mounted) {
        HapticFeedback.heavyImpact();

        final record = PalletMergeRecord(
          sourcePalletCode: sourceCode,
          targetPalletCode: targetCode,
          itemCount: sourceItemsCount,
          targetLocationName: targetLocName,
          timestamp: DateTime.now(),
        );

        setState(() {
          _recentMerges.insert(0, record);
          _lastMergedRecord = record;
        });

        _showFeedbackSnackBar(
          '⚡ ĐÃ TỰ ĐỘNG GỘP $sourceItemsCount SP: [$sourceCode] ➔ [$targetCode] (Kệ: $targetLocName)',
          isSuccess: true,
        );

        // Hẹn giờ tự động dọn màn hình sau 2 giây để sẵn sàng quét cặp pallet tiếp theo hands-free
        _resetTimer?.cancel();
        _resetTimer = Timer(const Duration(milliseconds: 2000), () {
          if (mounted) {
            setState(() {
              _sourcePallet = null;
              _targetPallet = null;
            });
          }
        });
      }
    } catch (e, st) {
      debugPrint('EXECUTE_AUTO_MERGE_ERROR: $e\n$st');
      if (mounted) {
        _showFeedbackSnackBar('Lỗi gộp Pallet: $e', isError: true);
        HapticFeedback.vibrate();
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showFeedbackSnackBar(String msg, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    final c = _eyeCare.colors;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : (isSuccess ? const Color(0xFF10B981) : c.rfidCyan),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : (isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Item> _getSourceItems() {
    if (_sourcePallet == null) return [];
    return _repo.items.where((it) => it.palletId == _sourcePallet!.palletId).toList();
  }

  List<Item> _getTargetItems() {
    if (_targetPallet == null) return [];
    return _repo.items.where((it) => it.palletId == _targetPallet!.palletId).toList();
  }

  String _getLocationName(String? locationId) {
    if (locationId == null || locationId.isEmpty) return 'Chưa xếp kệ';
    final loc = _repo.locations.where((l) => l.locationId == locationId).firstOrNull;
    return loc?.locationCode ?? locationId;
  }

  void _manualReset() {
    _resetTimer?.cancel();
    _resetTimer = null;
    setState(() {
      _sourcePallet = null;
      _targetPallet = null;
    });
    _showFeedbackSnackBar('Đã đặt lại trạng thái quét');
  }

  void _showManualSelectModal(bool isSelectingSource) {
    final c = _eyeCare.colors;
    final allPallets = _repo.pallets;

    // Lọc danh sách hợp lệ
    final List<Pallet> candidates = allPallets.where((p) {
      if (isSelectingSource) {
        // Nguồn phải có hàng
        final cnt = _repo.items.where((it) => it.palletId == p.palletId).length;
        if (cnt == 0) return false;
        if (_targetPallet != null && p.palletId == _targetPallet!.palletId) return false;
        return true;
      } else {
        // Đích không được trùng nguồn
        if (_sourcePallet != null && p.palletId == _sourcePallet!.palletId) return false;
        return true;
      }
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final filtered = candidates.where((p) {
              if (filter.isEmpty) return true;
              return p.palletCode.toUpperCase().contains(filter.toUpperCase()) ||
                  (p.rfidEpc != null && p.rfidEpc!.toUpperCase().contains(filter.toUpperCase()));
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: 480,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSelectingSource ? Icons.upload_rounded : Icons.download_rounded,
                          color: isSelectingSource ? const Color(0xFFF59E0B) : c.rfidCyan,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSelectingSource ? 'CHỌN PALLET NGUỒN' : 'CHỌN PALLET ĐÍCH (GỘP NGAY)',
                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(modalCtx)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      style: TextStyle(color: c.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm mã Pallet hoặc RFID...',
                        hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                        prefixIcon: Icon(Icons.search, color: c.textMuted, size: 18),
                        filled: true,
                        fillColor: c.bgCardElevated,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      ),
                      onChanged: (val) => setModalState(() => filter = val.trim()),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('Không có Pallet nào phù hợp', style: TextStyle(color: c.textMuted, fontSize: 13)),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(color: c.border, height: 1),
                              itemBuilder: (ctx, idx) {
                                final p = filtered[idx];
                                final itemCount = _repo.items.where((it) => it.palletId == p.palletId).length;
                                final locName = _getLocationName(p.locationId);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  title: Text(p.palletCode, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text('Kệ: $locName | Số lượng: $itemCount sản phẩm', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                                  trailing: Icon(
                                    isSelectingSource ? Icons.arrow_forward_ios : Icons.bolt_rounded,
                                    color: isSelectingSource ? c.textMuted : const Color(0xFFF59E0B),
                                    size: 16,
                                  ),
                                  onTap: () async {
                                    Navigator.pop(modalCtx);
                                    if (isSelectingSource) {
                                      setState(() {
                                        _sourcePallet = p;
                                        _targetPallet = null;
                                      });
                                      _showFeedbackSnackBar('Đã chọn Nguồn: ${p.palletCode}. Mời quét Pallet Đích để gộp tự động.');
                                    } else {
                                      setState(() {
                                        _targetPallet = p;
                                      });
                                      // Tự động gộp luôn khi chọn xong Pallet đích
                                      await _executeAutoMerge();
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final sourceItems = _getSourceItems();
    final targetItems = _getTargetItems();

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: const HardwareStatusAppBar(title: 'GỘP 2 PALLET (PDA)'),
      body: SafeArea(
        child: Column(
          children: [
            // Banner trạng thái quét thông minh (Smart Scanning Workflow)
            _buildWorkflowStatusBanner(c),

            // Khu vực nội dung chính cuộn được
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // THẺ PALLET NGUỒN (A)
                    _buildPalletSection(
                      title: '1. PALLET NGUỒN (A) - CHUYỂN ĐI',
                      badge: 'NGUỒN',
                      badgeColor: const Color(0xFFF59E0B),
                      pallet: _sourcePallet,
                      itemsCount: sourceItems.length,
                      isSource: true,
                      c: c,
                    ),

                    const SizedBox(height: 10),

                    // BIỂU TƯỢNG MŨI TÊN TỰ ĐỘNG GỘP
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _sourcePallet != null ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : c.bgCardElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _sourcePallet != null ? const Color(0xFFF59E0B) : c.border,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              color: _sourcePallet != null ? const Color(0xFFF59E0B) : c.textMuted,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isProcessing
                                  ? 'ĐANG TỰ ĐỘNG GỘP...'
                                  : (_sourcePallet != null && _targetPallet == null
                                      ? 'QUÉT ĐÍCH ĐỂ TỰ ĐỘNG GỘP NGAY'
                                      : 'CHẾ ĐỘ TỰ ĐỘNG GỘP (ZERO-TOUCH)'),
                              style: TextStyle(
                                color: _sourcePallet != null ? const Color(0xFFF59E0B) : c.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // THẺ PALLET ĐÍCH (B)
                    _buildPalletSection(
                      title: '2. PALLET ĐÍCH (B) - NHẬN HÀNG',
                      badge: 'ĐÍCH',
                      badgeColor: c.successEmerald,
                      pallet: _targetPallet,
                      itemsCount: targetItems.length,
                      isSource: false,
                      c: c,
                    ),

                    const SizedBox(height: 14),

                    // THÔNG BÁO VỪA GỘP THÀNH CÔNG GẦN NHẤT
                    if (_lastMergedRecord != null) _buildLastMergedBanner(c),

                    const SizedBox(height: 14),

                    // TÙY CHỌN & CẤU HÌNH NHANH
                    _buildOptionsCard(c),

                    const SizedBox(height: 14),

                    // LỊCH SỬ CÁC LẦN TỰ ĐỘNG GỘP TRONG PHIÊN NÀY
                    _buildRecentMergesList(c),
                  ],
                ),
              ),
            ),

            // THANH TRẠNG THÁI & HƯỚNG DẪN DƯỚI CÙNG (Thay thế nút bấm thủ công)
            _buildBottomStatusIndicator(c),
          ],
        ),
      ),
    );
  }

  /// Banner trạng thái quy trình tự động quét
  Widget _buildWorkflowStatusBanner(EyeCareColors c) {
    String stepText;
    IconData stepIcon;
    Color stepColor;

    if (_isProcessing) {
      stepText = 'Đang tự động gộp và chuyển toàn bộ dữ liệu hàng hóa...';
      stepIcon = Icons.sync_rounded;
      stepColor = c.rfidCyan;
    } else if (_sourcePallet == null) {
      stepText = 'BƯỚC 1/2: Bóp cò súng PDA quét mã Pallet NGUỒN (có hàng).';
      stepIcon = Icons.qr_code_scanner_rounded;
      stepColor = const Color(0xFFF59E0B);
    } else if (_targetPallet == null) {
      stepText = 'BƯỚC 2/2: Quét mã Pallet ĐÍCH ➔ Hệ thống sẽ TỰ ĐỘNG GỘP NGAY LẬP TỨC!';
      stepIcon = Icons.bolt_rounded;
      stepColor = c.successEmerald;
    } else {
      stepText = 'Đã hoàn tất gộp! Sẵn sàng quét cặp Pallet tiếp theo...';
      stepIcon = Icons.check_circle_rounded;
      stepColor = c.successEmerald;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: stepColor.withValues(alpha: 0.12),
      child: Row(
        children: [
          _isProcessing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: stepColor),
                )
              : Icon(stepIcon, color: stepColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              stepText,
              style: TextStyle(color: stepColor, fontSize: 12, fontWeight: FontWeight.bold, height: 1.3),
            ),
          ),
          if (_sourcePallet != null && !_isProcessing)
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.refresh_rounded, color: c.textMuted, size: 16),
              label: Text('Hủy / Đặt lại', style: TextStyle(color: c.textMuted, fontSize: 11)),
              onPressed: _manualReset,
            ),
        ],
      ),
    );
  }

  /// Khối hiển thị thông tin Pallet Nguồn hoặc Pallet Đích
  Widget _buildPalletSection({
    required String title,
    required String badge,
    required Color badgeColor,
    required Pallet? pallet,
    required int itemsCount,
    required bool isSource,
    required EyeCareColors c,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pallet != null ? badgeColor.withValues(alpha: 0.6) : c.border,
          width: pallet != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                if (pallet != null)
                  InkWell(
                    onTap: _isProcessing
                        ? null
                        : () {
                            setState(() {
                              if (isSource) {
                                _sourcePallet = null;
                              } else {
                                _targetPallet = null;
                              }
                            });
                          },
                    child: Text('Đổi', style: TextStyle(color: c.rfidCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                else
                  InkWell(
                    onTap: _isProcessing ? null : () => _showManualSelectModal(isSource),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.list, color: c.rfidCyan, size: 16),
                        const SizedBox(width: 4),
                        Text('Chọn danh sách', style: TextStyle(color: c.rfidCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: pallet == null
                ? InkWell(
                    onTap: _isProcessing ? null : () => _showManualSelectModal(isSource),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: c.border, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            isSource ? Icons.qr_code_scanner : Icons.sensors_rounded,
                            color: isSource ? const Color(0xFFF59E0B) : c.textMuted,
                            size: 26,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isSource
                                ? 'Bóp cò súng PDA quét mã Pallet Nguồn'
                                : 'Bóp cò súng PDA quét mã Pallet Đích (Sẽ gộp ngay)',
                            style: TextStyle(
                              color: isSource ? c.textPrimary : c.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('hoặc chạm vào đây để chọn danh sách', style: TextStyle(color: c.textMuted, fontSize: 10.5)),
                        ],
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.inventory_2_rounded, color: badgeColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pallet.palletCode,
                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isSource ? '$itemsCount sản phẩm cần chuyển' : '$itemsCount sản phẩm hiện tại',
                              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, color: c.textMuted, size: 16),
                          const SizedBox(width: 4),
                          Text('Kệ lưu kho: ', style: TextStyle(color: c.textMuted, fontSize: 11.5)),
                          Text(
                            _getLocationName(pallet.locationId),
                            style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      if (pallet.rfidEpc != null && pallet.rfidEpc!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.sensors, color: c.textMuted, size: 16),
                            const SizedBox(width: 4),
                            Text('RFID: ', style: TextStyle(color: c.textMuted, fontSize: 11)),
                            Expanded(
                              child: Text(
                                pallet.rfidEpc!,
                                style: TextStyle(color: c.textMuted, fontSize: 11, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Banner thông báo kết quả gộp gần nhất
  Widget _buildLastMergedBanner(EyeCareColors c) {
    final rec = _lastMergedRecord!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.successEmerald.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.successEmerald.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.successEmerald.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bolt_rounded, color: c.successEmerald, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VỪA TỰ ĐỘNG GỘP THÀNH CÔNG!',
                  style: TextStyle(color: c.successEmerald, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'Đã chuyển ${rec.itemCount} sản phẩm từ [${rec.sourcePalletCode}] sang [${rec.targetPalletCode}]',
                  style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Vị trí kệ mới: ${rec.targetLocationName}',
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Card tùy chọn xóa Pallet nguồn
  Widget _buildOptionsCard(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: _deleteSourcePallet,
              activeColor: const Color(0xFFEF4444),
              onChanged: _isProcessing
                  ? null
                  : (val) => setState(() => _deleteSourcePallet = val ?? false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _isProcessing
                  ? null
                  : () => setState(() => _deleteSourcePallet = !_deleteSourcePallet),
              child: Text(
                'Xóa mã Pallet nguồn khỏi hệ thống sau khi chuyển hết hàng (mặc định giữ lại làm Pallet rỗng)',
                style: TextStyle(
                  color: _deleteSourcePallet ? const Color(0xFFEF4444) : c.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lịch sử các lần gộp trong phiên
  Widget _buildRecentMergesList(EyeCareColors c) {
    if (_recentMerges.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: c.rfidCyan, size: 16),
                const SizedBox(width: 6),
                Text(
                  'LỊCH SỬ GỘP TRONG PHIÊN (${_recentMerges.length})',
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentMerges.length > 5 ? 5 : _recentMerges.length,
            separatorBuilder: (_, __) => Divider(color: c.border, height: 1),
            itemBuilder: (ctx, idx) {
              final m = _recentMerges[idx];
              final timeStr =
                  '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}:${m.timestamp.second.toString().padLeft(2, '0')}';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: c.successEmerald.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check, color: c.successEmerald, size: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(m.sourcePalletCode, style: TextStyle(color: const Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, color: c.textMuted, size: 12),
                              const SizedBox(width: 4),
                              Text(m.targetPalletCode, style: TextStyle(color: c.successEmerald, fontWeight: FontWeight.bold, fontSize: 12)),
                              const Spacer(),
                              Text(timeStr, style: TextStyle(color: c.textMuted, fontSize: 10)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Chuyển ${m.itemCount} SP ➔ Vị trí kệ: ${m.targetLocationName}',
                            style: TextStyle(color: c.textSecondary, fontSize: 10.5),
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
    );
  }

  /// Thanh trạng thái Auto-Merge dưới cùng màn hình (Hands-free visual confirmation)
  Widget _buildBottomStatusIndicator(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (_sourcePallet != null && _targetPallet == null)
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                  : c.successEmerald.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isProcessing
                  ? Icons.sync_rounded
                  : (_sourcePallet != null ? Icons.bolt_rounded : Icons.qr_code_scanner_rounded),
              color: (_sourcePallet != null && _targetPallet == null)
                  ? const Color(0xFFF59E0B)
                  : c.successEmerald,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'TỰ ĐỘNG GỘP PALLET:',
                      style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: c.successEmerald.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'HOẠT ĐỘNG ⚡',
                        style: TextStyle(color: c.successEmerald, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isProcessing
                      ? 'Đang tiến hành gộp dữ liệu hàng hóa...'
                      : (_sourcePallet == null
                          ? 'Sẵn sàng: Bóp cò súng PDA quét Pallet Nguồn'
                          : 'Đã nhận Nguồn ➔ Quét Pallet Đích để Gộp Ngay'),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_sourcePallet != null && !_isProcessing)
            IconButton(
              icon: Icon(Icons.close_rounded, color: c.textMuted, size: 20),
              tooltip: 'Hủy chọn',
              onPressed: _manualReset,
            ),
        ],
      ),
    );
  }
}
