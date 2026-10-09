# Graph Report - uhf  (2026-10-09)

## Corpus Check
- 235 files · ~419,370 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 44 file(s) not represented in the graph (top: .xml 7, (none) 5, .dll 5)

## Summary
- 3888 nodes · 5457 edges · 137 communities (119 shown, 18 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 52 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Warehouse Repository State Engine
- Inventory Models and Entity Schema
- Desktop Inbound Goods Receive View
- UHF Tag Telemetry and RFID Models
- Desktop Outbound Goods Delivery View
- SQLite Database Local Persistence
- PDA Mobile Inbound Workflow
- Desktop Hopeland TCP Reader Service
- PDA Mobile Outbound Workflow
- C# WPF RFID Hardware Bridge
- Android Kotlin Seuic Reflection Bridge
- Industrial Color Tokens Design System
- UHF Core Scanning and Device Service
- Desktop UHF Studio Reader Controller
- Outbound Order and Shipment Models
- PDA Pallet Transfer and Relocation
- Desktop Stock Reconciliation and Reporting
- Desktop Warehouse 2D Location Management
- Eye Care Theme and Typography
- PDA Warehouse Management Operations
- Desktop Uhf Studio View desktop uhf studio view.d
- Supabase Sync Service ../config/secrets.dart
- Mainwindow BtnDisconnect
- Report Export Service CellStyle get
- Pda Inventory Screen InventorySession get
- Tower Light Service desktop uhf tcp service.d
- Pda Putaway Screen FocusNode
- Pda Merge Pallets Screen @visibleForTesting
- Desktop Warehouse Management View desktop location manageme
- Desktop Inventory View desktop audit ticket deta
- Api Service api service.dart
- Warehouse Location Grid Widget warehouse location grid w
- Excel Import Service excel import service.dart
- Desktop Main Layout desktop goods delivery vi
- Desktop Audit Ticket Detail View desktop audit ticket deta
- Inventory Models ItemStatus
- Catalog Models catalog models.dart
- Desktop Stock Reconciliation View desktop stock reconciliat
- Pda Lookup Screen pda lookup screen.dart
- Mainwindow.Xaml .OnDeviceDiscovered()
- Desktop Audit Ticket Detail View DesktopAuditTicketDetailV
- Warehouse Floor Plan Widget warehouse floor plan widg
- Radar Spatial Tracker double get
- Storage Screen storage screen.dart
- Sonar Radar Widget Color
- Main RfidWmsApp
- Report Export Service dart:convert
- Mainwindow BtnAutoConnect105
- App Notification Bar Test package:flutter/material.
- Auth Service database service.dart
- Fifo Search Screen fifo search screen.dart
- Uhf Service UhfService
- Desktop Inventory View Sync Test package:uhf/main.dart
- Adversarial M1 Empirical Test package:uhf/models/invent
- Tower Light Widget Animation
- Catalog Models WarehouseFloorPlanConfig
- Order Models InboundOrder
- User Models BaseRolePermission get
- Erp Bravo Service DateTime? get
- Inventory Models InventorySession
- Desktop User Management View desktop user management v
- Role Registry admin role.dart
- Hardware Trigger Feedback Banner class
- Catalog Models Location
- Register Screen register screen.dart
- Scenedelegate Any
- Uhf Connection Config uhf connection config.dar
- Pda Home Screen pda home screen.dart
- Pda Location Barcode Card pda location barcode card
- Pda Drawer ../desktop/desktop user m
- Inventory Models GateMode
- Devices Erp Screen devices erp screen.dart
- Splash Screen dart:async
- Resource dwmapi
- Flutter Window FlutterViewController
- Main main.dart
- App Typography app typography.dart
- Api Service Test package:flutter test/flut
- Generate Sample Excel Script generate sample excel scr
- Pda Home Screen build
- Antenna Power Config Test Exception
- Hardware Trigger And Pda Ergonomics Test package:uhf/screens/deskt
- Inventory Models fifo search screen.dart
- Role Base role base.dart
- Tag Info tag info.dart
- Login Screen login screen.dart
- Pda Locate Tasks Screen pda locate tasks screen.d
- Generate Two Products Two Pallets Script generate two products two
- Mainwindow BtnConnectSelectedDevice
- Main flutter windows
- Admin Role bool get
- Technician Role technician role.dart
- Flutter Window dart project
- Flutter Window generated plugin registra
- Inventory Models Item
- Handheld Role handheld role.dart
- Seller Role seller role.dart
- Warehouse Keeper Role warehouse keeper role.dar
- Rfid Telemetry Card rfid telemetry card.dart
- Manifest manifest.json
- Win32 Window HWND
- App Theme Tokens Test dart:math
- Admin Role AdminRole
- Secrets secrets.dart
- Mainwindow BtnReadData
- Mainwindow BtnStartInventory
- App Notification Bar app notification bar.dart
- Win32 Window Point
- Desktop Pda Wrapper auth/login screen.dart
- Mainwindow BtnApplyAllPower
- Mainwindow SliderPower1
- Api Service ChangeNotifier
- Agents No Mock Data & Single Sou
- Skill Flutter UI Taste & Ergono
- Mainwindow BtnApplyLock
- Clear Orders And Products package:supabase/supabase
- Generated Plugin Registrant plugin registry
- Pda Goods Delivery Screen OutboundScreen
- App Theme app colors.dart
- Pda Inbound Screen InboundScreen
- Runner-Bridging-Header c users mnt documents uhf
- Desktop Goods Delivery View DesktopGoodsDeliveryView
- Desktop Goods Receive View DesktopGoodsReceiveView
- Desktop Location Management View DesktopLocationManagement
- Desktop Report View DesktopReportView
- Inbound Screen inbound screen.dart
- Outbound Screen outbound screen.dart
- Pda Transfer Screen PdaTransferScreen
- Module bool?
- Module DateTime
- Module List
- Module String?
- Module Timer?

## God Nodes (most connected - your core abstractions)
1. `Window` - 136 edges
2. `MainWindow` - 66 edges
3. `RFIDReaderService` - 57 edges
4. `MainActivity` - 50 edges
5. `Program` - 39 edges
6. `WarehouseRepository` - 37 edges
7. `EyeCareThemeService` - 33 edges
8. `Button` - 29 edges
9. `UHFReader105ENService` - 25 edges
10. `Win32Window` - 24 edges

## Surprising Connections (you probably didn't know these)
- `OnCreate` --calls--> `RegisterPlugins()`  [INFERRED]
  windows/runner/flutter_window.h → windows/flutter/generated_plugin_registrant.cc
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  windows/runner/win32_window.cpp → windows/runner/win32_window.h
- `RFID Warehouse Management System` --references--> `No Mock Data & Single Source of Truth`  [EXTRACTED]
  PROJECT.md → AGENTS.md
- `RFID Warehouse Management System` --references--> `Architecture & State Flow Blueprint`  [EXTRACTED]
  PROJECT.md → CODE_GRAPH.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **AI Specialist Squad Coordination** — agents_skills_rfid_hardware_engineer_skill_rfid_hardware_engineer, agents_skills_flutter_ui_taste_skill_flutter_ui_taste, agents_skills_supabase_db_architect_skill_supabase_db_architect, agents_skills_qa_test_engineer_skill_qa_test_engineer [EXTRACTED 0.95]

## Communities (137 total, 18 thin omitted)

### Community 0 - "Warehouse Repository State Engine"
Cohesion: 0.01
Nodes (157): erp_bravo_service.dart, Future, addCustomer, addCustomLocation, addDeliveryNote, addInboundOrder, addItem, addLocation (+149 more)

### Community 1 - "Inventory Models and Entity Schema"
Cohesion: 0.01
Nodes (134): DeviceType, action, actualLocation, actualQty, actualScannedCount, allocatedTime, assignedBy, assignedToDisplay (+126 more)

### Community 2 - "Desktop Inbound Goods Receive View"
Cohesion: 0.02
Nodes (117): _activeExpectedItems, _activeOrderNo, _activePallet, _activePalletTag, _applyDemoInboundPackage, _autoCompleteTimer, build, _buildActiveVehicleScanView (+109 more)

### Community 3 - "UHF Tag Telemetry and RFID Models"
Cohesion: 0.03
Nodes (93): Antenna, Count, DeviceType, EPC, Frequency, Gateway, Index, IP (+85 more)

### Community 4 - "Desktop Outbound Goods Delivery View"
Cohesion: 0.02
Nodes (94): _auth, _autoConfirmTimer, build, _buildBottomControlBar, _buildBottomControlBarWrapper, _buildIdleGateMonitor, _buildLedBulb, _buildMetricBadge (+86 more)

### Community 5 - "SQLite Database Local Persistence"
Cohesion: 0.02
Nodes (94): checkExistingEpcs, clearAllData, clearCompletedSyncQueue, clearTagLifecycleLogs, _customers, deleteAllLocations, deleteCustomer, deleteDeliveryNote (+86 more)

### Community 6 - "PDA Mobile Inbound Workflow"
Cohesion: 0.02
Nodes (91): _activeFilter, activePalletCode, _autoConfirmedThisSession, build, _buildEmptyStateOrOrderList, _buildFilterChip, _buildFilterChips, _buildHardwareScannerControls (+83 more)

### Community 7 - "Desktop Hopeland TCP Reader Service"
Cohesion: 0.02
Nodes (86): Completer, _activeAntennas, _antennaPower, _bridgeProcess, _bridgeSocket, _cachedTagsList, clearTags, _config (+78 more)

### Community 8 - "PDA Mobile Outbound Workflow"
Cohesion: 0.02
Nodes (81): _auth, _autoConfirmTimer, build, _buildActiveOutboundView, _buildBottomControlBar, _buildIdleGateMonitor, _buildLedBulb, _buildMetricBox (+73 more)

### Community 9 - "C# WPF RFID Hardware Bridge"
Cohesion: 0.05
Nodes (42): UHFDesktopApp.Models, UHFDesktopApp, UHFHardwareBridge, UHFDesktopApp.Services, Application, App, CallBackEnum, DateTime (+34 more)

### Community 10 - "Android Kotlin Seuic Reflection Bridge"
Cohesion: 0.05
Nodes (33): MainActivity, StreamHandler, StreamHandler, SensorEventListener, atomicboolean, audiomanager, broadcastreceiver, Bundle (+25 more)

### Community 11 - "Industrial Color Tokens Design System"
Cohesion: 0.03
Nodes (77): amberEnterprise, AppColors, coralEnterprise, cyanTech, duplicate, duplicateDeep, duplicateGlow, duplicateLight (+69 more)

### Community 12 - "UHF Core Scanning and Device Service"
Cohesion: 0.03
Nodes (76): auth_service.dart, _activeScanModule, _barcodeStreamController, _cachedTagsList, clearTags, _currentHeading, disableScanning, enableScanning (+68 more)

### Community 13 - "Desktop UHF Studio Reader Controller"
Cohesion: 0.05
Nodes (29): BtnApplyBaseBand, BtnBeepTest, BtnClearList, BtnConnect, BtnConnect105, BtnExportCsv, BtnGenRandomEpc, BtnGetNetConfig (+21 more)

### Community 14 - "Outbound Order and Shipment Models"
Cohesion: 0.03
Nodes (69): address, carrier, cartonCode, code, contactPerson, createdAt, createdBy, Customer (+61 more)

### Community 15 - "PDA Pallet Transfer and Relocation"
Cohesion: 0.03
Nodes (68): _auth, _barcodeSub, _buildCountBadge, _buildEpcChip, _buildErrorBanner, _buildItemsConfirmContent, _buildItemsScanContent, _buildItemStepIndicator (+60 more)

### Community 16 - "Desktop Stock Reconciliation and Reporting"
Cohesion: 0.03
Nodes (66): desktop_stock_reconciliation_view.dart, _applyPeriodPreset, build, _buildActionToolbar, _buildBusinessOperationsReportTab, _buildBusinessPreviewContent, _buildBusinessToolbar, _buildBusinessTypeSelector (+58 more)

### Community 17 - "Desktop Warehouse 2D Location Management"
Cohesion: 0.04
Nodes (54): _auth, bgLight, build, _buildEmptyRackView, _buildFilterToolbar, _buildKpiAndLegendBar, _buildKpiCard, _buildLegendPill (+46 more)

### Community 18 - "Eye Care Theme and Typography"
Cohesion: 0.04
Nodes (53): app_theme.dart, app_typography.dart, Color get, EyeCareColors get, EyeCareMode get, amberNight, bgCard, bgCardElevated (+45 more)

### Community 19 - "PDA Warehouse Management Operations"
Cohesion: 0.04
Nodes (52): AutomaticKeepAliveClientMixin, _auth, build, _buildDetailRow, _buildHistoryCategoryChip, _buildHistoryItemCard, _buildHistoryStatusChip, _buildMetricMiniCard (+44 more)

### Community 20 - "Desktop Uhf Studio View desktop uhf studio view.d"
Cohesion: 0.04
Nodes (52): _auth, _autoScrollLog, _baudRates, build, _buildConnectionToolbar, _buildConsoleLog, _buildKpiCard, _buildKpiMetrics (+44 more)

### Community 21 - "Supabase Sync Service ../config/secrets.dart"
Cohesion: 0.04
Nodes (51): ../config/secrets.dart, action, _addLog, anonKey, _autoSyncTimer, checkConnectivity, clearAllSupabaseData, _client (+43 more)

### Community 22 - "Mainwindow BtnDisconnect"
Cohesion: 0.07
Nodes (17): BtnDisconnect, BtnGetDeviceInfo, CallBackEnum, Device_Model, GPI_Model, Tag_Model, Timer, RFIDReaderService (+9 more)

### Community 23 - "Report Export Service CellStyle get"
Cohesion: 0.04
Nodes (48): CellStyle get, DateFormat, _autoFitColumns, _buildAuditSummarySheet, _buildInboundSummarySheet, _buildOutboundSummarySheet, _buildSingleAuditSessionSheet, _buildSingleInboundOrderSheet (+40 more)

### Community 24 - "Pda Inventory Screen InventorySession get"
Cohesion: 0.04
Nodes (48): InventorySession get, _activeSession, _addManualEpc, _barcodeSub, build, _buildFilterTabChip, _buildInventoryScanningScreen, _buildInventoryTypeCard (+40 more)

### Community 25 - "Tower Light Service desktop uhf tcp service.d"
Cohesion: 0.04
Nodes (46): desktop_uhf_tcp_service.dart, buzzerPin, color, config, _currentStatus, dispose, fromMap, _getConfigFile (+38 more)

### Community 26 - "Pda Putaway Screen FocusNode"
Cohesion: 0.04
Nodes (46): FocusNode, _activePalletGroup, _barcodeFocusNode, _barcodeInputController, _barcodeSub, build, _buildAllDoneView, _buildEmptyPendingView (+38 more)

### Community 27 - "Pda Merge Pallets Screen @visibleForTesting"
Cohesion: 0.05
Nodes (44): @visibleForTesting, _auth, _barcodeSub, build, _buildBottomStatusIndicator, _buildLastMergedBanner, _buildPalletSection, _buildRecentMergesList (+36 more)

### Community 28 - "Desktop Warehouse Management View desktop location manageme"
Cohesion: 0.04
Nodes (44): desktop_location_management_view.dart, desktop_lookup_view.dart, build, _buildCategoryTabButton, _buildFilterPill, _buildHeaderBar, _buildHistoryInfoRow, _buildHistoryManagementTab (+36 more)

### Community 29 - "Desktop Inventory View desktop audit ticket deta"
Cohesion: 0.05
Nodes (42): desktop_audit_ticket_detail_view.dart, _activeSession, _auth, build, _buildActionHeroCard, _buildActiveInventoryView, _buildAuditKpiCard, _buildExportOptionCard (+34 more)

### Community 30 - "Api Service api service.dart"
Cohesion: 0.05
Nodes (40): batchUpsertItems, _broadcastChannel, broadcastGatePass, broadcastPutaway, dispose, epcs, fetchInboundOrders, fetchLocations (+32 more)

### Community 31 - "Warehouse Location Grid Widget warehouse location grid w"
Cohesion: 0.05
Nodes (40): bgLight, build, _buildGridBody, _buildLegendPill, _buildQuickStatusBtn, _buildShelfCard, color, _confirmResetLocations (+32 more)

### Community 32 - "Excel Import Service excel import service.dart"
Cohesion: 0.05
Nodes (39): cartonCode, cartons, _cellToString, customer, customerName, epc, ExcelImportResult, ExcelImportService (+31 more)

### Community 33 - "Desktop Main Layout desktop goods delivery vi"
Cohesion: 0.06
Nodes (36): desktop_goods_delivery_view.dart, desktop_goods_receive_view.dart, desktop_inventory_view.dart, desktop_report_view.dart, desktop_uhf_studio_view.dart, desktop_user_management_view.dart, desktop_warehouse_management_view.dart, IconData (+28 more)

### Community 34 - "Desktop Audit Ticket Detail View desktop audit ticket deta"
Cohesion: 0.06
Nodes (35): build, _buildEpcTagsSection, _buildHeaderBar, _buildMetricTile, _buildScorecard, _buildSkuBreakdownSection, _buildStatusPill, _buildTabBarContainer (+27 more)

### Community 35 - "Inventory Models ItemStatus"
Cohesion: 0.06
Nodes (34): ItemStatus, allFlatTable, build, _buildAllFlatTableView, _buildDialogTextField, _buildFilterChip, _buildItemsDataTable, _buildMiniStatusTag (+26 more)

### Community 36 - "Catalog Models catalog models.dart"
Cohesion: 0.06
Nodes (33): aisleSide, aisleWidth, category, copyWith, currentPallets, defaultConfig, description, entryGateName (+25 more)

### Community 37 - "Desktop Stock Reconciliation View desktop stock reconciliat"
Cohesion: 0.06
Nodes (31): build, _buildFilterToolbar, _buildHeaderBar, _buildReconciliationTable, _buildScorecard, _buildStatusPill, createState, _dataCell (+23 more)

### Community 38 - "Pda Lookup Screen pda lookup screen.dart"
Cohesion: 0.06
Nodes (31): _auth, _barcodeSub, build, _buildLocationResultCard, _buildLookupBody, _buildPalletResultCard, createState, _currentScanMode (+23 more)

### Community 39 - "Mainwindow.Xaml .OnDeviceDiscovered()"
Cohesion: 0.06
Nodes (27): DiscoveredDevice, ConnectState, DeviceType, Gateway, IP, MAC, Mask, RemoteIP (+19 more)

### Community 40 - "Desktop Audit Ticket Detail View DesktopAuditTicketDetailV"
Cohesion: 0.11
Nodes (31): DesktopAuditTicketDetailView, _DesktopAuditTicketDetailViewState, DesktopUhfStudioView, _DesktopUhfStudioViewState, DesktopWarehouseManagementView, _DesktopWarehouseManagementViewState, DevicesErpScreen, _DevicesErpScreenState (+23 more)

### Community 41 - "Warehouse Floor Plan Widget warehouse floor plan widg"
Cohesion: 0.07
Nodes (30): build, _buildAisleRackColumn, _buildBackRowRacks, _buildCentralForkliftCorridor, _buildFloorPlanCanvas, _buildGateBar, _buildHeaderBar, _buildNavigationBreadcrumbBanner (+22 more)

### Community 42 - "Radar Spatial Tracker double get"
Cohesion: 0.07
Nodes (29): double get, int get, decayWithoutSignal, _deviceHeadingDeg, hasLockedTarget, _hasReceivedHeading, headingDeg, _lastKnownTargetAzimuthDeg (+21 more)

### Community 43 - "Storage Screen storage screen.dart"
Cohesion: 0.07
Nodes (29): build, _buildMovementHistoryTab, _buildPalletManagementTab, _buildSkuStockTab, _buildStockStatBox, _confirmClearAllData, _confirmDeletePallet, createState (+21 more)

### Community 44 - "Sonar Radar Widget Color"
Cohesion: 0.07
Nodes (28): Color, CustomPainter, double?, build, _buildRadarRing, color, createState, didUpdateWidget (+20 more)

### Community 45 - "Main RfidWmsApp"
Cohesion: 0.07
Nodes (27): RfidWmsApp, DesktopPdaWrapper, PdaDrawer, RadarLocateScreen, build, GatePassFailBanner, isScanning, result (+19 more)

### Community 46 - "Report Export Service dart:convert"
Cohesion: 0.10
Nodes (21): dart:convert, dart:io, dart:typed_data, ReportExportService, package:archive/archive.dart, package:excel/excel.dart, package:uhf/services/excel_import_service.dart, package:uhf/services/report_export_service.dart (+13 more)

### Community 47 - "Mainwindow BtnAutoConnect105"
Cohesion: 0.12
Nodes (11): BtnAutoConnect105, BtnDisconnect105, BtnStopInventory, UHFReader105ENService, ComAddr, ComPort, Instance, IsConnected (+3 more)

### Community 48 - "App Notification Bar Test package:flutter/material."
Cohesion: 0.10
Nodes (18): package:flutter/material.dart, package:uhf/screens/desktop/desktop_goods_receive_view.dart, package:uhf/screens/pda/pda_inventory_screen.dart, package:uhf/screens/pda/pda_lookup_screen.dart, package:uhf/screens/pda/pda_merge_pallets_screen.dart, package:uhf/screens/pda/pda_transfer_screen.dart, package:uhf/screens/storage_screen.dart, package:uhf/services/uhf_service.dart (+10 more)

### Community 49 - "Auth Service database service.dart"
Cohesion: 0.08
Nodes (25): database_service.dart, adminCreateUser, adminDeleteUser, adminResetPassword, adminToggleUserActive, adminUpdateUser, _authError, _currentUser (+17 more)

### Community 50 - "Fifo Search Screen fifo search screen.dart"
Cohesion: 0.08
Nodes (25): _barcodeSub, build, _buildEmptySearchCard, _buildFifoSummaryBanner, _buildQuickSkuChips, _buildSearchBar, createState, dispose (+17 more)

### Community 51 - "Uhf Service UhfService"
Cohesion: 0.09
Nodes (19): UhfService, WarehouseRepository, package:uhf/models/wms_models.dart, package:uhf/screens/fifo_search_screen.dart, package:uhf/widgets/warehouse_floor_plan_editor_dialog.dart, package:uhf/widgets/warehouse_floor_plan_widget.dart, main, repo (+11 more)

### Community 52 - "Desktop Inventory View Sync Test package:uhf/main.dart"
Cohesion: 0.08
Nodes (21): package:uhf/main.dart, package:uhf/screens/desktop/desktop_audit_ticket_detail_view.dart, package:uhf/screens/desktop/desktop_inventory_view.dart, package:uhf/screens/desktop/desktop_location_management_view.dart, package:uhf/screens/desktop/desktop_lookup_view.dart, package:uhf/screens/desktop/desktop_report_view.dart, package:uhf/screens/desktop/desktop_stock_reconciliation_view.dart, package:uhf/screens/desktop/desktop_uhf_studio_view.dart (+13 more)

### Community 53 - "Adversarial M1 Empirical Test package:uhf/models/invent"
Cohesion: 0.14
Nodes (16): package:uhf/models/inventory_models.dart, package:uhf/models/order_models.dart, package:uhf/screens/desktop/desktop_goods_delivery_view.dart, package:uhf/screens/pda/pda_goods_delivery_screen.dart, package:uhf/services/warehouse_repository.dart, package:uhf/widgets/warehouse_location_grid_widget.dart, main, main (+8 more)

### Community 54 - "Tower Light Widget Animation"
Cohesion: 0.08
Nodes (23): Animation, AnimationController, _animController, build, _buildCompactView, _buildCoupler, _buildFullPanel, _buildMiniLamp (+15 more)

### Community 55 - "Catalog Models WarehouseFloorPlanConfig"
Cohesion: 0.08
Nodes (23): WarehouseFloorPlanConfig, _aisleLabelCtrl, build, _buildPresetCard, _buildRackRowItem, _buildTabGatesAndAisle, _buildTabPresets, _buildTabRacks (+15 more)

### Community 56 - "Order Models InboundOrder"
Cohesion: 0.08
Nodes (23): InboundOrder, allAssetSpecs, buildDemoPackage, category, DemoAssetSpec, DemoInboundPackage, fixedEpcs, InboundDemoScenarioService (+15 more)

### Community 57 - "User Models BaseRolePermission get"
Cohesion: 0.09
Nodes (21): BaseRolePermission get, catalog_models.dart, inventory_models.dart, canAdjustAntennaPower, canConfigureHardware, createdAt, email, fromMap (+13 more)

### Community 58 - "Erp Bravo Service DateTime? get"
Cohesion: 0.09
Nodes (22): DateTime? get, action, addLog, BravoIntegrationLog, documentNo, ErpBravoService, _instance, _isConnected (+14 more)

### Community 59 - "Inventory Models InventorySession"
Cohesion: 0.09
Nodes (22): InventorySession, _activeSession, build, _buildHandheldScanCard, _buildSessionConfigCard, _buildVarianceItemList, _buildVarianceTabsCard, _completeSession (+14 more)

### Community 60 - "Desktop User Management View desktop user management v"
Cohesion: 0.09
Nodes (22): _auth, build, _buildRoleFilterChip, _buildStatCard, _confirmDeleteUser, createState, DesktopUserManagementView, _DesktopUserManagementViewState (+14 more)

### Community 61 - "Role Registry admin role.dart"
Cohesion: 0.10
Nodes (20): admin_role.dart, handheld_role.dart, admin, allRoles, dropdownItems, fromCode, handheld, RoleRegistry (+12 more)

### Community 62 - "Hardware Trigger Feedback Banner class"
Cohesion: 0.10
Nodes (20): class, int?, build, compact, createState, customIdleLabel, dispose, externalIsScanning (+12 more)

### Community 63 - "Catalog Models Location"
Cohesion: 0.10
Nodes (20): Location, _barcodeSub, build, _buildSelectedShelfPanel, _buildShelfListItem, _buildStatusUpdateButton, createState, dispose (+12 more)

### Community 64 - "Register Screen register screen.dart"
Cohesion: 0.10
Nodes (20): _auth, build, _confirmPasswordController, createState, dispose, _emailController, _eyeCare, _fullNameController (+12 more)

### Community 65 - "Scenedelegate Any"
Cohesion: 0.11
Nodes (14): Any, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, FlutterSceneDelegate, AppDelegate, Bool (+6 more)

### Community 66 - "Uhf Connection Config uhf connection config.dar"
Cohesion: 0.10
Nodes (19): activeAntennas, antennaPowers, autoConnectOnScan, autoConnectOnStartup, autoReconnect, baudRate, comPort, connectionType (+11 more)

### Community 67 - "Pda Home Screen pda home screen.dart"
Cohesion: 0.10
Nodes (19): _authService, _buildPdaActionTile, createState, dispose, _eyeCare, initState, _onRepoChange, _onStateChange (+11 more)

### Community 68 - "Pda Location Barcode Card pda location barcode card"
Cohesion: 0.10
Nodes (19): autoListenHardwareBarcode, _barcodeSub, build, _buildFilterChip, _buildInfoTag, createState, dispose, _eyeCare (+11 more)

### Community 69 - "Pda Drawer ../desktop/desktop user m"
Cohesion: 0.11
Nodes (18): ../desktop/desktop_user_management_view.dart, build, colors, createState, _currentPowerDouble, _currentPowerInt, initialPower, initState (+10 more)

### Community 70 - "Inventory Models GateMode"
Cohesion: 0.11
Nodes (18): GateMode, GateVerificationResult, build, createState, _gateMode, GateMonitorScreen, _GateMonitorScreenState, _gateResult (+10 more)

### Community 71 - "Devices Erp Screen devices erp screen.dart"
Cohesion: 0.11
Nodes (18): _bravo, build, _buildDevicesTab, _buildErpBravoTab, createState, dispose, _getDeviceIcon, _getLiveDevices (+10 more)

### Community 72 - "Splash Screen dart:async"
Cohesion: 0.12
Nodes (17): dart:async, ../desktop_pda_wrapper.dart, Duration?, build, createState, didChangeDependencies, dispose, duration (+9 more)

### Community 73 - "Resource dwmapi"
Cohesion: 0.17
Nodes (14): dwmapi, wchar_t, Scale(), Create, Destroy, SetQuitOnClose, Show, Win32Window::Win32Window() (+6 more)

### Community 74 - "Flutter Window FlutterViewController"
Cohesion: 0.16
Nodes (18): FlutterViewController, RECT, unique_ptr, FlutterWindow, flutter_controller_, OnCreate, OnDestroy, project_ (+10 more)

### Community 75 - "Main main.dart"
Cohesion: 0.12
Nodes (16): build, main, actions, build, leading, preferredSize, showScanMode, title (+8 more)

### Community 76 - "App Typography app typography.dart"
Cohesion: 0.11
Nodes (17): AppTypography, barcode, codeLabel, dataGridCell, epc, epcCompact, fieldLabel, kpiNumber (+9 more)

### Community 77 - "Api Service Test package:flutter test/flut"
Cohesion: 0.13
Nodes (12): package:flutter_test/flutter_test.dart, package:uhf/screens/pda/pda_putaway_screen.dart, package:uhf/services/api_service.dart, package:uhf/services/inbound_demo_service.dart, package:uhf/services/radar_spatial_tracker.dart, package:uhf/services/tower_light_service.dart, main, main (+4 more)

### Community 78 - "Generate Sample Excel Script generate sample excel scr"
Cohesion: 0.11
Nodes (17): bytes, cartonsPerPallet, codeStyle, defaultSheet, excel, headers, headerStyle, itemsPerCarton (+9 more)

### Community 79 - "Pda Home Screen build"
Cohesion: 0.12
Nodes (17): build, _buildDesktopOrderNotificationCard, _buildDesktopCompletionBanner, _buildPassSuccessBanner, _buildStep1CartonSelection, _buildStep2RfidVerification, _confirmGoodsReceiveAtGate, build (+9 more)

### Community 80 - "Antenna Power Config Test Exception"
Cohesion: 0.12
Nodes (12): Exception, package:uhf/models/catalog_models.dart, package:uhf/models/tag_info.dart, package:uhf/models/uhf_connection_config.dart, package:uhf/services/auth_service.dart, package:uhf/services/database_service.dart, package:uhf/services/desktop_uhf_tcp_service.dart, package:uhf/services/supabase_sync_service.dart (+4 more)

### Community 81 - "Hardware Trigger And Pda Ergonomics Test package:uhf/screens/deskt"
Cohesion: 0.17
Nodes (13): package:uhf/screens/desktop/desktop_main_layout.dart, package:uhf/theme/app_colors.dart, package:uhf/theme/app_theme.dart, package:uhf/widgets/gate_pass_fail_banner.dart, package:uhf/widgets/hardware_trigger_feedback_banner.dart, package:uhf/widgets/putaway_barcode_modal.dart, package:uhf/widgets/rfid_telemetry_card.dart, package:uhf/widgets/sonar_radar_widget.dart (+5 more)

### Community 82 - "Inventory Models fifo search screen.dart"
Cohesion: 0.14
Nodes (13): fifo_search_screen.dart, LocateOrder, Pallet, build, equalsIgnoreCase, initialEpc, initialItem, initialItemId (+5 more)

### Community 83 - "Role Base role base.dart"
Cohesion: 0.14
Nodes (13): canAdjustAntennaPower, canAudit, canConfigureHardware, canInbound, canLookup, canManageUsers, canOutbound, canTransfer (+5 more)

### Community 84 - "Tag Info tag info.dart"
Cohesion: 0.14
Nodes (13): ant, count, epc, firstSeen, fromMap, lastSeen, pc, rssi (+5 more)

### Community 85 - "Login Screen login screen.dart"
Cohesion: 0.15
Nodes (13): _auth, build, createState, dispose, _eyeCare, _handleLogin, LoginScreen, _LoginScreenState (+5 more)

### Community 86 - "Pda Locate Tasks Screen pda locate tasks screen.d"
Cohesion: 0.14
Nodes (13): _auth, _buildFilterChip, _buildTagChip, createState, dispose, _eyeCare, _filter, _formatDate (+5 more)

### Community 87 - "Generate Two Products Two Pallets Script generate two products two"
Cohesion: 0.14
Nodes (13): bytes, codeStyle, currentRow, defaultSheet, excel, headers, headerStyle, main (+5 more)

### Community 88 - "Mainwindow BtnConnectSelectedDevice"
Cohesion: 0.15
Nodes (8): BtnConnectSelectedDevice, CmbConnType, CmbSdkMode, DgDiscoveredDevices, DgTags, MouseButtonEventArgs, SelectionChangedEventArgs, DataGrid

### Community 89 - "Main flutter windows"
Cohesion: 0.19
Nodes (12): flutter_windows, _In_, _In_opt_, io, iostream, stdio, wWinMain(), string (+4 more)

### Community 90 - "Admin Role bool get"
Cohesion: 0.17
Nodes (11): bool get, canAdjustAntennaPower, canAudit, canConfigureHardware, canInbound, canManageUsers, canOutbound, canTransfer (+3 more)

### Community 91 - "Technician Role technician role.dart"
Cohesion: 0.17
Nodes (11): canAudit, canConfigureHardware, canInbound, canManageUsers, canOutbound, canTransfer, code, description (+3 more)

### Community 92 - "Flutter Window dart project"
Cohesion: 0.27
Nodes (7): dart_project, flutter_view_controller, functional, memory, string, vector, windows

### Community 93 - "Flutter Window generated plugin registra"
Cohesion: 0.18
Nodes (10): generated_plugin_registrant, optional, DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM (+2 more)

### Community 94 - "Inventory Models Item"
Cohesion: 0.18
Nodes (10): Item, _buildInfoBadge, epc, _formatDateTime, _getActionIcon, item, show, _timeAgo (+2 more)

### Community 95 - "Handheld Role handheld role.dart"
Cohesion: 0.18
Nodes (10): canAdjustAntennaPower, canAudit, canConfigureHardware, canInbound, canManageUsers, canOutbound, canTransfer, code (+2 more)

### Community 96 - "Seller Role seller role.dart"
Cohesion: 0.18
Nodes (10): canAudit, canConfigureHardware, canInbound, canManageUsers, canOutbound, canTransfer, code, description (+2 more)

### Community 97 - "Warehouse Keeper Role warehouse keeper role.dar"
Cohesion: 0.18
Nodes (10): canAdjustAntennaPower, canAudit, canConfigureHardware, canInbound, canManageUsers, canOutbound, canTransfer, code (+2 more)

### Community 98 - "Rfid Telemetry Card rfid telemetry card.dart"
Cohesion: 0.18
Nodes (10): antennaInfo, build, _buildMetricTile, isScanning, readRate, rssi, totalReads, uniqueTags (+2 more)

### Community 99 - "Manifest manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 100 - "Win32 Window HWND"
Cohesion: 0.33
Nodes (11): HWND, LPARAM, LRESULT, UINT, WPARAM, EnableFullDpiSupportIfAvailable(), GetHandle, GetThisFromHandle (+3 more)

### Community 101 - "App Theme Tokens Test dart:math"
Cohesion: 0.20
Nodes (9): dart:math, Material, package:uhf/theme/eye_care_theme.dart, Set, calculateContrastRatio, calculateRelativeLuminance, legacyPaperHexValues, main (+1 more)

### Community 102 - "Admin Role AdminRole"
Cohesion: 0.29
Nodes (9): AdminRole, HandheldRole, BaseRolePermission, SellerRole, TechnicianRole, WarehouseKeeperRole, package:uhf/models/roles/role_registry.dart, package:uhf/models/user_models.dart (+1 more)

### Community 103 - "Secrets secrets.dart"
Cohesion: 0.22
Nodes (7): AppSecrets, AppSecrets, supabaseAnonKey, supabaseUrl, supabaseAnonKey, supabaseUrl, static const String

### Community 104 - "Mainwindow BtnReadData"
Cohesion: 0.25
Nodes (6): BtnReadData, TagMemoryBank, EPC, Reserved, TID, UserData

### Community 105 - "Mainwindow BtnStartInventory"
Cohesion: 0.25
Nodes (4): BtnStartInventory, eAntennaNo, eAntennaNo, eReadType

### Community 106 - "App Notification Bar app notification bar.dart"
Cohesion: 0.25
Nodes (7): AppNotificationType, AppSnackBar, show, showError, showInfo, showSuccess, showWarning

### Community 107 - "Win32 Window Point"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 108 - "Desktop Pda Wrapper auth/login screen.dart"
Cohesion: 0.29
Nodes (6): auth/login_screen.dart, desktop/desktop_main_layout.dart, build, package:flutter/foundation.dart, pda/pda_home_screen.dart, ../../services/auth_service.dart

### Community 109 - "Mainwindow BtnApplyAllPower"
Cohesion: 0.29
Nodes (3): BtnApplyAllPower, BtnQueryPower, Dictionary

### Community 110 - "Mainwindow SliderPower1"
Cohesion: 0.43
Nodes (6): SliderPower1, SliderPower2, SliderPower3, SliderPower4, RoutedPropertyChangedEventArgs, Slider

### Community 111 - "Api Service ChangeNotifier"
Cohesion: 0.33
Nodes (6): ChangeNotifier, ApiService, DesktopUhfTcpService, SupabaseSyncService, TowerLightService, EyeCareThemeService

### Community 112 - "Agents No Mock Data & Single Sou"
Cohesion: 0.40
Nodes (5): No Mock Data & Single Source of Truth, Architecture & State Flow Blueprint, RFID Warehouse Management System, Warehouse Inbound/Outbound RFID Flow, Test Infrastructure & Zero-Regression Suite

### Community 113 - "Skill Flutter UI Taste & Ergono"
Cohesion: 0.40
Nodes (5): Flutter UI Taste & Ergonomics Skill, QA Test Engineer Skill, RFID Hardware Engineer Skill, Supabase DB Architect Skill, Antigravity Specialist AI Squad

### Community 114 - "Mainwindow BtnApplyLock"
Cohesion: 0.40
Nodes (3): BtnApplyLock, eLockArea, eLockType

### Community 115 - "Clear Orders And Products package:supabase/supabase"
Cohesion: 0.40
Nodes (4): package:supabase/supabase.dart, main, steps, supa

### Community 116 - "Generated Plugin Registrant plugin registry"
Cohesion: 0.40
Nodes (3): plugin_registry, PluginRegistry, RegisterPlugins()

### Community 117 - "Pda Goods Delivery Screen OutboundScreen"
Cohesion: 0.50
Nodes (4): OutboundScreen, _OutboundScreenState, PdaGoodsDeliveryScreen, PdaOutboundScreen

### Community 119 - "Pda Inbound Screen InboundScreen"
Cohesion: 0.67
Nodes (3): InboundScreen, _InboundScreenState, PdaInboundScreen

## Knowledge Gaps
- **2783 isolated node(s):** `TabControl`, `Index`, `EPC`, `TID`, `RssiDisplay` (+2778 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 3055 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **18 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WarehouseRepository` connect `Uhf Service UhfService` to `Warehouse Repository State Engine`, `Desktop Inbound Goods Receive View`, `Desktop Outbound Goods Delivery View`, `PDA Mobile Inbound Workflow`, `PDA Mobile Outbound Workflow`, `PDA Pallet Transfer and Relocation`, `Desktop Stock Reconciliation and Reporting`, `Desktop Warehouse 2D Location Management`, `PDA Warehouse Management Operations`, `Report Export Service CellStyle get`, `Pda Inventory Screen InventorySession get`, `Pda Putaway Screen FocusNode`, `Pda Merge Pallets Screen @visibleForTesting`, `Desktop Warehouse Management View desktop location manageme`, `Desktop Inventory View desktop audit ticket deta`, `Warehouse Location Grid Widget warehouse location grid w`, `Desktop Audit Ticket Detail View desktop audit ticket deta`, `Inventory Models ItemStatus`, `Desktop Stock Reconciliation View desktop stock reconciliat`, `Pda Lookup Screen pda lookup screen.dart`, `Warehouse Floor Plan Widget warehouse floor plan widg`, `Storage Screen storage screen.dart`, `Report Export Service dart:convert`, `Fifo Search Screen fifo search screen.dart`, `Catalog Models WarehouseFloorPlanConfig`, `Inventory Models InventorySession`, `Desktop User Management View desktop user management v`, `Catalog Models Location`, `Pda Location Barcode Card pda location barcode card`, `Inventory Models GateMode`, `Pda Locate Tasks Screen pda locate tasks screen.d`, `Api Service ChangeNotifier`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Why does `EyeCareThemeService` connect `Api Service ChangeNotifier` to `Desktop Inbound Goods Receive View`, `Desktop Outbound Goods Delivery View`, `PDA Mobile Inbound Workflow`, `PDA Mobile Outbound Workflow`, `PDA Pallet Transfer and Relocation`, `Desktop Stock Reconciliation and Reporting`, `Desktop Warehouse 2D Location Management`, `Eye Care Theme and Typography`, `PDA Warehouse Management Operations`, `Desktop Uhf Studio View desktop uhf studio view.d`, `Pda Putaway Screen FocusNode`, `Pda Merge Pallets Screen @visibleForTesting`, `Desktop Warehouse Management View desktop location manageme`, `Desktop Inventory View desktop audit ticket deta`, `Warehouse Location Grid Widget warehouse location grid w`, `Desktop Main Layout desktop goods delivery vi`, `Desktop Audit Ticket Detail View desktop audit ticket deta`, `Inventory Models ItemStatus`, `Desktop Stock Reconciliation View desktop stock reconciliat`, `Pda Lookup Screen pda lookup screen.dart`, `Warehouse Floor Plan Widget warehouse floor plan widg`, `Storage Screen storage screen.dart`, `Fifo Search Screen fifo search screen.dart`, `Tower Light Widget Animation`, `Catalog Models WarehouseFloorPlanConfig`, `Desktop User Management View desktop user management v`, `Hardware Trigger Feedback Banner class`, `Catalog Models Location`, `Register Screen register screen.dart`, `Pda Location Barcode Card pda location barcode card`, `Login Screen login screen.dart`, `Pda Locate Tasks Screen pda locate tasks screen.d`?**
  _High betweenness centrality (0.030) - this node is a cross-community bridge._
- **Why does `Pallet` connect `Inventory Models fifo search screen.dart` to `Inventory Models and Entity Schema`, `Desktop Inbound Goods Receive View`, `PDA Mobile Inbound Workflow`, `Pda Lookup Screen pda lookup screen.dart`, `PDA Pallet Transfer and Relocation`, `Desktop Warehouse 2D Location Management`, `Fifo Search Screen fifo search screen.dart`, `Pda Merge Pallets Screen @visibleForTesting`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **What connects `TabControl`, `Index`, `EPC` to the rest of the system?**
  _2783 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Warehouse Repository State Engine` be split into smaller, more focused modules?**
  _Cohesion score 0.012658227848101266 - nodes in this community are weakly interconnected._
- **Should `Inventory Models and Entity Schema` be split into smaller, more focused modules?**
  _Cohesion score 0.014814814814814815 - nodes in this community are weakly interconnected._
- **Should `Desktop Inbound Goods Receive View` be split into smaller, more focused modules?**
  _Cohesion score 0.01694915254237288 - nodes in this community are weakly interconnected._