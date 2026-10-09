import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/inventory_models.dart';
import '../../models/order_models.dart';
import '../../models/tag_info.dart';
import '../../services/auth_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/excel_import_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/tower_light_service.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

/// Mô hình chi tiết từng sản phẩm cần xuất kho qua cổng RFID
class _PendingOutboundItem {
  final String sku;
  final String productId;
  final String cartonCode;
  final String palletCode;
  final String supplier;
  final String customer;
  final String productName;
  final String palletEpc;
  final String epc;
  final String serialNumber;
  final bool isInStock;
  final String locationCode;
  final DateTime? inboundTime;
  final int fifoPriority;
  final String? fifoWarning;

  _PendingOutboundItem({
    required this.sku,
    this.productId = '',
    required this.cartonCode,
    required this.palletCode,
    required this.supplier,
    required this.customer,
    required this.productName,
    required this.palletEpc,
    required this.epc,
    this.serialNumber = '--',
    this.isInStock = true,
    this.locationCode = '--',
    this.inboundTime,
    this.fifoPriority = 1,
    this.fifoWarning,
  });

  _PendingOutboundItem copyWith({
    String? sku,
    String? productId,
    String? cartonCode,
    String? palletCode,
    String? supplier,
    String? customer,
    String? productName,
    String? palletEpc,
    String? epc,
    String? serialNumber,
    bool? isInStock,
    String? locationCode,
    DateTime? inboundTime,
    int? fifoPriority,
    String? fifoWarning,
  }) {
    return _PendingOutboundItem(
      sku: sku ?? this.sku,
      productId: productId ?? this.productId,
      cartonCode: cartonCode ?? this.cartonCode,
      palletCode: palletCode ?? this.palletCode,
      supplier: supplier ?? this.supplier,
      customer: customer ?? this.customer,
      productName: productName ?? this.productName,
      palletEpc: palletEpc ?? this.palletEpc,
      epc: epc ?? this.epc,
      serialNumber: serialNumber ?? this.serialNumber,
      isInStock: isInStock ?? this.isInStock,
      locationCode: locationCode ?? this.locationCode,
      inboundTime: inboundTime ?? this.inboundTime,
      fifoPriority: fifoPriority ?? this.fifoPriority,
      fifoWarning: fifoWarning ?? this.fifoWarning,
    );
  }
}

/// Mô hình đơn xuất kho nạp từ file (lưu tạm trong RAM chờ đối soát qua cổng)
class _PendingOutboundOrder {
  final String? outboundOrderId;
  final String orderNo;
  final String customer;
  final List<_PendingOutboundItem> items;
  final Map<String, String?> pallets; // palletCode -> palletEpc
  final String fileName;
  bool isStockSufficient;
  final int shortageCount;
  final Map<String, int> shortageBySku;

  _PendingOutboundOrder({
    this.outboundOrderId,
    required this.orderNo,
    required this.customer,
    required this.items,
    required this.pallets,
    required this.fileName,
    this.isStockSufficient = true,
    this.shortageCount = 0,
    this.shortageBySku = const {},
  });
}

class DesktopGoodsDeliveryView extends StatefulWidget {
  final bool isActive;
  const DesktopGoodsDeliveryView({super.key, this.isActive = true});

  @override
  State<DesktopGoodsDeliveryView> createState() => _DesktopGoodsDeliveryViewState();
}

class _DesktopGoodsDeliveryViewState extends State<DesktopGoodsDeliveryView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final DesktopUhfTcpService _desktopUhf = DesktopUhfTcpService();
  final TowerLightService _towerLight = TowerLightService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();
  final ExcelImportService _excelService = ExcelImportService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();


  bool _isImporting = false;
  bool _isSaving = false;

  // Đơn xuất kho đang chờ đối soát qua cổng
  _PendingOutboundOrder? _pendingOutboundOrder;

  // Danh sách chip RFID đã quét tại trạm/cổng
  final Map<String, TagInfo> _gateScannedTags = {};
  final Set<String> _securityAlertLoggedEpcs = {};
  final Set<String> _duplicateShippedEpcs = {};
  String? _duplicateShippedAlertMessage;
  bool _isScanning = false;
  bool _isConnectingUhf = false;
  bool _isBuzzerManuallySilenced = false;
  int _scanDurationSeconds = 0; // 0 = liên tục (mặc định), 5s, 10s
  int _scanCountdown = 0;
  Timer? _countdownTimer;
  Timer? _uiRefreshTimer;

  StreamSubscription<TagInfo>? _uhfSub;
  StreamSubscription<TagInfo>? _desktopUhfSub;

  // Thông báo đối soát thành công (tự động ẩn sau 3s)
  String? _lastSuccessOrderNo;
  String? _lastSuccessPalletCode;
  int _lastSuccessCount = 0;
  Timer? _successBannerTimer;

  // Tự động xác nhận xuất kho sau 1s khi quét đủ 100%
  Timer? _autoConfirmTimer;
  bool _isAutoConfirming = false;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onThemeChanged);
    _auth.addListener(_onThemeChanged);
    _desktopUhf.addListener(_onDesktopUhfUpdate);
    _towerLight.addListener(_onThemeChanged);

    _initTagListeners();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onDesktopUhfUpdate() {
    final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');
    final bool isGateActive = _pendingOutboundOrder == null
        ? (_isScanning || _desktopUhf.isScanning || isTest)
        : (_isScanning || isTest);
    if (!mounted || !widget.isActive || !isGateActive) return;
    for (final tag in _desktopUhf.tags) {
      final epc = tag.epc.trim().toUpperCase();
      if (!_gateScannedTags.containsKey(epc)) {
        _handleIncomingGateTag(tag);
      }
    }
  }

  void _initTagListeners() {
    _uhfSub = _uhf.onTagRead.listen((tag) {
      final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');
      final bool isGateActive = _pendingOutboundOrder == null
          ? (_isScanning || _desktopUhf.isScanning || isTest)
          : (_isScanning || isTest);
      if (!mounted || !widget.isActive || !isGateActive) return;
      _handleIncomingGateTag(tag);
    });

    _desktopUhfSub = _desktopUhf.onTagRead.listen((tag) {
      final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');
      final bool isGateActive = _pendingOutboundOrder == null
          ? (_isScanning || _desktopUhf.isScanning || isTest)
          : (_isScanning || isTest);
      if (!mounted || !widget.isActive || !isGateActive) return;
      _handleIncomingGateTag(tag);
    });
  }

  void _handleIncomingGateTag(TagInfo tag) {
    final bool isTest = Platform.environment.containsKey('FLUTTER_TEST');
    final bool isGateActive = _pendingOutboundOrder == null
        ? (_isScanning || _desktopUhf.isScanning || isTest)
        : (_isScanning || isTest);
    if (!isGateActive) return;
    final epc = tag.epc.trim().toUpperCase();
    final isNewTag = !_gateScannedTags.containsKey(epc);
    if (!isNewTag && _uhf.filterDuplicates) return;

    if (isNewTag) {
      _isBuzzerManuallySilenced = false;
    }

    _gateScannedTags[epc] = tag;

    // Kiểm tra hàng đã xuất kho trước đó (trùng EPC / SN đã xuất):
    final shippedItem = _repo.findShippedItem(epc: epc);
    if (shippedItem != null) {
      _duplicateShippedEpcs.add(epc);
      final snStr = shippedItem.serialNumber.isNotEmpty ? shippedItem.serialNumber : '--';
      _duplicateShippedAlertMessage = '🚨 LỖI TRÙNG EPC/SN: Hàng hóa [${shippedItem.productName}] (SN: $snStr, EPC: $epc) ĐÃ ĐƯỢC XUẤT KHO TRƯỚC ĐÓ!';
      _cancelAutoConfirm();
      SystemSound.play(SystemSoundType.alert);
      _towerLight.triggerWarningRed(
        withBuzzer: !_isBuzzerManuallySilenced,
        reason: _duplicateShippedAlertMessage!,
        persistent: false,
        durationSeconds: 4,
      );
      if (!_securityAlertLoggedEpcs.contains(epc)) {
        _securityAlertLoggedEpcs.add(epc);
        _repo.recordTagLifecycle(
          epc: epc,
          itemId: shippedItem.itemId,
          sku: shippedItem.sku,
          productName: shippedItem.productName,
          serialNumber: shippedItem.serialNumber,
          action: TagLifecycleAction.unauthorizedExit,
          previousStatus: ItemStatus.out.code,
          newStatus: ItemStatus.out.code,
          performedBy: _auth.currentUser?.fullName ?? 'Hệ thống Cổng RFID Gate Xuất Kho',
          device: 'Cổng RFID Desktop Hopeland',
          notes: '🚨 PHÁT HIỆN TRÙNG EPC/SN ĐÃ XUẤT: Thẻ RFID của hàng đã xuất kho trước đó bị quét lại khi xuất hàng mới!',
        );
      }
      _scheduleUiRefresh();
      return;
    }

    if (_pendingOutboundOrder != null) {
      final order = _pendingOutboundOrder!;

      // 1. Kiểm tra xem thẻ quét có phải là Pallet RFID Tag (xuất cả Pallet qua RFID gate)
      final matchingPalletInOrder = order.pallets.entries.where(
        (e) => (e.value != null && e.value!.trim().toUpperCase() == epc) || e.key.trim().toUpperCase() == epc,
      ).firstOrNull;
      final matchedPalletCode = matchingPalletInOrder?.key ?? _repo.pallets.where(
        (p) => (p.rfidEpc != null && p.rfidEpc!.trim().toUpperCase() == epc) || p.palletCode.trim().toUpperCase() == epc || p.palletId.trim().toUpperCase() == epc,
      ).firstOrNull?.palletCode;

      if (matchedPalletCode != null || matchingPalletInOrder != null) {
        final pCode = (matchedPalletCode ?? matchingPalletInOrder!.key).trim().toUpperCase();
        final autoMatchedPalletItems = order.items.where((i) =>
          i.palletCode.trim().toUpperCase() == pCode ||
          (i.palletEpc.isNotEmpty && i.palletEpc.trim().toUpperCase() == epc)
        ).toList();

        for (final it in autoMatchedPalletItems) {
          final itemEpc = it.epc.trim().toUpperCase();
          if (itemEpc.isNotEmpty && itemEpc != '--') {
            _gateScannedTags[itemEpc] = TagInfo(
              epc: it.epc,
              rssi: tag.rssi,
              count: tag.count,
              timestamp: tag.timestamp,
              ant: tag.ant,
            );
          }
        }
      }

      // 2. Tự động đối chiếu mã chip EPC trong CSDL tồn kho:
      // Tìm chip trong CSDL kho (chỉ chấp nhận hàng còn trong kho khả dụng)
      final inStockItem = _repo.items.where((it) =>
        it.epc.toUpperCase() == epc &&
        (it.status == ItemStatus.inStock || it.status == ItemStatus.waitingPutaway || it.status == ItemStatus.allocated)
      ).firstOrNull;

      if (inStockItem != null) {
        final itemSku = inStockItem.sku.trim().toUpperCase();
        final itemProdId = inStockItem.productId.trim().toUpperCase();
        final itemItemId = inStockItem.itemId.trim().toUpperCase();

        // 2.1 Nếu chip này đã được gán vào 1 slot trong đơn, bổ sung serialNumber nếu chưa có
        final existingIndex = order.items.indexWhere((it) => it.epc.toUpperCase() == epc);
        if (existingIndex >= 0) {
          final slotItem = order.items[existingIndex];
          if (slotItem.serialNumber == '--' || slotItem.serialNumber.isEmpty) {
            order.items[existingIndex] = slotItem.copyWith(
              serialNumber: inStockItem.serialNumber.isNotEmpty ? inStockItem.serialNumber : '--',
            );
          }
        } else {
          // 2.2 Tìm 1 slot chưa quét trong đơn có cùng SKU hoặc Mã Hàng / Mã SP
          final slotIndex = order.items.indexWhere((it) {
            final isScanned = it.epc != '--' && it.epc.isNotEmpty && _gateScannedTags.containsKey(it.epc.toUpperCase());
            if (isScanned) return false;

            final slotSku = it.sku.trim().toUpperCase();
            final slotProdId = it.productId.trim().toUpperCase();
            final matchSku = itemSku.isNotEmpty && (slotSku == itemSku || slotProdId == itemSku);
            final matchProd = itemProdId.isNotEmpty && (slotProdId == itemProdId || slotSku == itemProdId);
            final matchItem = itemItemId.isNotEmpty && (slotProdId == itemItemId || slotSku == itemItemId);
            return matchSku || matchProd || matchItem;
          });

          if (slotIndex >= 0) {
            final oldItem = order.items[slotIndex];
            final resolvedLoc = _repo.resolveItemLocation(inStockItem)?.locationCode ?? oldItem.locationCode;
            order.items[slotIndex] = oldItem.copyWith(
              epc: epc,
              serialNumber: inStockItem.serialNumber.isNotEmpty ? inStockItem.serialNumber : '--',
              productName: inStockItem.productName.isNotEmpty ? inStockItem.productName : oldItem.productName,
              locationCode: resolvedLoc,
              inboundTime: _repo.getItemInboundTime(inStockItem),
              isInStock: true,
            );
            if (order.items.every((i) => i.isInStock)) {
              order.isStockSufficient = true;
            }
          }
        }
      }
    }

    _evaluateGateSecurityAndTowerLight(latestTag: tag);
  }

  void _evaluateGateSecurityAndTowerLight({TagInfo? latestTag}) {
    if (_pendingOutboundOrder == null) {
      // ===== 1. CHẾ ĐỘ GIÁM SÁT AN NINH CỔNG TỰ DO (CHƯA NẠP ĐƠN XUẤT) =====
      final unauthorizedItems = _gateScannedTags.keys
          .map((e) => _repo.items.where((i) => i.epc.toUpperCase() == e).firstOrNull)
          .whereType<Item>()
          .toList();

      final strangerEpcs = _gateScannedTags.keys
          .where((e) => !_repo.items.any((i) => i.epc.toUpperCase() == e))
          .toList();

      final hasSecurityViolation = unauthorizedItems.isNotEmpty || strangerEpcs.isNotEmpty;

      if (hasSecurityViolation) {
        final String reasonText;
        if (unauthorizedItems.isNotEmpty) {
          final first = unauthorizedItems.first;
          final extra = unauthorizedItems.length + strangerEpcs.length - 1;
          final extraStr = extra > 0 ? ' và $extra hàng/chip khác' : '';
          reasonText = '🚨 BÁO ĐỘNG AN NINH: [${first.productName}] (Kệ ${first.locationId ?? "--"})$extraStr qua cổng khi CHƯA CÓ ĐƠN XUẤT!';
        } else {
          final firstEpc = strangerEpcs.first;
          final shortEpc = firstEpc.length > 8 ? '...${firstEpc.substring(firstEpc.length - 8)}' : firstEpc;
          reasonText = '🚨 CẢNH BÁO AN NINH: Phát hiện ${strangerEpcs.length} chip lạ ($shortEpc) qua cổng khi CHƯA CÓ ĐƠN XUẤT!';
        }

        SystemSound.play(SystemSoundType.alert);
        _towerLight.triggerWarningRed(
          withBuzzer: !_isBuzzerManuallySilenced,
          reason: reasonText,
          persistent: false,
          durationSeconds: 3,
        );

        for (final it in unauthorizedItems) {
          final epc = it.epc.toUpperCase();
          if (!_securityAlertLoggedEpcs.contains(epc)) {
            _securityAlertLoggedEpcs.add(epc);
            _repo.recordTagLifecycle(
              epc: epc,
              itemId: it.itemId,
              sku: it.sku,
              productName: it.productName,
              serialNumber: it.serialNumber,
              action: TagLifecycleAction.unauthorizedExit,
              previousStatus: it.status.code,
              newStatus: it.status.code,
              fromLocation: it.locationId,
              fromPallet: it.palletId,
              performedBy: _auth.currentUser?.fullName ?? 'Hệ thống Cổng RFID Gate An Ninh',
              device: 'Cổng RFID Desktop Hopeland',
              notes: '🚨 PHÁT HIỆN QUA CỔNG TRÁI PHÉP: Hàng hóa trong kho đi qua cổng khi chưa có lệnh/đơn xuất kho!',
            );
          }
        }

        for (final epc in strangerEpcs) {
          final upper = epc.toUpperCase();
          if (!_securityAlertLoggedEpcs.contains(upper)) {
            _securityAlertLoggedEpcs.add(upper);
            _repo.recordTagLifecycle(
              epc: upper,
              productName: 'Chip RFID Lạ (Chưa đăng ký)',
              action: TagLifecycleAction.unauthorizedExit,
              newStatus: 'UNAUTHORIZED_STRANGER',
              performedBy: _auth.currentUser?.fullName ?? 'Hệ thống Cổng RFID Gate An Ninh',
              device: 'Cổng RFID Desktop Hopeland',
              notes: '🚨 PHÁT HIỆN QUA CỔNG TRÁI PHÉP: Mã chip lạ không có trong dữ liệu kho đi qua cổng kiểm soát!',
            );
          }
        }
      } else {
        if (_isScanning) {
          _towerLight.triggerScanning(
            reason: 'GIÁM SÁT AN NINH CỔNG: Đang quét kiểm soát thất thoát...',
          );
        } else {
          _towerLight.turnOffAll(reason: 'Sẵn sàng tiếp nhận hàng xuất');
        }
      }
      _scheduleUiRefresh();
      return;
    }

    // ===== 2. CHẾ ĐỘ ĐỐI SOÁT ĐƠN XUẤT KHO (_pendingOutboundOrder != null) =====
    if (_duplicateShippedEpcs.isNotEmpty) {
      _cancelAutoConfirm();
      SystemSound.play(SystemSoundType.alert);
      _towerLight.triggerWarningRed(
        withBuzzer: !_isBuzzerManuallySilenced,
        reason: _duplicateShippedAlertMessage ?? '🚨 LỖI TRÙNG EPC/SN: Có chip của hàng đã xuất kho trước đó bị quét lại!',
        persistent: false,
        durationSeconds: 4,
      );
      _scheduleUiRefresh();
      return;
    }

    final order = _pendingOutboundOrder!;
    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).where((e) => e.isNotEmpty && e != '--').toSet();
    final validPalletEpcs = <String>{};
    for (final e in order.pallets.values) {
      if (e != null && e.isNotEmpty && e != '--') validPalletEpcs.add(e.toUpperCase());
    }
    for (final code in order.pallets.keys) {
      validPalletEpcs.add(code.toUpperCase());
      final pal = _repo.pallets.where((p) => p.palletCode.toUpperCase() == code.toUpperCase() || p.palletId.toUpperCase() == code.toUpperCase()).firstOrNull;
      if (pal?.rfidEpc != null && pal!.rfidEpc!.isNotEmpty) {
        validPalletEpcs.add(pal.rfidEpc!.toUpperCase());
      }
    }
    for (final it in order.items) {
      if (it.palletEpc.isNotEmpty && it.palletEpc != '--') validPalletEpcs.add(it.palletEpc.toUpperCase());
      if (it.palletCode.isNotEmpty && it.palletCode != '--') validPalletEpcs.add(it.palletCode.toUpperCase());
    }

    final totalExpected = order.items.length;
    final scannedMatching = order.items.where((i) => i.epc.isNotEmpty && i.epc != '--' && _gateScannedTags.containsKey(i.epc.toUpperCase())).length;
    final unexpected = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e) && !validPalletEpcs.contains(e)).toList();

    if (unexpected.isNotEmpty) {
      _cancelAutoConfirm();
      final matchedInRepo = unexpected
          .map((u) => _repo.items.where((i) => i.epc.toUpperCase() == u).firstOrNull)
          .whereType<Item>()
          .toList();
      final String reasonText;
      if (matchedInRepo.isNotEmpty) {
        final firstItem = matchedInRepo.first;
        final extraCount = unexpected.length - 1;
        final extraStr = extraCount > 0 ? ' và $extraCount hàng khác' : '';
        reasonText = 'CẢNH BÁO AN NINH: Hàng không nằm trong đơn xuất! [${firstItem.productName}] (SKU: ${firstItem.sku}, Kệ: ${firstItem.locationId ?? "--"})$extraStr';
      } else {
        final firstEpc = unexpected.first;
        final shortEpc = firstEpc.length > 8 ? '...${firstEpc.substring(firstEpc.length - 8)}' : firstEpc;
        reasonText = 'CẢNH BÁO: Phát hiện ${unexpected.length} chip lạ ($shortEpc) ngoài danh sách xuất kho!';
      }

      SystemSound.play(SystemSoundType.alert);
      _towerLight.triggerWarningRed(
        withBuzzer: !_isBuzzerManuallySilenced,
        reason: reasonText,
        persistent: false,
        durationSeconds: 3,
      );

      for (final unexpEpc in unexpected) {
        final upper = unexpEpc.toUpperCase();
        if (!_securityAlertLoggedEpcs.contains(upper)) {
          _securityAlertLoggedEpcs.add(upper);
          final it = _repo.items.where((i) => i.epc.toUpperCase() == upper).firstOrNull;
          _repo.recordTagLifecycle(
            epc: upper,
            itemId: it?.itemId,
            sku: it?.sku,
            productName: it?.productName ?? 'Chip RFID Lạ (Chưa đăng ký)',
            serialNumber: it?.serialNumber,
            action: TagLifecycleAction.unauthorizedExit,
            previousStatus: it?.status.code,
            newStatus: it?.status.code ?? 'UNAUTHORIZED_STRANGER',
            fromLocation: it?.locationId,
            fromPallet: it?.palletId,
            documentNo: order.orderNo,
            performedBy: _auth.currentUser?.fullName ?? 'Hệ thống Cổng RFID Gate An Ninh',
            device: 'Cổng RFID Desktop Hopeland',
            notes: it != null
                ? '🚨 HÀNG KHÔNG THUỘC ĐƠN XUẤT: Hàng đi kèm xe qua cổng nhưng không nằm trong PO ${order.orderNo}!'
                : '🚨 PHÁT HIỆN CHIP LẠ: Chip không tồn tại trong hệ thống đi qua cổng cùng đơn xuất PO ${order.orderNo}!',
          );
        }
      }
    } else {
      if (latestTag != null) {
        final latestEpc = latestTag.epc.trim().toUpperCase();
        final item = order.items.where((i) => i.epc.toUpperCase() == latestEpc).firstOrNull;
        if (item != null) {
          if (!item.isInStock) {
            _cancelAutoConfirm();
            _towerLight.triggerWarningRed(
              withBuzzer: true,
              reason: 'CẢNH BÁO TỒN KHO: Mã chip $latestEpc (SKU: ${item.sku}) không có trong kho!',
            );
            _scheduleUiRefresh();
            return;
          } else {
            final olderUnscanned = order.items.where((i) =>
                i.sku.toUpperCase() == item.sku.toUpperCase() &&
                i.isInStock &&
                i.fifoPriority < item.fifoPriority &&
                !_gateScannedTags.containsKey(i.epc.toUpperCase())
            ).toList();

            if (olderUnscanned.isNotEmpty) {
              final oldest = olderUnscanned.first;
              _towerLight.triggerWarningRed(
                withBuzzer: false,
                reason: 'LƯU Ý FIFO: Quét lô mới (FIFO #${item.fifoPriority}) của ${item.sku}. Cần lấy lô cũ trước: kệ ${oldest.locationCode} (FIFO #${oldest.fifoPriority})!',
              );
            }
          }
        }
      }

      if (totalExpected > 0 && scannedMatching >= totalExpected) {
        order.isStockSufficient = true;
        _towerLight.triggerPass(
          reason: 'ĐỦ HÀNG XUẤT KHO: $scannedMatching/$totalExpected sản phẩm đã thông qua cổng RFID!',
        );
        _triggerAutoConfirmIfReady(
          totalExpected: totalExpected,
          scannedMatching: scannedMatching,
          unexp: unexpected,
        );
      } else {
        _cancelAutoConfirm();
        if (_isScanning) {
          _towerLight.triggerScanning(
            reason: 'ĐANG ĐỐI SOÁT XUẤT KHO: Cổng RFID đang tiếp nhận dữ liệu ($scannedMatching/$totalExpected)...',
          );
        } else {
          _towerLight.turnOffAll(reason: 'Sẵn sàng đối soát cổng xuất kho');
        }
      }
    }

    _scheduleUiRefresh();
  }

  void _cancelAutoConfirm() {
    if (_autoConfirmTimer != null) {
      _autoConfirmTimer?.cancel();
      _autoConfirmTimer = null;
    }
    if (_isAutoConfirming && mounted) {
      setState(() => _isAutoConfirming = false);
    }
  }

  void _triggerAutoConfirmIfReady({
    required int totalExpected,
    required int scannedMatching,
    required List<String> unexp,
  }) {
    if (_isSaving || _pendingOutboundOrder == null) {
      _cancelAutoConfirm();
      return;
    }
    final order = _pendingOutboundOrder!;
    if (scannedMatching >= totalExpected && unexp.isEmpty) {
      order.isStockSufficient = true;
    }
    if (!order.isStockSufficient || order.items.any((i) => !i.isInStock)) {
      _cancelAutoConfirm();
      return;
    }
    if (_gateScannedTags.isEmpty ||
        scannedMatching == 0 ||
        totalExpected == 0 ||
        scannedMatching < totalExpected ||
        unexp.isNotEmpty ||
        _hasUnresolvedSecurityViolation()) {
      _cancelAutoConfirm();
      return;
    }

    if (_autoConfirmTimer == null && !_isSaving) {
      if (mounted) {
        setState(() => _isAutoConfirming = true);
      }
      _autoConfirmTimer = Timer(const Duration(milliseconds: 1000), () async {
        if (!mounted || _pendingOutboundOrder == null || _isSaving) return;
        await _confirmOutboundDelivery(isAuto: true);
      });
    }
  }

  void _silenceBuzzer() {
    setState(() {
      _isBuzzerManuallySilenced = true;
    });
    _towerLight.turnOffAll(reason: 'Bảo vệ đã tắt còi cảnh báo');
  }

  bool _hasUnresolvedSecurityViolation() {
    if (_duplicateShippedEpcs.isNotEmpty) return true;
    if (_pendingOutboundOrder == null) {
      return _gateScannedTags.isNotEmpty;
    }
    final order = _pendingOutboundOrder!;
    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).where((e) => e.isNotEmpty && e != '--').toSet();
    final validPalletEpcs = <String>{};
    for (final e in order.pallets.values) {
      if (e != null && e.isNotEmpty && e != '--') validPalletEpcs.add(e.toUpperCase());
    }
    for (final code in order.pallets.keys) {
      validPalletEpcs.add(code.toUpperCase());
      final pal = _repo.pallets.where((p) => p.palletCode.toUpperCase() == code.toUpperCase() || p.palletId.toUpperCase() == code.toUpperCase()).firstOrNull;
      if (pal?.rfidEpc != null && pal!.rfidEpc!.isNotEmpty) {
        validPalletEpcs.add(pal.rfidEpc!.toUpperCase());
      }
    }
    for (final it in order.items) {
      if (it.palletEpc.isNotEmpty && it.palletEpc != '--') validPalletEpcs.add(it.palletEpc.toUpperCase());
      if (it.palletCode.isNotEmpty && it.palletCode != '--') validPalletEpcs.add(it.palletCode.toUpperCase());
    }
    return _gateScannedTags.keys.any((e) => !expectedEpcs.contains(e) && !validPalletEpcs.contains(e));
  }

  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(DesktopGoodsDeliveryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      if (_isScanning) _stopGateScan();
    }
  }

  @override
  void dispose() {
    _autoConfirmTimer?.cancel();
    _auth.removeListener(_onThemeChanged);
    _repo.removeListener(_onThemeChanged);
    _eyeCare.removeListener(_onThemeChanged);
    _desktopUhf.removeListener(_onDesktopUhfUpdate);
    _towerLight.removeListener(_onThemeChanged);
    _uiRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _successBannerTimer?.cancel();
    _uhfSub?.cancel();
    _desktopUhfSub?.cancel();
    super.dispose();
  }

  // ---------- SCANNER CONTROLS ----------
  void _toggleGateScan() async {
    if (_isConnectingUhf) return;
    final isScanning = _isScanning || _desktopUhf.isScanning;
    if (isScanning) {
      _stopGateScan();
    } else {
      _startGateScan(durationSeconds: _scanDurationSeconds);
    }
  }

  Future<void> _startGateScan({int durationSeconds = 0}) async {
    if (_isConnectingUhf) return;
    _countdownTimer?.cancel();

    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && !_desktopUhf.isConnected) {
      setState(() => _isConnectingUhf = true);
      try {
        final ok = await _desktopUhf.connectWithSavedConfig();
        if (!ok && !_desktopUhf.isConnected) {
          debugPrint('⚠️ Chưa kết nối được đầu đọc RFID (${_desktopUhf.config.connectionSummary}).');
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 4),
                backgroundColor: const Color(0xFFF59E0B),
                content: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Chưa kết nối được đầu đọc RFID (${_desktopUhf.config.connectionSummary}). Đang ở chế độ quét chờ thiết bị...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      } finally {
        if (mounted) setState(() => _isConnectingUhf = false);
      }
    }

    _uhf.enableScanning('xuat_kho');
    _uhf.startInventory();
    if (!isTest && _desktopUhf.isConnected) {
      await _desktopUhf.startInventory();
    }

    if (mounted) {
      setState(() {
        _isScanning = true;
        _isBuzzerManuallySilenced = false;
        _scanCountdown = durationSeconds > 0 ? durationSeconds : 0;
      });
    }

    _evaluateGateSecurityAndTowerLight();

    if (durationSeconds > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_scanCountdown > 1) {
          setState(() => _scanCountdown--);
        } else {
          timer.cancel();
          _stopGateScan();
        }
      });
    }
  }

  Future<void> _stopGateScan() async {
    _isScanning = false;
    _countdownTimer?.cancel();
    _uhf.disableScanning();
    await _desktopUhf.stopInventory();

    final hasViolation = _hasUnresolvedSecurityViolation();

    if (hasViolation) {
      _towerLight.triggerWarningRed(
        withBuzzer: false,
        reason: 'CẢNH BÁO AN NINH: Phát hiện hàng trong kho / chip lạ qua cổng (Chờ xử lý)!',
        persistent: false,
        durationSeconds: 3,
      );
    } else {
      _towerLight.turnOffAll(reason: 'Đã dừng quét cổng xuất kho');
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        _scanCountdown = _scanDurationSeconds;
      });
    }

    if (_pendingOutboundOrder != null) {
      final order = _pendingOutboundOrder!;
      final totalExpected = order.items.length;
      final scannedMatching = order.items.where((i) => i.epc.isNotEmpty && i.epc != '--' && _gateScannedTags.containsKey(i.epc.toUpperCase())).length;
      final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).where((e) => e.isNotEmpty && e != '--').toSet();
      final validPalletEpcs = <String>{};
      for (final e in order.pallets.values) {
        if (e != null && e.isNotEmpty && e != '--') validPalletEpcs.add(e.toUpperCase());
      }
      for (final code in order.pallets.keys) {
        validPalletEpcs.add(code.toUpperCase());
      }
      for (final it in order.items) {
        if (it.palletEpc.isNotEmpty && it.palletEpc != '--') validPalletEpcs.add(it.palletEpc.toUpperCase());
        if (it.palletCode.isNotEmpty && it.palletCode != '--') validPalletEpcs.add(it.palletCode.toUpperCase());
      }
      final unexpected = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e) && !validPalletEpcs.contains(e)).toList();
      if (totalExpected > 0 && scannedMatching >= totalExpected && unexpected.isEmpty && !hasViolation) {
        order.isStockSufficient = true;
        _triggerAutoConfirmIfReady(
          totalExpected: totalExpected,
          scannedMatching: scannedMatching,
          unexp: unexpected,
        );
      }
    }
  }

  void _clearGateScan() {
    _isScanning = false;
    _cancelAutoConfirm();
    _stopGateScan();
    setState(() {
      _gateScannedTags.clear();
      _securityAlertLoggedEpcs.clear();
      _duplicateShippedEpcs.clear();
      _duplicateShippedAlertMessage = null;
      _isBuzzerManuallySilenced = false;
    });
    _uhf.clearTags();
    _desktopUhf.clearTags();
    _towerLight.turnOffAll();
  }

  /// Dọn dẹp trạng thái quét trước khi nạp file mới (bảo toàn 100% dữ liệu đơn hàng trong kho)
  Future<void> _cleanupPendingDraftOutboundOrders() async {
    // Không tự ý xóa đơn hàng hợp lệ trong CSDL khi nạp file mới.
    // Việc cập nhật hoặc tạo mới đơn hàng đã được đối soát an toàn theo mã PO (R1, R3).
  }

  // ---------- NẠP FILE XUẤT KHO (EXCEL / CSV: MÃ SKU, MÃ HÀNG, SỐ LƯỢNG) ----------
  Future<void> _pickAndLoadOutboundFile() async {
    _cancelAutoConfirm();
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final outboundResult = await _excelService.pickAndParseOutboundExcel();
      if (outboundResult == null) return;

      await _stopGateScan();
      _clearGateScan();
      await _cleanupPendingDraftOutboundOrders();

      final now = DateTime.now();
      final orderNo = outboundResult.orderNo.isNotEmpty
          ? outboundResult.orderNo
          : 'XK-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final detectedCustomer = outboundResult.customer.isNotEmpty
          ? outboundResult.customer
          : 'Khách mua xuất kho';

      final Map<String, String?> pallets = {};
      final List<Map<String, dynamic>> rawRequests = [];

      for (var r in outboundResult.rows) {
        if (r.palletCode.isNotEmpty && r.palletCode != '--') {
          pallets[r.palletCode] = r.palletEpc.isNotEmpty ? r.palletEpc : r.palletCode;
        }
        for (int i = 0; i < r.quantity; i++) {
          rawRequests.add({
            'sku': r.sku,
            'productId': r.productId,
            'itemId': r.productId,
            'cartonCode': r.cartonCode.isNotEmpty ? r.cartonCode : '--',
            'palletCode': r.palletCode.isNotEmpty ? r.palletCode : '--',
            'supplier': '--',
            'customer': r.customer.isNotEmpty ? r.customer : detectedCustomer,
            'productName': r.productName,
            'palletEpc': r.palletEpc.isNotEmpty ? r.palletEpc : '--',
            'epc': (r.epc != null && r.epc!.isNotEmpty) ? r.epc! : '--',
          });
        }
      }

      if (rawRequests.isEmpty) {
        throw Exception('Không tìm thấy danh sách mã hàng hợp lệ trong tệp!');
      }

      // Đối soát tồn kho thực tế và kiểm tra vị trí kệ & thứ tự FIFO
      final validation = _repo.validateOutboundInventoryAndFifo(requestedItems: rawRequests);

      final hasExplicitEpc = outboundResult.rows.any((r) => r.epc != null && r.epc!.isNotEmpty);
      final List<_PendingOutboundItem> validatedItems = validation.items.map((vi) => _PendingOutboundItem(
        sku: vi.sku,
        productId: (vi.productId != null && vi.productId!.isNotEmpty) ? vi.productId! : vi.sku,
        cartonCode: vi.cartonCode,
        palletCode: vi.palletCode,
        supplier: vi.supplier,
        customer: vi.customer.isNotEmpty && vi.customer != '--' ? vi.customer : detectedCustomer,
        productName: _repo.getSkuProductName(vi.sku, vi.productName),
        palletEpc: vi.palletEpc,
        epc: hasExplicitEpc ? vi.epc : '--',
        serialNumber: hasExplicitEpc ? (vi.serialNumber ?? '--') : '--',
        isInStock: vi.isInStock,
        locationCode: vi.locationCode,
        inboundTime: vi.inboundTime,
        fifoPriority: vi.fifoPriority,
        fifoWarning: vi.fifoWarning,
      )).toList();

      // Lưu đơn vào CSDL và đồng bộ lên Supabase Cloud TRƯỚC khi kích hoạt _pendingOutboundOrder trên giao diện
      final outboundId = 'OUT-${now.millisecondsSinceEpoch}';
      final Map<String, OutboundOrderDetail> detailsBySku = {};
      for (final it in validatedItems) {
        final sku = it.sku.isNotEmpty ? it.sku : 'MULTI';
        final matchingProd = _repo.products.where((p) => p.sku.trim().toUpperCase() == sku.trim().toUpperCase()).firstOrNull;
        final effectiveProdId = matchingProd?.productId ?? sku;
        final pName = _repo.getSkuProductName(sku, it.productName.isNotEmpty ? it.productName : 'Sản phẩm xuất kho');

        if (!detailsBySku.containsKey(sku)) {
          detailsBySku[sku] = OutboundOrderDetail(
            productId: effectiveProdId,
            sku: sku,
            productName: pName,
            requiredQty: 1,
            pickedQty: 0,
            epcList: it.epc.isNotEmpty && it.epc != '--' ? [it.epc] : [],
          );
        } else {
          final cur = detailsBySku[sku]!;
          detailsBySku[sku] = OutboundOrderDetail(
            productId: cur.productId,
            sku: cur.sku,
            productName: cur.productName,
            requiredQty: cur.requiredQty + 1,
            pickedQty: 0,
            epcList: [...?cur.epcList, if (it.epc.isNotEmpty && it.epc != '--') it.epc],
          );
        }
      }

      final cleanPoUpper = orderNo.trim().toUpperCase();
      final existing = _repo.outboundOrders.where((o) =>
          o.poNo.trim().toUpperCase() == cleanPoUpper ||
          o.outboundOrderId.trim().toUpperCase() == cleanPoUpper).firstOrNull;
      late final OutboundOrder finalOrder;
      if (existing == null) {
        final newOrder = OutboundOrder(
          outboundOrderId: outboundId,
          poNo: orderNo,
          customer: detectedCustomer,
          status: OutboundOrderStatus.newOrder,
          createdAt: now,
          details: detailsBySku.values.toList(),
        );
        await _repo.addOutboundOrder(newOrder);
        await _supabaseSync.syncNow();
        finalOrder = newOrder;
      } else {
        if (existing.status != OutboundOrderStatus.shipped) {
          existing.details
            ..clear()
            ..addAll(detailsBySku.values);
          existing.status = OutboundOrderStatus.newOrder;
          await _repo.addOutboundOrder(existing);
          await _supabaseSync.syncNow();
        }
        finalOrder = existing;
      }

      _cancelAutoConfirm();
      _clearGateScan();

      if (mounted) {
        setState(() {
          _isScanning = false;
          _isAutoConfirming = false;
          _gateScannedTags.clear();
          _pendingOutboundOrder = _PendingOutboundOrder(
            outboundOrderId: finalOrder.outboundOrderId,
            orderNo: orderNo,
            customer: detectedCustomer,
            items: validatedItems,
            pallets: pallets,
            fileName: outboundResult.fileName,
            isStockSufficient: validation.isStockSufficient,
            shortageCount: validation.shortageCount,
            shortageBySku: validation.shortageBySku,
          );
        });
      }

      if (mounted) {
        if (!validation.isStockSufficient) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 2),
              content: Text('⚠️ CẢNH BÁO TỒN KHO: Không đủ hàng tồn để xuất (Thiếu ${validation.shortageCount} món)! Đã khóa nút xác nhận xuất.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
          duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF10B981),
              content: Text('✓ Đã nạp thành công ${validatedItems.length} chip xuất kho từ file "${outboundResult.fileName}" (Đủ tồn kho & đã định vị kệ)'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Lỗi nạp file xuất hàng: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------- NẠP FILE ĐƠN XUẤT HÀNG PO (EXCEL / CSV) ----------
  Future<void> _pickAndLoadOutboundPoFile() async {
    _cancelAutoConfirm();
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final rows = await _excelService.pickAndParseBatchOrdersExcel();
      if (rows == null || rows.isEmpty) return;

      await _stopGateScan();
      _clearGateScan();
      await _cleanupPendingDraftOutboundOrders();

      final Map<String, String?> pallets = {};
      String orderNo = 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      String customer = 'Xuất Kho';
      final List<Map<String, dynamic>> rawRequests = [];

      for (var r in rows) {
        final po = (r['orderNo'] ?? '').toString().trim();
        if (po.isNotEmpty) orderNo = po;
        final cust = (r['customer'] ?? r['supplier'] ?? '').toString().trim();
        if (cust.isNotEmpty) customer = cust;

        final sku = (r['sku'] ?? '--').toString().trim();
        final qty = (r['quantity'] as int?) ?? 1;
        final prodName = (r['productName'] ?? 'Sản phẩm xuất kho').toString().trim();
        final rowEpc = (r['epc'] ?? '').toString().trim().toUpperCase();

        final rowCarton = (r['cartonCode'] ?? '').toString().trim();
        final rowPallet = (r['palletCode'] ?? '').toString().trim();
        final rowPalletEpc = (r['palletEpc'] ?? '').toString().trim();

        if (rowPallet.isNotEmpty && rowPallet != '--') {
          pallets[rowPallet] = rowPalletEpc.isNotEmpty ? rowPalletEpc : rowPallet;
        }

        if (rowEpc.isNotEmpty) {
          rawRequests.add({
            'sku': sku,
            'cartonCode': rowCarton.isNotEmpty ? rowCarton : '--',
            'palletCode': rowPallet.isNotEmpty ? rowPallet : '--',
            'customer': customer,
            'productName': prodName,
            'palletEpc': rowPalletEpc.isNotEmpty ? rowPalletEpc : '--',
            'epc': rowEpc,
          });
        } else {
          for (int i = 0; i < qty; i++) {
            rawRequests.add({
              'sku': sku,
              'cartonCode': rowCarton.isNotEmpty ? rowCarton : '--',
              'palletCode': rowPallet.isNotEmpty ? rowPallet : '--',
              'customer': customer,
              'productName': prodName,
              'palletEpc': rowPalletEpc.isNotEmpty ? rowPalletEpc : '--',
              'epc': '--',
            });
          }
        }
      }

      if (rawRequests.isEmpty) {
        throw Exception('Không tìm thấy danh sách mã hàng / chip hợp lệ trong file PO!');
      }

      final validation = _repo.validateOutboundInventoryAndFifo(requestedItems: rawRequests);
      final hasExplicitEpc = rows.any((r) => (r['epc'] ?? '').toString().trim().isNotEmpty);
      final List<_PendingOutboundItem> validatedItems = validation.items.map((vi) => _PendingOutboundItem(
        sku: vi.sku,
        productId: (vi.productId != null && vi.productId!.isNotEmpty) ? vi.productId! : vi.sku,
        cartonCode: vi.cartonCode,
        palletCode: vi.palletCode,
        supplier: vi.supplier,
        customer: vi.customer.isNotEmpty && vi.customer != '--' ? vi.customer : customer,
        productName: _repo.getSkuProductName(vi.sku, vi.productName),
        palletEpc: vi.palletEpc,
        epc: hasExplicitEpc ? vi.epc : '--',
        serialNumber: hasExplicitEpc ? (vi.serialNumber ?? '--') : '--',
        isInStock: vi.isInStock,
        locationCode: vi.locationCode,
        inboundTime: vi.inboundTime,
        fifoPriority: vi.fifoPriority,
        fifoWarning: vi.fifoWarning,
      )).toList();

      // Lưu đơn PO vào CSDL và đồng bộ lên Supabase Cloud TRƯỚC khi kích hoạt _pendingOutboundOrder
      final outboundId = 'OUT-${DateTime.now().millisecondsSinceEpoch}';
      final Map<String, OutboundOrderDetail> detailsBySku = {};
      for (final it in validatedItems) {
        final sku = it.sku.isNotEmpty ? it.sku : 'MULTI';
        final matchingProd = _repo.products.where((p) => p.sku.trim().toUpperCase() == sku.trim().toUpperCase()).firstOrNull;
        final effectiveProdId = matchingProd?.productId ?? sku;
        final pName = _repo.getSkuProductName(sku, it.productName.isNotEmpty ? it.productName : 'Sản phẩm xuất kho');

        if (!detailsBySku.containsKey(sku)) {
          detailsBySku[sku] = OutboundOrderDetail(
            productId: effectiveProdId,
            sku: sku,
            productName: pName,
            requiredQty: 1,
            pickedQty: 0,
            epcList: it.epc.isNotEmpty && it.epc != '--' ? [it.epc] : [],
          );
        } else {
          final cur = detailsBySku[sku]!;
          detailsBySku[sku] = OutboundOrderDetail(
            productId: cur.productId,
            sku: cur.sku,
            productName: cur.productName,
            requiredQty: cur.requiredQty + 1,
            pickedQty: 0,
            epcList: [...?cur.epcList, if (it.epc.isNotEmpty && it.epc != '--') it.epc],
          );
        }
      }

      final cleanPoUpper = orderNo.trim().toUpperCase();
      final existingPo = _repo.outboundOrders.where((o) =>
          o.poNo.trim().toUpperCase() == cleanPoUpper ||
          o.outboundOrderId.trim().toUpperCase() == cleanPoUpper).firstOrNull;
      final OutboundOrder finalPoOrder;
      if (existingPo == null) {
        final newOrder = OutboundOrder(
          outboundOrderId: outboundId,
          poNo: orderNo,
          customer: customer,
          status: OutboundOrderStatus.newOrder,
          createdAt: DateTime.now(),
          details: detailsBySku.values.toList(),
        );
        await _repo.addOutboundOrder(newOrder);
        await _supabaseSync.syncNow();
        finalPoOrder = newOrder;
      } else {
        if (existingPo.status != OutboundOrderStatus.shipped) {
          existingPo.details
            ..clear()
            ..addAll(detailsBySku.values);
          existingPo.status = OutboundOrderStatus.newOrder;
          await _repo.addOutboundOrder(existingPo);
          await _supabaseSync.syncNow();
        }
        finalPoOrder = existingPo;
      }

      _cancelAutoConfirm();
      _clearGateScan();

      if (mounted) {
        setState(() {
          _isScanning = false;
          _isAutoConfirming = false;
          _gateScannedTags.clear();
          _pendingOutboundOrder = _PendingOutboundOrder(
            orderNo: orderNo,
            customer: customer,
            outboundOrderId: finalPoOrder.outboundOrderId,
            items: validatedItems,
            pallets: pallets,
            fileName: 'File PO: $orderNo',
            isStockSufficient: validation.isStockSufficient,
            shortageCount: validation.shortageCount,
            shortageBySku: validation.shortageBySku,
          );
        });
      }

      if (mounted) {
        if (!validation.isStockSufficient) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 2),
              content: Text('⚠️ CẢNH BÁO TỒN KHO: Đơn $orderNo thiếu ${validation.shortageCount} sản phẩm! Đã khóa xác nhận xuất.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
          duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF10B981),
              content: Text('✓ Đã nạp thành công ${validatedItems.length} sản phẩm từ file PO! Sẵn sàng quét qua cổng.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Lỗi nạp file PO: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------- TẢI FILE MẪU XUẤT KHO (LẺ HOẶC PALLET) ----------
  Future<void> _downloadOutboundTemplate() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Chọn mẫu file Excel xuất kho', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hệ thống hỗ trợ 2 định dạng file xuất kho chuẩn:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 12),
            ListTile(
              tileColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              leading: const Icon(Icons.inventory_2_outlined, color: Color(0xFF06B6D4)),
              title: const Text('Mẫu xuất hàng lẻ (Ảnh 3)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('CARTON CODE, NAME, SL, SKU', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              onTap: () => Navigator.pop(ctx, 'retail'),
            ),
            const SizedBox(height: 8),
            ListTile(
              tileColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              leading: const Icon(Icons.pallet, color: Color(0xFF10B981)),
              title: const Text('Mẫu xuất gom Pallet (Ảnh 2)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('CARTON CODE, NAME, SL, SKU, NCC, BARCODE PALET, EPC PALLET', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              onTap: () => Navigator.pop(ctx, 'pallet'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );

    if (choice == null) return;

    try {
      final String path;
      if (choice == 'pallet') {
        path = await _excelService.exportOutboundPalletTemplate();
      } else {
        path = await _excelService.exportOutboundTemplate();
      }
      if (!mounted) return;
      if (path.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã tải file mẫu xuất kho thành công: $path'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Lỗi tải file mẫu xuất kho: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ---------- CHỌN TỪ ĐƠN XUẤT CÓ SẴN TRONG CSDL ----------
  void _loadOutboundOrderFromDb(OutboundOrder order) {
    final Map<String, String?> pallets = {};
    final List<Map<String, dynamic>> rawRequests = [];

    for (final detail in order.details) {
      final remainingQty = (detail.requiredQty - detail.pickedQty).clamp(0, detail.requiredQty);
      final prodId = detail.productId.isNotEmpty ? detail.productId : detail.sku;
      if (detail.epcList != null && detail.epcList!.isNotEmpty) {
        for (final epc in detail.epcList!) {
          final it = _repo.items.where((i) => i.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;
          if (it == null || it.status != ItemStatus.out) {
            rawRequests.add({
              'sku': detail.sku,
              'productId': prodId,
              'itemId': prodId,
              'cartonCode': '--',
              'palletCode': '--',
              'customer': order.customer,
              'productName': detail.productName,
              'palletEpc': '--',
              'epc': epc,
            });
          }
        }
      } else {
        for (int i = 0; i < remainingQty; i++) {
          rawRequests.add({
            'sku': detail.sku,
            'productId': prodId,
            'itemId': prodId,
            'cartonCode': '--',
            'palletCode': '--',
            'customer': order.customer,
            'productName': detail.productName,
            'palletEpc': '--',
            'epc': '--',
          });
        }
      }
    }

    final validation = _repo.validateOutboundInventoryAndFifo(requestedItems: rawRequests);
    final hasExplicitEpc = order.details.any((d) => d.epcList != null && d.epcList!.isNotEmpty);
    final List<_PendingOutboundItem> validatedItems = validation.items.map((vi) => _PendingOutboundItem(
      sku: vi.sku,
      productId: (vi.productId != null && vi.productId!.isNotEmpty) ? vi.productId! : vi.sku,
      cartonCode: vi.cartonCode,
      palletCode: vi.palletCode,
      supplier: vi.supplier,
      customer: vi.customer.isNotEmpty && vi.customer != '--' ? vi.customer : order.customer,
      productName: vi.productName,
      palletEpc: vi.palletEpc,
      epc: hasExplicitEpc ? vi.epc : '--',
      serialNumber: hasExplicitEpc ? (vi.serialNumber ?? '--') : '--',
      isInStock: vi.isInStock,
      locationCode: vi.locationCode,
      inboundTime: vi.inboundTime,
      fifoPriority: vi.fifoPriority,
      fifoWarning: vi.fifoWarning,
    )).toList();

    _clearGateScan();
    setState(() {
      _pendingOutboundOrder = _PendingOutboundOrder(
        orderNo: order.poNo,
        customer: order.customer,
        outboundOrderId: order.outboundOrderId,
        items: validatedItems,
        pallets: pallets,
        fileName: 'Đơn xuất: ${order.poNo}',
        isStockSufficient: validation.isStockSufficient,
        shortageCount: validation.shortageCount,
        shortageBySku: validation.shortageBySku,
      );
    });

    if (mounted) {
      if (!validation.isStockSufficient) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 2),
            content: Text('⚠️ CẢNH BÁO TỒN KHO: Đơn ${order.poNo} thiếu ${validation.shortageCount} sản phẩm! Đã khóa xác nhận xuất.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã nạp đơn ${order.poNo} (${validatedItems.length} sản phẩm - Sẵn sàng đối soát cổng)'),
          ),
        );
      }
    }
  }

  void _showSelectOrderDialog() {
    final c = _eyeCare.colors;
    final orders = _repo.outboundOrders.where((o) => o.status != OutboundOrderStatus.shipped).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: c.rfidCyan, size: 22),
            const SizedBox(width: 8),
            Text('CHỌN ĐƠN XUẤT KHO TỪ HỆ THỐNG', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: orders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Không có đơn xuất kho nào đang chờ trên hệ thống.', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                  itemBuilder: (ctx, idx) {
                    final o = orders[idx];
                    final totalQty = o.details.fold(0, (s, d) => s + d.requiredQty);
                    final pickedQty = o.details.fold(0, (s, d) => s + d.pickedQty);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      title: Text(o.poNo, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5)),
                      subtitle: Text('${o.customer} • Đã nhặt: $pickedQty/$totalQty SP • ${DateFormat("dd/MM/yyyy HH:mm").format(o.createdAt)}', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.rfidCyan,
                          foregroundColor: const Color(0xFFFFFFFF),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _loadOutboundOrderFromDb(o);
                        },
                        child: const Text('CHỌN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }

  // ---------- XÁC NHẬN XUẤT KHO & CẬP NHẬT CƠ SỞ DỮ LIỆU ----------
  Future<void> _confirmOutboundDelivery({bool isAuto = false}) async {
    _cancelAutoConfirm();
    if (_isSaving || _pendingOutboundOrder == null) return;
    final order = _pendingOutboundOrder!;
    final totalExpected = order.items.length;
    final scannedMatching = order.items.where((i) => i.epc.isNotEmpty && i.epc != '--' && _gateScannedTags.containsKey(i.epc.toUpperCase())).length;
    if (totalExpected > 0 && scannedMatching >= totalExpected && order.items.every((i) => i.isInStock)) {
      order.isStockSufficient = true;
    }

    if (!order.isStockSufficient || order.items.any((i) => !i.isInStock)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Không thể xuất kho: Kho không đủ tồn kho (Thiếu ${order.shortageCount} sản phẩm)! Vui lòng kiểm tra lại tồn kho.'),
        ),
      );
      return;
    }

    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).where((e) => e.isNotEmpty && e != '--').toSet();
    final validPalletEpcs = <String>{};
    for (final e in order.pallets.values) {
      if (e != null && e.isNotEmpty && e != '--') validPalletEpcs.add(e.toUpperCase());
    }
    for (final code in order.pallets.keys) {
      validPalletEpcs.add(code.toUpperCase());
      final pal = _repo.pallets.where((p) => p.palletCode.toUpperCase() == code.toUpperCase() || p.palletId.toUpperCase() == code.toUpperCase()).firstOrNull;
      if (pal?.rfidEpc != null && pal!.rfidEpc!.isNotEmpty) {
        validPalletEpcs.add(pal.rfidEpc!.toUpperCase());
      }
    }
    for (final it in order.items) {
      if (it.palletEpc.isNotEmpty && it.palletEpc != '--') validPalletEpcs.add(it.palletEpc.toUpperCase());
      if (it.palletCode.isNotEmpty && it.palletCode != '--') validPalletEpcs.add(it.palletCode.toUpperCase());
    }

    final unexp = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e) && !validPalletEpcs.contains(e)).toList();

    if (_gateScannedTags.isEmpty || scannedMatching == 0 || totalExpected == 0 || scannedMatching < totalExpected || unexp.isNotEmpty || _hasUnresolvedSecurityViolation() || _duplicateShippedEpcs.isNotEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xFFEF4444),
          content: Text(_duplicateShippedAlertMessage ?? 'Không thể xuất kho: Chưa quét đủ sản phẩm, có chip lạ hoặc trùng EPC đã xuất kho!'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isScanning) await _stopGateScan();

      final actualScannedEpcs = expectedEpcs.where((e) => _gateScannedTags.containsKey(e)).toList();
      if (actualScannedEpcs.isEmpty) {
        setState(() => _isSaving = false);
        return;
      }

      final shippedCount = await _repo.confirmGateOutbound(
        orderId: order.outboundOrderId,
        poNo: order.orderNo,
        customer: order.customer,
        scannedEpcs: actualScannedEpcs,
        performedBy: _auth.currentUser?.fullName ?? 'Cổng RFID Gate Outbound',
      );

      _towerLight.triggerPass(reason: 'HOÀN TẤT XUẤT KHO: $shippedCount sản phẩm đã thông qua cổng');
      await _supabaseSync.syncNow();

      if (!mounted) return;

      // Banner thông báo thành công
      setState(() {
        _lastSuccessOrderNo = order.orderNo;
        _lastSuccessPalletCode = order.pallets.keys.firstOrNull ?? '--';
        _lastSuccessCount = order.items.length;
        _pendingOutboundOrder = null;
        _clearGateScan();
      });

      _successBannerTimer?.cancel();
      _successBannerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _lastSuccessOrderNo = null);
      });

      if (isAuto) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✓ ĐÃ TỰ ĐỘNG XUẤT KHO HOÀN TẤT: $shippedCount sản phẩm cho đơn ${order.orderNo}! Tồn kho và vị trí đã được giải phóng.',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: _eyeCare.colors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 48, color: Color(0xFF10B981)),
                ),
                const SizedBox(height: 14),
                Text(
                  'XUẤT KHO THÀNH CÔNG!',
                  style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Đã thông qua cổng và xuất $shippedCount sản phẩm.\nSố lượng tồn vị trí đã được tự động giải phóng và trừ tồn kho.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('TIẾP TỤC ĐƠN MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi xác nhận xuất kho: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------- 3 Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ (ĐỀU NHAU, 3 MÀU XANH - VÀNG - ĐỎ) ----------
  Widget _buildMetricBadge({
    required String label,
    required int count,
    required Color color,
    required EyeCareColors c,
    double width = 80,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$count',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== GIAO DIỆN CHÍNH (BUILD) ====================
  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        const minW = 1150.0;
        const minH = 650.0;
        final isNarrow = constraints.maxWidth < minW;
        final isShort = constraints.maxHeight < minH;

        final contentW = isNarrow ? minW : constraints.maxWidth;
        final contentH = isShort ? minH : constraints.maxHeight;

        Widget mainContent = Container(
          width: contentW,
          height: contentH,
          color: c.bgDeep,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh tiêu đề Header đồng bộ với Nhập Kho
              _buildTopHeaderBar(c, isNarrow),
              const SizedBox(height: 10),

              // Nội dung chính: Cổng đối soát xuất kho RFID
              Expanded(
                child: _buildOutboundGateMonitor(c),
              ),
              const SizedBox(height: 10),

              // Thanh điều khiển dưới cùng: Nút Quét, Thời lượng, Trạng thái Đầu đọc (LUÔN CỐ ĐỊNH Ở ĐÁY)
              _buildBottomControlBarWrapper(c),
            ],
          ),
        );

        if (isNarrow || isShort) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: mainContent,
            ),
          );
        }
        return mainContent;
      },
    );
  }

  // ---------- 1. THANH TIÊU ĐỀ HEADER (NÚT XUẤT HÀNG DROPDOWN CYAN GIỐNG NHẬP HÀNG) ----------
  Widget _buildTopHeaderBar(EyeCareColors c, bool isNarrow) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Tiêu đề
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.outbox_rounded, color: Color(0xFF10B981), size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'QUẢN LÝ XUẤT KHO RFID',
                    style: TextStyle(color: c.textPrimary, fontSize: isNarrow ? 15 : 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Kiểm đếm hàng hóa • Cổng quét RFID đối soát xuất kho',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),

          // Nhóm nút thao tác: [XUẤT HÀNG ▼] màu cyan + LỊCH SỬ XUẤT KHO + LÀM MỚI
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nút XUẤT HÀNG dạng PopupMenuButton màu Cyan giống Nhập Hàng
              PopupMenuButton<String>(
                tooltip: 'Chọn nạp file xuất hàng',
                onSelected: (val) {
                  if (val == 'file_excel') {
                    _pickAndLoadOutboundFile();
                  } else if (val == 'file_template') {
                    _downloadOutboundTemplate();
                  } else if (val == 'file_po') {
                    _pickAndLoadOutboundPoFile();
                  } else if (val == 'select_order') {
                    _showSelectOrderDialog();
                  } else if (val == 'clear_pending') {
                    setState(() {
                      _pendingOutboundOrder = null;
                      _clearGateScan();
                    });
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem<String>(
                    value: 'file_excel',
                    enabled: !_isImporting,
                    child: SizedBox(
                      width: 360,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.table_chart, color: Color(0xFF10B981), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Nhập File Excel / CSV (.xlsx, .csv)',
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Nạp file xuất gồm Mã SKU, Mã Hàng, Số lượng (Tự đối chiếu EPC CSDL)',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                  softWrap: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'file_template',
                    child: SizedBox(
                      width: 360,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.download_rounded, color: Color(0xFF3B82F6), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Tải File Mẫu Xuất Kho (Excel)',
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'File mẫu gồm cột Mã SKU, Mã Hàng, Số lượng (Không cần nhập EPC)',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                  softWrap: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'file_po',
                    enabled: !_isImporting,
                    child: SizedBox(
                      width: 360,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: c.rfidCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.receipt_long, color: c.rfidCyan, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Nhập Từ PO (File PO)',
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Nạp file đơn đặt hàng / xuất kho: Mã PO, SKU, Số lượng',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                  softWrap: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'select_order',
                    enabled: !_isImporting,
                    child: SizedBox(
                      width: 360,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.cloud_download_outlined, color: Color(0xFFF59E0B), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Chọn Đơn Xuất Có Sẵn Từ Hệ Thống',
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Mở đơn xuất kho đã tạo để đối soát qua cổng hoặc kiểm tra',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                  softWrap: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_pendingOutboundOrder != null) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'clear_pending',
                      enabled: !_isImporting,
                      child: SizedBox(
                        width: 360,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Xóa Danh Sách Đang Chờ Xuất',
                                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Xóa toàn bộ dữ liệu đơn chờ để chọn nạp file khác',
                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                                    softWrap: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isImporting ? c.rfidCyan.withValues(alpha: 0.5) : c.rfidCyan,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: c.rfidCyan.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isImporting)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFFFFF)),
                        )
                      else
                        const Icon(Icons.file_upload_outlined, size: 18, color: Color(0xFFFFFFFF)),
                      const SizedBox(width: 6),
                      Text(
                        _isImporting ? 'ĐANG XỬ LÝ...' : 'XUẤT HÀNG',
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFFFFFFF)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),


              // Nút Làm Mới
              Tooltip(
                message: 'Đồng bộ & làm mới dữ liệu từ CSDL',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  onPressed: () async {
                    await _repo.reloadFromDatabase();
                    await _supabaseSync.syncNow();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 2. MÀN HÌNH CHỜ QUÉT KHI CHƯA NẠP FILE ----------
  Widget _buildIdleGateMonitor(EyeCareColors c) {
    final pendingOrders = _repo.outboundOrders
        .where((o) => o.status != OutboundOrderStatus.shipped)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final scannedTagsList = _gateScannedTags.values.toList();
    final unauthorizedItems = _gateScannedTags.keys
        .map((e) => _repo.items.where((i) => i.epc.toUpperCase() == e).firstOrNull)
        .whereType<Item>()
        .toList();
    final strangerEpcs = _gateScannedTags.keys
        .where((e) => !_repo.items.any((i) => i.epc.toUpperCase() == e))
        .toList();
    final hasSecurityViolation = unauthorizedItems.isNotEmpty || strangerEpcs.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Cổng RFID sẵn sàng tiếp nhận hàng xuất
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.sensors, size: 28, color: c.rfidCyan),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG XUẤT',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Bấm nút [BẮT ĐẦU QUÉT] ở thanh điều khiển bên dưới để kiểm tra cổng & chống thất thoát, hoặc chọn đơn xuất kho để tự động đối soát.',
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.table_chart, size: 15),
                  label: const Text('NẠP EXCEL / CSV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: _pickAndLoadOutboundFile,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.rfidCyan,
                    side: BorderSide(color: c.rfidCyan),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.receipt_long, size: 15),
                  label: const Text('NẠP FILE PO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: _pickAndLoadOutboundPoFile,
                ),
              ],
            ),
          ),

          // Banner Báo Động An Ninh: Phát hiện hàng hóa trong kho qua cổng khi chưa có đơn xuất hoặc chip lạ
          if (hasSecurityViolation) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emergency_rounded, color: Color(0xFFEF4444), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unauthorizedItems.isNotEmpty
                              ? '🚨 BÁO ĐỘNG AN NINH: PHÁT HIỆN ${unauthorizedItems.length} HÀNG HÓA TRONG KHO${strangerEpcs.isNotEmpty ? " VÀ ${strangerEpcs.length} CHIP LẠ" : ""} QUA CỔNG KHI CHƯA CÓ LỆNH XUẤT!'
                              : '🚨 BÁO ĐỘNG AN NINH: PHÁT HIỆN ${strangerEpcs.length} CHIP LẠ QUA CỔNG KHI CHƯA CÓ LỆNH XUẤT!',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          unauthorizedItems.isNotEmpty
                              ? 'Đèn tháp Đỏ & Còi báo động đang hú. Mặt hàng: ${unauthorizedItems.map((u) => "${u.productName} (Kệ: ${u.locationId ?? '--'})").take(3).join(", ")}${unauthorizedItems.length > 3 ? "..." : ""}. Yêu cầu dừng xe/người để kiểm tra chống thất thoát!'
                              : 'Đèn tháp Đỏ & Còi báo động đang hú. Phát hiện mã chip lạ: ${strangerEpcs.take(3).join(", ")}${strangerEpcs.length > 3 ? "..." : ""}. Yêu cầu kiểm tra người/xe qua cổng!',
                          style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                    ),
                    icon: const Icon(Icons.volume_off, size: 15),
                    label: const Text('TẮT CÒI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: _silenceBuzzer,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                    ),
                    icon: const Icon(Icons.delete_sweep, size: 15),
                    label: const Text('XÓA QUÉT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: _clearGateScan,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Nội dung bên dưới: Chia 2 cột nếu có thẻ quét tự do tại cổng, hoặc 1 bảng danh sách đơn xuất
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Khối danh sách đơn xuất chờ quét
                Expanded(
                  flex: scannedTagsList.isNotEmpty ? 6 : 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header khối đơn xuất
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: c.bgDeep,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                            border: Border(bottom: BorderSide(color: c.border)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 16, color: c.rfidCyan),
                              const SizedBox(width: 8),
                              Text(
                                'DANH SÁCH ĐƠN XUẤT CHỜ QUÉT (${pendingOrders.length})',
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Bấm chọn đơn để nạp đối soát qua cổng RFID',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Danh sách đơn xuất
                        Expanded(
                          child: pendingOrders.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.inbox_outlined, size: 42, color: c.textSecondary.withValues(alpha: 0.35)),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Chưa có đơn xuất nào trong hệ thống',
                                        style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Vui lòng bấm [NẠP EXCEL / CSV] hoặc [NẠP FILE PO] ở trên để tải đơn vào hệ thống.',
                                        style: TextStyle(color: c.textMuted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(10),
                                  itemCount: pendingOrders.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                                  itemBuilder: (ctx, idx) {
                                    final o = pendingOrders[idx];
                                    final totalQty = o.details.fold(0, (s, d) => s + d.requiredQty);
                                    final pickedQty = o.details.fold(0, (s, d) => s + d.pickedQty);
                                    final isPartial = pickedQty > 0 && pickedQty < totalQty;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: c.bgDeep,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isPartial ? const Color(0xFFF59E0B).withValues(alpha: 0.5) : c.border,
                                          width: isPartial ? 1.4 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(7),
                                            decoration: BoxDecoration(
                                              color: (isPartial ? const Color(0xFFF59E0B) : const Color(0xFF0284C7)).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              isPartial ? Icons.shopping_basket_outlined : Icons.receipt_long,
                                              color: isPartial ? const Color(0xFFF59E0B) : const Color(0xFF0284C7),
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      o.poNo,
                                                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.5),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: (isPartial ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        isPartial ? 'Đang xuất ($pickedQty/$totalQty)' : 'Mới tạo ($totalQty SP)',
                                                        style: TextStyle(
                                                          color: isPartial ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Khách hàng: ${o.customer} • ${o.details.length} loại SKU • Tạo lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(o.createdAt)}',
                                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: c.rfidCyan,
                                              foregroundColor: const Color(0xFFFFFFFF),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                              elevation: 0,
                                            ),
                                            icon: const Icon(Icons.play_arrow_rounded, size: 15),
                                            label: const Text(
                                              'CHỌN ĐƠN NÀY ĐỂ XUẤT',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                            onPressed: () => _loadOutboundOrderFromDb(o),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Nếu có chip quét tự do tại cổng: hiển thị cột bên phải
                if (scannedTagsList.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: c.bgDeep,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                              border: Border(bottom: BorderSide(color: c.border)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.sensors, size: 16, color: c.rfidCyan),
                                const SizedBox(width: 6),
                                Text(
                                  'CHIP QUA CỔNG (${scannedTagsList.length})',
                                  style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                InkWell(
                                  onTap: _clearGateScan,
                                  child: const Text('Xóa', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: scannedTagsList.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final tag = scannedTagsList[idx];
                                final itemInRepo = _repo.items.where((i) => i.epc.toUpperCase() == tag.epc.toUpperCase()).firstOrNull;
                                final isItemInStock = itemInRepo != null;
                                final alertColor = isItemInStock ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

                                return Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: BoxDecoration(
                                    color: alertColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: alertColor.withValues(alpha: 0.6)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text('${idx + 1}', style: TextStyle(color: alertColor, fontSize: 10.5, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(isItemInStock ? Icons.warning_rounded : Icons.help_outline_rounded, color: alertColor, size: 13),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    tag.epc,
                                                    style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, fontWeight: FontWeight.bold, color: alertColor),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isItemInStock
                                                  ? '🚨 [TRONG KHO] ${itemInRepo.productName} (Kệ: ${itemInRepo.locationId ?? "--"})'
                                                  : '⚠️ [CHIP LẠ] Chưa đăng ký trong danh mục kho',
                                              style: TextStyle(fontSize: 10, color: alertColor, fontWeight: FontWeight.bold),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: alertColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${tag.rssi} dBm',
                                          style: TextStyle(color: isItemInStock ? const Color(0xFFEF4444) : c.textSecondary, fontSize: 9.5, fontWeight: isItemInStock ? FontWeight.bold : FontWeight.normal),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 3. MÀN HÌNH CỔNG XUẤT KHO RFID ĐỐI SOÁT THỜI GIAN THỰC ----------
  Widget _buildOutboundGateMonitor(EyeCareColors c) {
    if (_pendingOutboundOrder == null) {
      if (_lastSuccessOrderNo != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPassSuccessBanner(c),
              const SizedBox(height: 10),
              Expanded(child: _buildIdleGateMonitor(c)),
            ],
          ),
        );
      }
      return _buildIdleGateMonitor(c);
    }

    final order = _pendingOutboundOrder!;
    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).where((e) => e.isNotEmpty && e != '--').toSet();
    final validPalletEpcs = <String>{};
    for (final e in order.pallets.values) {
      if (e != null && e.isNotEmpty && e != '--') validPalletEpcs.add(e.toUpperCase());
    }
    for (final code in order.pallets.keys) {
      validPalletEpcs.add(code.toUpperCase());
      final pal = _repo.pallets.where((p) => p.palletCode.toUpperCase() == code.toUpperCase() || p.palletId.toUpperCase() == code.toUpperCase()).firstOrNull;
      if (pal?.rfidEpc != null && pal!.rfidEpc!.isNotEmpty) {
        validPalletEpcs.add(pal.rfidEpc!.toUpperCase());
      }
    }
    for (final it in order.items) {
      if (it.palletEpc.isNotEmpty && it.palletEpc != '--') validPalletEpcs.add(it.palletEpc.toUpperCase());
      if (it.palletCode.isNotEmpty && it.palletCode != '--') validPalletEpcs.add(it.palletCode.toUpperCase());
    }

    final expectedCount = expectedEpcs.length;
    final scannedCount = order.items.where((i) => _gateScannedTags.containsKey(i.epc.toUpperCase())).length;
    final missingCount = (expectedCount - scannedCount).clamp(0, expectedCount);
    final unexpList = _gateScannedTags.values.where((t) => !expectedEpcs.contains(t.epc.toUpperCase()) && !validPalletEpcs.contains(t.epc.toUpperCase())).toList();
    final unexpCount = unexpList.length;

    final isComplete = expectedCount > 0 && scannedCount >= expectedCount && _duplicateShippedEpcs.isEmpty;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final hasUnexpectedTags = unexpCount > 0 || _duplicateShippedEpcs.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner thông cổng xuất thành công
          if (_lastSuccessOrderNo != null) ...[
            _buildPassSuccessBanner(c),
            const SizedBox(height: 10),
          ],

          // Banner Cảnh báo Tồn kho không đủ
          if (!order.isStockSufficient) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CẢNH BÁO: KHÔNG ĐỦ HÀNG TỒN KHO ĐỂ XUẤT (THIẾU ${order.shortageCount} SẢN PHẨM)',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Chi tiết thiếu theo SKU: ${order.shortageBySku.entries.map((e) => "${e.key}: thiếu ${e.value}").join(", ")}. Hệ thống khóa nút xác nhận xuất kho cho đến khi có đủ tồn kho.',
                          style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'KHÓA XUẤT',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 0. THANH TRẠNG THÁI & CẢNH BÁO ĐÈN THÁP TÍN HIỆU (TOWER LIGHT)
          _buildTowerLightAlertBar(c),

          // Banner Cảnh Báo Trùng EPC/SN Đã Xuất Kho
          if (_duplicateShippedEpcs.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444), width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🚨 LỖI TRÙNG EPC/SN: PHÁT HIỆN ${_duplicateShippedEpcs.length} CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ!',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _duplicateShippedAlertMessage ?? 'Hàng hóa này đã làm thủ tục xuất kho trước đó! Nghiêm cấm xuất lại lần 2 để tránh trùng lặp.',
                          style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Banner Cảnh Báo An Ninh: Khi có hàng lạ không thuộc đơn xuất
          if (hasUnexpectedTags) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emergency_rounded, color: Color(0xFFEF4444), size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🚨 CẢNH BÁO AN NINH: CÓ $unexpCount HÀNG HÓA / CHIP LẠ KHÔNG THUỘC ĐƠN XUẤT ĐI QUA CỔNG!',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Đèn đỏ và còi báo động đang hú liên tục. Dừng xe kiểm tra và đưa hàng không thuộc đơn ra khỏi cổng để thông xe.',
                          style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.volume_off, size: 16),
                    label: const Text('TẮT CÒI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _silenceBuzzer,
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text('XÓA CHIP LẠ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() {
                        _gateScannedTags.removeWhere((k, v) => !expectedEpcs.contains(k) && !validPalletEpcs.contains(k));
                        _isBuzzerManuallySilenced = false;
                      });
                      _evaluateGateSecurityAndTowerLight();
                    },
                  ),
                ],
              ),
            ),
          ],

          // 1. Thanh tiến độ đọc & 3 Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ (Đều nhau, 3 màu: Xanh - Vàng - Đỏ)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: hasUnexpectedTags
                  ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                  : (isComplete ? const Color(0xFF10B981).withValues(alpha: 0.08) : c.bgDeep),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasUnexpectedTags
                    ? const Color(0xFFEF4444)
                    : (isComplete ? const Color(0xFF10B981).withValues(alpha: 0.4) : c.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TIẾN ĐỘ ĐỐI SOÁT QUA CỔNG: ($scannedCount / $expectedCount chip)',
                        style: TextStyle(
                          color: hasUnexpectedTags ? const Color(0xFFEF4444) : c.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 7,
                          backgroundColor: c.border.withValues(alpha: 0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            hasUnexpectedTags
                                ? const Color(0xFFEF4444)
                                : (isComplete ? const Color(0xFF10B981) : c.rfidCyan),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // 3 Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ (Đều nhau, 3 màu: Xanh - Vàng - Đỏ)
                _buildMetricBadge(
                  label: 'ĐÃ QUÉT',
                  count: scannedCount,
                  color: const Color(0xFF10B981),
                  c: c,
                ),
                const SizedBox(width: 8),
                _buildMetricBadge(
                  label: 'THIẾU',
                  count: missingCount,
                  color: const Color(0xFFF59E0B),
                  c: c,
                ),
                const SizedBox(width: 8),
                _buildMetricBadge(
                  label: 'LẠ',
                  count: unexpCount,
                  color: const Color(0xFFEF4444),
                  c: c,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Ô TÊN KHÁCH HÀNG: TRÊN BẢNG DANH SÁCH PHÍA BÊN TRÁI DƯỚI DÒNG TIẾN ĐỘ
          Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_pin, size: 15, color: Color(0xFF0284C7)),
                      const SizedBox(width: 6),
                      const Text(
                        'KHÁCH HÀNG:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0284C7),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          order.customer.trim().isNotEmpty && order.customer.trim() != '--' && order.customer.trim() != 'Khách mua xuất kho'
                              ? order.customer.trim()
                              : 'Xuất Kho',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: c.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. BẢNG THÔNG TIN ĐỐI SOÁT CỔNG CÓ VỊ TRÍ KỆ & ƯU TIÊN FIFO
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final tableWidth = constraints.maxWidth > 1150 ? constraints.maxWidth : 1150.0;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        children: [
                          // Header bảng
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: c.bgDeep,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              border: Border(bottom: BorderSide(color: c.border)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 50, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 130, child: Text('MÃ HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 110, child: Text('MÃ SP', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 130, child: Text('MÃ SN', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 110, child: Text('MÃ THÙNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 95, child: Text('MÃ PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 100, child: Text('VỊ TRÍ', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 105, child: Text('NGÀY NHẬP', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),

                          // Danh sách rows
                          Expanded(
                            child: ListView.separated(
                              itemCount: order.items.length + unexpList.length,
                              separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                              itemBuilder: (ctx, idx) {
                                if (idx < order.items.length) {
                                  final item = order.items[idx];
                                  final epc = item.epc.trim().toUpperCase();
                                  final isScanned = epc != '--' && epc.isNotEmpty && _gateScannedTags.containsKey(epc);

                                  return Container(
                                    color: isScanned ? const Color(0xFF10B981).withValues(alpha: 0.08) : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        // 1. STT
                                        SizedBox(
                                          width: 50,
                                          child: Row(
                                            children: [
                                              if (isScanned) ...[
                                                const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                '${idx + 1}',
                                                style: TextStyle(
                                                  color: isScanned ? const Color(0xFF10B981) : c.textSecondary,
                                                  fontSize: 12,
                                                  fontWeight: isScanned ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 2. MÃ HÀNG (SKU)
                                        SizedBox(
                                          width: 130,
                                          child: Text(
                                            item.sku,
                                            style: TextStyle(
                                              color: isScanned ? const Color(0xFF10B981) : c.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 3. MÃ SP
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            item.productId.isNotEmpty ? item.productId : '--',
                                            style: TextStyle(
                                              color: isScanned ? const Color(0xFF10B981) : c.textSecondary,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 4. MÃ SN (Được tự động match khi quét RFID)
                                        SizedBox(
                                          width: 130,
                                          child: isScanned
                                              ? Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                                    ),
                                                    child: Text(
                                                      item.serialNumber.isNotEmpty && item.serialNumber != '--'
                                                          ? item.serialNumber
                                                          : item.epc,
                                                      style: const TextStyle(
                                                        color: Color(0xFF10B981),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        fontFamily: 'monospace',
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                )
                                              : Text(
                                                  'Chờ quét...',
                                                  style: TextStyle(
                                                    color: c.textMuted,
                                                    fontSize: 11,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 5. TÊN SẢN PHẨM
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            item.productName,
                                            style: TextStyle(
                                              color: isScanned ? const Color(0xFF10B981) : c.textPrimary,
                                              fontSize: 12,
                                              fontWeight: isScanned ? FontWeight.w500 : FontWeight.normal,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 6. MÃ THÙNG
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            item.cartonCode,
                                            style: TextStyle(color: c.textSecondary, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 7. MÃ PALLET
                                        SizedBox(
                                          width: 95,
                                          child: Text(
                                            item.palletCode,
                                            style: TextStyle(color: c.textSecondary, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 8. VỊ TRÍ
                                        SizedBox(
                                          width: 100,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: item.isInStock
                                                    ? (item.locationCode != '--' ? const Color(0xFF0284C7).withValues(alpha: 0.12) : c.bgDeep)
                                                    : const Color(0xFFEF4444).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: item.isInStock
                                                      ? (item.locationCode != '--' ? const Color(0xFF0284C7).withValues(alpha: 0.4) : c.border)
                                                      : const Color(0xFFEF4444).withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    item.isInStock ? Icons.shelves : Icons.error_outline,
                                                    size: 13,
                                                    color: item.isInStock
                                                        ? (item.locationCode != '--' ? const Color(0xFF0284C7) : c.textMuted)
                                                        : const Color(0xFFEF4444),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      item.isInStock ? item.locationCode : 'Không có',
                                                      style: TextStyle(
                                                        color: item.isInStock
                                                            ? (item.locationCode != '--' ? const Color(0xFF0284C7) : c.textMuted)
                                                            : const Color(0xFFEF4444),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 9. NGÀY NHẬP
                                        SizedBox(
                                          width: 105,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: item.isInStock
                                                ? Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons.calendar_today_outlined,
                                                          size: 12,
                                                          color: Color(0xFF10B981),
                                                        ),
                                                        const SizedBox(width: 5),
                                                        Flexible(
                                                          child: Text(
                                                            item.inboundTime != null
                                                                ? DateFormat('dd/MM/yyyy').format(item.inboundTime!)
                                                                : '--',
                                                            style: const TextStyle(
                                                              color: Color(0xFF10B981),
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  )
                                                : Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: const Color(0xFFEF4444)),
                                                    ),
                                                    child: const Text(
                                                      'HẾT TỒN',
                                                      style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  // Chip lạ hoặc ngoài danh sách đơn xuất
                                  final unexp = unexpList[idx - order.items.length];
                                  final unexpEpc = unexp.epc.trim().toUpperCase();
                                  final foundInDb = _repo.items.where((i) => i.epc.toUpperCase() == unexpEpc).firstOrNull;

                                  final skuText = foundInDb?.sku ?? 'CHIP LẠ';
                                  final prodIdText = foundInDb?.productId.isNotEmpty == true ? foundInDb!.productId : '--';
                                  final snText = foundInDb != null && foundInDb.serialNumber.isNotEmpty ? foundInDb.serialNumber : unexp.epc;
                                  final cartonText = foundInDb?.cartonCode ?? '--';
                                  final palletText = foundInDb?.palletId ?? '--';
                                  final locText = foundInDb?.locationId ?? '--';
                                  final dateText = foundInDb?.inboundTime != null ? DateFormat('dd/MM/yyyy').format(foundInDb!.inboundTime!) : '--';
                                  final nameText = foundInDb != null
                                      ? '⚠️ [NGOÀI ĐƠN XUẤT] ${foundInDb.productName}'
                                      : 'Chip lạ không thuộc danh sách xuất kho!';

                                  return Container(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        // 1. STT + nút hủy chip lạ
                                        SizedBox(
                                          width: 50,
                                          child: Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.close, size: 14, color: Color(0xFFEF4444)),
                                                tooltip: 'Bỏ chip này khỏi cổng',
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () {
                                                  setState(() {
                                                    _gateScannedTags.remove(unexp.epc.toUpperCase());
                                                  });
                                                  final remaining = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e) && !validPalletEpcs.contains(e)).toList();
                                                  if (remaining.isEmpty) {
                                                    if (_isScanning) {
                                                      _towerLight.triggerScanning(reason: 'Đã loại bỏ chip lạ. Tiếp tục đối soát cổng...');
                                                    } else {
                                                      _towerLight.turnOffAll();
                                                    }
                                                  }
                                                },
                                              ),
                                              const SizedBox(width: 2),
                                              Text('${idx + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 2. MÃ HÀNG (SKU)
                                        SizedBox(
                                          width: 130,
                                          child: Text(
                                            skuText,
                                            style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 3. MÃ SP
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            prodIdText,
                                            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 4. MÃ SN
                                        SizedBox(
                                          width: 130,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                                              ),
                                              child: Text(
                                                snText,
                                                style: const TextStyle(
                                                  color: Color(0xFFEF4444),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'monospace',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 5. TÊN SẢN PHẨM
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            nameText,
                                            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 6. MÃ THÙNG
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            cartonText,
                                            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 7. MÃ PALLET
                                        SizedBox(
                                          width: 95,
                                          child: Text(
                                            palletText,
                                            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 8. VỊ TRÍ
                                        SizedBox(
                                          width: 100,
                                          child: Text(
                                            locText,
                                            style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // 9. NGÀY NHẬP
                                        SizedBox(
                                          width: 105,
                                          child: Text(
                                            dateText,
                                            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
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

  // ---------- 4. BỘ ĐIỀU KHIỂN DƯỚI CÙNG (LUÔN CỐ ĐỊNH Ở ĐÁY MÀN HÌNH) ----------
  Widget _buildBottomControlBarWrapper(EyeCareColors c) {
    if (_pendingOutboundOrder != null) {
      final order = _pendingOutboundOrder!;
      final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).where((e) => e.isNotEmpty && e != '--').toSet();
      final validPalletEpcs = <String>{};
      for (final e in order.pallets.values) {
        if (e != null && e.isNotEmpty && e != '--') validPalletEpcs.add(e.toUpperCase());
      }
      for (final code in order.pallets.keys) {
        validPalletEpcs.add(code.toUpperCase());
        final pal = _repo.pallets.where((p) => p.palletCode.toUpperCase() == code.toUpperCase() || p.palletId.toUpperCase() == code.toUpperCase()).firstOrNull;
        if (pal?.rfidEpc != null && pal!.rfidEpc!.isNotEmpty) {
          validPalletEpcs.add(pal.rfidEpc!.toUpperCase());
        }
      }
      for (final it in order.items) {
        if (it.palletEpc.isNotEmpty && it.palletEpc != '--') validPalletEpcs.add(it.palletEpc.toUpperCase());
        if (it.palletCode.isNotEmpty && it.palletCode != '--') validPalletEpcs.add(it.palletCode.toUpperCase());
      }

      final expectedCount = expectedEpcs.length;
      final scannedCount = order.items.where((i) => _gateScannedTags.containsKey(i.epc.toUpperCase())).length;
      final unexpList = _gateScannedTags.values.where((t) => !expectedEpcs.contains(t.epc.toUpperCase()) && !validPalletEpcs.contains(t.epc.toUpperCase())).toList();
      final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
      final hasUnexpectedTags = unexpList.isNotEmpty;

      return _buildBottomControlBar(
        c,
        scannedCount: scannedCount,
        expectedCount: expectedCount,
        isComplete: isComplete,
        hasUnexpectedTags: hasUnexpectedTags,
        isStockSufficient: order.isStockSufficient,
      );
    } else {
      return _buildBottomControlBar(
        c,
        scannedCount: _gateScannedTags.length,
        expectedCount: 0,
        isComplete: false,
        hasUnexpectedTags: false,
        isStockSufficient: true,
      );
    }
  }

  Widget _buildBottomControlBar(
    EyeCareColors c, {
    required int scannedCount,
    required int expectedCount,
    required bool isComplete,
    required bool hasUnexpectedTags,
    required bool isStockSufficient,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Trạng thái kết nối đầu đọc RFID & Tháp Đèn Tín Hiệu
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildReaderStatusBadge(c),
                      const SizedBox(width: 8),
                      _buildTowerLightBadge(c),
                    ],
                  ),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nút Làm Mới Quét
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.textPrimary,
                          side: BorderSide(color: c.border),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.replay, size: 14),
                        label: const Text('Làm Mới Quét', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        onPressed: _clearGateScan,
                      ),
                      const SizedBox(width: 8),

                      // Chọn thời gian quét: 5s, 10s, Liên tục
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildScanDurationButton(5, '5s', c),
                            const SizedBox(width: 3),
                            _buildScanDurationButton(10, '10s', c),
                            const SizedBox(width: 3),
                            _buildScanDurationButton(0, 'Liên tục', c),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Nút Bắt đầu quét / Dừng quét
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConnectingUhf
                              ? const Color(0xFFF59E0B)
                              : ((_isScanning || _desktopUhf.isScanning) ? const Color(0xFFEF4444) : c.rfidCyan),
                          foregroundColor: ((_isScanning || _desktopUhf.isScanning) || _isConnectingUhf)
                              ? Colors.white
                              : const Color(0xFFFFFFFF),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        icon: _isConnectingUhf
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon((_isScanning || _desktopUhf.isScanning) ? Icons.stop_rounded : Icons.sensors, size: 16),
                        label: Text(
                          _isConnectingUhf
                              ? 'ĐANG KẾT NỐI ĐẦU ĐỌC...'
                              : ((_isScanning || _desktopUhf.isScanning)
                                  ? (_scanDurationSeconds > 0 ? 'DỪNG (${_scanCountdown}s)' : 'DỪNG QUÉT')
                                  : (_scanDurationSeconds > 0 ? 'BẮT ĐẦU (${_scanDurationSeconds}s)' : 'BẮT ĐẦU QUÉT (LIÊN TỤC)')),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        onPressed: _isConnectingUhf ? null : _toggleGateScan,
                      ),

                      // Nút Xác Nhận Xuất Kho: CHỈ HIỆN KHI ĐÃ ĐỌC ĐỦ 100% VÀ KHÔNG CÓ CHIP LẠ
                      if (isComplete && !hasUnexpectedTags) ...[
                        const SizedBox(width: 10),
                        Builder(
                          builder: (ctx) {
                            final effectiveStockSuff = isStockSufficient || isComplete;
                            return ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: effectiveStockSuff ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: effectiveStockSuff ? 3 : 0,
                              ),
                              icon: Icon(
                                effectiveStockSuff
                                    ? (_isAutoConfirming ? Icons.hourglass_top_rounded : Icons.check_circle)
                                    : Icons.block,
                                size: 16,
                              ),
                              label: Text(
                                !effectiveStockSuff
                                    ? 'KHÓA XUẤT (THIẾU TỒN KHO)'
                                    : (_isSaving
                                        ? 'ĐANG LƯU...'
                                        : (_isAutoConfirming
                                            ? 'ĐÃ ĐỦ $scannedCount/$expectedCount (TỰ ĐỘNG XUẤT SAU 1S...)'
                                            : 'ĐÃ ĐỌC ĐỦ $scannedCount/$expectedCount (XÁC NHẬN XUẤT KHO)')),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              onPressed: (_isSaving || !effectiveStockSuff) ? null : () => _confirmOutboundDelivery(isAuto: false),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReaderStatusBadge(EyeCareColors c) {
    final connected = _desktopUhf.isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xFF10B981).withValues(alpha: 0.12)
            : const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: connected
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.sensors : Icons.sensors_off,
            size: 14,
            color: connected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
          const SizedBox(width: 6),
          Text(
            connected
                ? 'Đầu đọc: ${_desktopUhf.config.connectionSummary}'
                : 'Đầu đọc: Chưa kết nối (${_desktopUhf.config.connectionSummary})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: connected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTowerLightBadge(EyeCareColors c) {
    final status = _towerLight.currentStatus;
    final isConnected = _desktopUhf.isConnected;
    final Color badgeColor = switch (status.color) {
      TowerLightColor.red => const Color(0xFFEF4444),
      TowerLightColor.yellow => const Color(0xFFF59E0B),
      TowerLightColor.green => const Color(0xFF10B981),
      TowerLightColor.off => isConnected ? const Color(0xFF10B981) : c.textMuted,
    };
    final String label = switch (status.color) {
      TowerLightColor.red => 'ĐÈN ĐỎ (BÁO ĐỘNG)',
      TowerLightColor.yellow => 'ĐÈN VÀNG (ĐANG QUÉT)',
      TowerLightColor.green => 'ĐÈN XANH (THÔNG QUA)',
      TowerLightColor.off => isConnected ? 'SẴN SÀNG (GPO 1-4)' : 'CHƯA KẾT NỐI',
    };

    return PopupMenuButton<String>(
      tooltip: 'Trạng thái & Kiểm tra Tháp Đèn Tín Hiệu (Bấm để thử đèn & cài đặt chân GPO)',
      onSelected: (val) {
        if (val == 'test_red') {
          _towerLight.triggerWarningRed(withBuzzer: true, reason: 'Thử nghiệm thủ công: Đèn Đỏ + Còi Hú');
        } else if (val == 'test_yellow') {
          _towerLight.triggerScanning(reason: 'Thử nghiệm thủ công: Đèn Vàng');
        } else if (val == 'test_green') {
          _towerLight.triggerPass(reason: 'Thử nghiệm thủ công: Đèn Xanh');
        } else if (val == 'turn_off') {
          _towerLight.turnOffAll(reason: 'Tắt đèn về Standby');
        } else if (val == 'config_gpo') {
          _showTowerLightGpoDialog(c);
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            'THÁP ĐÈN CTP50-3T-D-J (${isConnected ? "ĐÃ NỐI GPO" : "CHƯA NỐI ĐẦU ĐỌC"})',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textSecondary),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'test_red',
          child: Row(
            children: [
              Icon(Icons.circle, color: Color(0xFFEF4444), size: 14),
              SizedBox(width: 8),
              Text('Thử Đèn Đỏ + Còi Báo Động (Chống Trộm)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'test_yellow',
          child: Row(
            children: [
              Icon(Icons.circle, color: Color(0xFFF59E0B), size: 14),
              SizedBox(width: 8),
              Text('Thử Đèn Vàng (Đang Quét Đối Soát)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'test_green',
          child: Row(
            children: [
              Icon(Icons.circle, color: Color(0xFF10B981), size: 14),
              SizedBox(width: 8),
              Text('Thử Đèn Xanh (Đủ Hàng Thông Cổng)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'turn_off',
          child: Row(
            children: [
              Icon(Icons.power_settings_new, color: Colors.grey, size: 14),
              SizedBox(width: 8),
              Text('Tắt Tháp Đèn (Về Chế Độ Chờ)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'config_gpo',
          child: Row(
            children: [
              Icon(Icons.settings, color: c.rfidCyan, size: 15),
              const SizedBox(width: 8),
              Text('Cài Đặt & Test Chân Relay GPO 1-4...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.rfidCyan)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badgeColor,
                boxShadow: [
                  BoxShadow(color: badgeColor.withValues(alpha: 0.6), blurRadius: 4, spreadRadius: 1),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'THÁP ĐÈN: $label',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: badgeColor),
          ],
        ),
      ),
    );
  }

  // ---------- THANH TRẠNG THÁI & CẢNH BÁO ĐÈN THÁP XUẤT KHO (TOWER LIGHT) ----------
  Widget _buildTowerLightAlertBar(EyeCareColors c) {
    final status = _towerLight.currentStatus;
    final (barColor, borderColor, statusTitle, statusIcon) = switch (status.color) {
      TowerLightColor.red => (
        const Color(0xFFEF4444),
        const Color(0xFFEF4444),
        'ĐÈN ĐỎ: CẢNH BÁO XUẤT KHO',
        Icons.warning_rounded,
      ),
      TowerLightColor.yellow => (
        const Color(0xFFF59E0B),
        const Color(0xFFF59E0B),
        'ĐÈN VÀNG: ĐANG ĐỐI SOÁT',
        Icons.hourglass_top_rounded,
      ),
      TowerLightColor.green => (
        const Color(0xFF10B981),
        const Color(0xFF10B981),
        'ĐÈN XANH: THÔNG QUA CỔNG',
        Icons.check_circle_rounded,
      ),
      TowerLightColor.off => (
        c.textMuted,
        c.border,
        'ĐÈN CHỜ (STANDBY)',
        Icons.lightbulb_outline_rounded,
      ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: status.isOff ? c.bgCard : barColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: status.isOff ? c.border : borderColor.withValues(alpha: 0.8),
          width: status.isOff ? 1 : 1.5,
        ),
      ),
      child: Row(
        children: [
          // Mô phỏng 3 bóng đèn LED (Đỏ - Vàng - Xanh)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.bgDeep,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLedBulb(
                  color: const Color(0xFFEF4444),
                  isActive: status.color == TowerLightColor.red,
                  isBuzzer: status.isBuzzerOn,
                ),
                const SizedBox(width: 6),
                _buildLedBulb(
                  color: const Color(0xFFF59E0B),
                  isActive: status.color == TowerLightColor.yellow,
                ),
                const SizedBox(width: 6),
                _buildLedBulb(
                  color: const Color(0xFF10B981),
                  isActive: status.color == TowerLightColor.green,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Icon + Tiêu đề + Lý do cảnh báo
          Icon(statusIcon, color: barColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        color: barColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (status.isBuzzerOn) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.volume_up_rounded, color: Colors.white, size: 10),
                            SizedBox(width: 2),
                            Text('CÒI BÁO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  status.reason,
                  style: TextStyle(
                    color: status.isOff ? c.textSecondary : c.textPrimary,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Menu thử đèn thủ công (Manual Test Controls)
          PopupMenuButton<String>(
            tooltip: 'Thử nghiệm tín hiệu đèn tháp',
            onSelected: (val) {
              if (val == 'test_green') {
                _towerLight.triggerPass(reason: 'Kiểm tra thủ công: Đèn Xanh thông qua');
              } else if (val == 'test_yellow') {
                _towerLight.triggerScanning(reason: 'Kiểm tra thủ công: Đèn Vàng đang quét');
              } else if (val == 'test_red') {
                _towerLight.triggerWarningRed(withBuzzer: true, reason: 'Kiểm tra thủ công: Đèn Đỏ + Còi báo động');
              } else if (val == 'turn_off') {
                _towerLight.turnOffAll();
              } else if (val == 'config_gpo') {
                _showTowerLightGpoDialog(c);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'test_green',
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFF10B981), size: 14),
                    SizedBox(width: 8),
                    Text('Thử Đèn Xanh (Thông qua)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'test_yellow',
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFFF59E0B), size: 14),
                    SizedBox(width: 8),
                    Text('Thử Đèn Vàng (Đang quét)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'test_red',
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFFEF4444), size: 14),
                    SizedBox(width: 8),
                    Text('Thử Đèn Đỏ + Còi (Cảnh báo)'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'turn_off',
                child: Row(
                  children: [
                    Icon(Icons.power_settings_new, color: Colors.grey, size: 14),
                    SizedBox(width: 8),
                    Text('Tắt tháp đèn (Standby)'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'config_gpo',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: c.rfidCyan, size: 14),
                    const SizedBox(width: 8),
                    Text('Cài đặt & Test chân GPO 1-4...', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.bgDeep,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 13, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text('Thử đèn', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTowerLightGpoDialog(EyeCareColors c) {
    int redPin = _towerLight.config.redPin;
    int yellowPin = _towerLight.config.yellowPin;
    int greenPin = _towerLight.config.greenPin;
    int buzzerPin = _towerLight.config.buzzerPin;
    final Map<int, bool> pinStates = {1: false, 2: false, 3: false, 4: false};

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.border),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings_input_composite, color: Color(0xFFEF4444), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CẤU HÌNH & TEST CHÂN RELAY GPO THÁP ĐÈN',
                          style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Đầu đọc Hopeland CL7206 / Tháp đèn CTP50-3T-D-J (Cổng COM/TCP)',
                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.bolt, size: 16, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 6),
                                Text(
                                  'BẬT / TẮT TRỰC TIẾP TỪNG CHÂN RELAY (TEST PHẦN CỨNG)',
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gạt công tắc để kiểm tra xem bóng đèn nào hoặc còi nào thực tế đang nối vào cổng GPO tương ứng:',
                              style: TextStyle(color: c.textSecondary, fontSize: 11),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [1, 2, 3, 4].map((pin) {
                                final isOn = pinStates[pin] ?? false;
                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: isOn ? c.rfidCyan.withValues(alpha: 0.15) : c.bgCard,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isOn ? c.rfidCyan : c.border),
                                    ),
                                    child: Column(
                                      children: [
                                        Text('GPO $pin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: isOn ? c.rfidCyan : c.textPrimary)),
                                        const SizedBox(height: 6),
                                        Switch(
                                          value: isOn,
                                          activeThumbColor: c.rfidCyan,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          onChanged: (val) {
                                            setDialogState(() {
                                              pinStates[pin] = val;
                                            });
                                            _towerLight.testIndividualPin(pin, val);
                                          },
                                        ),
                                        Text(isOn ? 'BẬT' : 'TẮT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOn ? const Color(0xFF10B981) : c.textSecondary)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'GÁN CHÂN CHO TỪNG TÍN HIỆU CẢNH BÁO:',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Đèn Đỏ (Cảnh báo / Thất thoát)',
                        color: const Color(0xFFEF4444),
                        currentPin: redPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => redPin = p),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Đèn Vàng (Đang quét đối soát)',
                        color: const Color(0xFFF59E0B),
                        currentPin: yellowPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => yellowPin = p),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Đèn Xanh (Đủ hàng thông cổng)',
                        color: const Color(0xFF10B981),
                        currentPin: greenPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => greenPin = p),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Còi Hú Buzzer (Báo động trộm)',
                        color: const Color(0xFF8B5CF6),
                        currentPin: buzzerPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => buzzerPin = p),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () {
                    for (int p = 1; p <= 4; p++) {
                      _towerLight.testIndividualPin(p, false);
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('ĐÓNG'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('LƯU CẤU HÌNH GPO'),
                  onPressed: () async {
                    for (int p = 1; p <= 4; p++) {
                      await _towerLight.testIndividualPin(p, false);
                    }
                    final newConfig = TowerLightPinConfig(
                      redPin: redPin,
                      yellowPin: yellowPin,
                      greenPin: greenPin,
                      buzzerPin: buzzerPin,
                    );
                    await _towerLight.saveConfig(newConfig);
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF10B981),
                          content: Text('✓ Đã lưu cấu hình chân GPO Tháp Đèn thành công!'),
                        ),
                      );
                      setState(() {});
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPinSelectorRow({
    required String title,
    required Color color,
    required int currentPin,
    required EyeCareColors c,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: currentPin,
                isDense: true,
                dropdownColor: c.bgCard,
                items: [1, 2, 3, 4].map((pin) {
                  return DropdownMenuItem<int>(
                    value: pin,
                    child: Text('GPO $pin', style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onChanged(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedBulb({required Color color, required bool isActive, bool isBuzzer = false}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? color : color.withValues(alpha: 0.15),
        border: Border.all(
          color: isActive ? color : Colors.transparent,
          width: 1.2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildScanDurationButton(int seconds, String label, EyeCareColors c) {
    final isSelected = _scanDurationSeconds == seconds;
    final isScanningActive = _isScanning || _desktopUhf.isScanning || _isConnectingUhf;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: isScanningActive
          ? null
          : () {
              setState(() {
                _scanDurationSeconds = seconds;
                _scanCountdown = seconds;
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (seconds == 0)
              Icon(
                Icons.all_inclusive,
                size: 13,
                color: isSelected ? const Color(0xFFFFFFFF) : c.textSecondary,
              )
            else
              Icon(
                Icons.timer_outlined,
                size: 13,
                color: isSelected ? const Color(0xFFFFFFFF) : c.textSecondary,
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFFFFFF) : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- BANNER THÔNG CỔNG XUẤT THÀNH CÔNG ----------
  Widget _buildPassSuccessBanner(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✓ ĐƠN HÀNG $_lastSuccessOrderNo ĐÃ QUA CỔNG XUẤT THÀNH CÔNG!',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pallet: ${_lastSuccessPalletCode ?? "--"} • Đã xuất $_lastSuccessCount sản phẩm (Trạng thái: Đã Xuất Kho) • Cổng sẵn sàng cho chuyến tiếp theo...',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
