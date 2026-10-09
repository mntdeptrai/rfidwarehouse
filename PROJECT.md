# Project: UHF RFID Warehouse Management System UI/UX Redesign (Industrial Modern Tech)

## Architecture
- **Framework**: Flutter 3 (Multi-platform: Mobile PDA & Desktop Workstation).
- **Target Mobile Hardware**: Seuic AUTOID UTouch 2 & UTouch C pistol-grip handhelds (4.0" - 5.5", 480x800 to HD).
- **Desktop Target**: Windows/Linux/macOS High-Density Workstation (1080p - 4K, keyboard/mouse shortcuts, Fixed Reader TCP).
- **Visual Style**: Industrial Modern Tech (Deep Slate `#0F172A` / `#1E293B`, Electric Cyan `#00E5FF`, Tech Blue `#0284C7`, Emerald Green `#10B981`, Amber `#F59E0B`, Coral Red `#EF4444`, Deep Indigo `#6366F1`).
- **Layers**:
  - `lib/theme/`: Design tokens, colors, typography, and legacy adapter.
  - `lib/widgets/`: Reusable industrial widgets (Hardware trigger banner, RFID telemetry, radar sweep, gate banners, status badges).
  - `lib/screens/pda/`: Handheld screens organized into Eye-Level Zone (top metrics) and Thumb Zone (bottom >=48dp action bar).
  - `lib/screens/desktop/`: Workstation screens with unified reader header, KPI tiles, high-density data tables, and modal dialogs.
  - `lib/services/`: UHF hardware integration (`UhfService`, `DesktopUhfTcpService`), Supabase, and in-memory repository (Zero mock data).

## Code Layout
- `lib/theme/app_colors.dart`: Industrial Modern Tech color tokens & RFID status colors.
- `lib/theme/app_typography.dart`: Monospace font & `FontFeature.tabularFigures()` typography.
- `lib/theme/app_theme.dart`: ThemeData configurations for Dark Slate & Light Slate.
- `lib/theme/eye_care_theme.dart`: Backward-compatible adapter redirecting legacy calls to `AppColors`.
- `lib/widgets/hardware_trigger_feedback_banner.dart`: Live reactive widget bound to `UhfService.isTriggerPressed` and `onTriggerStateChanged`.
- `lib/widgets/rfid_telemetry_card.dart`, `gate_pass_fail_banner.dart`, `sonar_radar_widget.dart`, `tower_light_widget.dart`: Shared industrial widgets updated to Modern Tech tokens.
- `lib/screens/pda/`: PDA screens (Inbound, Goods Delivery, Inventory Audit, Putaway, Pallet Merge, Transfer, Lookup, FIFO Search, Radar Locate).
- `lib/screens/desktop/`: Desktop screens (Main Layout, Inbound, Outbound, Inventory, Warehouse Management, Location Management, UHF Studio, Reports, Users).
- `test/`: Automated test suite (unit, widget, E2E).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | Modern Tech Color Palette | Define Slate 950-50, Electric Cyan, Tech Blue, eliminates all paper sepia (`#F4EFE6`, `#E9E2D5`) | M1 | R1 |
| F2 | Standardized RFID Status Colors | 5 core RFID states: Emerald (Match), Cyan (Scanning), Amber (Mismatch/Warning), Coral (Error/Unknown), Indigo (Duplicate) | M1 | R1 |
| F3 | Monospace & Tabular Figures Typography | Font with `FontFeature.tabularFigures()` for EPC, barcode, counters, eliminating count jitter | M1 | R1 |
| F4 | Legacy Theme Compatibility Adapter | `eye_care_theme.dart` remapped to modern tokens to maintain zero breakage across 33+ callers | M1 | R1 |
| F5 | Shared Widgets Industrial Styling | Migrate `rfid_telemetry_card`, `gate_pass_fail_banner`, `sonar_radar_widget`, `tower_light_widget` to Modern Tech | M1 | R1 |
| F6 | Live Hardware Trigger Feedback | Reactive banner & dynamic radar animation bound to `UhfService.isTriggerPressed` & `onTriggerStateChanged` ("Đang giữ cò súng quét") | M2 | R2 |
| F7 | Pistol-Grip Three-Tier PDA Layout | Eye-Level Zone (top KPI), Scrollable Body (cards), Thumb Zone (bottom >=48dp action bar) | M2 | R2 |
| F8 | Touch Targets >= 48dp on PDA | Ensure all scan, stop, save, confirm, pallet change buttons meet or exceed 48x48dp | M2 | R2 |
| F9 | Narrow-Screen Overflow Fixes | Eliminate RenderFlex overflows on 320px-360px widths (Putaway barcode modal, delivery tables, telemetry tiles) | M2 | R2 |
| F10 | Arm's-Length Readability Enhancement | High-contrast EPC >=13pt bold monospace and SKU >=12.5pt readable at 50-70cm distance | M2 | R2 |
| F11 | Desktop Unified Reader Status Header | Add global RFID reader status bar (TCP connection, antenna status, power) to `DesktopMainLayout` | M3 | R3 |
| F12 | High-Density Workstation Data Tables | Modern Slate table layouts with elegant dividers, alternating row shading, and hover highlights | M3 | R3 |
| F13 | Desktop KPI Metric Cards & Dashboard | Sleek KPI tiles with accent borders, electric cyan highlights, and responsive spacing | M3 | R3 |
| F14 | Workstation Modals & Filter Ergonomics | Refined dialogs, search bars, and dropdown menus for rapid keyboard/mouse workflow | M3 | R3 |
| F15 | Zero Mock Data Enforcement | Audit and verify zero static data hardcoded or seeded in RAM/database (Rule 6) | M4 | R4 |
| F16 | Static Analysis 0 Warnings Cleanup | Resolve 10 current warnings/lints in `flutter analyze` to achieve 0 compile warnings/errors | M4 | R4 |
| F17 | Business Logic & Repository Preservation | 100% preservation of `WarehouseRepository`, `UhfService`, Supabase flows, and 286 existing tests | M4 | R4 |
| F18 | Dual-Track Automated E2E Test Suite | Automated test suite verifying theme tokens, PDA ergonomics, trigger feedback, and desktop layouts | M5 | Acceptance Criteria |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Theme & Token Architecture | `lib/theme/` (app_colors, app_typography, app_theme, eye_care_theme adapter) & core shared widgets | none | DONE |
| M2 | Ergonomic PDA Mobile Handheld | `lib/screens/pda/`, trigger banner, touch targets >=48dp, 3-tier layout, overflow fixes | M1 | DONE |
| M3 | Desktop Workstation Layout | `lib/screens/desktop/`, `DesktopMainLayout` reader header, high-density tables, KPI cards | M1 | DONE |
| M4 | Analyzer Cleanup & Logic Preservation | Fix 10 analyze warnings, verify zero mock data, verify 286/286 tests pass | M2, M3 | DONE |
| M5 | Automated E2E Verification & Hardening | Pass 100% of E2E test suite (Tiers 1-4) & adversarial test hardening (Tier 5) | M4 | DONE |

## Interface Contracts
### Theme ↔ Screens
- `AppColors.slate950` (`#020617`), `slate900` (`#0F172A`), `slate800` (`#1E293B`), `slate700` (`#334155`), `slate100` (`#F1F5F9`), `white` (`#FFFFFF`).
- `AppColors.electricCyan` (`#00E5FF`), `techBlue` (`#0284C7`).
- `AppColors.rfidMatched` (`#10B981`), `rfidScanning` (`#00E5FF`), `rfidMismatch` (`#F59E0B`), `rfidError` (`#EF4444`), `rfidDuplicate` (`#6366F1`).
- `AppTypography.epcMono({double fontSize, FontWeight fontWeight, Color color})`: Returns `TextStyle` with `fontFamily: 'monospace'`, `fontFeatures: [FontFeature.tabularFigures()]`.
- `EyeCareThemeService`: Exposes `.colors` mapped to `AppColors` for zero disruption to existing views.

### Hardware Trigger ↔ PDA Screens
- `UhfService.isTriggerPressed` (`bool`): Live trigger state.
- `UhfService.onTriggerStateChanged` (`Stream<bool>`): Emits on press and release.
- `HardwareTriggerFeedbackBanner`: Reusable widget listening to `UhfService.onTriggerStateChanged` that renders an animated pulsating "Đang giữ cò súng quét" banner and radar scan glow.
