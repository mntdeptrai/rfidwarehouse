import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/tag_info.dart';
import '../services/uhf_service.dart';

class InventoryScreen extends StatefulWidget {
  final Function(String epc)? onSelectTagForReadWrite;
  final Function(String epc)? onSelectTagForLocate;

  const InventoryScreen({
    super.key,
    this.onSelectTagForReadWrite,
    this.onSelectTagForLocate,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final UhfService _uhfService = UhfService();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _uhfService.addListener(_onUhfUpdate);
  }

  @override
  void dispose() {
    _uhfService.removeListener(_onUhfUpdate);
    _searchController.dispose();
    super.dispose();
  }

  void _onUhfUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleInventory() async {
    if (_uhfService.isScanning) {
      await _uhfService.stopInventory();
    } else {
      await _uhfService.startInventory();
    }
  }

  Future<void> _exportCsv() async {
    final tags = _uhfService.tags;
    if (tags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu thẻ để xuất!')),
      );
      return;
    }

    try {
      List<List<dynamic>> rows = [
        ['STT', 'EPC', 'TID', 'User Data', 'RSSI (dBm)', 'Antenna', 'Count', 'First Seen', 'Last Seen']
      ];

      for (int i = 0; i < tags.length; i++) {
        final t = tags[i];
        rows.add([
          i + 1,
          t.epc,
          t.tid,
          t.user,
          t.rssi,
          t.ant,
          t.count,
          DateFormat('yyyy-MM-dd HH:mm:ss').format(t.firstSeen),
          DateFormat('yyyy-MM-dd HH:mm:ss').format(t.lastSeen),
        ]);
      }

      final String csvData = rows.map((r) => r.map((cell) => '"${cell.toString().replaceAll('"', '""')}"').join(',')).join('\r\n');
      final directory = await getTemporaryDirectory();
      final String filePath = '${directory.path}/UHF_Tags_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      final File file = File(filePath);
      await file.writeAsString(csvData);

      await SharePlus.instance.share(
        ShareParams(
          text: 'Danh sách thẻ RFID UHF (${tags.length} thẻ)',
          files: [XFile(filePath)],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất file: $e')),
        );
      }
    }
  }

  void _showTagDetailModal(TagInfo tag) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFE9E2D5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.nfc, color: Color(0xFF0284C7), size: 28),
                    const SizedBox(width: 10),
                    const Text(
                      'Chi tiết Thẻ UHF RFID',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C251E)),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF6B5D4D)),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const Divider(color: Color(0xFF8F8070)),
                _buildDetailRow('EPC', tag.epc, isSelectable: true),
                if (tag.tid.isNotEmpty) _buildDetailRow('TID', tag.tid, isSelectable: true),
                if (tag.user.isNotEmpty) _buildDetailRow('User', tag.user, isSelectable: true),
                _buildDetailRow('RSSI', '${tag.rssi} dBm'),
                _buildDetailRow('Anten', 'Antenna #${tag.ant}'),
                _buildDetailRow('Số lần đọc', '${tag.count} lần'),
                _buildDetailRow('Lần đầu thấy', DateFormat('HH:mm:ss dd/MM/yyyy').format(tag.firstSeen)),
                _buildDetailRow('Lần cuối thấy', DateFormat('HH:mm:ss dd/MM/yyyy').format(tag.lastSeen)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: const Text('Đọc / Ghi'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0EA5E9),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onSelectTagForReadWrite?.call(tag.epc);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.radar, size: 18),
                        label: const Text('Tìm thẻ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onSelectTagForLocate?.call(tag.epc);
                        },
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 13)),
          ),
          Expanded(
            child: isSelectable
                ? Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          value,
                          style: const TextStyle(
                            color: Color(0xFF2C251E),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: value));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Đã sao chép $label!'), duration: const Duration(seconds: 1)),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.copy, size: 16, color: Color(0xFF0284C7)),
                        ),
                      )
                    ],
                  )
                : Text(
                    value,
                    style: const TextStyle(color: Color(0xFF2C251E), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allTags = _uhfService.tags;
    final filteredTags = _searchQuery.isEmpty
        ? allTags
        : allTags.where((t) => t.epc.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            t.tid.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E2D5),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.wifi_tethering, color: Color(0xFF0284C7)),
            const SizedBox(width: 8),
            const Text(
              'Quét Thẻ UHF RFID',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2C251E)),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _uhfService.isScanning ? const Color(0xFF065F46) : const Color(0xFFC7BDAF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _uhfService.isScanning ? const Color(0xFF34D399) : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _uhfService.isScanning ? 'RUNNING' : 'STOPPED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _uhfService.isScanning ? const Color(0xFF34D399) : Colors.white60,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download, color: Color(0xFF6B5D4D)),
            tooltip: 'Xuất CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFF6B5D4D)),
            tooltip: 'Xóa danh sách',
            onPressed: () {
              _uhfService.clearTags();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // KPI Metric Dashboard
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFE9E2D5),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                _buildKpiCard('Số thẻ duy nhất', '${_uhfService.uniqueTagCount}', const Color(0xFF0284C7), Icons.tag),
                const SizedBox(width: 10),
                _buildKpiCard('Tổng lượt đọc', '${_uhfService.totalReadCount}', const Color(0xFFA78BFA), Icons.sync),
                const SizedBox(width: 10),
                _buildKpiCard('Tốc độ', '${_uhfService.readRate.toInt()}/s', const Color(0xFF34D399), Icons.speed),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(color: Color(0xFF2C251E)),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm theo EPC hoặc TID...',
                hintStyle: const TextStyle(color: Color(0xFF8F8070)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8F8070)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF8F8070)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFE9E2D5),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Tag List
          Expanded(
            child: filteredTags.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _uhfService.isScanning ? Icons.radar : Icons.nfc_outlined,
                          size: 64,
                          color: _uhfService.isScanning ? const Color(0xFF0284C7) : Colors.white24,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _uhfService.isScanning ? 'Đang quét thẻ UHF xung quanh...' : 'Chưa có thẻ nào được quét',
                          style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 14),
                        ),
                        if (!_uhfService.isScanning)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Bắt đầu quét'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _toggleInventory,
                            ),
                          )
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                    itemCount: filteredTags.length,
                    itemBuilder: (context, index) {
                      final tag = filteredTags[index];
                      return _buildTagCard(tag, index + 1);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            icon: Icon(
              _uhfService.isScanning ? Icons.stop : Icons.play_arrow,
              size: 26,
            ),
            label: Text(
              _uhfService.isScanning ? 'DỪNG QUÉT' : 'BẮT ĐẦU QUÉT LIÊN TỤC',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _uhfService.isScanning ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _toggleInventory,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF4EFE6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B5D4D)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagCard(TagInfo tag, int index) {
    final signalPct = tag.signalPercent;
    Color signalColor = signalPct > 0.7
        ? const Color(0xFF10B981)
        : signalPct > 0.4
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFFE9E2D5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFC7BDAF), width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTagDetailModal(tag),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC7BDAF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#$index',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6B5D4D), fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tag.epc,
                      style: const TextStyle(
                        color: Color(0xFF2C251E),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EFE6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'x${tag.count}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ],
              ),
              if (tag.tid.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'TID: ${tag.tid}',
                  style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  // RSSI Signal Bar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'RSSI: ${tag.rssi} dBm',
                              style: TextStyle(fontSize: 11, color: signalColor, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              'Ant: #${tag.ant}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF6B5D4D)),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('HH:mm:ss').format(tag.lastSeen),
                              style: const TextStyle(fontSize: 11, color: Color(0xFF8F8070)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: signalPct,
                            minHeight: 4,
                            backgroundColor: const Color(0xFFF4EFE6),
                            valueColor: AlwaysStoppedAnimation<Color>(signalColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
