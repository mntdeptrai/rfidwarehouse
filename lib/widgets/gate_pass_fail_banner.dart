import 'package:flutter/material.dart';
import '../models/wms_models.dart';

class GatePassFailBanner extends StatelessWidget {
  final GateVerificationResult? result;
  final bool isScanning;

  const GatePassFailBanner({
    super.key,
    required this.result,
    this.isScanning = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isScanning && result == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'ĐANG QUÉT & ĐỐI CHIẾU CỔNG GATE...',
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Đang thu nhận dữ liệu RFID từ 02 Antenna HF340...',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (result == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Row(
          children: const [
            Icon(Icons.sensors, color: Colors.white54, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sẵn sàng quét qua Cổng RFID Gate HF340',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final isPass = result!.isPass;
    final color = isPass ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final bgGradient = isPass
        ? const LinearGradient(
            colors: [Color(0xFF064E3B), Color(0xFF065F46)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF7F1D1D), Color(0xFF991B1B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Icon(
                  isPass ? Icons.check_circle : Icons.dangerous,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPass ? 'KẾT QUẢ: PASS - ĐẠT 100%' : 'KẾT QUẢ: FAIL - SAI LỆCH',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPass
                          ? 'Chứng từ ${result!.documentNo}: Toàn bộ cơ cấu SKU và số lượng trùng khớp.'
                          : 'Phát hiện sai lệch giữa hàng hóa quét thực tế và chứng từ.',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${result!.totalActualQty} / ${result!.totalRequiredQty} Thẻ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),

          // Chi tiết từng SKU
          Column(
            children: result!.skuBreakdowns.map((b) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      b.isMatched ? Icons.check_circle_outline : Icons.highlight_off,
                      color: b.isMatched ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${b.sku} - ${b.productName}',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'Thực tế: ${b.actualQty} / Cần: ${b.requiredQty}',
                      style: TextStyle(
                        color: b.isMatched ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

          // Cảnh báo thẻ lạ nếu có
          if (result!.unexpectedEpcs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Phát hiện ${result!.unexpectedEpcs.length} thẻ lạ không có trong chứng từ: ${result!.unexpectedEpcs.join(', ')}',
                      style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
