## no-mistakes policy

Treat `no-mistakes` as a final quality and release gate, not as part of the
normal development loop.

Run `no-mistakes` only when the agent is confident that a major feature is
complete. Before invoking it, the implementation must be stable, requirements
must no longer be changing, direct tests and static analysis must pass, required
builds must succeed, and no known failures may remain.

Do not invoke `no-mistakes` during planning, active implementation, exploration,
routine debugging, or ordinary targeted testing. Use direct tests, analysis, and
build commands during those stages.

Invocation also requires an explicit user request such as `/no-mistakes` or
"run the final gate." Run one repository at a time. Ask the user before rerunning
a failed gate. Small UI, copy, documentation, and low-risk refactoring changes do
not require `no-mistakes` unless the user explicitly requests it.

## Building a shareable APK

When asked to compile, build, or produce an APK for a client, teammate, or
tester, run the script. Never hand-assemble the `--dart-define` flags.

```sh
./tool/build_tester_apk.sh
```

It runs `flutter analyze` and the full test suite, verifies the backend
precondition, builds, and copies a dated APK to `~/Desktop/Portraitor-Builds/`.
Report the folder and filename back to the user, because their next action is
attaching that file to a message.

| Ask | Command |
|---|---|
| Default. Simulated purchase, real backend, real portrait, real email. | `./tool/build_tester_apk.sh` |
| Screens only. No backend, local sample portrait. | `./tool/build_tester_apk.sh --demo` |
| Target production instead of staging. | `./tool/build_tester_apk.sh --api-base https://portraitor.ai` |
| Analyze and tests already green this session. | `./tool/build_tester_apk.sh --skip-checks` |

Two rules that are easy to get wrong and expensive to get wrong:

**Never build a tester APK with `--release`.** `FAKE_BILLING` and `DEMO_IAP` are
defined in `lib/core/config/build_flags.dart` as
`!kReleaseMode && bool.fromEnvironment(...)`, so a release build compiles them
out, falls through to real Google Play Billing, and fails on every phone because
the Play Console catalog does not exist yet. Profile mode is the correct choice
and needs no keystore.

**The default build needs `GOOGLE_PLAY_DEMO_GRANTS` on the backend.** The
simulated purchase presents a `demo.v1.` Google purchase token to the real
`/api/google/purchase/verify.php`, and that flag is what makes the backend
accept it. The script probes that endpoint and warns. If it warns, say so
plainly rather than shipping the build quietly: the tester will be stopped at
the pay screen with "Purchase could not be verified". The fix is to set
`SetEnv GOOGLE_PLAY_DEMO_GRANTS true` in the `.htaccess` profile that staging
actually deploys, then redeploy.

Do **not** reach for **Payment Mode** in `admin.php`. That governs the web
Stripe rail, staging deliberately stays on `stripe_sandbox`, and the mobile app
no longer touches Stripe at all. Leave **Email Mode** on a real SMTP option so
portraits are still emailed.

Do not work around a failing `flutter analyze` or `flutter test` with
`--skip-checks`. A build sent to a client is the worst place to find a
regression.

There is a matching `build-apk` skill in `.claude/skills/`, and the full
distribution plan, including iPhone and TestFlight, is in
[`docs/client-testing-distribution-plan.md`](docs/client-testing-distribution-plan.md).

<claude-mem-context>
# Memory Context

# [portraitor-mobile] recent context, 2026-06-06 2:39am GMT+8

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 50 obs (21,114t read) | 376,476t work | 94% savings

### Jun 5, 2026
10360 6:58p 🟣 Enhanced PDF diagnostics with version info and fallback service smoke test
10361 " ✅ Enhanced PDF diagnostics committed and pushed to portraitor_v2
10362 6:59p 🔵 Third staging deployment initiated with enhanced diagnostics commit 24e8b54
10363 7:10p ✅ Staging deployment completed successfully with enhanced PDF diagnostics
10364 7:11p 🔵 Staging PDF generation now working with PHP fallback successfully generating valid PDFs
10365 11:43p 🔵 Share functionality failing with invalid sharePositionOrigin coordinates
10366 11:44p 🔵 Located share functionality implementation in result_screen.dart
10367 " 🔵 Root cause identified: Share.shareXFiles missing sharePositionOrigin parameter
10368 " 🔴 Fixed iPad share crash by adding sharePositionOrigin parameter
10369 11:45p ✅ Added test assertion to verify sharePositionOrigin fix
10370 " 🔵 BuildContext used across async gap in _sharePdf method
10371 " 🔴 Fixed BuildContext async gap by capturing shareOrigin early
10372 " 🔵 Share functionality fixes verified with clean analysis and passing tests
10373 11:46p 🔵 Full codebase analysis passes with zero issues after share fixes
10374 11:59p 🔵 PDF generation uses pdfMake with PdfDocumentBuilder and PHP fallback
10375 " 🔵 PdfDocumentBuilder current styling and markdown parsing implementation
### Jun 6, 2026
10376 12:00a 🔵 PHP fallback PDF uses basic text rendering without pdfMake styling
10378 12:02a 🟣 PHP fallback PDF now renders styled output matching pdfMake browser version
10379 " ✅ All PDF generation tests passing after styled fallback refactor
10381 12:03a 🔵 iOS Simulator "iPhone 17 Pro" Not Available for Flutter Run
10383 12:04a 🔄 Improved PDF Layout and Visual Design in Portrait PDF Service
10385 " 🔵 iOS Simulator "iPhone 17 Pro" Not Available for Flutter Run
10387 12:05a 🟣 PDF Generation System with Fallback Verified
10388 " ✅ Fallback PDF Content Validation Tests Added
10389 " 🟣 Fallback PDF Generation System Completed and Validated
10390 12:06a ✅ PHP Portrait PDF Fallback Layout Improvements Committed
10391 " ✅ PDF Fallback Improvements Deployment to Staging Started
10394 12:08a 🔵 Staging Deployment Aborted Mid-Process
10396 " 🔵 Staging Deployment Still Running After Monitoring Abort
10411 12:38a 🔵 Flutter iOS simulator unavailable for target device
10413 12:40a 🔵 GitHub issue #9 not accessible for analysis
10414 12:41a 🔵 Web vs mobile processing persistence architecture comparison
10415 " 🔵 No final architectural decision found for issue #9 resume/cancel functionality
10416 12:42a 🔵 Mobile app has pending_jobs persistence infrastructure but no resume-on-launch logic
10417 " 🔵 Issue #9 closed with web localStorage job_status implementation, mobile has unused resume infrastructure
10418 12:43a 🔵 Web has complete tested resume implementation with UI prompts, mobile has none
10421 " 🔵 Web StorageManager implements complete pending job lifecycle with chunks_completed tracking
10423 " 🔵 Web app.js implements complete pending job lifecycle with navigation guard and resume UI
S4810 Confirm whether web pending job logic (IndexedDB/localStorage) can be replicated to mobile platform (Jun 6 at 12:49 AM)
S4819 Cross-platform storage schema analysis comparing web IndexedDB and mobile SQLite fields to identify missing capabilities for processing recovery payment queue coordination (Jun 6 at 1:00 AM)
10441 1:27a 🔵 Cross-platform storage schema differences mapped between web and mobile
10442 1:28a 🔵 Web storage manager method signatures extracted showing per-function field usage
10443 " 🔵 Mobile SQLite schema contains all web conversation fields plus mobile-specific additions
S4821 Guidance on which web storage fields to mirror in mobile implementation versus skip with rationale for selective adoption (Jun 6 at 1:29 AM)
S4824 Clarification on which web data model fields should not be copied directly to mobile implementation (Jun 6 at 1:30 AM)
S4825 Implementation strategy for building mobile pending job resume/cancel functionality in phases (Jun 6 at 1:36 AM)
S4827 Create implementation plan for mobile storage parity to enable resumable portrait processing after app kill (Jun 6 at 1:37 AM)
10445 1:38a 🔵 Current pending_jobs implementation state in web and mobile
10450 1:41a 🔵 Mobile pending_jobs schema missing critical resume fields compared to web
10454 1:45a 🔵 iPhone 17 Pro simulator unavailable in Xcode
10455 " ⚖️ Mobile storage parity plan for resumable portrait processing
S4828 Verify correctness of mobile storage parity plan through automated audit and structured review criteria (Jun 6 at 1:45 AM)
10456 1:51a 🔵 Web vs Mobile Storage Parity Audit Baseline
10457 " ✅ Mobile Storage Parity Review Prompt Created
S4831 Review mobile storage parity implementation plan for Portraitor Flutter app recovery feature (Jun 6 at 1:52 AM)
10462 1:57a 🔵 Web Pending Jobs Storage Schema Verified For Mobile Parity Plan
10463 " 🔵 Mobile Pending Job Persistence Missing Critical Recovery Data
S4836 Review mobile storage parity plan for Portraitor Flutter app to ensure correct recovery of unfinished paid portrait processing (Jun 6 at 1:59 AM)
10474 2:33a 🔵 Codex review task stuck on stdin read
S4837 Technical review of mobile storage parity plan to verify correctness against actual codebase and identify blockers before implementation (Jun 6 at 2:34 AM)
**Investigated**: After initial Codex task failed due to stdin piping issue, relaunched Codex review (task ID: bbkx1v1ep) with explicit verification checklist. The review examines 10 specific concerns including: whether current pending_jobs schema matches plan claims, whether example code uses real variable names from _processMapReduce/_processRolling, resume flow initialization of _leaseToken/_startHeartbeat/_stopwatch, SQLite ALTER TABLE migration safety, network-free refresh safety, iOS/Android write durability before SIGKILL, phase ordering dependencies, potential overengineering, and race conditions in appendPendingJobChunk.

**Learned**: The first Codex attempt hung on stdin input stream handling. The second approach pipes the prompt directly via printf to stdin rather than using a temp file reference. The review is configured with read-only mode, medium reasoning effort, and web search enabled to verify claims about web storage behavior that cannot be directly accessed from the mobile repo sandbox.

**Completed**: Killed stuck Codex process, cleaned up temporary files, and successfully launched second Codex review task with comprehensive verification prompt targeting specific implementation details in storage_service.dart, processing_provider.dart, and test files.

**Next Steps**: Waiting for background Codex task to complete analysis and return findings categorized by severity (blockers, majors, minors) with final verdict on plan approval status.


Access 376k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>
