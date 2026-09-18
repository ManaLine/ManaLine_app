# APP MAP — every screen, every route, who reaches it

<!-- GENERATED FILE. Do not edit by hand.
     Run: dart run tool/gen_app_map.dart
     Guarded by: test/app_map_sync_test.dart -->

Derived from both routers — `lib/app/router.dart` for the
handset, `lib/app/web_router.dart` for the restricted web build —
plus the screen files and `test/`,
by `tool/gen_app_map.dart`. It cannot go stale without failing
`flutter test`, which is the whole reason it is generated rather
than written.

**What this answers:** which file serves `/ow-005`, what arguments
it takes, what else in the app navigates to it, and whether
anything tests it.

**What it deliberately does not answer:** what a screen looks like
or where its buttons sit. That is in the screen file, which is 200
readable lines, and the placement rules that govern every screen
are in `docs/APP_FLOWS.md` §"Where things go".

## At a glance

| | |
|---|---|
| Routes declared | 86 |
| Routes that build a screen | 85 |
| Routes that only redirect | 1 |
| Distinct screen widgets | 76 |
| Literal navigation call sites | 407 |
| On the handset only | 51 |
| On the restricted web build | 35 |

## Login & Registration

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/lr-001` | `SystemStartupScreen` | `features/login_registration/screens/lr_001_system_startup.dart` | — | both | 7 via path | yes |
| `/lr-002` | `WorkspaceChoiceScreen` | `features/login_registration/screens/lr_002_workspace_choice.dart` | — | both | 4 via path | yes |
| `/lr-004` | `RegistrationFormScreen` | `features/login_registration/screens/lr_004_registration_form.dart` | — | both | 3 via path | yes |
| `/lr-005` | `OtpVerificationScreen` | `features/login_registration/screens/lr_005_otp_verification.dart` | extra: `OtpEntryArgs`, `OtpPurpose` | both | 6 via path | yes |
| `/lr-006` | `RegistrationResultScreen` | `features/login_registration/screens/lr_006_registration_result.dart` | — | both | 4 via path | yes |
| `/lr-007` | `DailyLoginScreen` | `features/login_registration/screens/lr_009_daily_login.dart` | extra: `LoginStepDownArgs` | both | 8 via path | yes |
| `/lr-008` | `CreatePinScreen` | `features/login_registration/screens/lr_008_create_pin.dart` | extra | both | 5 via path | yes |
| `/lr-009` | `DailyLoginScreen` | `features/login_registration/screens/lr_009_daily_login.dart` | — | both | 14 via path | yes |
| `/lr-010` | `ForgotPasswordScreen` | `features/login_registration/screens/lr_010_forgot_password.dart` | — | both | 5 via path | yes |
| `/lr-011` | `ForgotPinScreen` | `features/login_registration/screens/lr_011_forgot_pin.dart` | — | both | 5 via path | yes |
| `/lr-012` | `BusinessSelectorScreen` | `features/login_registration/screens/lr_012_business_selector.dart` | `?pick` | both | 17 via path | yes |
| `/lr-013` | `RoleSelectorScreen` | `features/login_registration/screens/lr_013_role_selector.dart` | — | both | 8 via path | yes |

## Owner

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/ow-000` | `FirstBusinessSetupScreen` | `features/owner_workspace/screens/ow_000_first_business_setup.dart` | extra | both | 8 via path | yes |
| `/ow-001` | `OwnerHomeDashboardScreen` | `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart` | — | handset | 32 via path | yes |
| `/ow-002` | `WorkforceManagementScreen` | `features/owner_workspace/screens/ow_002_workforce_management.dart` | `?agent` | handset | 8 via path | yes |
| `/ow-003` | `InvestorManagementScreen` | `features/owner_workspace/screens/ow_003_investor_management.dart` | `?open`<br>`?filter` | handset | 6 via path | yes |
| `/ow-004` | `CustomerManagementScreen` | `features/owner_workspace/screens/ow_004_customer_management.dart` | `?action` | handset | 7 via path | yes |
| `/ow-005` | `NewLoanWorkflowScreen` | `features/owner_workspace/screens/ow_005_new_loan_workflow.dart` | `?customerId`<br>`?requestId` | handset | 3 via path | yes |
| `/ow-006` | `CollectionModeScreen` | `features/owner_workspace/screens/ow_006_collection_mode.dart` | `?loan` | handset | 6 via path | yes |
| `/ow-007` | `LoanDetailsScreen` | `features/owner_workspace/screens/ow_007_loan_details.dart` | extra: `String` | handset | 3 via path<br>1 direct | yes |
| `/ow-009` | `DailyRecordBookScreen` | `features/owner_workspace/screens/ow_009_daily_record_book.dart` | — | handset | 1 via path | yes |
| `/ow-010` | `ReportHubScreen` | `features/owner_workspace/screens/ow_010_report_hub.dart` | — | handset | 3 via path | yes |
| `/ow-011` | `DayClosureScreen` | `features/owner_workspace/screens/ow_011_day_closure.dart` | — | handset | 2 via path | yes |
| `/ow-012` | `BusinessManagementScreen` | `features/owner_workspace/screens/ow_012_business_management.dart` | extra: `String`<br>`?tab` | handset | 4 via path | yes |
| `/ow-013` | `AccountReviewScreen` | `features/owner_workspace/screens/ow_013_account_review.dart` | — | both | 6 via path | yes |
| `/ow-014` | `GlobalWorkflowScreen` | `features/owner_workspace/screens/ow_014_global_workflow.dart` | `?type`<br>`?new` | handset | 2 via path | yes |
| `/ow-014-complete-profile` | `ProfileCompletionScreen` | `features/owner_workspace/screens/ow_014_profile_completion.dart` | `?personId`<br>`?membershipId` | handset | 1 via path | yes |
| `/ow-015` | `GroupLoanManagementScreen` | `features/owner_workspace/screens/ow_015_group_loan_management.dart` | — | handset | 3 via path | yes |
| `/ow-016` | `OwnerProfileScreen` | `features/owner_workspace/screens/ow_016_profile.dart` | — | both | 6 via path | yes |
| `/ow-017` | `TransactionHistoryScreen` | `features/owner_workspace/screens/ow_017_transaction_history.dart` | — | handset | 1 via path | yes |
| `/ow-017-statement` | `StatementScreen` | `features/owner_workspace/screens/ow_017_statement_screen.dart` | — | handset | 1 via path | yes |
| `/ow-018` | `BusinessMigrationScreen` | `features/owner_workspace/screens/ow_018_business_migration.dart` | — | both | 4 via path<br>1 direct | yes |
| `/ow-019` | `ChetiManagementScreen` | `features/owner_workspace/screens/ow_019_cheti_management.dart` | — | handset | 3 direct | yes |
| `/ow-bulk-onboarding` | `BulkOnboardingWizardScreen` | `features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart` | — | both | 3 via path | yes |
| `/ow-bulk-onboarding-menu` | `BulkOnboardingMenuScreen` | `features/owner_workspace/screens/ow_bulk_onboarding_menu.dart` | — | both | 5 via path | yes |
| `/ow-bulk-onboarding-web` | `BulkOnboardingOnWebScreen` | `features/owner_workspace/screens/ow_bulk_onboarding_on_web.dart` | — | handset | 1 via path | yes |
| `/ow-loan-requests` | `LoanRequestsScreen` | `features/owner_workspace/screens/loan_requests_screen.dart` | — | handset | 2 via path | yes |
| `/ow-search` | `UniversalSearchScreen` | `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart` | `?role` | both | 11 via path | yes |
| `/ow-settings` | `SettingsScreen` | `shared/settings_screen.dart` | extra: `String` | both | 4 via path | yes |
| `/ow-trash` | `OwnerTrashScreen` | `features/owner_workspace/screens/ow_trash_screen.dart` | — | handset | 1 via path | yes |
| `/ow-withdrawal-requests` | `WithdrawalRequestsScreen` | `features/owner_workspace/screens/withdrawal_requests_screen.dart` | — | handset | 1 via path | yes |

## Agent

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/ag-001` | `AgentHomeDashboardScreen` | `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart` | `?anchor` | handset | 16 via path | yes |
| `/ag-002` | `AgentCollectionModeScreen` | `features/agent_workspace/screens/ag_002_collection_mode.dart` | `?loan` | handset | 5 via path | yes |
| `/ag-003` | `AgentCollectionModeScreen` | `features/agent_workspace/screens/ag_002_collection_mode.dart` | `?loan` | handset | **nothing** | yes |
| `/ag-004` | `AgentCustomerManagementScreen` | `features/agent_workspace/screens/ag_004_customer_management.dart` | — | handset | 9 via path | yes |
| `/ag-005` | `DraftTransactionsScreen` | `features/agent_workspace/screens/ag_005_draft_transactions.dart` | — | handset | 3 via path<br>1 direct | yes |
| `/ag-006` | `OwnerSettlementScreen` | `features/agent_workspace/screens/ag_006_owner_settlement.dart` | — | handset | 2 direct | yes |
| `/ag-007` | `Ag007LoanDistributionScreen` | `features/agent_workspace/screens/ag_007_loan_distribution.dart` | `?customerId` | handset | 3 direct | yes |
| `/ag-008` | `Ag008NotificationsScreen` | `features/agent_workspace/screens/ag_008_notifications.dart` | — | handset | 1 direct | yes |
| `/ag-009` | `Ag009ProfileScreen` | `features/agent_workspace/screens/ag_009_profile.dart` | — | both | 6 via path | yes |
| `/ag-010` | `Ag010TransactionHistoryScreen` | `features/agent_workspace/screens/ag_010_transaction_history.dart` | — | handset | 2 via path | yes |
| `/ag-settings` | `SettingsScreen` | `shared/settings_screen.dart` | extra: `String` | both | 3 via path | yes |

## Customer

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/cw-001` | `CustomerHomeDashboardScreen` | `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart` | — | handset | 16 via path | yes |
| `/cw-002` | `FindABusinessScreen` | `features/customer_workspace/screens/cw_002_find_a_business.dart`<br>`features/investor_workspace/screens/iw_002_find_a_business.dart` | — | handset | 3 via path | yes |
| `/cw-003` | `RequestNewLoanScreen` | `features/customer_workspace/screens/cw_003_request_new_loan.dart` | — | handset | 3 via path | yes |
| `/cw-004` | `MyLoansScreen` | `features/customer_workspace/screens/cw_004_my_loans.dart` | — | both | 12 via path | yes |
| `/cw-005` | `MakeAPaymentScreen` | `features/customer_workspace/screens/cw_005_make_a_payment.dart` | extra: `String` | handset | 2 via path | yes |
| `/cw-006` | `MyProfileMembershipsScreen` | `features/customer_workspace/screens/cw_006_my_profile_memberships.dart`<br>`features/investor_workspace/screens/iw_005_my_profile_memberships.dart` | extra: `String` | both | 8 via path | yes |
| `/cw-settings` | `SettingsScreen` | `shared/settings_screen.dart` | extra: `String` | both | 3 via path | yes |

## Investor

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/iw-001` | `InvestorHomeDashboardScreen` | `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart` | — | handset | 12 via path | yes |
| `/iw-002` | `FindABusinessScreen` | `features/customer_workspace/screens/cw_002_find_a_business.dart`<br>`features/investor_workspace/screens/iw_002_find_a_business.dart` | — | handset | 3 via path | yes |
| `/iw-003` | `MyInvestmentsScreen` | `features/investor_workspace/screens/iw_003_my_investments.dart` | — | both | 8 via path | yes |
| `/iw-004` | `RequestWithdrawalScreen` | `features/investor_workspace/screens/iw_004_request_withdrawal.dart` | extra: `String` | handset | 2 via path | yes |
| `/iw-005` | `MyProfileMembershipsScreen` | `features/customer_workspace/screens/cw_006_my_profile_memberships.dart`<br>`features/investor_workspace/screens/iw_005_my_profile_memberships.dart` | — | both | 8 via path | yes |
| `/iw-settings` | `SettingsScreen` | `shared/settings_screen.dart` | extra: `String` | both | 3 via path | yes |

## Support Admin

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/sp-001` | `Sp001AadhaarDisputeResolutionScreen` | `features/support_admin/screens/sp_001_aadhaar_dispute_resolution.dart` | — | handset | **nothing** | yes |

## Platform Admin

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/admin-forgot-password` | `AdminForgotPasswordScreen` | `features/admin/screens/admin_forgot_password_screen.dart` | — | handset | 1 via path | yes |
| `/admin-login` | `AdminLoginScreen` | `features/admin/screens/admin_login_screen.dart` | — | handset | 3 via path | yes |
| `/admin-panel` | `AdminPanelScreen` | `features/admin/admin_panel_screen.dart` | — | handset | 1 via path | **no** |

## Shared / Utility

| Route | Screen | File | Takes | On | Reached from | Test |
|---|---|---|---|---|---|---|
| `/` | _redirects to `/lr-001`_ | — | — | handset | **nothing** | — |
| `/_design` | `DesignShowcaseScreen` | `app/design_showcase_screen.dart` | — | handset | **nothing** | **no** |
| `/about` | `AboutScreen` | `shared/about_screen.dart` | — | both | 3 via path | yes |
| `/account-closure` | `AccountClosureScreen` | `shared/account_closure_screen.dart` | — | handset | 1 via path | yes |
| `/appearance` | `AppearanceScreen` | `shared/appearance_screen.dart` | — | both | 3 via path | yes |
| `/backup` | `BackupScreen` | `features/owner_workspace/screens/backup_screen.dart` | — | handset | 1 via path | yes |
| `/business-suspended` | `BusinessSuspendedScreen` | `shared/business_suspension_gate.dart` | `?reason` | handset | 1 via path | **no** |
| `/business-transfer` | `BusinessTransferScreen` | `features/owner_workspace/screens/business_transfer_screen.dart` | — | handset | 1 via path | yes |
| `/customer-new` | `ManaAddCustomerScreen` | `features/owner_workspace/screens/ow_004_customer_management.dart` | `?migration` | handset | 3 via path | **no** |
| `/import` | `ImportScreen` | `features/owner_workspace/screens/import_screen.dart` | — | both | 3 via path | yes |
| `/notifications` | `NotificationsScreen` | `shared/notifications_screen.dart` | — | handset | 3 via path | yes |
| `/outbox` | `ManaOutboxScreen` | `shared/outbox/ow_outbox_screen.dart` | — | handset | 1 via path | **no** |
| `/profile` | `MyProfileMembershipsScreen` | `features/customer_workspace/screens/cw_006_my_profile_memberships.dart`<br>`features/investor_workspace/screens/iw_005_my_profile_memberships.dart` | extra: `String` | both | 3 via path | yes |
| `/recent-deletes` | `RecentDeletesScreen` | `shared/widgets/recent_deletes_screen.dart` | — | handset | **nothing** | **no** |
| `/settings` | `SettingsScreen` | `shared/settings_screen.dart` | — | both | 11 via path | yes |
| `/subscription` | `SubscriptionScreen` | `features/owner_workspace/screens/subscription_screen.dart` | — | both | 4 via path | yes |
| `/web-home` | `ManaWebHomeScreen` | `features/web/screens/web_home_screen.dart` | — | web | 16 via path | yes |

## Who navigates where

Every place in `lib/` that names a route path, by destination.
`go` / `push` / `replace` is a navigation call. `listed` is the
path sitting in a menu or tile table, reached through a variable —
the owner dashboard builds its whole menu that way, so those
screens have no literal nav call anywhere.

A path assembled at runtime appears in neither. Nothing here
proves a screen unreachable — only that nobody wrote its path.

**`/about`** — 3 call sites

- `app/web_router.dart:120` (`listed`)
- `app/web_router.dart:354` (`listed`)
- `shared/settings_screen.dart:606` (`push`)

**`/account-closure`** — 1 call site

- `shared/settings_screen.dart:532` (`push`)

**`/admin-forgot-password`** — 1 call site

- `features/admin/screens/admin_login_screen.dart:135` (`push`)

**`/admin-login`** — 3 call sites

- `features/admin/screens/admin_forgot_password_screen.dart:109` (`go`)
- `features/admin/screens/admin_forgot_password_screen.dart:128` (`listed`)
- `features/login_registration/screens/lr_002_workspace_choice.dart:54` (`push`)

**`/admin-panel`** — 1 call site

- `features/admin/screens/admin_login_screen.dart:56` (`go`)

**`/ag-001`** — 16 call sites

- `app/web_router.dart:155` (`listed`)
- `app/web_router.dart:364` (`listed`)
- `features/agent_workspace/screens/ag_002_collection_mode.dart:40` (`go`)
- `features/agent_workspace/screens/ag_004_customer_management.dart:111` (`listed`)
- `features/agent_workspace/screens/ag_006_owner_settlement.dart:67` (`listed`)
- `features/agent_workspace/screens/ag_007_loan_distribution.dart:1062` (`go`)
- `features/agent_workspace/screens/ag_008_notifications.dart:139` (`listed`)
- `features/agent_workspace/screens/ag_009_profile.dart:262` (`push`)
- `features/agent_workspace/screens/ag_010_transaction_history.dart:30` (`listed`)
- `features/customer_workspace/screens/cw_006_my_profile_memberships.dart:325` (`go`)
- `features/investor_workspace/screens/iw_005_my_profile_memberships.dart:297` (`go`)
- `features/login_registration/screens/lr_013_role_selector.dart:24` (`listed`)
- `shared/mana_back_handler.dart:49` (`listed`)
- `shared/settings_screen.dart:84` (`listed`)
- `shared/settings_screen.dart:126` (`listed`)
- `shared/widgets/workspace_nav.dart:52` (`listed`)

**`/ag-002`** — 5 call sites

- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:175` (`push`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:1014` (`push`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:1019` (`push`)
- `features/agent_workspace/screens/ag_005_draft_transactions.dart:191` (`push`)
- `shared/widgets/workspace_nav.dart:52` (`listed`)

**`/ag-004`** — 9 call sites

- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:153` (`push`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:163` (`push`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:1022` (`push`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:1080` (`push`)
- `features/agent_workspace/screens/ag_004_customer_management.dart:296` (`listed`)
- `features/agent_workspace/screens/ag_005_draft_transactions.dart:202` (`push`)
- `features/agent_workspace/screens/ag_008_notifications.dart:101` (`push`)
- `shared/widgets/workspace_actions.dart:204` (`listed`)
- `shared/widgets/workspace_nav.dart:52` (`listed`)

**`/ag-005`** — 3 call sites

- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:185` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:251` (`push`)
- `features/owner_workspace/state/day_closure_state.dart:77` (`listed`)

**`/ag-009`** — 6 call sites

- `app/web_router.dart:108` (`listed`)
- `app/web_router.dart:312` (`listed`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:220` (`push`)
- `features/login_registration/state/auth_flow_state.dart:150` (`listed`)
- `features/web/state/web_destinations.dart:100` (`listed`)
- `shared/settings_screen.dart:84` (`listed`)

**`/ag-010`** — 2 call sites

- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:189` (`push`)
- `shared/widgets/workspace_nav.dart:52` (`listed`)

**`/ag-settings`** — 3 call sites

- `app/web_router.dart:116` (`listed`)
- `app/web_router.dart:362` (`listed`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:224` (`push`)

**`/appearance`** — 3 call sites

- `app/web_router.dart:119` (`listed`)
- `app/web_router.dart:355` (`listed`)
- `shared/settings_screen.dart:574` (`push`)

**`/backup`** — 1 call site

- `shared/settings_screen.dart:457` (`push`)

**`/business-suspended`** — 1 call site

- `shared/business_suspension_gate.dart:90` (`listed`)

**`/business-transfer`** — 1 call site

- `shared/settings_screen.dart:551` (`push`)

**`/customer-new`** — 3 call sites

- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:93` (`listed`)
- `shared/widgets/workspace_actions.dart:128` (`listed`)
- `shared/widgets/workspace_actions.dart:166` (`listed`)

**`/cw-001`** — 16 call sites

- `app/web_router.dart:156` (`listed`)
- `app/web_router.dart:368` (`listed`)
- `features/customer_workspace/screens/cw_002_find_a_business.dart:43` (`listed`)
- `features/customer_workspace/screens/cw_002_find_a_business.dart:274` (`go`)
- `features/customer_workspace/screens/cw_002_find_a_business.dart:298` (`go`)
- `features/customer_workspace/screens/cw_003_request_new_loan.dart:93` (`listed`)
- `features/customer_workspace/screens/cw_003_request_new_loan.dart:145` (`go`)
- `features/customer_workspace/screens/cw_003_request_new_loan.dart:190` (`go`)
- `features/customer_workspace/screens/cw_003_request_new_loan.dart:454` (`go`)
- `features/customer_workspace/screens/cw_003_request_new_loan.dart:500` (`go`)
- `features/customer_workspace/screens/cw_004_my_loans.dart:50` (`listed`)
- `features/customer_workspace/screens/cw_006_my_profile_memberships.dart:43` (`listed`)
- `features/investor_workspace/screens/iw_005_my_profile_memberships.dart:306` (`go`)
- `features/login_registration/screens/lr_013_role_selector.dart:25` (`listed`)
- `shared/mana_back_handler.dart:50` (`listed`)
- `shared/settings_screen.dart:85` (`listed`)

**`/cw-002`** — 3 call sites

- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:98` (`push`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:334` (`listed`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:403` (`push`)

**`/cw-003`** — 3 call sites

- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:80` (`push`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:335` (`listed`)
- `features/customer_workspace/screens/cw_004_my_loans.dart:189` (`push`)

**`/cw-004`** — 12 call sites

- `app/web_router.dart:109` (`listed`)
- `app/web_router.dart:321` (`listed`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:76` (`push`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:339` (`listed`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:342` (`listed`)
- `features/customer_workspace/screens/cw_003_request_new_loan.dart:474` (`go`)
- `features/customer_workspace/screens/cw_005_make_a_payment.dart:56` (`go`)
- `features/customer_workspace/screens/cw_005_make_a_payment.dart:290` (`go`)
- `features/customer_workspace/screens/cw_005_make_a_payment.dart:334` (`go`)
- `features/customer_workspace/screens/cw_005_make_a_payment.dart:380` (`go`)
- `features/customer_workspace/screens/cw_006_my_profile_memberships.dart:342` (`go`)
- `features/web/state/web_destinations.dart:106` (`listed`)

**`/cw-005`** — 2 call sites

- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:84` (`push`)
- `features/customer_workspace/screens/cw_004_my_loans.dart:541` (`push`)

**`/cw-006`** — 8 call sites

- `app/web_router.dart:110` (`listed`)
- `app/web_router.dart:328` (`listed`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:94` (`push`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:106` (`push`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:349` (`listed`)
- `features/login_registration/state/auth_flow_state.dart:151` (`listed`)
- `features/web/state/web_destinations.dart:107` (`listed`)
- `shared/settings_screen.dart:85` (`listed`)

**`/cw-settings`** — 3 call sites

- `app/web_router.dart:117` (`listed`)
- `app/web_router.dart:366` (`listed`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:110` (`push`)

**`/import`** — 3 call sites

- `app/web_router.dart:106` (`listed`)
- `app/web_router.dart:303` (`listed`)
- `shared/settings_screen.dart:473` (`push`)

**`/iw-001`** — 12 call sites

- `app/web_router.dart:157` (`listed`)
- `app/web_router.dart:372` (`listed`)
- `features/customer_workspace/screens/cw_006_my_profile_memberships.dart:328` (`go`)
- `features/investor_workspace/screens/iw_002_find_a_business.dart:43` (`listed`)
- `features/investor_workspace/screens/iw_002_find_a_business.dart:284` (`go`)
- `features/investor_workspace/screens/iw_002_find_a_business.dart:309` (`go`)
- `features/investor_workspace/screens/iw_003_my_investments.dart:67` (`listed`)
- `features/investor_workspace/screens/iw_004_request_withdrawal.dart:61` (`listed`)
- `features/investor_workspace/screens/iw_005_my_profile_memberships.dart:42` (`listed`)
- `features/login_registration/screens/lr_013_role_selector.dart:23` (`listed`)
- `shared/mana_back_handler.dart:51` (`listed`)
- `shared/settings_screen.dart:86` (`listed`)

**`/iw-002`** — 3 call sites

- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:88` (`push`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:344` (`listed`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:407` (`push`)

**`/iw-003`** — 8 call sites

- `app/web_router.dart:111` (`listed`)
- `app/web_router.dart:342` (`listed`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:70` (`push`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:345` (`listed`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:355` (`listed`)
- `features/investor_workspace/screens/iw_004_request_withdrawal.dart:189` (`go`)
- `features/investor_workspace/screens/iw_005_my_profile_memberships.dart:303` (`go`)
- `features/web/state/web_destinations.dart:116` (`listed`)

**`/iw-004`** — 2 call sites

- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:74` (`push`)
- `features/investor_workspace/screens/iw_003_my_investments.dart:315` (`push`)

**`/iw-005`** — 8 call sites

- `app/web_router.dart:112` (`listed`)
- `app/web_router.dart:349` (`listed`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:84` (`push`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:104` (`push`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:358` (`listed`)
- `features/login_registration/state/auth_flow_state.dart:152` (`listed`)
- `features/web/state/web_destinations.dart:117` (`listed`)
- `shared/settings_screen.dart:86` (`listed`)

**`/iw-settings`** — 3 call sites

- `app/web_router.dart:118` (`listed`)
- `app/web_router.dart:370` (`listed`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:108` (`push`)

**`/lr-001`** — 7 call sites

- `app/web_router.dart:79` (`listed`)
- `app/web_router.dart:168` (`listed`)
- `app/web_router.dart:187` (`listed`)
- `features/login_registration/screens/lr_008_create_pin.dart:89` (`go`)
- `features/login_registration/screens/lr_009_daily_login.dart:306` (`go`)
- `features/web/widgets/mana_auth_shell.dart:64` (`listed`)
- `shared/mana_back_handler.dart:61` (`listed`)

**`/lr-002`** — 4 call sites

- `app/web_router.dart:80` (`listed`)
- `app/web_router.dart:188` (`listed`)
- `features/login_registration/screens/lr_001_system_startup.dart:117` (`listed`)
- `features/web/widgets/mana_auth_shell.dart:49` (`listed`)

**`/lr-004`** — 3 call sites

- `app/web_router.dart:81` (`listed`)
- `app/web_router.dart:189` (`listed`)
- `features/login_registration/screens/lr_007_first_login.dart:541` (`push`)

**`/lr-005`** — 6 call sites

- `app/web_router.dart:82` (`listed`)
- `app/web_router.dart:191` (`listed`)
- `features/login_registration/screens/lr_004_registration_form.dart:355` (`push`)
- `features/login_registration/screens/lr_007_first_login.dart:203` (`push`)
- `features/login_registration/screens/lr_009_daily_login.dart:374` (`push`)
- `features/login_registration/screens/lr_013_role_selector.dart:215` (`listed`)

**`/lr-006`** — 4 call sites

- `app/web_router.dart:83` (`listed`)
- `app/web_router.dart:202` (`listed`)
- `features/login_registration/screens/lr_005_otp_verification.dart:131` (`go`)
- `features/web/widgets/mana_auth_shell.dart:49` (`listed`)

**`/lr-007`** — 8 call sites

- `app/web_router.dart:84` (`listed`)
- `app/web_router.dart:204` (`listed`)
- `features/login_registration/screens/lr_005_otp_verification.dart:140` (`go`)
- `features/login_registration/screens/lr_006_registration_result.dart:40` (`go`)
- `features/login_registration/screens/lr_009_daily_login.dart:692` (`listed`)
- `features/login_registration/screens/lr_009_daily_login.dart:718` (`go`)
- `features/login_registration/screens/lr_010_forgot_password.dart:195` (`listed`)
- `features/login_registration/screens/lr_010_forgot_password.dart:206` (`listed`)

**`/lr-008`** — 5 call sites

- `app/web_router.dart:85` (`listed`)
- `app/web_router.dart:216` (`listed`)
- `features/login_registration/screens/lr_007_first_login.dart:329` (`go`)
- `features/login_registration/screens/lr_007_first_login.dart:334` (`go`)
- `features/login_registration/screens/lr_009_daily_login.dart:404` (`go`)

**`/lr-009`** — 14 call sites

- `app/web_router.dart:86` (`listed`)
- `app/web_router.dart:217` (`listed`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:227` (`go`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:113` (`go`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:111` (`go`)
- `features/login_registration/screens/lr_001_system_startup.dart:117` (`listed`)
- `features/login_registration/screens/lr_002_workspace_choice.dart:95` (`push`)
- `features/login_registration/screens/lr_012_business_selector.dart:396` (`go`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:295` (`go`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:396` (`go`)
- `features/owner_workspace/screens/ow_016_profile.dart:289` (`go`)
- `main.dart:144` (`go`)
- `shared/account_closure_screen.dart:87` (`go`)
- `shared/settings_screen.dart:615` (`go`)

**`/lr-010`** — 5 call sites

- `app/web_router.dart:87` (`listed`)
- `app/web_router.dart:218` (`listed`)
- `features/login_registration/screens/lr_005_otp_verification.dart:134` (`go`)
- `features/login_registration/screens/lr_007_first_login.dart:494` (`push`)
- `shared/settings_screen.dart:480` (`push`)

**`/lr-011`** — 5 call sites

- `app/web_router.dart:88` (`listed`)
- `app/web_router.dart:219` (`listed`)
- `features/login_registration/screens/lr_005_otp_verification.dart:137` (`go`)
- `features/login_registration/screens/lr_009_daily_login.dart:694` (`listed`)
- `shared/settings_screen.dart:485` (`push`)

**`/lr-012`** — 17 call sites

- `app/web_router.dart:89` (`listed`)
- `app/web_router.dart:221` (`listed`)
- `app/web_router.dart:337` (`listed`)
- `app/web_router.dart:356` (`listed`)
- `features/admin/admin_panel_screen.dart:27` (`listed`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:244` (`push`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:222` (`go`)
- `features/login_registration/screens/lr_007_first_login.dart:331` (`go`)
- `features/login_registration/screens/lr_008_create_pin.dart:133` (`go`)
- `features/login_registration/screens/lr_009_daily_login.dart:406` (`go`)
- `features/login_registration/screens/lr_011_forgot_pin.dart:253` (`go`)
- `features/login_registration/screens/lr_013_role_selector.dart:92` (`go`)
- `features/login_registration/screens/lr_013_role_selector.dart:139` (`go`)
- `features/login_registration/screens/lr_013_role_selector.dart:270` (`listed`)
- `features/login_registration/screens/lr_013_role_selector.dart:284` (`listed`)
- `features/web/widgets/mana_auth_shell.dart:49` (`listed`)
- `shared/business_suspension_gate.dart:196` (`go`)

**`/lr-013`** — 8 call sites

- `app/web_router.dart:90` (`listed`)
- `app/web_router.dart:230` (`listed`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:222` (`go`)
- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:108` (`go`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:106` (`go`)
- `features/login_registration/screens/lr_012_business_selector.dart:222` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:290` (`go`)
- `features/web/widgets/mana_auth_shell.dart:49` (`listed`)

**`/notifications`** — 3 call sites

- `features/customer_workspace/screens/cw_001_customer_home_dashboard.dart:237` (`push`)
- `features/login_registration/screens/lr_012_business_selector.dart:509` (`push`)
- `shared/notification_bell.dart:52` (`push`)

**`/outbox`** — 1 call site

- `shared/outbox/mana_outbox_banner.dart:72` (`push`)

**`/ow-000`** — 8 call sites

- `app/web_router.dart:95` (`listed`)
- `app/web_router.dart:281` (`listed`)
- `features/agent_workspace/screens/ag_001_agent_home_dashboard.dart:212` (`push`)
- `features/customer_workspace/screens/cw_002_find_a_business.dart:101` (`push`)
- `features/investor_workspace/screens/iw_001_investor_home_dashboard.dart:96` (`push`)
- `features/investor_workspace/screens/iw_002_find_a_business.dart:101` (`push`)
- `features/login_registration/screens/lr_012_business_selector.dart:265` (`push`)
- `features/login_registration/screens/lr_012_business_selector.dart:450` (`push`)

**`/ow-001`** — 32 call sites

- `app/web_router.dart:154` (`listed`)
- `app/web_router.dart:360` (`listed`)
- `features/customer_workspace/screens/cw_006_my_profile_memberships.dart:322` (`go`)
- `features/investor_workspace/screens/iw_005_my_profile_memberships.dart:294` (`go`)
- `features/login_registration/screens/lr_013_role_selector.dart:22` (`listed`)
- `features/owner_workspace/screens/ow_000_first_business_setup.dart:835` (`go`)
- `features/owner_workspace/screens/ow_004_customer_management.dart:179` (`listed`)
- `features/owner_workspace/screens/ow_005_new_loan_workflow.dart:85` (`listed`)
- `features/owner_workspace/screens/ow_005_new_loan_workflow.dart:815` (`go`)
- `features/owner_workspace/screens/ow_006_collection_mode.dart:54` (`go`)
- `features/owner_workspace/screens/ow_009_daily_record_book.dart:117` (`listed`)
- `features/owner_workspace/screens/ow_010_report_hub.dart:64` (`listed`)
- `features/owner_workspace/screens/ow_011_day_closure.dart:71` (`listed`)
- `features/owner_workspace/screens/ow_013_account_review.dart:46` (`listed`)
- `features/owner_workspace/screens/ow_015_group_loan_management.dart:46` (`listed`)
- `features/owner_workspace/screens/ow_016_profile.dart:210` (`listed`)
- `features/owner_workspace/screens/ow_016_profile.dart:281` (`push`)
- `features/owner_workspace/screens/ow_017_statement_screen.dart:112` (`listed`)
- `features/owner_workspace/screens/ow_017_transaction_history.dart:23` (`listed`)
- `features/owner_workspace/screens/ow_bulk_onboarding_on_web.dart:76` (`listed`)
- `features/owner_workspace/screens/ow_bulk_onboarding_wizard.dart:948` (`listed`)
- `features/owner_workspace/screens/ow_line_pending_list.dart:74` (`listed`)
- `shared/mana_back_handler.dart:48` (`listed`)
- `shared/mlti_upgrade_sheet.dart:307` (`listed`)
- `shared/payment_details_editor.dart:133` (`listed`)
- `shared/settings_screen.dart:83` (`listed`)
- `shared/settings_screen.dart:92` (`listed`)
- `shared/settings_screen.dart:126` (`listed`)
- `shared/settings_screen.dart:401` (`listed`)
- `shared/settings_screen.dart:420` (`listed`)
- `shared/settings_screen.dart:438` (`listed`)
- `shared/widgets/workspace_nav.dart:51` (`listed`)

**`/ow-002`** — 8 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:79` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1214` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1785` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:2015` (`listed`)
- `features/owner_workspace/screens/ow_002_workforce_management.dart:249` (`listed`)
- `features/owner_workspace/screens/ow_002_workforce_management.dart:457` (`listed`)
- `shared/settings_screen.dart:407` (`push`)
- `shared/widgets/workspace_actions.dart:48` (`listed`)

**`/ow-003`** — 6 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:93` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1215` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1810` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1813` (`listed`)
- `features/owner_workspace/screens/ow_003_investor_management.dart:229` (`listed`)
- `shared/widgets/workspace_actions.dart:49` (`listed`)

**`/ow-004`** — 7 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:61` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1216` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1775` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:2008` (`listed`)
- `features/owner_workspace/screens/ow_004_customer_management.dart:1498` (`listed`)
- `features/owner_workspace/screens/ow_004_customer_management.dart:1933` (`listed`)
- `shared/widgets/workspace_nav.dart:51` (`listed`)

**`/ow-005`** — 3 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:65` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1771` (`listed`)
- `features/owner_workspace/screens/ow_011_day_closure.dart:153` (`listed`)

**`/ow-006`** — 6 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1772` (`listed`)
- `features/owner_workspace/screens/ow_004_customer_management.dart:1568` (`push`)
- `features/owner_workspace/screens/ow_011_day_closure.dart:151` (`listed`)
- `features/owner_workspace/screens/ow_011_day_closure.dart:159` (`listed`)
- `features/owner_workspace/state/day_closure_state.dart:275` (`listed`)
- `shared/widgets/workspace_nav.dart:51` (`listed`)

**`/ow-007`** — 3 call sites

- `features/owner_workspace/screens/ow_004_customer_management.dart:1724` (`push`)
- `features/owner_workspace/screens/ow_009_daily_record_book.dart:732` (`listed`)
- `features/owner_workspace/screens/ow_015_group_loan_management.dart:347` (`push`)

**`/ow-009`** — 1 call site

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1787` (`listed`)

**`/ow-010`** — 3 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:139` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1788` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:2017` (`listed`)

**`/ow-011`** — 2 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1786` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:2010` (`listed`)

**`/ow-012`** — 4 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:134` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:218` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1816` (`listed`)
- `features/owner_workspace/screens/ow_012_business_management.dart:553` (`listed`)

**`/ow-013`** — 6 call sites

- `app/web_router.dart:101` (`listed`)
- `app/web_router.dart:260` (`listed`)
- `design/tokens/breakpoints.dart:86` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:83` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1791` (`listed`)
- `features/web/state/web_destinations.dart:127` (`listed`)

**`/ow-014`** — 2 call sites

- `features/owner_workspace/screens/ow_011_day_closure.dart:155` (`listed`)
- `features/owner_workspace/screens/ow_011_day_closure.dart:157` (`listed`)

**`/ow-014-complete-profile`** — 1 call site

- `features/owner_workspace/screens/ow_014_global_workflow.dart:597` (`listed`)

**`/ow-015`** — 3 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:69` (`push`)
- `features/owner_workspace/screens/ow_005_new_loan_workflow.dart:111` (`push`)
- `features/owner_workspace/screens/ow_015_group_loan_management.dart:259` (`listed`)

**`/ow-016`** — 6 call sites

- `app/web_router.dart:102` (`listed`)
- `app/web_router.dart:285` (`listed`)
- `features/login_registration/state/auth_flow_state.dart:153` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:288` (`push`)
- `features/web/state/web_destinations.dart:146` (`listed`)
- `shared/settings_screen.dart:83` (`listed`)

**`/ow-017`** — 1 call site

- `shared/widgets/workspace_nav.dart:51` (`listed`)

**`/ow-017-statement`** — 1 call site

- `features/owner_workspace/screens/ow_017_transaction_history.dart:24` (`listed`)

**`/ow-018`** — 4 call sites

- `app/web_router.dart:103` (`listed`)
- `app/web_router.dart:287` (`listed`)
- `features/owner_workspace/screens/ow_000_first_business_setup.dart:638` (`push`)
- `features/web/state/web_destinations.dart:131` (`listed`)

**`/ow-bulk-onboarding`** — 3 call sites

- `app/web_router.dart:104` (`listed`)
- `app/web_router.dart:299` (`listed`)
- `features/owner_workspace/screens/ow_bulk_onboarding_menu.dart:140` (`push`)

**`/ow-bulk-onboarding-menu`** — 5 call sites

- `app/web_router.dart:105` (`listed`)
- `app/web_router.dart:295` (`listed`)
- `design/tokens/breakpoints.dart:88` (`listed`)
- `features/owner_workspace/screens/ow_018_business_migration.dart:137` (`listed`)
- `features/web/state/web_destinations.dart:141` (`listed`)

**`/ow-bulk-onboarding-web`** — 1 call site

- `features/owner_workspace/screens/ow_018_business_migration.dart:137` (`listed`)

**`/ow-loan-requests`** — 2 call sites

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1776` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:2009` (`listed`)

**`/ow-search`** — 11 call sites

- `app/web_router.dart:100` (`listed`)
- `app/web_router.dart:269` (`listed`)
- `features/owner_workspace/screens/ow_000_first_business_setup.dart:795` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:282` (`push`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1804` (`listed`)
- `features/owner_workspace/screens/ow_002_workforce_management.dart:163` (`push`)
- `features/owner_workspace/screens/ow_003_investor_management.dart:148` (`push`)
- `features/owner_workspace/screens/ow_012_business_management.dart:568` (`push`)
- `features/owner_workspace/screens/ow_012_business_management.dart:1418` (`push`)
- `features/owner_workspace/screens/ow_018_business_migration.dart:316` (`push`)
- `shared/widgets/workspace_actions.dart:203` (`listed`)

**`/ow-settings`** — 4 call sites

- `app/web_router.dart:115` (`listed`)
- `app/web_router.dart:358` (`listed`)
- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:292` (`push`)
- `features/owner_workspace/screens/ow_trash_screen.dart:148` (`listed`)

**`/ow-trash`** — 1 call site

- `shared/settings_screen.dart:443` (`push`)

**`/ow-withdrawal-requests`** — 1 call site

- `features/owner_workspace/screens/ow_001_owner_home_dashboard.dart:1823` (`listed`)

**`/profile`** — 3 call sites

- `app/web_router.dart:113` (`listed`)
- `app/web_router.dart:334` (`listed`)
- `features/login_registration/state/auth_flow_state.dart:160` (`listed`)

**`/settings`** — 11 call sites

- `app/web_router.dart:114` (`listed`)
- `app/web_router.dart:356` (`listed`)
- `features/login_registration/screens/lr_012_business_selector.dart:391` (`push`)
- `features/owner_workspace/screens/backup_screen.dart:74` (`listed`)
- `features/owner_workspace/screens/business_transfer_screen.dart:169` (`listed`)
- `features/owner_workspace/screens/import_screen.dart:115` (`listed`)
- `features/owner_workspace/screens/subscription_screen.dart:29` (`listed`)
- `features/web/state/web_destinations.dart:92` (`listed`)
- `shared/about_screen.dart:43` (`listed`)
- `shared/account_closure_screen.dart:94` (`listed`)
- `shared/appearance_screen.dart:31` (`listed`)

**`/subscription`** — 4 call sites

- `app/web_router.dart:107` (`listed`)
- `app/web_router.dart:307` (`listed`)
- `features/web/state/web_destinations.dart:145` (`listed`)
- `shared/settings_screen.dart:426` (`push`)

**`/web-home`** — 16 call sites

- `app/web_router.dart:91` (`listed`)
- `app/web_router.dart:128` (`listed`)
- `app/web_router.dart:129` (`listed`)
- `app/web_router.dart:130` (`listed`)
- `app/web_router.dart:131` (`listed`)
- `app/web_router.dart:154` (`listed`)
- `app/web_router.dart:155` (`listed`)
- `app/web_router.dart:156` (`listed`)
- `app/web_router.dart:157` (`listed`)
- `app/web_router.dart:257` (`listed`)
- `app/web_router.dart:441` (`go`)
- `design/components/mana_app_bar.dart:182` (`go`)
- `design/tokens/breakpoints.dart:87` (`listed`)
- `features/owner_workspace/screens/ow_bulk_onboarding_menu.dart:222` (`listed`)
- `features/web/widgets/mana_web_shell.dart:66` (`go`)
- `features/web/widgets/mana_web_shell.dart:90` (`listed`)

## Worth a look

**Routes with no way in that anybody wrote down** — neither the
path nor the screen is named anywhere outside the routers. Each
is reachable by typing the URL and, as far as the source shows,
no other way. Deep-link-only by design, or orphaned — check which
before assuming either:

- `/_design`
- `/ag-003`
- `/recent-deletes`
- `/sp-001`

**Navigation targets with no matching route** — each one is a
dead end at runtime, not a compile error:

- none

**Routes whose screen is not named in any test:**

- `/_design`
- `/admin-panel`
- `/business-suspended`
- `/customer-new`
- `/outbox`
- `/recent-deletes`

