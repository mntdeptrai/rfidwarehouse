import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tag_info.dart';
import '../services/uhf_service.dart';

class LocateTagScreen extends StatefulWidget {
  final String? targetEpc;

  const LocateTagScreen({super.key, this.targetEpc});

  @override
  State<LocateTagScreen> createState() => _LocateTagScreenState();
}

class _LocateTagScreenState extends State<LocateTagScreen> {
  final UhfService _uhfService = UhfService();
  final TextEditingController _epcController = TextEditingController();

  StreamSubscription<TagInfo>? _tagSubscription;
  double _currentRssi = -100.0;
  double _signalPercent = 0.0;
  DateTime? _lastSeenTime;
  Timer? _decayTimer;
  Timer? _beepTimer;

  @override
  void initState() {
    super.initState();
    if (widget.targetEpc != null && widget.targetEpc!.isNotEmpty) {
      _epcController.text = widget.targetEpc!;
    }
    _startLocating();
  }

  @override
  void didUpdateWidget(covariant LocateTagScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetEpc != null && widget.targetEpc!.isNotEmpty) {
      _epcController.text = widget.targetEpc!;
    }
  }

  @override
  void dispose() {
    _tagSubscription?.cancel();
    _decayTimer?.cancel();
    _beepTimer?.cancel();
    _epcController.dispose();
    super.dispose();
  }

  void _startLocating() {
    _tagSubscription?.cancel();
    _tagSubscription = _uhfService.onTagRead.listen((tag) {
      final target = _epcController.text.trim().toLowerCase();
      if (target.isNotEmpty && tag.epc.toLowerCase() == target) {
        setState(() {
          _currentRssi = tag.rssiValue;
          _signalPercent = tag.signalPercent;
          _lastSeenTime = DateTime.now();
        });
        _triggerProximityBeep();
      }
    });

    // Gradually decay signal if tag is not detected for a while
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_lastSeenTime != null && DateTime.now().difference(_lastSeenTime!).inMilliseconds > 1200) {
        if (_signalPercent > 0.05 && mounted) {
          setState(() {
            _signalPercent = (_signalPercent * 0.7).clamp(0.0, 1.0);
            if (_signalPercent < 0.1) {
              _currentRssi = -100.0;
            }
          });
        }
      }
    });
  }

  void _triggerProximityBeep() {
    if (!_uhfService.soundEnabled && !_uhfService.hapticEnabled) return;

    if (_uhfService.hapticEnabled && _signalPercent > 0.3) {
      HapticFeedback.lightImpact();
    }
    if (_uhfService.soundEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  String get _proximityStatus {
    if (_signalPercent <= 0.05 || _currentRssi <= -90) return 'Chưa phát hiện tín hiệu';
    if (_signalPercent < 0.3) return 'Xa (~ 3-5m)';
    if (_signalPercent < 0.6) return 'Đang tiếp cận (~ 1-2m)';
    if (_signalPercent < 0.85) return 'Gần (< 1m)';
    return '🎯 RẤT GẦN / ĐÍCH ĐẾN! (< 30cm)';
  }

  Color get _proximityColor {
    if (_signalPercent <= 0.05) return Colors.grey;
    if (_signalPercent < 0.3) return const Color(0xFF0284C7);
    if (_signalPercent < 0.6) return const Color(0xFFF59E0B);
    if (_signalPercent < 0.85) return const Color(0xFFF97316);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final tags = _uhfService.tags;

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E2D5),
        title: const Text(
          'Định Vị & Tìm Thẻ RFID',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2C251E)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Target EPC Input
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE9E2D5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC7BDAF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.gps_fixed, color: Color(0xFF0284C7), size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Mã EPC thẻ cần tìm kiếm',
                        style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _epcController,
                    style: const TextStyle(color: Color(0xFF2C251E), fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Nhập hoặc chọn mã EPC cần định vị...',
                      hintStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFFF4EFE6),
                      suffixIcon: tags.isNotEmpty
                          ? PopupMenuButton<String>(
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0284C7)),
                              onSelected: (epc) {
                                setState(() => _epcController.text = epc);
                              },
                              itemBuilder: (ctx) => tags
                                  .map((t) => PopupMenuItem(
                                        value: t.epc,
                                        child: Text(t.epc, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                      ))
                                  .toList(),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Radar Visualizer
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer concentric circles
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _proximityColor.withValues(alpha: 0.2), width: 2),
                    ),
                  ),
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _proximityColor.withValues(alpha: 0.3), width: 2),
                    ),
                  ),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _proximityColor.withValues(alpha: 0.4), width: 2),
                    ),
                  ),
                  // Glowing Center Pulse
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 60 + (_signalPercent * 60),
                    height: 60 + (_signalPercent * 60),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _proximityColor.withValues(alpha: 0.2 + (_signalPercent * 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: _proximityColor.withValues(alpha: _signalPercent * 0.6),
                          blurRadius: 20 * _signalPercent,
                          spreadRadius: 10 * _signalPercent,
                        ),
                      ],
                    ),
                  ),
                  // Center Icon
                  Icon(
                    Icons.radar,
                    size: 48,
                    color: _proximityColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Proximity Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE9E2D5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _proximityColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Text(
                    _proximityStatus,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _proximityColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('RSSI', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            _currentRssi <= -95 ? '-- dBm' : '${_currentRssi.toStringAsFixed(1)} dBm',
                            style: const TextStyle(color: Color(0xFF2C251E), fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 30, color: const Color(0xFF8F8070)),
                      Column(
                        children: [
                          const Text('Cường độ', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(
                            '${(_signalPercent * 100).toInt()}%',
                            style: TextStyle(color: _proximityColor, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _signalPercent,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFF4EFE6),
                      valueColor: AlwaysStoppedAnimation<Color>(_proximityColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Toggle Scan Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: Icon(_uhfService.isScanning ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _uhfService.isScanning ? 'DỪNG QUÉT TÌM KIẾM' : 'BẮT ĐẦU QUÉT TÌM THẺ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _uhfService.isScanning ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (_uhfService.isScanning) {
                    await _uhfService.stopInventory();
                  } else {
                    await _uhfService.startInventory();
                  }
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
