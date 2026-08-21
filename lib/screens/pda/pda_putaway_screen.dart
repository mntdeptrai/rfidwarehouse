import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/tag_info.dart';
import '../../models/wms_models.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../widgets/hardware_status_appbar.dart';
import '../../widgets/pda_location_barcode_card.dart';

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

  String? _selectedLocationId;
  StreamSubscription<String>? _barcodeSub;
  StreamSubscription<TagInfo>? _rfidSub;

  final TextEditingController _cartonInputController = TextEditingController();
  final FocusNode _cartonFocusNode = FocusNode();

  int _sessionPutawayCount = 0;
  String? _lastConfirmedCarton;
  String? _lastConfirmedLocation;
  int _lastConfirmedItemCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedLocationId = widget.initialLocationId ?? (_repo.locations.isNotEmpty ? _repo.locations.first.locationId : null);

    // Lắng nghe sự kiện bóp cò quét Barcode phần cứng PDA
    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      _handleIncomingBarcode(barcode);
    });

    // Lắng nghe thẻ RFID nếu nhân viên quét chip trên thùng
    _rfidSub = _uhf.onTagRead.listen((tag) {
      _handleIncomingRfid(tag.epc);
    });
  }

  @override
  void dispose() {
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
            content: Text('📍 ĐÃ KHÓA VỊ TRÍ KỆ: ${loc.locationCode} (${loc.zone} • ${loc.shelf})'),
          ),
        );
        return;
      }
    }

    // 2. Nếu không phải là vị trí kệ -> Đó là Mã Barcode Thùng Hàng / Đơn hàng -> Thực hiện xếp kho ngay!
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

    if (_selectedLocationId == null || _selectedLocationId!.isEmpty) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          duration: Duration(seconds: 3),
          content: Text('⚠️ VUI LÒNG QUÉT MÃ VỊ TRÍ KỆ TRƯỚC KHI XẾP THÙNG HÀNG!'),
        ),
      );
      return;
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
        _lastConfirmedLocation = locName;
        _lastConfirmedItemCount = savedCount;
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
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
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
    final waitingOrders = _repo.inboundOrders.where((o) =>
        o.status == InboundOrderStatus.waitingPutaway ||
        o.status == InboundOrderStatus.newOrder ||
        o.status == InboundOrderStatus.processing).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: const HardwareStatusAppBar(
        title: 'CẤT HÀNG LÊN KỆ (PUTAWAY)',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner tóm tắt ca làm việc
            _buildSessionSummaryBanner(),
            const SizedBox(height: 14),

            // BƯỚC 1: CHỌN / QUÉT VỊ TRÍ KỆ
            _buildStep1LocationCard(),
            const SizedBox(height: 14),

            // BƯỚC 2: QUÉT BARCODE TRÊN THÙNG HÀNG
            _buildStep2CartonBarcodeCard(),
            const SizedBox(height: 16),

            // DANH SÁCH CÁC THÙNG ĐANG CHỜ XẾP KHO
            _buildWaitingOrdersList(waitingOrders),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSummaryBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.shelves, color: Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TIẾN ĐỘ CA XẾP KHO', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text(
                    'Đã cất: $_sessionPutawayCount kiện hàng',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          if (_lastConfirmedCarton != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF10B981)),
              ),
              child: Text(
                'Vừa cất: $_lastConfirmedCarton',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep1LocationCard() {
    final locations = _repo.locations;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _selectedLocationId != null ? const Color(0xFF10B981) : const Color(0xFF0284C7),
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
                decoration: const BoxDecoration(
                  color: Color(0xFF0284C7),
                  shape: BoxShape.circle,
                ),
                child: const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'BƯỚC 1: CHỌN VỊ TRÍ KỆ ĐÍCH (DATABASE)',
                  style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedLocationId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ĐÃ CHỌN',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 9.5, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Dropdown lấy từ bảng locations trên Database
          DropdownButtonFormField<String>(
            value: (locations.any((l) => l.locationId == _selectedLocationId))
                ? _selectedLocationId
                : (locations.isNotEmpty ? locations.first.locationId : null),
            dropdownColor: const Color(0xFF0F172A),
            icon: const Icon(Icons.arrow_drop_down_circle, color: Color(0xFF38BDF8)),
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0F172A),
              labelText: 'Vị trí kệ kho (Từ Database)',
              labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
              prefixIcon: const Icon(Icons.shelves, color: Color(0xFF38BDF8), size: 22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
              ),
            ),
            items: locations.map((loc) {
              return DropdownMenuItem<String>(
                value: loc.locationId,
                child: Text(
                  '${loc.locationCode} (${loc.zone} • ${loc.shelf} - ${loc.level})',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
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
          const SizedBox(height: 8),

          // Hoặc bóp cò PDA quét mã kệ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Hoặc bóp cò Barcode để tự động chọn kệ',
                style: TextStyle(color: Colors.white54, fontSize: 10.5),
              ),
              Text(
                'Tổng: ${locations.length} vị trí',
                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep2CartonBarcodeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Text('2', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'BƯỚC 2: BÓP CÒ QUÉT BARCODE TRÊN THÙNG HÀNG',
                  style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
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
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner, color: Color(0xFF10B981), size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SẴN SÀNG QUÉT (CÒ PDA)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Hướng tia laser/camera vào mã vạch dán trên kiện hàng để cất',
                        style: TextStyle(color: Colors.white54, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _uhf.triggerBarcodeScan(),
                  child: const Text(
                    'BẬT QUÉT',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cartonInputController,
            focusNode: _cartonFocusNode,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Nhập hoặc quét mã vạch thùng (VD: CARTONTEST0001)...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              prefixIcon: const Icon(Icons.inventory_2, color: Color(0xFF38BDF8), size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, color: Color(0xFF10B981)),
                onPressed: () => _processPutawayCarton(_cartonInputController.text),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
            ),
            onSubmitted: (val) => _processPutawayCarton(val),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingOrdersList(List<InboundOrder> orders) {
    if (orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Hiện không có kiện hàng nào đang chờ xếp kho.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
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
            const Text(
              '📦 KIỆN HÀNG ĐANG CHỜ XẾP KHO',
              style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
            ),
            Text(
              '${orders.length} kiện',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, idx) {
            final o = orders[idx];
            final totalReq = o.details.fold(0, (sum, d) => sum + d.requiredQty);

            return InkWell(
              onTap: () => _processPutawayCarton(o.orderNo),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.inventory_2, color: Color(0xFF38BDF8), size: 20),
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
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Chờ xếp',
                                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Số lượng: $totalReq SP • ${o.details.isNotEmpty ? o.details.first.productName : ""}',
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _processPutawayCarton(o.orderNo),
                      child: const Text('Cất vị trí này', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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
