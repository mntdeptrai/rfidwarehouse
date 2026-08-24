import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/tag_info.dart';
import '../../models/wms_models.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';

class PdaPutawayScreen extends StatefulWidget {
  final String? initialLocationId;

  const PdaPutawayScreen({
    super.key,
    this.initialLocationId,
  });

  @override
  State<PdaPutawayScreen> createState() => _PdaPutawayScreenState();
}

class _PdaPutawayScreenState extends State<PdaPutawayScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  String? _selectedLocationId;
  StreamSubscription<String>? _barcodeSub;
  StreamSubscription<TagInfo>? _rfidSub;

  final TextEditingController _cartonInputController = TextEditingController();
  final FocusNode _cartonFocusNode = FocusNode();

  int _sessionPutawayCount = 0;
  String? _lastConfirmedCarton;


  @override
  void initState() {
    super.initState();
    _selectedLocationId = widget.initialLocationId ?? (_repo.locations.isNotEmpty ? _repo.locations.first.locationId : null);
    _eyeCare.addListener(_onStateChange);
    _uhf.setScanMode(PdaScanMode.barcode);

    // Lắng nghe sự kiện bóp cò quét Barcode phần cứng PDA
    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      _handleIncomingBarcode(barcode);
    });

    // Lắng nghe thẻ RFID nếu nhân viên quét chip trên thùng
    _rfidSub = _uhf.onTagRead.listen((tag) {
      _handleIncomingRfid(tag.epc);
    });
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _uhf.setScanMode(PdaScanMode.rfid);
    _eyeCare.removeListener(_onStateChange);
    _barcodeSub?.cancel();
    _rfidSub?.cancel();
    _cartonInputController.dispose();
    _cartonFocusNode.dispose();
    super.dispose();
  }

  void _handleIncomingBarcode(String rawBarcode) {
    final clean = rawBarcode.trim();
    if (clean.isEmpty) return;

    // 1. Kiểm tra nếu mã quét được là mã vị trí kệ (Bắt đầu bằng LOC- hoặc khớp trong bảng locations)
    final isLocationCode = clean.toUpperCase().startsWith('LOC-') ||
        _repo.locations.any((l) => l.locationCode.toUpperCase() == clean.toUpperCase());

    if (isLocationCode) {
      final loc = _repo.locations.where((l) =>
          l.locationCode.toUpperCase() == clean.toUpperCase() ||
          l.locationId.toUpperCase() == clean.toUpperCase()).firstOrNull;

      if (loc != null) {
        setState(() {
          _selectedLocationId = loc.locationId;
        });
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0284C7),
            duration: const Duration(seconds: 2),
            content: Text('📍 ĐÃ KHÓA VỊ TRÍ KỆ: ${loc.locationCode} - ${loc.zone} • ${loc.shelf}'),
          ),
        );
        return;
      }
    }

    // 2. Nếu không phải là vị trí kệ -> Đó là Mã Barcode Thùng Hàng / Đơn hàng -> Thực hiện xếp kho ngay!
    _cartonInputController.text = clean;
    _processPutawayCarton(clean);
  }

  void _handleIncomingRfid(String epc) {
    final clean = epc.trim().toUpperCase();
    final item = _repo.items.where((i) => i.epc.toUpperCase() == clean).firstOrNull;
    if (item != null && item.orderNo != null && item.orderNo!.isNotEmpty) {
      _processPutawayCarton(item.orderNo!);
    }
  }

  Future<void> _processPutawayCarton(String cartonBarcode) async {
    final clean = cartonBarcode.trim();
    if (clean.isEmpty) return;

    // Tự động lấy vị trí kệ nếu chưa chọn
    if (_selectedLocationId == null || _selectedLocationId!.isEmpty) {
      if (_repo.locations.isNotEmpty) {
        setState(() {
          _selectedLocationId = _repo.locations.first.locationId;
        });
      } else {
        setState(() {
          _selectedLocationId = 'LOC-A01-01';
        });
      }
    }

    final savedCount = await _repo.confirmPdaPutawayByCarton(
      cartonOrOrderBarcode: clean,
      locationId: _selectedLocationId!,
      performedBy: 'Thủ kho PDA',
    );

    if (savedCount > 0) {
      final loc = _repo.locations.where((l) => l.locationId == _selectedLocationId).firstOrNull;
      final locName = loc != null ? loc.locationCode : _selectedLocationId!;

      setState(() {
        _sessionPutawayCount++;
        _lastConfirmedCarton = clean;
        _cartonInputController.clear();
      });

      HapticFeedback.heavyImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF2C251E), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✅ ĐÃ CẤT THÙNG $clean VÀO $locName ($savedCount SP ĐANG TRONG KHO)!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      HapticFeedback.vibrate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFF59E0B),
            duration: const Duration(seconds: 3),
            content: Text('⚠️ Không tìm thấy thùng/đơn hàng có mã "$clean" để xếp kho.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final waitingOrders = _repo.inboundOrders.where((o) =>
        o.status == InboundOrderStatus.waitingPutaway ||
        o.status == InboundOrderStatus.newOrder ||
        o.status == InboundOrderStatus.processing).toList();

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: const HardwareStatusAppBar(
        title: 'CẤT HÀNG LÊN KỆ',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner tóm tắt ca làm việc
            _buildSessionSummaryBanner(c),
            const SizedBox(height: 14),

            // BƯỚC 1: CHỌN / QUÉT VỊ TRÍ KỆ
            _buildStep1LocationCard(c),
            const SizedBox(height: 14),

            // BƯỚC 2: QUÉT BARCODE TRÊN THÙNG HÀNG
            _buildStep2CartonBarcodeCard(c),
            const SizedBox(height: 16),

            // DANH SÁCH CÁC THÙNG ĐANG CHỜ XẾP KHO
            _buildWaitingOrdersList(waitingOrders, c),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSummaryBanner(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shelves, color: c.rfidCyan, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TIẾN ĐỘ CA XẾP KHO', style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(
                    'Đã cất: $_sessionPutawayCount kiện hàng',
                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          if (_lastConfirmedCarton != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.successEmerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.successEmerald),
              ),
              child: Text(
                'Vừa cất: $_lastConfirmedCarton',
                style: TextStyle(color: c.successEmerald, fontSize: 10.5, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep1LocationCard(EyeCareColors c) {
    final locations = _repo.locations;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _selectedLocationId != null ? c.successEmerald : c.rfidCyan,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.rfidCyan,
                  shape: BoxShape.circle,
                ),
                child: const Text('1', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BƯỚC 1: CHỌN VỊ TRÍ KỆ ĐÍCH',
                  style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedLocationId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.successEmerald.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'ĐÃ CHỌN',
                    style: TextStyle(color: c.successEmerald, fontSize: 9.5, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Dropdown lấy từ bảng locations trên Database
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedLocationId),
            isExpanded: true,
            initialValue: (locations.any((l) => l.locationId == _selectedLocationId))
                ? _selectedLocationId
                : (locations.isNotEmpty ? locations.first.locationId : null),
            dropdownColor: c.bgCardElevated,
            icon: Icon(Icons.arrow_drop_down_circle, color: c.rfidCyan),
            style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.bgCardElevated,
              labelText: 'Vị trí kệ kho',
              labelStyle: TextStyle(color: c.rfidCyan, fontSize: 11),
              prefixIcon: Icon(Icons.shelves, color: c.rfidCyan, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.rfidCyan, width: 1.5),
              ),
            ),
            items: locations.map((loc) {
              return DropdownMenuItem<String>(
                value: loc.locationId,
                child: Text(
                  '${loc.locationCode} - ${loc.zone} • ${loc.shelf} - ${loc.level}',
                  style: TextStyle(color: c.textPrimary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedLocationId = val;
                });
                HapticFeedback.selectionClick();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep2CartonBarcodeCard(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.successEmerald,
                  shape: BoxShape.circle,
                ),
                child: const Text('2', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BƯỚC 2: QUÉT MÃ THÙNG HÀNG',
                  style: TextStyle(color: c.successEmerald, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner, color: c.successEmerald, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SẴN SÀNG QUÉT (BARCODE / RFID)',
                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.successEmerald,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _uhf.triggerBarcodeScan(),
                  child: const Text(
                    'BẬT QUÉT',
                    style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cartonInputController,
            focusNode: _cartonFocusNode,
            style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Quét hoặc nhập mã Barcode ngoài thùng...',
              hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
              filled: true,
              fillColor: c.bgCardElevated,
              prefixIcon: Icon(Icons.inventory_2, color: c.rfidCyan, size: 18),
              suffixIcon: IconButton(
                icon: Icon(Icons.send_rounded, color: c.successEmerald),
                onPressed: () => _processPutawayCarton(_cartonInputController.text),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
            ),
            onSubmitted: (val) => _processPutawayCarton(val),
          ),
        ],
      ),
    );
  }


  Widget _buildWaitingOrdersList(List<InboundOrder> orders, EyeCareColors c) {
    if (orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Center(
          child: Text(
            'Hiện không có kiện hàng nào đang chờ xếp kho.',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '📦 KIỆN HÀNG ĐANG CHỜ XẾP KHO',
              style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
            ),
            Text(
              '${orders.length} kiện',
              style: TextStyle(color: c.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orders.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, idx) {
            final o = orders[idx];
            final totalReq = o.details.fold(0, (sum, d) => sum + d.requiredQty);

            return InkWell(
              onTap: () => _processPutawayCarton(o.orderNo),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.rfidCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory_2, color: c.rfidCyan, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o.orderNo,
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.warningAmber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Chờ xếp',
                                  style: TextStyle(color: c.warningAmber, fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mã Barcode quét: ${o.orderNo} • $totalReq SP',
                            style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.w600, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (o.details.isNotEmpty && o.details.first.productName.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              o.details.first.productName,
                              style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.rfidCyan,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _processPutawayCarton(o.orderNo),
                      child: const Text('Cất vị trí này', style: TextStyle(color: Color(0xFF2C251E), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
