import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../widgets/gate_pass_fail_banner.dart';
import '../widgets/rfid_telemetry_card.dart';

class GateMonitorScreen extends StatefulWidget {
  const GateMonitorScreen({super.key});

  @override
  State<GateMonitorScreen> createState() => _GateMonitorScreenState();
}

class _GateMonitorScreenState extends State<GateMonitorScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  GateMode _gateMode = GateMode.inbound;
  String _selectedDocNo = 'INB-2026-001';
  bool _isGateScanning = false;
  GateVerificationResult? _gateResult;
  final List<String> _liveScannedEpcs = [];

  @override
  void initState() {
    super.initState();
    _updateDefaultDoc();
  }

  void _updateDefaultDoc() {
    if (_gateMode == GateMode.inbound) {
      if (_repo.inboundOrders.isNotEmpty) {
        _selectedDocNo = _repo.inboundOrders.first.orderNo;
      }
    } else {
      if (_repo.outboundOrders.isNotEmpty) {
        _selectedDocNo = _repo.outboundOrders.first.poNo;
      }
    }
  }

  void _simulateLiveGatePass() {
    setState(() {
      _isGateScanning = true;
      _gateResult = null;
      _liveScannedEpcs.clear();
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _isGateScanning = false;
        if (_gateMode == GateMode.inbound) {
          final order = _repo.inboundOrders.firstWhere((o) => o.orderNo == _selectedDocNo);
          final items = _repo.generateItemsForInbound(order);
          _liveScannedEpcs.addAll(items.map((e) => e.epc));
          _gateResult = _repo.verifyGateInbound(orderNo: _selectedDocNo, scannedEpcs: _liveScannedEpcs);
        } else {
          final po = _repo.outboundOrders.firstWhere((p) => p.poNo == _selectedDocNo);
          final plan = _repo.generateFifoPickingPlan(po.outboundOrderId);
          final targetItemIds = plan.lines.expand((l) => l.targetItemIds).toList();
          final epcs = _repo.items.where((it) => targetItemIds.contains(it.itemId)).map((e) => e.epc).toList();
          _liveScannedEpcs.addAll(epcs);
          _gateResult = _repo.verifyGateOutbound(poNo: _selectedDocNo, scannedEpcs: _liveScannedEpcs);
        }
      });
    });
  }

  void _simulateLiveGateFail() {
    setState(() {
      _isGateScanning = true;
      _gateResult = null;
      _liveScannedEpcs.clear();
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _isGateScanning = false;
        // Quét thiếu và có thẻ lạ
        _liveScannedEpcs.add('E28011600000000000000101');
        _liveScannedEpcs.add('E28011600000000000099999'); // Thẻ lạ

        if (_gateMode == GateMode.inbound) {
          _gateResult = _repo.verifyGateInbound(orderNo: _selectedDocNo, scannedEpcs: _liveScannedEpcs);
        } else {
          _gateResult = _repo.verifyGateOutbound(poNo: _selectedDocNo, scannedEpcs: _liveScannedEpcs);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: [
            const Icon(Icons.meeting_room, color: Color(0xFF10B981)),
            const SizedBox(width: 10),
            const Text(
              'KIOSK RFID GATE HF340',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF10B981), width: 0.8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.sensors, color: Color(0xFF10B981), size: 14),
                  SizedBox(width: 4),
                  Text('2 ANTENNAS ACTIVE', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Mode Switcher INBOUND / OUTBOUND
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _gateMode = GateMode.inbound;
                          _updateDefaultDoc();
                          _gateResult = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _gateMode == GateMode.inbound ? const Color(0xFF0284C7) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            '🟢 MODE: NHẬP KHO (INBOUND)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _gateMode = GateMode.outbound;
                          _updateDefaultDoc();
                          _gateResult = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _gateMode == GateMode.outbound ? const Color(0xFF6366F1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            '🔵 MODE: XUẤT KHO (OUTBOUND)',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Telemetry Cards
            RfidTelemetryCard(
              uniqueTags: _liveScannedEpcs.toSet().length,
              totalReads: _liveScannedEpcs.length * 4,
              readRate: _isGateScanning ? 120.0 : 0.0,
              isScanning: _isGateScanning,
              antennaInfo: 'HF340 Dual-Antenna',
            ),
            const SizedBox(height: 16),

            // Giant Status Banner
            GatePassFailBanner(
              result: _gateResult,
              isScanning: _isGateScanning,
            ),
            const SizedBox(height: 16),

            // Simulation Trigger Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isGateScanning ? null : _simulateLiveGatePass,
                    child: const Text(
                      'PALLET ĐẠT CHUẨN (PASS)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isGateScanning ? null : _simulateLiveGateFail,
                    child: const Text(
                      'PALLET LỖI/SAI SKU (FAIL)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
