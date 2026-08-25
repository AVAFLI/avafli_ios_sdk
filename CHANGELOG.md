# Changelog


## 3.0.0 — 2026-08-25

**Brand rename: WINR → Avafli.** No behavioral changes — 3.0.0 is 2.9.5
with every public and internal type, file, module, and install coordinate
renamed to the Avafli brand. The major bump exists because every public
symbol changed name.

### Migration (one screen)

Update your install coordinates, then let the compiler walk you through
the renames — every one is mechanical (`WINR` prefix → `Avafli`):

| 2.9.x (old) | 3.0.0 (new) |
|---|---|
| `pod 'WINRSDK'` | `pod 'AvafliSDK'` |
| SPM `https://github.com/AVAFLI/winr_ios_sdk.git` | SPM `https://github.com/AVAFLI/avafli_ios_sdk.git` |
| `import WINRSDK` | `import AvafliSDK` |
| `WINR.configure(config)` | `Avafli.configure(config)` |
| `WINR` (static entry point: `demoWipeIdentity`, `didReceiveFCMToken`, `registerForPushNotifications`, …) | `Avafli` |
| `WINRConfiguration` | `AvafliConfiguration` |
| `WINRUser` (incl. `.guest`) | `AvafliUser` (incl. `.guest`) |
| `WINROptions` | `AvafliOptions` |
| `WINREnvironment` | `AvafliEnvironment` |
| `WINRError` | `AvafliError` |
| `WINRConstants` (`sdkVersion` now `"3.0.0"`) | `AvafliConstants` |
| `WINRBranding` | `AvafliBranding` |
| `WINRLogo` | `AvafliLogo` |
| `WINRAnalyticsEvent` | `AvafliAnalyticsEvent` |
| analytics event names `winr_registration`, `winr_experience_opened`, `winr_experience_closed`, `winr_daily_entry_claimed`, `winr_bonus_entry_claimed`, `winr_streak_milestone`, `winr_prize_won`, `winr_badge_earned`, `winr_winner_claim_shown`, `winr_prize_claim_submitted` | same names with the `avafli_` prefix |
| share-link UTM `utm_medium=winr_share` | `utm_medium=avafli_share` |
| guest id prefix `winr_guest_…` (new mints) | `avafli_guest_…` — an id already persisted by 2.9.x keeps its `winr_guest_` value; stored ids are NOT rewritten |

`LoggingLevel`, `AnalyticsAdapter`, `PushNotificationManager`, and every
other unprefixed public type are unchanged. The analytics/UTM/guest wire
renames land in 3.0.0 across all platform SDKs (iOS, Android, web) — the
backend neither validates nor aggregates these values, and 3.0 is the one
breaking-change window. Update any downstream dashboards or funnels that
filter on the old `winr_*` event names.

### What deliberately did NOT change

- **Persistence keys** (keychain service `com.winr.sdk`, `winr_*`
  keychain/UserDefaults keys such as `winr_guest_id` and
  `winr_marketing_consent`): upgrading from 2.9.x keeps the user's
  identity, streak, and tokens. Stored values — including an existing
  `winr_guest_…` id — are not rewritten.
- **Legal URLs** stay on `winrmedia.com` (domain migration is a separate
  later step). The privacy webview's delete bridge now intercepts BOTH
  `winr://delete` (what the live privacy page emits) and `avafli://delete`
  (future-proofing).
- **API key formats** (`winr_live_…` / `winr_test_…`) are unchanged.

### Upgrade policy

2.9.x remains fully functional against the same backend but is frozen —
no further releases on the WINRSDK coordinates. All future work ships as
AvafliSDK 3.x.

## 2.9.5 — 2026-08-18

- **Removed the redundant Privacy choices link from How-it-works** — the
  Privacy Policy links on the capture sentence and the legal rows keep the
  delete path findable (all opening the in-app privacy webview).

## 2.9.4 — 2026-08-18

- **Legal pages open in-app** — Official Rules and Privacy Policy now
  present inside the experience in a WKWebView sheet (gunmetal chrome,
  slim title header with an X, loading spinner, retryable error state)
  instead of kicking the user out to Safari. Every legal link routes
  there: the capture sentence's inline links, the OFFICIAL RULES •
  PRIVACY POLICY rows (dashboard, code entry), and the how-it-works
  privacy entry point. Rules loads the giveaway/sdkConfig `rulesUrl`;
  Privacy loads the WINR privacy URL with `?app=1` appended (built with
  URLComponents, so a base URL already carrying a query is extended
  correctly).
- **Delete-my-data moves into the privacy page** — loaded with `?app=1`,
  winrmedia.com/sdk/privacy renders its own delete section; using it
  navigates to `winr://delete`, which the SDK intercepts in the
  webview's navigation delegate (no URL-scheme registration required of
  the host app) and hands to the EXISTING destructive opt-out
  confirmation + authenticated erasure. The confirmation dialog now
  renders at the experience root so the bridge can raise it from any
  screen. The intermediate native "Privacy choices" dialog (policy link
  + red delete) is deleted; the muted "Privacy choices" entry point on
  how-it-works stays and now opens the Privacy Policy webview directly.
- **Share-link UTM tagging** — when the publisher's `shareUrl` is included
  in a share action, the SDK appends `utm_source={network}&utm_medium=winr_share`
  ({network} = x | facebook | instagram | snapchat | tiktok, per the tapped
  button; system-share-sheet paths keep their network's value). Built with
  URLComponents so URLs with existing query strings are extended correctly,
  and a shareUrl that already carries a `utm_source` param is left untouched
  (publisher tagging wins). Share-text URLs only — nothing else changes.

## 2.9.3 — 2026-08-17

- **Claim review drops the legal sentence** — the "By submitting, you agree
  to the / Official Rules / Privacy Policy" sentence and its links are
  removed from the "ALMOST DONE!" review screen entirely (Ryan's call,
  Joe's updated Figma). The screen now carries only the optional likeness
  checkbox, SUBMIT, and the "secure and encrypted" note. Other screens'
  legal links are unchanged.
- **Likeness checkbox names the actual publisher** — "I authorize
  {publisher} and its promotional partners…" instead of "this app's
  publisher". The name comes from the new server-fed `sdkConfig.appName`,
  falling back to the host app's bundle display name (same source as the
  share line), and only then to the old generic wording.
- **Winner splash confetti** — the CONGRATULATIONS splash now plays the
  V2 celebration confetti emitter over the whole screen on appear (Joe's
  dedicated Confetti overlay, frame 5369:5594) plus a one-shot
  confetti-burst on mount, matching Android / Flutter / web. Both layers
  are non-blocking.
- **Blue top glow gone from every screen** — the radial primary-color
  top glow (`WINRV2TopGlow`) is removed from its last remaining screen,
  the adoption code-entry ("CHECK YOUR EMAIL"), which now uses the same
  flat gunmetal drawer background the capture screen got in 2.9.0. The
  now-unused component is deleted. The winner-flow gold sparkle prize
  art is content, not the gradient — untouched.
- **Claim confirmation matches Joe's frame (5386:5807)** — the
  "YOUR PRIZE CLAIM HAS BEEN SUBMITTED" screen now plays the celebration
  confetti on appearance (drifting field + one-shot burst, non-blocking);
  the "3-5 Business Days" card is a solid gunmetal card with a subtle
  border (shared with the splash's info card) instead of translucent
  gray, with the envelope ring and "3-5 Business Days" in the publisher
  primary accent (already accent-tokened); and the gold winner card's
  OFFICIAL / WINNER labels render in the publisher primary accent — the
  card's gold body and typography stay.
- **Capture screen brand tinting** — in "VISIT. EARN. WIN." the word
  "EARN." (with its period) now renders in the publisher's primary brand
  color; and both checkboxes (18+ confirm, marketing consent) are tinted
  the primary color — checked is a primary-filled box with a contrasting
  check (white or dark, picked by luminance), unchecked keeps a
  primary-tinted outline.

## 2.9.2 — 2026-08-14

- **Single legal surface on email capture** — the capture screen's legal
  sentence now carries "Official Rules" and "Privacy Policy" as underlined
  tappable links, and the separate OFFICIAL RULES • PRIVACY POLICY links row
  is removed from that screen only. The "Powered by © WINR Media"
  attribution stays; every other screen keeps its links row.
- **Privacy Policy links now open the privacy policy** — every "Privacy
  Policy" link (capture sentence, legal-links rows, claim review, privacy
  choices) used to open `rulesUrl`; they now open the WINR privacy policy
  (`https://winrmedia.com/sdk/privacy`). "Official Rules" keeps `rulesUrl`.
- **Legal block anchored to the bottom of the capture screen** — the legal
  sentence and attribution now sit at the drawer's bottom edge instead of
  directly under the CLAIM button. On short screens or with the keyboard up
  the page keeps a minimum gap and scrolls as before — no overlap with the
  button.

## 2.9.1 — 2026-08-14

- **Official brand share icons** — the claim flow's "Share on Social Media"
  row (X / Facebook / Instagram / Snapchat / TikTok) now renders the official
  WINR brand glyph set from the Figma exports, replacing the hand-drawn
  stand-ins. Glyphs are drawn in-code from the exact SVG path data via a
  minimal path-data parser Shape — no image assets added, sizing and share
  behavior unchanged.

## 2.9.0 — 2026-08-14

Keyboard-safe forms everywhere, a streamlined claim flow with a post-submit
share step, in-experience privacy choices, and adoption re-entry.

- **Keyboard avoidance on every text-input screen** — email capture, code
  entry, and every claim step (including the story editor) now keep the
  focused field visible above the keyboard, via a shared keyboard observer
  with scroll-content padding and scroll-to-focused-field. Root cause: the
  drawer root's `ignoresSafeArea()` had swallowed SwiftUI's built-in
  keyboard avoidance.
- **Flat capture background** — the email-capture screen swaps the blue
  radial glow for the same flat gunmetal background as the dashboard drawer.
- **Claim review down to one checkbox** — the accuracy and rules checkboxes
  are gone (the rules/privacy links stay tappable); what remains is a single
  optional likeness/promo checkbox, default unchecked, with submit always
  enabled. The choice is always sent as `promoConsentGranted`.
- **Share step after submit** — "Please share a little" now comes after the
  claim submits, so closing it loses nothing: a typed story rides the new
  `attachClaimStory` callable (fire-and-forget with one retry, deduped).
- **Social share intents** — X opens the tweet intent with prefilled text;
  Facebook opens the sharer with the configured link (falling back to the
  system share sheet when none is set, since the sharer ignores prefilled
  text by design); Instagram, Snapchat, and TikTok use the system share
  sheet with the share line — no platform gets a pretend prefill.
- **Publisher `shareUrl`** — publishers can configure a share link that is
  appended to the X post, drives the Facebook sharer, and rides along in the
  system share text.
- **Address autocomplete (optional)** — when a publisher configures
  `sdkConfig.placesApiKey`, the claim address step's street field suggests US
  addresses via Google Places (API New) as you type: up to 5 debounced
  suggestions in the dark claim styling with a "powered by Google" row, and a
  tap fills street/city/state/zip (all still hand-editable). No key → the
  plain street field, exactly as before; any Places failure degrades silently
  to plain typing.
- **Zip field fix** — widened so all five digits fit past the field's inner
  padding instead of clipping.
- **Privacy choices surface** — delete-my-data moves off the how-it-works
  screen into a dedicated "Privacy choices" surface (policy link + delete
  action with the existing confirmation).
- **Adoption re-entry** — a user who backed out of adoption mid-flow is no
  longer dead-ended: an `adoptionPending` flag on register/getActiveGiveaway
  triggers the new `restageAdoption` callable on open, then the code-entry
  screen with "pick up where you left off" copy; resend re-stages too.
- **Build fix** — removed stale `amazon.json` references from the Xcode
  project (the file was deleted earlier but stayed in the Resources phase).

## 2.8.0 — 2026-08-13

- `WINRConfiguration.environment` now defaults to `.production` — omit it; sandbox API keys (`winr_test_…`) are the supported way to test.
- Public-repo Swift package builds standalone (conditional test target).
- Removed a stray resource that warned in every consuming project.
## 2.7.0 — 2026-08-11

2.7.0 — "Verify your email" soft-verification: a persistent chip on the streak
dashboard lets users confirm a newly-typed email (reusing the code screen); never
blocks daily play, only prize-draw eligibility.

## 2.6.3 — 2026-08-11

2.6.3 — firstName/lastName are now optional on WINRUser; pass only the identity
data you have and the SDK captures the rest (email via the capture screen).

## 2.6.2 — 2026-08-11

2.6.2 — age-gate text honors publisher config; push notifications functional on
Android/web; resend keeps the code screen; error screens pick up publisher
branding.

- **Age-gate copy honors server config** — the email-capture age checkbox now
  renders the publisher's `ageGateText` when present, and otherwise builds the
  label from `ageGateMinAge` ("I confirm I am {minAge} years of age or older",
  default 18). The minimum age is never hardcoded when config says otherwise.
- **Resend keeps the code screen** — requesting a new adoption code no longer
  flips back to email capture first, so a failed resend shows an inline error on
  the code screen instead of stranding the user. The original age/marketing
  consents are reused, never fabricated or reset.
- **Impression counter matches web/Flutter** — the unregistered auto-open
  impression is counted only after presentation is committed (a presenting view
  controller exists), so a suppressed open never burns an impression.
- **Error screens pick up publisher branding** — the empty, geo-blocked, and
  session-expired screens now use the publisher accent color instead of WINR
  blue, matching the dashboard screens.
- **Three-way adoption-code error taxonomy** — an expired code and a
  too-many-attempts lockout now show distinct messages (from the backend's
  `deadline-exceeded` / `resource-exhausted` errors); other failures keep the
  generic "that code didn't match" copy.

## 2.6.1 — 2026-08-11

In-experience privacy opt-out (delete my data); District of Columbia added to
the prize-claim form.

- **Privacy choices** — the how-it-works ("?") screen gains a muted "Privacy
  choices" link. It raises a destructive confirmation ("Delete my data & stop
  participating"); confirming performs the existing RTD opt-out
  (`WINR.optOut()`), shows "Your data has been deleted.", and dismisses the
  experience. Failure keeps the confirmation up with "Something went wrong.
  Please check your connection and try again." — never a pretended success.
- **District of Columbia** in the prize-claim state dropdown, per the official
  rules' "50 states and the District of Columbia".

## 2.6.0 — 2026-08-10

User-facing error messaging per the Master Field List; honest failure states —
no fabricated claim success.

- **Inline field validation** with mandated copy, centralized in
  `WINRV2Strings`:
  - Email capture: "Please enter a valid email address." under the field,
    shown only after the field is touched or a submit attempt — never while
    typing the first characters.
  - Winner claim step 1: "Please enter a valid first name." / "Please enter a
    valid last name." on a continue attempt (unicode letters, spaces,
    apostrophes, hyphens, periods; max 50).
  - Claim phone stays optional, but a non-blank value must be a valid US
    10-digit number ("Please enter a valid 10-digit mobile number."); the
    normalized 10 digits are what gets submitted.
- **No fabricated claim success** — a transport failure during the daily claim
  no longer fakes a local success and celebrates an entry that was never
  recorded. The dashboard shows the honest unclaimed state with "We couldn't
  record today's entry. Check your connection and try again." and a TRY AGAIN
  affordance.
- **Duplicate same-day entry** (claim rejected as already-claimed when local
  state didn't know, e.g. another device claimed first) now shows a transient
  dashboard notice: "You've already entered today. Come back tomorrow to keep
  your streak going!"
- **Geo-blocked** backend rejections render a dedicated "Not available in your
  location" state instead of the generic empty state.
- **Session expired** (silent token refresh failed) renders "Your session has
  expired. Please try again." with a RETRY button that re-registers and
  reloads — no longer collapsed into the empty state.
- **Failed email submits stay on the capture screen** with "Something went
  wrong sending your email. Please try again." and a retry; consent is now
  recorded only after a confirmed submit (previously it was persisted before
  the network call, so a failed submit skipped the capture screen forever).
- Raw `WINRError`/backend error text is never rendered to users; all other
  errors keep the friendly empty state.

## 2.5.1 — 2026-08-10

Consent correctness and cross-device security.

- **Marketing consent checkbox starts UNCHECKED** — consent is an affirmative
  act (pre-ticked boxes are invalid under GDPR and disfavored by US state
  regulators). Declining still blocks nothing.
- **Email pre-fill**: pass your signed-in user's email via `WINRUser.email` and
  the capture screen shows it read-only — the address the user consents for is
  always one they proved to you. Malformed values fall back to the editable
  field.
- **Guest sessions**: no account system, or the user is signed out? Use the
  guest sentinel (or omit the user on web). The SDK mints a stable per-install
  `winr_guest_…` id for attribution; re-configure with the real user later and
  the streak carries over.
- **Verified adoption**: typing an email that already belongs to an existing
  WINR account now requires a 6-digit code sent to that inbox before the
  streak transfers to the new device. Fresh signups and pre-filled partner
  emails never see it.

## [2.5.0] - 2026-08-06

### Breaking

`WINR.deleteAccount()` is **removed**. Use `WINR.optOut()`.

It called a backend hard-delete that wiped the user's entry records. Those
records are the evidence that a drawing was fair, and destroying them is not
what erasure requires — GDPR Art. 17(3) exempts data needed for legal claims.
It also left no tombstone, so delete-and-re-register farmed unlimited entries,
and it never touched prize-claim records, leaving a winner's name, address and
phone orphaned after the account pointing at them was gone.

`optOut()` is the complete path: identity-wide, scrubs prize-claim PII too,
tombstoned so it survives a reinstall, and it keeps de-identified records as
proof the prize went to a real eligible person.

### Removed

Dead rewarded-video client code. The backend endpoint it called was deleted —
it granted a second daily batch of entries and no SDK had invoked it since the
V2 rebuild.

## [2.4.0] - 2026-08-05

Consent capture. The 18+ checkbox has always been on the capture screen but its
value was never transmitted, and there was no way for a user to say whether the
publisher could market to them. Both are now real, transmitted, stored values.

### Added
- **A marketing-consent checkbox on the email-capture screen**, directly under
  the age gate. It governs one thing: whether the publisher may send this
  person marketing email. It is **pre-checked** — unlike the age box, which
  stays unchecked because confirming your age has to be an affirmative act.
  Copy comes from the publisher's `emailConsentText` config (nested
  `copy.emailCapture.emailConsentText`, then the flat legacy field), which the
  backend fills in with the publisher's own name — "I agree to receive
  marketing emails from Acme". The bundled fallback, used only before any
  config has been fetched, is "I agree to receive marketing emails from this
  app". Both checkboxes render through one shared builder, so their box size,
  tint, spacing and tap target cannot drift apart.
- **`submitEmail` now sends `ageConfirmed` and `marketingConsent`** carrying
  the real checkbox states. The backend stores both with timestamps, plus the
  consent-text version and the verbatim copy shown, so an audit can prove what
  was agreed to.

### Changed
- **Declining marketing changes nothing about the giveaway.** The submit button
  is gated on age + a valid email exactly as before; the marketing box is
  deliberately excluded from that check. A user can untick it and still enter
  every day — and if they win, they are still contacted, because winner contact
  is operational and no checkbox governs it.

## [2.3.3] - 2026-08-05

Load-experience defects found testing the SDK inside a real publisher app.

### Fixed
- **The drawer no longer sits on a spinner for seconds.** It auto-opens ahead
  of its sequential network calls (registerDevice → getActiveGiveaway →
  claim). When the device already has a cached giveaway and streak, the real
  dashboard now paints IMMEDIATELY from that cache and the fresh response
  reconciles silently in place — the same no-replay reconcile the celebration
  staging already used (a celebration staged after the cache render still
  fires exactly once; the come-back bar now accepts a late-arriving toast
  rather than missing it). A local streak-engine failure after a successful
  cache render no longer replaces the live dashboard with an error screen. The
  email-capture gate is unchanged: an unconsented user never sees a cached
  dashboard.
- **Cold start shows a skeleton, not a bare spinner.** With nothing cached to
  paint, the loading view is now a pulsing block-out of the real layout (grab
  handle, header, prize card, three streak tiles, come-back bar, CTA pill) in
  the drawer's own gunmetal instead of a centered `ProgressView` and
  "Loading…". One shared pulse, so it reads as a single surface breathing.
- **The prize image arrives with the card instead of popping in after it.**
  The publisher's `prizeImageUrl` (and logo) are now decoded into an image
  cache as soon as the SDK learns the giveaway config — at registration and on
  every giveaway refresh, alongside the existing confetti-GIF prewarm — so the
  card normally paints its art on its first frame. `AsyncImage` is replaced by
  a warmer-backed view that reads the cache synchronously: a cold URL fades in
  over ~200ms against the card's dark background rather than flashing, and a
  broken one falls back to the bundled cash hero. Warmed URLs are tracked so
  repeat refreshes are no-ops, and a failed URL is dropped so it can retry.
- **No "0 Total Entries" first frame.** With the dashboard mounting instantly,
  the stats strip's count-up (which seeded itself in `onAppear`) and the view
  model's display total (which fell through to a zero placeholder until the
  network landed) both painted a 0 for a frame. Both are now seeded from the
  persisted streak state.
- **Cached email-consent flag is set on a successful email submit**, not only
  by the next `getActiveGiveaway`, so the auto-present engine's unregistered
  impression cap can never briefly apply to someone who just registered.

## [2.3.0] - 2026-08-04

### Added
- **Winner prize-claim flow (stepped, masked email)** — when the backend marks the user as the drawn winner (`prizeClaim.status == "pending"` on `getActiveGiveaway`), the drawer opens on the winner splash instead of the dashboard: CONGRATULATIONS! + prize strip → a 4-step claim form with a persistent header, "STEP N OF 4" label, and connected accent progress dots (1. TELL US ABOUT YOURSELF — name, the locked masked winning email from `prizeClaim.maskedEmail`, optional phone; 2. WHERE SHOULD WE SEND YOUR PRIZE? — address with 50-state picker; 3. SHOW OFF YOUR WIN! — optional photo; 4. PLEASE SHARE A LITTLE — optional story + social share row) → ALMOST DONE! review with three required consent checkboxes → `submitPrizeClaim` → confirmation with the gold OFFICIAL WINNER card and RETURN TO APP. Appears automatically; no integration work. The daily auto-claim still fires silently while the flow is up, and an already-submitted claim shows the normal dashboard.

### Changed
- **First-frame celebration beat** — on a claim-day open the dashboard mounts with a PREDICTED grant already staged from the pre-claim status (ladder math mirrors the backend), so the celebration is the first visible frame; the real claim runs in the background and reconciles totals/streak silently in place (no second celebration; failures settle back to server truth quietly). The 2.2.0 "CLAIM N ENTRIES" tap is gone — nothing to press, the pill reads GOT IT throughout, and only the Day-1 "You're in!" welcome modal remains.
- **Toast-first come-back bar, new copy** — on celebration opens the bar's first visible state is the "YOU'RE ON A ROLL! / Your {N} entries have been added automatically." toast; it holds ~2.5s, then slides once to the resting come-back pitch. Non-celebration opens rest on the pitch.
- **Reveal-beat tile: confetti-burst explosion + restored check/confetti** — the active day tile keeps the original drawn draw-on check, falling-confetti field, and glow, now topped by a one-shot confetti-burst GIF explosion that overflows the tile (the big-check tile-burst GIF was rejected and removed). The burst fires only on the reveal, never on a same-day reopen.
- **Count-up total with burst** — Total Entries counts up (ease-out, ~0.7s) and pops a confetti burst as it lands.
- **Prize card — the Delta A/B visuals** — dark and full-bleed: the prize image fills the whole card, the streak/total-entries stats sit in a solid black strip inside the top edge, and the headline overlays the bottom over a black→transparent scrim, in two layouts (A: right-aligned "WIN $1,000 / CASH PRIZE" for cash; B: centered "Win a {Prize}" + accent value line otherwise).

### Removed
- The `lottie-ios` dependency (nothing in the shipping V2 experience used it; it also broke `pod trunk push` at the link step), along with the dead `WINRLogo.lottie` / `.remoteLottie` cases.

## [2.2.0] - 2026-08-04

### Changed (BREAKING UX)
- Day 2+ reveal flow: the auto-claim still fires silently on open, but the UI
  now holds the previous day's numbers behind a "CLAIM N ENTRIES" pill; the tap
  reveals the celebration in place (tile check + confetti, streak/total advance)
  and the pill becomes GOT IT. No celebration modal for returning users.
- Day-1 celebration modal's GOT IT now closes the whole experience.
- Email-capture CTA renamed to "CLAIM MY N ENTRIES".

All notable changes to the WINR SDK will be documented in this file.

## [2.1.0] - 2026-08-04

### Removed (BREAKING)
- Manual `present()` / `present(from:)` and the public `isAvailable` check — the experience is exclusively auto-opened by the SDK (once per calendar day). `configure(_:)` is the entire integration; publishers can no longer launch the experience manually.
- `WINREnvironment.staging` and `.qa` — production-only; no staging/QA infrastructure exists (the removed cases silently pointed at production).

### Fixed
- Docs: push reminders are delivered via FCM (Firebase service account uploaded in the dashboard) with a local-notification fallback — not via an APNs certificate.

## [2.0.0] - 2026-08-03

### Added
- **V2 experience** — full rebuild to the WINR-High-V2 Figma design: gunmetal bottom drawer over the host app (dim backdrop, rounded top corners, spring slide-up), bundled Inter/Oswald fonts, prize card with cash lockup / prize headline, horizontally scrolling streak rail with accelerator milestone tiles, come-back bar, and how-it-works screen
- **Auto-open** — the experience presents itself on the first app-open of each calendar day (launch + foreground), always on; respects the server kill switch (`sdkConfig.experience.autoOpenEnabled`), the unregistered impression cap (default 3), and RTD opt-out
- **Auto-claim** — daily entries are claimed automatically when the experience opens; a celebration modal (looping confetti, animated checkmark) confirms the grant
- **Winner announcements** — "WE HAVE A WINNER!" banner and winner dialog, driven by the giveaway's `latestWinner`
- **Visit mode** — `streakMode: "visit"` giveaways use a never-resetting streak with visit-based copy, for low-frequency apps
- **Ladder accelerators** — streak ladder math mirrors the backend exactly, including milestone accelerators beyond the explicit ladder
- **RTD opt-out** — new `WINR.optOut()` tombstones the person on the backend and permanently silences the experience on the device

### Changed
- Branding is server-driven and limited to logo, prize image, and primary color; the V1 theming/copy/media system is gone
- `WINR.present` is now optional — the default integration is `configure(_:)` only

### Removed (BREAKING)
- Rewarded-video/bonus entry flow (provider options, bonus claim UI)
- The `autoPresent` option — auto-open is always on (server kill switch replaces it)
- V1 server-driven copy/media theming

## [1.2.0] - 2026-02-18

### Added
- **Push Notifications**: `PushNotificationManager` with APNs token registration (no Firebase Messaging dependency), local notification fallback, `WINR.registerForPushNotifications()` public API
- **Streak Reminders**: `sendStreakReminders` scheduled Cloud Function — notifies users who claimed yesterday but not today
- **Winner Fulfillment**: Full winner lifecycle tracking — `winners` collection with status flow (selected → notified → claimed → fulfilled → expired), `updateWinnerStatus` and `getWinners` admin-only functions
- **Winner Notification**: `selectWinner` now creates winner doc and sends push notification to winner

### Backend
- New Cloud Functions: `registerPushToken`, `sendStreakReminders`, `updateWinnerStatus`, `getWinners`
- Total Cloud Functions: 13

## [1.1.0] - 2026-02-18

### Added
- **Milestone Badges**: Server-configurable streak milestones (5 days +10 bonus, 15 days +50 + Silver, 25 days +200 + Gold), badges tracked on user doc, `.milestoneCelebration` state in SDK
- **Anti-Spam/Anti-Cheat**: Rate limiting per IP hash (10 req/min) and per user (5 claims/min), claim velocity check (1s dedup), suspicious activity flags (ip_mismatch, timezone_drift), admin ban system (`isBanned` field)
- **Certificate Pinning Fix**: ASN.1 DER header prepending for correct SPKI hash verification, pin rotation support (array of current + backup pins), default enabled
- **Analytics Default Implementation**: `ConsoleAnalyticsAdapter` with `os_log`, `WINRAnalyticsEvent` constants for all key events, convenience extension methods on `AnalyticsAdapter` protocol
- **Developer Documentation**: Comprehensive `GETTING_STARTED.md`, `API_REFERENCE.md`, `CODE_EXAMPLES.md` (14 real-world examples)
- **Unit Tests**: 12 test files (~1,700 lines) covering registration, token refresh, streaks, prize capping, geo-fence, analytics, email validation, age gate, keychain, giveaway config

### Fixed
- **Weekly Reset**: Changed from Monday-based to Sunday midnight UTC per UX Runtime Spec
- **Prize Capping**: `maxTotalEntries`, `maxPrizesPerPeriod` + `prizePeriodDays` (rolling window), `maxPrizeValue` enforcement in `claimDailyEntries`

### Backend
- New Cloud Function: `antispam.ts` module with rate limiting and suspicious activity detection
- `antispam` Firestore collection for rate limit tracking with TTL
- `ipTracking` user subcollection for multi-IP detection
- Updated `selectWinner` with enhanced winner doc creation

## [1.0.0] - 2026-02-18

### Added
- Core SDK: device registration, email capture, daily entries, bonus entries
- Three-tier streak system (daily/weekly/monthly) with server-driven configuration
- Rewarded video integration via `RewardedVideoProvider` protocol
- Google AdMob reference adapter (`GoogleAdMobRewardedProvider`)
- 18+ age gate with inline email validation
- Official Rules & Privacy Policy links on registration screen
- AES-256-GCM encryption for all PII (email, name, phone)
- IDFA collection via ATT framework
- SHA-256 IP hashing (raw IP never stored)
- IP-to-state geo-fencing (US-only, NY/FL restricted)
- Token refresh flow (silent re-authentication)
- Certificate pinning (opt-in, Google Trust Services SPKI pins)
- Right-to-be-Forgotten: `WINR.deleteAccount()` endpoint
- White-label branding system with 7 preset themes
- Single entry point: `WINR.configure(WINRConfiguration)` + `WINR.present()`
- Full configuration API for advanced customization
- Keychain-based secure storage for tokens and UUID
- Offline fallback with local streak engine
- Swift Package Manager support
- CocoaPods support

### Backend
- 9 Cloud Functions: registerDevice, refreshToken, submitEmail, submitUserProfile, claimDailyEntries, claimBonusEntries, getActiveGiveaway, selectWinner, deleteUserData
- Firestore security rules scoped per-user with admin custom claim
- Gatekeeper: publisher validation, rate limiting, geo-fencing, PII encryption
- All 22 Master Field List fields captured and stored
