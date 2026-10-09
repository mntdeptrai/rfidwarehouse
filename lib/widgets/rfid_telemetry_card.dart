import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class RfidTelemetryCard extends StatelessWidget {
  final int uniqueTags;
  final int totalReads;
  final double readRate;
  final double rssi;
  final bool isScanning;
  final String antennaInfo;

  const RfidTelemetryCard({
    super.key,
    required this.uniqueTags,
    required this.totalReads,
    required this.readRate,
    this.rssi = -55.0,
    required this.isScanning,
    this.antennaInfo = 'Antenna 1 & 2',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate700, width: 1.0),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isScanning ? AppColors.electricCyan : AppColors.slate500,
                        shape: BoxShape.circle,
                        boxShadow: isScanning
                            ? [
                                BoxShadow(
                                  color: AppColors.electricCyan.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isScanning ? 'SÓNG RFID ĐANG PHÁT' : 'CHẾ ĐỘ CHỜ',
                        style: TextStyle(
                          color: isScanning ? AppColors.electricCyan : AppColors.slate400,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.slate850,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.slate700, width: 0.5),
                ),
                child: Text(
                  antennaInfo,
                  style: const TextStyle(
                    color: AppColors.cyanTech,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  title: 'Thẻ Duy Nhất',
                  value: uniqueTags.toString(),
                  unit: 'Tags',
                  color: AppColors.cyanTech,
                  icon: Icons.tag,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  title: 'Tổng Đọc Thô',
                  value: totalReads.toString(),
                  unit: 'Lượt',
                  color: AppColors.rfidDuplicate,
                  icon: Icons.repeat,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  title: 'Tốc Độ Đọc',
                  value: readRate.toStringAsFixed(0),
                  unit: 'Tag/s',
                  color: AppColors.rfidMatched,
                  icon: Icons.speed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String unit,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.slate850,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slate700, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: AppTypography.kpiNumber.copyWith(
                    color: AppColors.slate50,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
