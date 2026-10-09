# E2E Test Infra: UHF RFID Warehouse Management System

## Test Philosophy
- Opaque-box & Requirement-driven: Derived directly from `ORIGINAL_REQUEST.md` (R1, R2, R3, R4) and acceptance criteria.
- Complete coverage of Feature Inventory (F1 - F18).
- Zero dependency on internal widget private states.
- Methodology: Category-Partition + Boundary Value Analysis + Pairwise Combinations + Real-World Workload Scenarios.

## Feature Inventory Test Mapping
| # | Feature | Requirement | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---------|-------------|:------:|:------:|:------:|:------:|
| F1 | Modern Tech Color Palette | R1 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F2 | Standardized RFID Status Colors | R1 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F3 | Monospace & Tabular Figures | R1 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F4 | Legacy Theme Compatibility Adapter | R1 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F5 | Shared Widgets Industrial Styling | R1 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F6 | Live Hardware Trigger Feedback | R2 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F7 | Pistol-Grip Three-Tier PDA Layout | R2 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F8 | Touch Targets >= 48dp on PDA | R2 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F9 | Narrow-Screen Overflow Fixes (320px) | R2 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F10 | Arm's-Length Readability | R2 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F11 | Desktop Unified Reader Status Header | R3 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F12 | High-Density Workstation Data Tables | R3 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F13 | Desktop KPI Metric Cards & Dashboard | R3 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F14 | Workstation Modals & Filters | R3 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F15 | Zero Mock Data Enforcement | R4 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F16 | Static Analysis 0 Warnings | R4 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F17 | Business Logic Preservation | R4 | ✓ (5) | ✓ (5) | ✓ | ✓ |
| F18 | Regression of Existing 286 Tests | Acceptance | ✓ (5) | ✓ (5) | ✓ | ✓ |

## Test Architecture
- Test runner: `flutter test test/`
- Verification semantics: Exit code 0, all tests pass.
- Key Test Suites:
  - `test/theme/app_theme_tokens_test.dart`: Verifies tokens, contrast ratios >= 7.0:1 (AAA), elimination of `#F4EFE6` / `#E9E2D5`, 5 RFID status colors.
  - `test/pda/pda_ergonomics_test.dart`: Verifies touch targets >= 48dp, 3-tier layout, trigger feedback banner, and zero overflow on 320x600, 360x640, 480x800.
  - `test/desktop/desktop_workstation_test.dart`: Verifies unified reader status header in `DesktopMainLayout`, data grid layouts, and zero overflow on 1024x768 to 1920x1080.
  - `test/integrity/zero_mock_data_test.dart`: Verifies `DatabaseService` empty state in RAM and zero static hardcoded items.
  - Existing suite: All 286 tests in `test/` remain intact and passing.

## Coverage Thresholds
- Tier 1: Feature Coverage (>=5 per feature)
- Tier 2: Boundary & Corner Cases (>=5 per feature: 320px width, 0 tags scanned, 10,000 tags/s, rapid trigger toggle)
- Tier 3: Cross-Feature Interactions (e.g. trigger press during pallet putaway on 320px screen in Dark Slate mode)
- Tier 4: Real-World Workload Scenarios (Complete inbound PO scan, full inventory audit, radar tag search)
