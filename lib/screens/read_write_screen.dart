import 'package:flutter/material.dart';
import '../services/uhf_service.dart';

class ReadWriteScreen extends StatefulWidget {
  final String? initialEpc;

  const ReadWriteScreen({super.key, this.initialEpc});

  @override
  State<ReadWriteScreen> createState() => _ReadWriteScreenState();
}

class _ReadWriteScreenState extends State<ReadWriteScreen> with SingleTickerProviderStateMixin {
  final UhfService _uhfService = UhfService();
  late TabController _tabController;

  // General Read/Write Fields
  int _selectedBank = 1; // 0=Reserved, 1=EPC, 2=TID, 3=USER
  final TextEditingController _ptrController = TextEditingController(text: '2');
  final TextEditingController _cntController = TextEditingController(text: '6');
  final TextEditingController _passwordController = TextEditingController(text: '00000000');
  final TextEditingController _dataController = TextEditingController();
  final TextEditingController _filterEpcController = TextEditingController();
  bool _useFilter = false;

  // Quick EPC Write Fields
  final TextEditingController _quickTargetEpcController = TextEditingController();
  final TextEditingController _quickNewEpcController = TextEditingController();

  bool _isLoading = false;
  String _statusMessage = '';
  bool _isSuccess = true;

  final List<Map<String, dynamic>> _banks = [
    {'id': 0, 'name': 'RESERVED (Password)', 'desc': 'Chứa Kill & Access Password'},
    {'id': 1, 'name': 'EPC (Electronic Product Code)', 'desc': 'Mã nhận diện sản phẩm'},
    {'id': 2, 'name': 'TID (Tag Identifier)', 'desc': 'Mã định danh duy nhất của chip'},
    {'id': 3, 'name': 'USER (Bộ nhớ người dùng)', 'desc': 'Vùng nhớ lưu dữ liệu tùy biến'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialEpc != null && widget.initialEpc!.isNotEmpty) {
      _filterEpcController.text = widget.initialEpc!;
      _quickTargetEpcController.text = widget.initialEpc!;
      _useFilter = true;
    }
  }

  @override
  void didUpdateWidget(covariant ReadWriteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialEpc != null && widget.initialEpc!.isNotEmpty) {
      _filterEpcController.text = widget.initialEpc!;
      _quickTargetEpcController.text = widget.initialEpc!;
      _useFilter = true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ptrController.dispose();
    _cntController.dispose();
    _passwordController.dispose();
    _dataController.dispose();
    _filterEpcController.dispose();
    _quickTargetEpcController.dispose();
    _quickNewEpcController.dispose();
    super.dispose();
  }

  Future<void> _handleRead() async {
    final ptr = int.tryParse(_ptrController.text.trim()) ?? 2;
    final cnt = int.tryParse(_cntController.text.trim()) ?? 6;
    final pwd = _passwordController.text.trim().isEmpty ? '00000000' : _passwordController.text.trim();
    final filterData = _useFilter ? _filterEpcController.text.trim() : null;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Đang đọc dữ liệu từ thẻ...';
    });

    final data = await _uhfService.readData(
      bank: _selectedBank,
      ptr: ptr,
      cnt: cnt,
      accessPassword: pwd,
      filterData: filterData,
      filterBank: 1,
      filterPtr: 32,
      filterCnt: filterData != null ? filterData.length * 4 : 0,
    );

    setState(() {
      _isLoading = false;
      if (data != null && data.isNotEmpty) {
        _dataController.text = data;
        _statusMessage = 'Đọc thành công! (${data.length / 2} bytes)';
        _isSuccess = true;
      } else {
        _statusMessage = 'Đọc thất bại! Hãy kiểm tra vị trí thẻ hoặc mật khẩu.';
        _isSuccess = false;
      }
    });
  }

  Future<void> _handleWrite() async {
    final ptr = int.tryParse(_ptrController.text.trim()) ?? 2;
    final cnt = int.tryParse(_cntController.text.trim()) ?? 6;
    final pwd = _passwordController.text.trim().isEmpty ? '00000000' : _passwordController.text.trim();
    final data = _dataController.text.trim();
    final filterData = _useFilter ? _filterEpcController.text.trim() : null;

    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập dữ liệu Hex cần ghi!')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Đang ghi dữ liệu vào thẻ...';
    });

    final success = await _uhfService.writeData(
      bank: _selectedBank,
      ptr: ptr,
      cnt: cnt,
      data: data,
      accessPassword: pwd,
      filterData: filterData,
      filterBank: 1,
      filterPtr: 32,
      filterCnt: filterData != null ? filterData.length * 4 : 0,
    );

    setState(() {
      _isLoading = false;
      if (success) {
        _statusMessage = 'Ghi dữ liệu thành công!';
        _isSuccess = true;
      } else {
        _statusMessage = 'Ghi dữ liệu thất bại! Vui lòng kiểm tra mật khẩu hoặc vùng nhớ bị khóa.';
        _isSuccess = false;
      }
    });
  }

  Future<void> _handleQuickWriteEpc() async {
    final targetEpc = _quickTargetEpcController.text.trim();
    final newEpc = _quickNewEpcController.text.trim();
    final pwd = _passwordController.text.trim().isEmpty ? '00000000' : _passwordController.text.trim();

    if (newEpc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mã EPC mới!')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Đang đổi mã EPC mới...';
    });

    final success = await _uhfService.writeDataToEpc(
      epc: newEpc,
      accessPassword: pwd,
      filterData: targetEpc.isNotEmpty ? targetEpc : null,
      filterBank: 1,
      filterPtr: 32,
      filterCnt: targetEpc.isNotEmpty ? targetEpc.length * 4 : 0,
    );

    setState(() {
      _isLoading = false;
      if (success) {
        _statusMessage = 'Đổi mã EPC thành công: $newEpc';
        _isSuccess = true;
        _quickTargetEpcController.text = newEpc;
      } else {
        _statusMessage = 'Đổi mã EPC thất bại! Kiểm tra mật khẩu hoặc khóa thẻ.';
        _isSuccess = false;
      }
    });
  }

  String _hexToAscii(String hexStr) {
    try {
      hexStr = hexStr.replaceAll(' ', '');
      if (hexStr.length % 2 != 0) return '';
      List<int> bytes = [];
      for (int i = 0; i < hexStr.length; i += 2) {
        bytes.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes.where((b) => b >= 32 && b <= 126));
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = _uhfService.tags;

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E2D5),
        title: const Text(
          'Đọc & Ghi Thẻ UHF',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF2C251E)),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF0284C7),
          labelColor: const Color(0xFF0284C7),
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.memory, size: 20), text: 'Đọc / Ghi chi tiết'),
            Tab(icon: Icon(Icons.flash_on, size: 20), text: 'Ghi nhanh EPC'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Detailed Read/Write
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Banner
                if (_statusMessage.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isSuccess ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _isSuccess ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isSuccess ? Icons.check_circle : Icons.error_outline,
                          color: _isSuccess ? const Color(0xFF34D399) : const Color(0xFFF87171),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              color: _isSuccess ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Filter Tag section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9E2D5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC7BDAF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.filter_alt, size: 18, color: Color(0xFF0284C7)),
                          const SizedBox(width: 6),
                          const Text(
                            'Lọc theo thẻ cụ thể (Filter Mask)',
                            style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const Spacer(),
                          Switch(
                            value: _useFilter,
                            activeThumbColor: const Color(0xFF0284C7),
                            onChanged: (val) => setState(() => _useFilter = val),
                          ),
                        ],
                      ),
                      if (_useFilter) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _filterEpcController,
                          style: const TextStyle(color: Color(0xFF2C251E), fontFamily: 'monospace', fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Mã EPC thẻ mục tiêu',
                            labelStyle: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFFF4EFE6),
                            suffixIcon: tags.isNotEmpty
                                ? PopupMenuButton<String>(
                                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0284C7)),
                                    onSelected: (epc) => setState(() => _filterEpcController.text = epc),
                                    itemBuilder: (ctx) => tags
                                        .map((t) => PopupMenuItem(
                                              value: t.epc,
                                              child: Text(t.epc, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                            ))
                                        .toList(),
                                  )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Bank Selector
                const Text(
                  '1. Chọn Vùng nhớ (Memory Bank)',
                  style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9E2D5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC7BDAF)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFFE9E2D5),
                      value: _selectedBank,
                      items: _banks.map((b) {
                        return DropdownMenuItem<int>(
                          value: b['id'] as int,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(b['name'] as String, style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(b['desc'] as String, style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedBank = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Parameters: Offset, Length, Password
                const Text(
                  '2. Tham số truy xuất (Word = 2 Bytes = 4 Hex chars)',
                  style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ptrController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Color(0xFF2C251E)),
                        decoration: InputDecoration(
                          labelText: 'Word Offset (ptr)',
                          labelStyle: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                          helperText: 'Bắt đầu từ word',
                          helperStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 10),
                          filled: true,
                          fillColor: const Color(0xFFE9E2D5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _cntController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Color(0xFF2C251E)),
                        decoration: InputDecoration(
                          labelText: 'Word Count (cnt)',
                          labelStyle: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                          helperText: 'Số word cần đọc/ghi',
                          helperStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 10),
                          filled: true,
                          fillColor: const Color(0xFFE9E2D5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  maxLength: 8,
                  style: const TextStyle(color: Color(0xFF2C251E), fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: 'Access Password (8 Hex chars)',
                    labelStyle: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                    helperText: 'Mặc định: 00000000',
                    helperStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 10),
                    filled: true,
                    fillColor: const Color(0xFFE9E2D5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),

                // Data (Hex & ASCII preview)
                const Text(
                  '3. Dữ liệu (Hex Data)',
                  style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _dataController,
                  maxLines: 3,
                  style: const TextStyle(color: Color(0xFF0284C7), fontFamily: 'monospace', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Nhập hoặc xem dữ liệu định dạng HEX...',
                    hintStyle: const TextStyle(color: Color(0xFF8F8070)),
                    filled: true,
                    fillColor: const Color(0xFFE9E2D5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_dataController.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'ASCII Preview: ${_hexToAscii(_dataController.text)}',
                    style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 20),

                // Read & Write Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('ĐỌC DỮ LIỆU', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isLoading ? null : _handleRead,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.upload),
                          label: const Text('GHI DỮ LIỆU', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isLoading ? null : _handleWrite,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab 2: Quick EPC Write
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9E2D5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF0284C7), size: 24),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Chức năng này cho phép ghi đè nhanh mã EPC mới vào thẻ một cách tự động và an toàn.',
                          style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Target Tag EPC
                const Text(
                  'Thẻ mục tiêu cần đổi EPC',
                  style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _quickTargetEpcController,
                  style: const TextStyle(color: Color(0xFF2C251E), fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'Nhập hoặc chọn thẻ từ danh sách đã quét',
                    hintStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFE9E2D5),
                    suffixIcon: tags.isNotEmpty
                        ? PopupMenuButton<String>(
                            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0284C7)),
                            onSelected: (epc) => setState(() => _quickTargetEpcController.text = epc),
                            itemBuilder: (ctx) => tags
                                .map((t) => PopupMenuItem(
                                      value: t.epc,
                                      child: Text(t.epc, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                    ))
                                .toList(),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),

                // New EPC
                const Text(
                  'Mã EPC mới (Hex string, thường 24 ký tự / 96 bits)',
                  style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _quickNewEpcController,
                  style: const TextStyle(color: Color(0xFF34D399), fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'Ví dụ: E28011700000020ECA509999',
                    hintStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFE9E2D5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.flash_on),
                    label: const Text('GHI ĐÈ EPC MỚI NGAY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _handleQuickWriteEpc,
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
