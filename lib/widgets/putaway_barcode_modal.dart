import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/eye_care_theme.dart';
import '../models/wms_models.dart';

class PutawayBarcodeModal extends StatelessWidget {
  final String barcode;
  final String orderNo;
  final int itemCount;
  final String? cartonName;
  final List<InboundOrderDetail>? details;
  final String performedBy;
  final DateTime receivedTime;

  const PutawayBarcodeModal({
    super.key,
    required this.barcode,
    required this.orderNo,
    required this.itemCount,
    this.cartonName,
    this.details,
    this.performedBy = 'Trạm Cổng Desktop',
    required this.receivedTime,
  });

  static Future<void> show(
    BuildContext context, {
    required String barcode,
    required String orderNo,
    required int itemCount,
    String? cartonName,
    List<InboundOrderDetail>? details,
    String performedBy = 'Trạm Cổng Desktop',
    DateTime? receivedTime,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PutawayBarcodeModal(
        barcode: barcode,
        orderNo: orderNo,
        itemCount: itemCount,
        cartonName: cartonName,
        details: details,
        performedBy: performedBy,
        receivedTime: receivedTime ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = EyeCareThemeService().colors;
    final timeStr = DateFormat('HH:mm:ss - dd/MM/yyyy').format(receivedTime);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TEM MÃ VẠCH THÙNG HÀNG XẾP KHO',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tự động sinh mã để tay cầm PDA quét xác nhận đưa lên kệ',
                          style: TextStyle(color: c.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                    tooltip: 'Đóng',
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hourglass_top_rounded, color: Color(0xFFF59E0B), size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            'TRẠNG THÁI: CHỜ PDA QUÉT XẾP LÊN KỆ',
                            style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Barcode Card (High Contrast White Board for easy scanning off-screen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2C251E), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'MÃ THÙNG / ĐƠN NHẬP KHO',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Vector Barcode 128
                          BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: barcode,
                            width: 380,
                            height: 80,
                            drawText: true,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                '$itemCount chip RFID / sản phẩm trong thùng',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Quick Guide Alert
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFF0284C7), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'HƯỚNG DẪN XẾP KHO BẰNG PDA:',
                                  style: TextStyle(
                                    color: Color(0xFF0284C7),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '1. Thủ kho mở mục "XẾP KHO" trên tay cầm PDA.\n2. Chọn hoặc quét mã vị trí kệ đích (LOC-A01-01,...).\n3. Bóp cò súng quét trực tiếp mã vạch trên màn hình này (hoặc tem in) để hoàn tất cất hàng!',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Details Summary Table
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow('Số chứng từ / Đơn nhập:', orderNo, c),
                          const Divider(height: 12),
                          _buildInfoRow('Thời gian tiếp nhận:', timeStr, c),
                          const Divider(height: 12),
                          _buildInfoRow('Trạm tiếp nhận:', performedBy, c),
                          const Divider(height: 12),
                          _buildInfoRow('Tổng số lượng hàng:', '$itemCount sản phẩm', c, isBold: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(15),
                  bottomRight: Radius.circular(15),
                ),
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: barcode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF047857),
                          content: Text('Đã sao chép mã Barcode "$barcode" vào bộ nhớ tạm!'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Sao chép mã'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('XÁC NHẬN & ĐÓNG'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildInfoRow(String label, String value, EyeCareColors c, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
