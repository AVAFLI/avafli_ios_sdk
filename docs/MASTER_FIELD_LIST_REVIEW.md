# Master Field List — Columns M & N Review

**Tracker item 5** — "Review Publisher Integration and SDK enforcement logic on field docs, columns M, N (Ryan 2.3)"

**Source spreadsheet:** `master_field_list_v4_with_test_checklist June 2026.xlsx` (Google Drive `1y4xXsePvadic_iZsEL2KyiIml4QwCSi0`)
**Second source:** `security items.docx` (Google Drive `1r2imeywWXMP_mqdWMowypfjAoGK7ctdF`) — Scott's
Hybrid Trust Pipeline / domain strategy / SLA document. Cross-checked in [section 3](#3-cross-check-against-scotts-security-document).
**Code reviewed:** backend `functions/src/` @ `1ae12aa` (latest `main`); SDKs iOS / Android / Web / Flutter all at `2.4.0`
**Date:** 2026-08-05

Column M = *Publisher / Integration Instructions*. Column N = *SDK / Backend Enforcement Logic*.

Every DONE below is backed by a specific file:line that was actually opened and read. Where the
spreadsheet and the shipped system disagree, the disagreement is called out rather than smoothed over —
in several cases the shipped behaviour is deliberately *stronger* than the spec, and it is the spec
that should change.

---

## Scorecard

| | Fields (23) | Tech Exec Summary mandates (9) | Security-doc stages (Part A, 6) |
|---|---|---|---|
| DONE | 9 | 5 | 2 |
| PARTIAL | 10 | 3 | 2 |
| NOT BUILT | 1 | 0 | 2 |
| NEEDS DECISION | 3 | 1 | 0 |

Changes since the June pass: **field 4–5 (`first_name`/`last_name`) moved PARTIAL → DONE** — the
apostrophe defect is fixed and deployed (`92f76cb`).

**Changes since the last version of this document (`56a41e8`).** Release **2.4.0** (`4cb48af`) shipped
consent capture and publisher delivery, plus two follow-on fixes (`38486ad`, `1ae12aa`). What that closed:

- **Gap #1, the 18+ age attestation, is RESOLVED.** It was the largest legal exposure carried by both
  previous passes. The attestation is now transmitted, stored and timestamped, *alongside the verbatim
  copy the person saw*. See [Gaps not in the field list](#gaps-not-in-the-field-list).
- **Gap #3, marketing consent with no consumer, is RESOLVED.** The checkbox now drives a distinct
  `marketing_consent_status`, and `getPublisherUserExport` gives publishers a consent-filtered,
  server-decrypted, audit-logged CSV. Decision 8 was *"who owns the list"*; the code has now been built
  toward option B, so what remains is contractual, not architectural.
- **Field 3's "unreachable in admin" deviation is FIXED** — `emailConsentTs` is surfaced in both the
  admin user view and the CSV export, along with the marketing and age fields.
- **Field 21 gained ingest normalization** — mixed `v2.4.0` / `2.4.0` shapes are canonicalized server-side.

The raw counts in the table above are unchanged, and that is deliberate rather than pessimistic: fields 2
and 3 each retain a *narrower* deviation from columns M/N (see each entry), so neither has earned a DONE
yet. What changed is the character of both partials — from "the mechanism does not exist" to "the
mechanism exists and one detail differs from the sheet."

Now **1 cross-cutting gap that does not appear anywhere in the spreadsheet** (the `prizeClaims`/400-cap
holes in PII anonymization). The second — the orphaned `claimBonusEntries` grant — was **found, framed
correctly and closed during this pass** — see
[Gaps not in the field list](#gaps-not-in-the-field-list).

Two things also got *worse* on inspection, both previously understated:
**certificate pinning is switched off on the main iOS client** (mandate 4), and **Firebase App Check —
the entire web perimeter of Scott's pipeline — does not exist anywhere** (section 3, stage 2). Both
remain open at this pass.

One new defect found while verifying the 2.4.0 work, unrelated to it: **the admin "ban user" button
wrote a field the backend never read**, so bans had no effect on entries or the draw. Found, fixed and
deployed during this pass; no user had ever been banned, so nothing slipped through. See
[field 2's ban note](#2-email_consent_status--partial-narrowed) and follow-up 2.

---

## 1. Field-by-field: columns M and N

### 1. `user_email` — **DONE** (col N) / **NEEDS DECISION** (col M)

- **Col N — DONE.** Trim → lowercase → validate → reject → persist normalized, exactly as written.
  `index.ts:632` `const email = (rawEmail ?? "").trim().toLowerCase();` then `index.ts:636` `validateEmail(email)`.
  Validator `gatekeeper.ts:131-136` enforces the regex *and* the min-6 / max-254 bounds (`gatekeeper.ts:134`).
  Normalization is re-applied defensively inside `hashEmail` (`gatekeeper.ts:41`) and `encryptEmail`
  (`gatekeeper.ts:51`), so even a bypassing caller stores a normalized value. Same pattern in
  `recoverAccount` (`index.ts:803`, `index.ts:807`). Tests: `test/gatekeeper.test.ts:50-76`.
- **Col M — NEEDS DECISION.** The sheet instructs "App Dev pass to SDK using App's SSO". The shipped SDK
  **deliberately refuses** a publisher-supplied email — `WINRUser.swift:24`: *"Email is NOT accepted here —
  the SDK captures it via its own consent flow."* `WINRUser` exposes only `id`, `firstName`, `lastName`, `phone`.
  This is a defensible choice (WINR owns the consent moment, so the consent record is ours to defend),
  but column M as written tells publishers to do something the SDK will not accept. **Either the spec
  changes or the SDK does.**

### 2. `email_consent_status` — **PARTIAL (narrowed)**

*Rewritten at this pass. 2.4.0 formally split one overloaded flag into two, and columns M/N describe the
old, conflated meaning. Read this entry as the definition of record.*

**The split, which is the substance of the change:**

| Field | What it means | Set by | What it gates |
|---|---|---|---|
| `email_consent_status` | **Operational.** We hold an address for this person, so we may confirm their entry and contact them if they win. | Implied by submitting an email — `index.ts:673`. **Not a checkbox, and it should not become one:** a winner we cannot reach is a prize we cannot award. | Nothing directly (see the gate note below) |
| `marketing_consent_status` | **The checkbox.** The *publisher's* permission to market to this person. | The box under the age gate — UNCHECKED by default since the Aug 2026 governance review (Scott's Decision 5: pre-ticked consent is invalid under GDPR and disfavored by state regulators) — `index.ts:679-682`, declared `types.ts:141-142` | The publisher export, and nothing else |

The rule that follows, and which the code now enforces: **declining marketing blocks neither entry nor
winning.** The iOS capture screen makes this structural — `WINRV2Screens.swift:322` `wantsMarketing = true`
with the comment *"Declining does not block entry, so it is deliberately excluded from `canSubmit`"*, and
`WINRV2Screens.swift:325-327` confirms `canSubmit` is `isAdult && email…` only.

- Default `false` at registration — `index.ts:275`. Declared `types.ts:132`.
- **`marketing_consent_status` is now declared on `UserDoc`** (`types.ts:141-142`), closing the
  "written as an untyped key" defect flagged at the last pass.
- **Consent copy is captured, not just the boolean.** `submitEmail` stores `consent_text_version`
  (`index.ts:688`), `age_consent_text` (`index.ts:691`) and `marketing_consent_text` (`index.ts:693`) —
  the verbatim wording the person saw. Critically, that wording is resolved **server-side**
  (`resolveConsentCopy`, `index.ts:567-594`) rather than echoed back by the client, with the reasoning
  stated at `index.ts:561-563`: *"the audit artifact has to be something the client can't forge."*
  The marketing string names the publisher — `marketingConsentTextFor` (`index.ts:507-510`) renders
  *"I agree to receive marketing emails from {PublisherName}"*, and only the server knows that name.
  This directly answers the objection recorded against Decision 8 option B at the last pass ("the consent
  copy the user actually saw must name the publisher").
- Both config-returning callables fill the copy in, not just one — `withMarketingConsentCopy`
  (`index.ts:539-556`) is applied to `registerDevice` as well as `getActiveGiveaway`, with the reason
  given at `index.ts:535-537`: a brand-new device is precisely the user who sees the capture screen.
- A pre-2.4.0 placeholder string (*"Get notified about prizes and rewards"*) was found stored as a
  per-publisher "override" on every existing `sdkConfig` despite no publisher having authored it. It is
  ignored on read (`STALE_CONSENT_PLACEHOLDERS`, `index.ts:522-524`). That matters for the audit record,
  not just the UI: it reads as *winner notification*, so filing it as the marketing consent record would
  have documented agreement to something the box does not govern.

**A real fix shipped here, and it is worth stating separately.** The entry gates in `claimDailyEntries`
and `claimBonusEntries` previously keyed off `email_consent_status`. They now key off **email presence** —
`hasConfirmedEmail` (`index.ts:605-607`), called at `index.ts:1147-1152` and `index.ts:1457-1462`. The two
were indistinguishable only because the flag was hardcoded `true`; if its meaning were ever narrowed, the
old gate would have silently started refusing entries. The reasoning is recorded in the code at
`index.ts:596-604`. **Entry gate: DONE, and stronger than the sheet asks.**

**Publisher delivery now exists.** The last pass's headline finding was that *no* mechanism let a
publisher reach a user's email. `getPublisherUserExport` (`publisherexport.ts:116-244`, exported at
`index.ts:4322`) is that mechanism, and its design is defensible on each of the four points that made the
last pass uneasy:

- **Consent-filtered.** Filters on `marketing_consent_status === true` (`publisherexport.ts:178`), not on
  `email_consent_status` — the distinction is written into the file header (`publisherexport.ts:4-8`).
- **Scope from the caller, not a parameter.** There is no `publisherId` argument; scope resolves from the
  authenticated uid via `resolvePublisherForAuthUid` (`publisherexport.ts:135-139`). A cross-publisher
  read is not expressible.
- **Decryption is server-side.** `decryptAES` at `publisherexport.ts:190`; the AES key never leaves the
  backend, the same posture as `admin.ts`.
- **Audited and throttled.** Every pull writes an `auditLogs` entry naming who pulled, for which
  publisher, and how many rows (`publisherexport.ts:218-231`); rate-limited to 5/hour per dashboard user
  (`publisherexport.ts:47-54`). Opted-out, anonymized and banned users are excluded
  (`publisherexport.ts:174`). It is wired to a real button in the publisher dashboard —
  `avafli-website/src/app/sdk/dashboard/page.tsx:548`, which requests `{ format: "csv" }` and therefore
  gets the consent-filtered list.

**What still keeps this PARTIAL — two things, both narrow:**

1. **The consent filter is a default, not an invariant.** `marketingConsentedOnly` defaults to
   marketing-consented-only (`publisherexport.ts:129`, *"Default-deny on the marketing question"*), but
   passing `false` returns the **full roster including people who declined marketing**
   (`publisherexport.ts:178`). The dashboard button never sends it, but the callable is public and a
   publisher holds valid dashboard credentials. Columns M/N say *"consent must be true before marketing
   access is allowed"* — as written, that is the default path, not a guarantee. Either remove the
   parameter or gate `false` behind a WINR-side approval.
2. **There is still no per-publisher marketing-enabled flag** (re-grepped
   `marketingEnabled|marketing_enabled|mailchimp|klaviyo|sendgrid|braze` across `functions/src/` and
   `WINRSDK/`: zero hits). Columns M and N assume one exists. Today every publisher can pull the export.

> **Unrelated defect found while verifying the export's exclusion list — the admin ban button does
> nothing.** `publisherexport.ts:174` excludes `data.banned`. The winner draw
> (`index.ts:1813`) and the entry gate (`enforceBanCheck`, `antispam.ts:92`) both read **`isBanned`**,
> which is what `types.ts:186` declares. Nothing in `functions/src/` writes either key — and the admin
> dashboard's ban action writes the *other* one: `winr-admin/src/lib/firebase-utils.ts:313-315`
> `banned: true`. So a user banned from the admin tool was **still allowed to claim entries and was
> still in the prize draw**; only the publisher export honoured the ban. This predates 2.4.0 and is not
> caused by it. **Now fixed:** both enforcement sites accept either spelling and the admin writes both.
> See follow-up 2.

*One honest caveat, unchanged and not user PII:* `publisherLogin` (`index.ts:2814`) and
`getPublisherDashboard` (`index.ts:2926`) still return `publisherData as any` — the raw
`publishers/{id}` document, unfiltered. Per `types.ts:60-64`, that document can still carry the
**legacy** `encryptionKey` (the AES key that decrypts end-user PII) alongside `fcmServiceAccount` and
Stripe IDs. Canonical keys already live in `publisherSecrets` (`gatekeeper.ts`,
`firestore.rules:24-26`); the doc field should be stripped from these two responses. See follow-up 9.

*Also unchanged:* the twelve pre-existing publisher callables still return **no** end-user email,
decrypted PII, `emailHash`, or consent flag — `getPublisherWinners`'s explicit allowlist
(`index.ts:3943-3958`) still exposes only the opaque `userId`, and `getPublisherAnalytics`'s `topUsers`
is the same. `getPublisherUserExport` is the single, deliberate, audited exception. Outside it, the only
decrypt paths remain admin-gated behind `assertAdmin` (`admin.ts:20-27`), which requires the Firebase
custom claim `admin: true` that publishers do not hold. And the SDK still refuses a publisher-supplied
email in the other direction — `WINRUser` (`WINRSDK/Public/WINRUser.swift:10-31`) exposes only `id`,
`firstName`, `lastName`, `phone`.

### 3. `email_consent_ts` — **PARTIAL**

- **Written at the moment of opt-in — DONE.** `index.ts:668` `emailConsentTs: Timestamp.now(),` in the same
  atomic `update()` as the consent flag (`index.ts:697`). Declared `types.ts:126`.
- **The third deviation — "unreachable in admin" — is FIXED (`4cb48af`).** The field the spec calls
  *"our primary defense for CAN-SPAM and CCPA audits"* is now retrievable without database access:
  - Admin user mapper — `admin.ts:110` `emailConsentTsMs: tsToMillis(data.emailConsentTs),` with the
    reason recorded in the code at `admin.ts:108-109` (*"written since V1.2 but never surfaced"*).
  - Admin CSV export — `admin.ts:454` `emailConsentTs: msToIso(tsToMillis(data.emailConsentTs)),`.
  - It arrived with the rest of the consent audit set in the same two surfaces: marketing consent +
    timestamp (`admin.ts:111-112`, `admin.ts:455-456`), the age fields (`admin.ts:115-116`,
    `admin.ts:457-458`) and `consent_text_version` (`admin.ts:117`, `admin.ts:459`).
  - One deliberate detail worth knowing for an audit: `age_confirmed` exports **blank, not `false`**,
    when it was never captured (`admin.ts:457`, `publisherexport.ts:206`) — a user who last submitted
    from a ≤2.3.3 client is distinguishable from one who actively declined. Absence of an affirmation
    is not a denial, and conflating them would have been the kind of error that only surfaces under
    challenge.
  - Rendered in the admin UI's export header alongside the rest —
    `winr-admin/src/app/users/page.tsx:163`.
- **Two deviations from columns M/N remain, both cosmetic:**
  1. Stored as a Firestore `Timestamp`, **not** an ISO-8601 UTC string. (Firestore Timestamps export as
     ISO-8601 — and the admin/publisher surfaces above now emit ISO strings — so this is presentation
     only, but it is not what the spec says.)
  2. Field is camelCase `emailConsentTs` while every sibling is snake_case (`sms_consent_ts` `index.ts:1011`,
     `marketing_consent_ts` `index.ts:681`). The stored key does not match the spec name. Renaming it now
     would require a backfill of every existing user doc; the cheaper correction is to the sheet.

### 4–5. `first_name` / `last_name` — **DONE** *(was PARTIAL in June; fixed and deployed)*

- **The apostrophe defect found in the June pass is FIXED.** Commit `92f76cb` widened the validator;
  it is deployed to production. `gatekeeper.ts:173-180` now reads
  `if (!name || name.length > 50) return false;` … `return /^[\p{L}\s'.\-]+$/u.test(name);`
- The old regex was `/^[a-zA-Z\s-]+$/`, which rejected `O'Brien`, `D'Angelo`, `N'Diaye`, `Jr.`, and every
  accented or non-Latin name. The new class accepts **O'Brien, D'Angelo, Jr., José, Müller, Nguyễn** —
  `\p{L}` covers any Unicode letter — while still rejecting digits and injection-shaped symbols. Max-50
  is unchanged and still enforced.
- The pre-existing test asserted the *broken* behaviour (it checked that an apostrophe name was
  rejected). It was corrected in the same commit rather than deleted, so the fix is now regression-guarded.
- This also goes beyond the spreadsheet's own regex (`^[a-zA-Z '-]{1,50}$`), which is ASCII-only and would
  itself reject `José`. **The spec regex should be updated to match the code, not the other way round.**
- Remaining cosmetic inconsistency (unchanged, low risk): `index.ts:977` / `index.ts:988` validate the **raw** value while `encryptPII`
  trims (`gatekeeper.ts:64`); `prizeclaim.ts:308` / `prizeclaim.ts:311` validate the **trimmed** value.
  `\s` also admits tabs/newlines, not just spaces.

### 6. `phone_mobile` — **PARTIAL**

- Validator `gatekeeper.ts:181-185` strips non-digits and requires exactly 10 (US). Correct per spec.
- **But the two writers normalize inconsistently, and one is a bug:**
  - `submitUserProfile` `index.ts:1002` encrypts the **raw** string — `encryptPII(phone, ...)` — so
    `(555) 123-4567` is stored as ciphertext-of-the-formatted-string. Stripping happens only inside
    `validatePhone`'s local variable and is thrown away.
  - `submitPrizeClaim` `prizeclaim.ts:317` strips correctly and encrypts `cleanPhone` (`prizeclaim.ts:442`).
- Net: the same logical field is stored in two different formats depending on entry path. Column N says
  "strip → validate → persist"; only the prize-claim path actually does.

### 7–8. `sms_consent_status` / `sms_consent_ts` — **PARTIAL (dormant)**

- Fields exist and are wired: `types.ts:165-166`, default false `index.ts:276`, written `index.ts:1009-1012`,
  cleared on opt-out `index.ts:931`, echoed to admin `admin.ts:108`.
- **There is no SMS capability whatsoever** — grepped `twilio|sendSms|smsProvider|10DLC|tcpa`: zero hits.
  Nothing reads `sms_consent_status` to gate an action.
- The web SDK hardcodes `smsConsent: false` (`winr_web_sdk/src/winr.ts:321`), so in practice the flag is
  never set true on web.
- Write path is a truthy check only (`index.ts:1009`) — passing `smsConsent: false` never records a
  **revocation**. If SMS ever ships, that is a TCPA problem.

### 9. `pub_app_id` — **DONE**

- Auto-detected by the SDK and sent on `registerDevice` (`index.ts:224`).
- Validated against the publisher's registered bundle list — `gatekeeper.ts:229-231`
  `if (!publisher.bundleIds.includes(bundleId)) throw ... "Bundle ID not authorized for this publisher"`.
- API-key status and publisher status also gate initialization (`gatekeeper.ts:198-200`, `gatekeeper.ts:227-228`).
- Tests: `test/gatekeeper.test.ts:363-422` (active key + authorized bundle, suspended key, suspended
  publisher, unauthorized bundle, unknown key, legacy key IDs).

### 10. `maid_id` — **DONE**

- iOS requests ATT and only then reads the IDFA — `WINR.swift:560-564`
  (`ATTrackingManager.requestTrackingAuthorization()` → `ASIdentifierManager.shared().advertisingIdentifier`).
- Server accepts it only when non-empty and **UUID-v4 valid** — `index.ts:1016-1020`, using
  `isUuidV4` (`gatekeeper.ts:138-142`); rejects with `invalid-argument` otherwise.
- Purged by the anonymization job (`index.ts:2155`) and by RTD opt-out (`index.ts:912`).

### 11. `streak_daily` — **NEEDS DECISION** (logic itself is DONE)

- Actual field is **`daily_current`** on `users/{uid}/streak/current` (`index.ts:1226`); the name
  `streak_daily` exists only in a comment (`firestore.rules:58`).
- Logic `index.ts:1271-1285`: same-day → `already-exists`; yesterday → `+1`; otherwise → **`1`**.
- **Same-day duplicate is rejected by four independent guards** — entry query (`index.ts:1221-1223`),
  `daily_last_claimed === today` (`index.ts:1271-1273`), legacy-format equivalent (`index.ts:1255-1256`),
  and **cross-device identity dedup** (`index.ts:1185-1200`, resolving through `identities` /
  `resolveCanonicalUserId` `index.ts:204-219`). This is what delivers "one entry per person per calendar
  day across devices."
- **DECISION 1 (still open since June):** the spec contradicts itself — the numbered rule says
  *"If current_date > last_date + 1 day: Reset to 0"* but the prose above says *"reset to 1"*.
  We implemented **reset to 1** (`index.ts:1284`, test `test/streak.test.ts:71-77`). Scott to confirm.
- **Col M discrepancy:** the sheet says *"The SDK should calculate daily streaks"* and the Tech Exec
  Summary says *"The SDK is the Source of Truth for these counters to prevent API spoofing."* That is
  backwards — a client-authoritative counter is exactly what enables spoofing. We made the **server**
  authoritative and locked the fields in `firestore.rules:60-64` (clients may only self-write
  `user_timezone`, `platform_os`, `sdk_version`, `fcmTokens`, `updatedAt`). **The implementation is right;
  the spec sentence should be corrected.**
- Minor client/server divergence: `StreakEngine.swift:59` caps the iOS display counter at 7
  (`min(state.currentDay + 1, 7)`) while the server lets it climb (`index.ts:1275-1276`). The stale
  comment at `index.ts:1241` ("max 7") should go.

### 12. `streak_weekly` — **NEEDS DECISION** (spec says FUTURE; it is already built)

- Built despite being marked *"FUTURE, ignore for now"*: `types.ts:203-205`, increment/reset
  `index.ts:1287-1294`, returned to SDKs `index.ts:1397`.
- **It grants nothing.** `index.ts:1356-1362`: *"PHASE 1 PARK (per the 2/26 call): the weekly/monthly
  streak bonuses … are intentionally NOT granted."* No `weekly_bonus` entry is ever written.
- **DECISION 2 (still open since June):** the spec says two different things — the field row says
  *"hard reset to 0 every Sunday at 00:00:01 **local** time"*, the Tech Exec Summary says
  *"resets to 0 every Sunday at 23:59:59 **UTC**"*. We implemented **Monday**, via `getMondayOfWeek`
  (`index.ts:132-138`); `getSundayOfWeek` (`index.ts:125-130`) is dead code kept for compatibility.
  Reset value is **1**, not 0. The `weekly_start` doc comment still says "Sunday" and is stale.

### 13. `streak_monthly` — **NEEDS DECISION** (spec says FUTURE; it is already built)

- `types.ts:207-209`, boundary `getFirstOfMonth` (`index.ts:140-143`), increment/reset `index.ts:1296-1301`
  (resets to 1). Same Phase-1 park — grants nothing.
- No `0-31` clamp exists anywhere, contrary to the stated format.

> **What actually pays today** is the **streak ladder**, which is not a row in the field list:
> `computeLadderEntries` (`index.ts:1046-1061`), default ladder `[10, 30, 60, 130, 240, 300, 500]`
> (`index.ts:1312`), milestone accelerators day 5 → +10, day 15 → +50, day 25 → +200 (`types.ts:11-15`),
> capped by `maxPrizeValue` (`index.ts:1319-1321`). Admin-only; publishers cannot edit it (`index.ts:3446-3448`).
> Tests: `test/ladder.test.ts`.

### 14–15. `current_entry_date` / `last_entry_date` — **DONE**

- Both `YYYY-MM-DD` strings on the canonical user doc (`types.ts:183-184`), written `index.ts:1382-1388`.
  `last_entry_date` is the previous `current_entry_date` (shift-register), seeded to today on first claim.
- Date key from `todayDateString(userTimezone?)` (`gatekeeper.ts:752-763`), with
  `yesterdayDateString` (`gatekeeper.ts:769-783`) and `localDayUtcWindow` (`gatekeeper.ts:714-743`).
  Surfaced in admin at `admin.ts:103-104`. Tests: `test/dates.test.ts`.
- **Minor inconsistency to log:** `getActiveGiveaway`'s sibling-device check (`index.ts:1698-1699`) uses a
  naive UTC window rather than `localDayUtcWindow`, unlike the claim path (`index.ts:1178`). A
  western-timezone user's late-evening claim can be missed by that *read-side* check. The write-side
  guards still hold, so this is a display glitch, not a double-entry hole.

### 16. `user_timezone` — **PARTIAL**

- Sent by the SDK from device local time (`WINR.swift:375`, `WINRAPI.swift:394`) and used for the daily
  reset boundary throughout (`index.ts:1177`, `1026`, `1062`, `1288`, `1451-1452`, reminders `index.ts:2263-2274`).
  Also a fraud signal — timezone-vs-IP drift (`antispam.ts:191-201`).
- **Column N says "validate against IANA format → *reject* invalid values". We do not reject.** The value
  is stored raw at registration (`index.ts:262`, `index.ts:279`) with no validation — unlike `platformOS`
  (`index.ts:230-233`) and `sdkVersion` (`index.ts:234-236`), which *are* checked. `validateTimezone` /
  `isValidTimezone` do not exist. Validation is lazy, at use time (`resolveTimezone` `gatekeeper.ts:689-702`),
  and garbage **silently degrades to UTC** (`gatekeeper.ts:761-762`, test `test/dates.test.ts:58-62`).
- Deliberate and correct: US abbreviations are mapped before the ICU probe (`TZ_ABBREV_MAP`
  `gatekeeper.ts:669-682`) because ICU treats `EST`/`HST` as fixed offsets and would shift the boundary
  an hour all summer (`gatekeeper.ts:691-693`).

### 17. `lifetime_count` — **DONE**

- `types.ts:182`, initialized 0 (`index.ts:274`), incremented `index.ts:1364`, written to both the streak
  doc (`index.ts:1375`) and the canonical user doc (`index.ts:1383`). Never resets. Server-authoritative
  (`firestore.rules:60-64`). Test: `test/streak.test.ts:128-143`.
- Nuance vs the spec wording: it counts **daily claims**, not "unique days" — equivalent in practice,
  since at most one daily claim per person per day is possible. It lives on the **canonical** user, so it
  is correctly shared across a person's devices.

### 18. `ip_address` — **PARTIAL** (core is DONE; territory handling is wrong)

- **Geo-fence FAILS CLOSED — DONE, and this is the single most important enforcement in the file.**
  `enforceGeoFence` `gatekeeper.ts:565-609`: inconclusive → block (`gatekeeper.ts:588-599`), confirmed
  non-US → block (`gatekeeper.ts:602-608`), private/loopback outside the emulator → block
  (`gatekeeper.ts:570-583`, *"there is deliberately NO production bypass"*). Primary source is a bundled
  local MaxMind GeoLite2 DB, with ipwho.is only as fallback (`gatekeeper.ts:513-553`) — this is what made
  fail-closed survivable after the June outage (history documented `gatekeeper.ts:347-361`).
  15 dedicated tests: `test/gatekeeper.test.ts:202-330`.
- **SHA-256 hash + purge raw — DONE.** `hashIP` `gatekeeper.ts:33-35` (salted; salt is a required Secret
  Manager secret, `gatekeeper.ts:16-28`). Only `ipHash` is persisted to entries (`index.ts:1333`,
  `index.ts:1527`). The raw IP is used transiently for the geo lookup and the timezone-drift check
  (`antispam.ts:162-163`) and is never written to Firestore — it is deliberately kept out of the logs too
  (`gatekeeper.ts:590-591`).
- **PARTIAL — US territories are blocked, contradicting our own user-facing promise.** The code comment
  (`gatekeeper.ts:343`) and the block message (`gatekeeper.ts:367`, *"50 states and U.S. territories"*)
  both say territories are eligible, but the check is `res.countryCode !== "US"` (`gatekeeper.ts:602`) and
  MaxMind returns `PR`, `GU`, `VI`, `MP`, `AS` for the territories. **A Puerto Rico resident is blocked
  from entering while `prizeclaim.ts:56-58` happily accepts a Puerto Rico mailing address.** Either the
  allowlist gains five country codes or the message stops promising territories.
- **Also note:** column N and the Tech Exec Summary specify an **IP-to-*State*** check ("50 US States").
  The implementation is **country-level only** — there is no state resolution in the fence. That is a
  deliberate policy call recorded at `gatekeeper.ts:343-345` (NY/FL burdens fall on the *operator*, not
  the user), and the tests assert NY and FL are allowed (`test/gatekeeper.test.ts:224-230`). Fine — but
  it is not what columns M/N say.

### 19. `platform_os` — **PARTIAL**

- **Column N says "accept only supported values → *reject* unsupported". We normalize instead of rejecting**
  (`normalizePlatformOS`, validated at `index.ts:230-233`) — a deliberate June decision to avoid breaking
  existing installs. Tests: `test/gatekeeper.test.ts:117-128`.
- The spec's enum is `iOS / Android`, but Web and Flutter SDKs also ship at 2.4.0, so the real value set
  is wider than the sheet documents.

### 20. `entry_source` — **DONE** (with a real fraud gap behind it)

- **Stronger than the spec asks:** the value is never accepted from the client, it is set server-side —
  `index.ts:1331` (`"Daily"`) and `index.ts:1525` (`"RV_Bonus"`). Typed `types.ts:225-227`.
- `isValidEntrySource` (`gatekeeper.ts:160-162`) is **dead code** — never called in production, only in
  `test/gatekeeper.test.ts:135-139`. Harmless, but it should either be wired in or deleted.
- ~~**GAP — `claimBonusEntries` is a live, publicly-callable entry grant that no client calls.**~~
  **RESOLVED — deleted, `429c235`.** The callable granted a second daily batch of entries, was deployed
  `invoker: "public"`, and no SDK invoked it after the V2 rebuild removed the rewarded-video flow.
  `doublingEnabled` was `true` on all three giveaway docs including both `active` ones. It is now
  removed from source and from the deployed project, and the flag is `false` everywhere. `RV_Bonus`
  survives only as a historical value in the `entry_source` union (`types.ts:225-227`) and on the one
  test entry already written. See gap 2.
- Secondary defect in the same function: `claimBonusEntries` writes to `users/{userId}` (`index.ts:1507`)
  — the **device** user — while `claimDailyEntries` writes to the **canonical** user (`index.ts:1226`).
  On a multi-device person these diverge. `index.ts:1509` also casts `streakSnap.data()` with no
  existence check, so a bonus attempt against a device-user with no streak doc throws at `index.ts:1513`.

### 21. `sdk_version` — **PARTIAL**

- Sent by all four SDKs, all currently `2.4.0` (`WINRConfiguration.swift:14`, `winr_web_sdk/package.json:3`,
  `winr_flutter_sdk/pubspec.yaml:6`, `winr_android_sdk/.../network/WinrApi.kt:548`). Format-validated at
  registration via `isValidSdkVersion` (`index.ts:234-236`); tests `test/gatekeeper.test.ts:129-134`.
- **NEW — the value is now normalized at ingest (`1ae12aa`).** Three SDKs sent bare semver (`2.4.0`) while
  the Flutter SDK prefixed a `v`: `winr_flutter_sdk/lib/src/winr.dart:135`
  `WINRRequestDefaults.sdkVersion = 'v$sdkVersion';`. Two shapes were therefore landing in the same
  column. `registerDevice` now strips a leading `v` before storing —
  `index.ts:241-242` `const normalizedSdkVersion = typeof sdkVersion === "string" ? sdkVersion.replace(/^v/i, "") : sdkVersion;`
  — applied on both the returning-device and new-user write paths (`index.ts:264`, `index.ts:281`), so
  stored values are canonical bare semver whatever the client sends. The visible symptom was cosmetic
  (`vv2.4.0` in the admin users table), but the real one was not: **any string comparison or version
  floor built on that column would have mis-ordered Flutter installs**, which is exactly the mechanism
  the next bullet describes. Fixing the data shape before building the comparator was the right order.
- **Column N's third step — "flag unsupported versions per compatibility policy" — remains NOT BUILT.**
  There is still no minimum-version floor, no deprecation path, and no way to force an upgrade if a
  shipped SDK version is found to be broken. Worth having before publishers are in the wild. Normalizing
  the input is a prerequisite for it, not a substitute — see follow-up 8.
- Cosmetic: the sheet's format cell still says `v1.x.x`; we are on `2.4.0`, and the stored form is
  deliberately **without** the `v`.

### 22. `user_uid` — **NOT BUILT as specified**

- The spec mandates a **UUID v4** with an explicit regex, in both the field row and the Tech Exec Summary
  ("The Handshake: … the backend returns a UUID v4 (user_uid)").
- **It is a Firestore auto-generated document ID** — 20-char base62, not a UUID —
  `index.ts:267-268`: `const newUserRef = usersRef.doc(); userId = newUserRef.id;`
- `isUuidV4` (`gatekeeper.ts:138-142`) documents itself as covering *"#22 user_uid"* but **is applied only
  to `maid_id`** (`index.ts:1017`). Applying it to `user_uid` today would reject every real user.
- What the spec asks for *around* the ID is done: server-generated at registration, used as the primary
  key for all later calls, and stored in the iOS Keychain — `KeychainStorage.swift:58-63`, class
  `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (device-only, no
  iCloud sync). Raw email is not persisted locally.
- **DECISION 7:** migrate to UUID v4 (a real migration — the ID is the primary key everywhere) or amend
  the spec to "opaque server-generated identifier". Flagged in June; still open.

### 23. `session_token` — **DONE** (different mechanism than the spec names)

- No field literally called `session_token` exists (grepped `session_token|sessionToken`: zero hits).
  Authentication is **Firebase Auth**, and a Firebase ID token *is* a JWT, so the spec's
  `header.payload.signature` format requirement is satisfied in substance.
- Flow: `registerDevice` mints a custom token (`index.ts:337`), exchanged server-side for an ID token +
  refresh token (`index.ts:21-38`) — deliberately keeping the Web API key off the client (`index.ts:18-20`).
  Returned as `{ token, refreshToken, uuid, ... }` (`index.ts:443`).
- **Signature verification and expiry are enforced by the Firebase Functions runtime**, not hand-rolled;
  every guarded callable begins `if (!request.auth) throw new HttpsError("unauthenticated", ...)`
  (`index.ts:1066-1069`, `1410-1413`, `1558-1561`).
- **Refresh/rotation — DONE.** `refreshToken` callable `index.ts:449-481`; the iOS client decodes the JWT
  `exp` and refreshes 60s early, falling back to 55 minutes (`KeychainStorage.swift:20-32`). The client
  decoder explicitly documents that it does **not** verify the signature — correctly, that is the
  backend's job.
- **Residual gap:** there is no Firebase **App Check**, and the publisher `apiKey` + `bundleId` pair is
  validated only at `registerDevice` (`index.ts:245`), not on subsequent calls. Once a client holds a
  valid ID token, later calls are authenticated as a *user* but not attested as a *genuine app build*.

### Admin visibility — new since the last pass, and it changes the cost of several findings above

This review repeatedly says some value *"cannot be retrieved without direct database access"* or would
need *"an engineer to retrieve it from the database."* Two commits since `56a41e8` shrank that list, so
the phrase should not be over-applied when reading the older entries.

**Attribution (`38486ad`).** The admin Users table previously showed no origin at all — with no publisher
filter applied, every row looked identical. It now shows, per user:

- **Publisher name** — resolved from the publisher list the filter dropdown already fetches, so the
  column costs no extra reads (`winr-admin/src/app/users/page.tsx:92-100`, rendered at
  `page.tsx:427-433`, with a deleted publisher falling back to its raw id rather than blank).
- **App / bundle ID** — `pub_app_id`, in the user mapper at `admin.ts:96` and the export at
  `admin.ts:442`, rendered at `page.tsx:436-443`. One publisher can ship several bundle IDs, so this is
  the column that says *which* app a user came from.
- **Giveaway attribution** — `resolveGiveawayAttribution` (`admin.ts:177-243`) joins two sources: the
  giveaways the person has actually *participated* in, read from the streak doc's `giveaway_totals` map
  (already fetched for the streak column, so free), and the giveaway they would enter today, from their
  publisher's `activeGiveawayId` (`admin.ts:196`). IDs are resolved to titles server-side
  (`admin.ts:220-232`).

Worth noting for anyone maintaining it: the join is **batched, not N+1** — at most one `getAll` for
publishers and one for giveaways per call, deduped across the page with caches the caller owns so they
survive across export pages (`admin.ts:307`, `admin.ts:348`, `admin.ts:413`). The commit records a
60-user page costing 2 reads instead of ~180. `adminExportUsers` gained the same three columns
(`admin.ts:442-445`), and its row cap was dropped 20,000 → 15,000 to keep the fatter rows inside the
callable response limit — a deliberate trade, not a regression.

**Consent (`4cb48af`).** Covered under field 3: `emailConsentTs`, marketing consent + timestamp, the age
fields and `consent_text_version` are all now in both the admin user view and the CSV export.

**What this does *not* fix.** The admin surfaces are staff-only (`assertAdmin`, `admin.ts:20-27`).
Everything above is reachable by a WINR operator without a database console; none of it is reachable by a
publisher. The one publisher-facing PII path is `getPublisherUserExport` (field 2).

---

## 2. Tech Exec Summary mandates

| # | Mandate | Status | Evidence / gap |
|---|---|---|---|
| 1 | UUID v4 + JWT handshake | **PARTIAL** | JWT side done (Firebase ID token, `index.ts:337`, `449-481`); UUID v4 side not built (`index.ts:267-268` — Firestore auto-ID) |
| 2 | `user_uid` in Keychain / EncryptedSharedPreferences; raw email not stored locally | **DONE** | `KeychainStorage.swift:58-63`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; raw email no longer persisted |
| 3 | Counters are spoof-proof source of truth | **DONE** (spec wording is wrong) | `firestore.rules:60-64` locks all counters/consent/ban flags to server writes; clients may self-write only 5 telemetry fields. Spec says the *SDK* should be source of truth — that is the insecure option |
| 4 | TLS 1.2+ with certificate pinning | **PARTIAL — and the gap is not only the browser** | Corrected below; the June note called this "PARTIAL (inherent)", implying the Web SDK was the sole exception. It is not |
| 5 | AES-256 at rest | **DONE** | AES-256-GCM: `encryptEmail` `gatekeeper.ts:47-55`, `encryptPII` `gatekeeper.ts:60-68`, 12-byte random IV, auth tag retained |
| 6 | Server-side decryption only | **DONE** | Every decrypt site is a Cloud Function on the admin SDK — `admin.ts:53-65`, `admin.ts:428-430`, `prizeclaim.ts:531-540`, and (new in 2.4.0) `publisherexport.ts:190`. No callable returns `encryptionKey`. The June finding (browser-side decryption) is genuinely fixed; header note at `admin.ts:5-7` records the move. The 2.4.0 publisher export is the first *non-admin* decrypt path, and it deliberately kept the posture: the key stays server-side and only the plaintext CSV crosses the wire (`publisherexport.ts:14-16`) |
| 7 | Key management | **NEEDS DECISION** | Per-publisher 32-byte keys live in Firestore `publisherSecrets`, protected by `firestore.rules:24-26` (`allow read, write: if false`) — **not a KMS/HSM** (grepped `kms`: zero hits). Adequate today; likely challenged in an enterprise security review |
| 8 | 3-year PII TTL, then anonymize | **PARTIAL** | `anonymizeStalePII` exists — `index.ts:2138-2194`, daily 03:00 UTC, 3-year cutoff `index.ts:2144`. **Three limits:** (a) hard cap of 400 users + 400 logs per run with no loop (`index.ts:2162`, `index.ts:2180`) — at scale the backlog can outgrow the sweep, so the 3-year guarantee is not actually bounded; (b) it sweeps only `users` + `auditLogs` — **`prizeClaims` PII is never anonymized**, including *plaintext* `firstName`/`city`/`state`/`story`/photo URL (`prizeclaim.ts:433-449`); (c) anchor is `lastSeenAt` (inactivity), not collection date |
| 9 | Geo-fence hard block + SHA-256 IP hash, purge raw | **DONE** | See field 18. Fail-closed `gatekeeper.ts:565-609`; salted hash `gatekeeper.ts:33-35`; raw IP never persisted |

### Mandate 4 in detail — pinning is written, and then switched off on the path that matters

The pinning **machinery** is real and rotation-capable: `NetworkClient.swift:140-180` does a full SPKI
evaluation (`SecTrustEvaluateWithError` → walk the chain → SHA-256 the public key → compare against
`pinnedKeyHashes`) and *cancels* the challenge when nothing matches (`NetworkClient.swift:178-179`).
Android has the equivalent via OkHttp `CertificatePinner` (`winr_android_sdk/.../network/NetworkClient.kt:53-59`).

**But the main iOS client constructs itself with pinning disabled:**

- `WINRSDK/DependencyContainer.swift:59` — `enablePinning: false,  // Disabled until pin rotation is automated`
- `WINRSDK/DependencyContainer.swift:48` — same, on the plain (pre-auth) client
- `WINRSDK/Services/PushNotificationManager.swift:106` — `enablePinning: false`

It **is** enabled on three clients built directly in `WINR.swift` — `enablePinning: true` at
`WINR.swift:366`, `463`, and `480` (registerDevice / profile / token-refresh).

So the split is the wrong way round: **device registration and token refresh are pinned, while the
DependencyContainer client that carries daily claims, bonus claims, and prize-claim submissions is not.**
The high-value, PII-bearing calls are the unpinned ones. That inversion is the actual finding — not
"pinning is partial".

Two further caveats:

- **iOS < 15 silently bypasses pinning entirely.** `NetworkClient.swift:171-174`: the `else` branch of
  `if #available(iOS 15.0, *)` calls `completionHandler(.useCredential, ...)` with the comment
  *"Fallback for iOS < 15: accept if standard trust evaluation passed"* — it returns before any pin is
  compared. On an older device the pin is not weakened, it is absent.
- **The Android example app ships pinning off.** The SDK default is correct
  (`WINROptions.kt:18-19`, `enableCertificatePinning: Boolean = true`), but
  `example/src/main/kotlin/com/avafli/winrexample/MainActivity.kt:49` sets
  `enableCertificatePinning = false // Disabled until pin rotation is automated`. Publishers copy
  example code; this is how a default gets un-defaulted in the field.
- The Web SDK genuinely cannot pin — browsers do not expose the API. That part *is* inherent and should
  be an explicit spec exception.

**Do not simply flip these to `true`.** Every comment above names the same real blocker: pin rotation is
not automated. A pinned build whose pin expires does not degrade — it **hard-fails every request, in
already-shipped app binaries, with no server-side remedy**. That is a worse outage than the risk pinning
mitigates. The prerequisite is a written pin-rotation policy (see follow-up 10), not a one-line change.

---

## 3. Cross-check against Scott's security document

*Source: `security items.docx`, Google Drive `1r2imeywWXMP_mqdWMowypfjAoGK7ctdF`.*

This document is new since the June review and is **not** derived from the Master Field List, so nothing
in it has been tracked against shipped code before. It has three parts: **A** — a 6-stage "Hybrid Trust
Pipeline"; **B** — a Cloudflare/Porkbun domain strategy; **C** — SLAs, an API failure catalogue, and an
outage protocol.

The analysis it opens with is correct and worth stating plainly: **our mobile-first security assumptions
do not survive contact with a web browser.** On iOS/Android there is a device-scoped identifier in a
hardware-backed store; in a browser there is a text box. Everything in Part A follows from that, and it
is a real gap in our current posture — the Web SDK ships at 2.4.0 with no perimeter defence of its own.

Below, each stage gets an honest status against code. **Partial matches are marked partial**, not done —
several of our mechanisms are adjacent to what the document describes without actually delivering it.

### Part A — the 6-stage Hybrid Trust Pipeline

| Stage | Doc calls it | Status | Verdict in one line |
|---|---|---|---|
| 1 | Mobile Hardware UUID Anchor | **PARTIAL** | We store an ID in the Keychain; we do not attest the device |
| 2 | App Check + reCAPTCHA (web perimeter) | **NOT BUILT** | Confirmed absent in every repo |
| 3 | Double Opt-In Magic Links | **NOT BUILT** | Consent is implied by submission; no email is ever sent to verify |
| 4 | Hashed-Email Identity Hub | **DONE** | This one we genuinely have, and it is load-bearing |
| 5 | Server-Side Referee Logic | **DONE** | Server-authoritative counters + rules lock |
| 6 | BI Quarantine `is_suspicious` | **PARTIAL** | We write the flag; nothing reads it, and the described detector does not exist |

---

**Stage 1 — Mobile Hardware UUID Anchor. PARTIAL.**

What exists: the server-issued `user_uid` is persisted in the iOS Keychain (`KeychainStorage.swift:58-63`,
`saveUUID`/`loadUUID`) with `kSecClassGenericPassword` and
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — device-only, never iCloud-synced. Registration keys
off a `deviceFingerprint` (`index.ts:224-226`, lookup at `index.ts:247-250`).

Where the document overstates it: it describes *"a cryptographically signed token"* dropped into the
hardware vault, guaranteeing *"1 physical phone = 1 real human."* Neither half holds today.

- The value is an **opaque server-generated ID, not a signed or attested token**. Nothing binds it to
  the device's secure hardware.
- `deviceFingerprint` is `UIDevice.current.identifierForVendor` (`WINR.swift:506-518`). That resets when
  the user deletes all of a vendor's apps, and it is trivially different across a reinstall cycle.
- **There is no device attestation anywhere.** Grepped `DeviceCheck|DCDevice|AppAttest|attestation|SecureEnclave`
  across `WINRSDK/` and `functions/src/`: **zero hits.** Apple's App Attest and Android's Play Integrity —
  the APIs that would actually deliver stage 1 as written — are not integrated.

So the mobile channel raises the cost of a bot farm; it does not "choke it instantly", and it does not
prove one human. **Our real one-person-one-entry guarantee comes from stage 4, not stage 1.** The spec
should say so.

**Stage 2 — Silent Behavioural Telemetry (Firebase App Check + reCAPTCHA). NOT BUILT.**

Grepped `appcheck|app_check|App Check` across `functions/src/`, `WINRSDK/`, `winr_web_sdk/src/`,
`winr_android_sdk/`, and `winr_flutter_sdk/`: **zero hits in source.** (The only matches anywhere are
inside compiled Firebase bundles in `winr-admin/.next/`, which are vendor artefacts, not our usage.)
`reCAPTCHA` likewise: zero hits. This confirms and sharpens the residual gap already noted under field 23.

**This is the single largest gap between the document and the code**, and it is precisely the one that
matters most for the web channel the document was written about. Today, `registerDevice` validates the
publisher `apiKey` + `bundleId` pair (`index.ts:245`) and nothing else attests the *caller*. A script with
a valid API key — which ships inside every publisher app and is therefore extractable — can register users.

What partly compensates, and must not be mistaken for App Check:

- **Rate limiting is real.** `checkRateLimit` (`antispam.ts:19-34`) throws `resource-exhausted` with
  *"Too many requests. Please try again later."*, wired as `enforceIPRateLimit` (`antispam.ts:50`),
  `enforceUserRateLimit` (`antispam.ts:61`), and `enforceAuthRateLimit` (`antispam.ts:73`); applied at
  `prizeclaim.ts:348-349`, `publisherusers.ts:373-374`, and imported into `index.ts:80-81`.
- **The geo-fence fails closed** (`gatekeeper.ts:565-609`), which blocks most offshore scripted traffic.

Rate limiting caps the *volume* of abuse; App Check would deny the *class* of caller. They are not
substitutes. The cost-control argument in the document is sound — Firestore bills per operation, and a
blocked request that never reaches the database is the only one that is free.

**Stage 3 — Double Opt-In Verification (Magic Links / Email Codes). NOT BUILT.**

Grepped `magiclink|magic_link|magic link|doubleOptIn|double_opt_in`: **zero hits.** There is no email
delivery path for verification at all.

Today the email is accepted, validated for *shape only* (`validateEmail`, `gatekeeper.ts:131-136`),
hashed, encrypted, and treated as consented — `email_consent_status` is hardcoded `true` by the act of
submission (`index.ts:673`, and see field 2). **Nothing ever proves the inbox exists or belongs to the
submitter.** A typo'd address and a deliberately fabricated one are indistinguishable to us.

**2.4.0 improved the consent *record* without touching this.** We now capture an explicit marketing
checkbox, a timestamp, and the verbatim publisher-named copy the person saw (field 2) — so we can prove
precisely *what* was agreed to. We still cannot prove *who* agreed, or that the inbox exists. Those are
different problems, and only the first one has been solved. Anyone reading the 2.4.0 changelog should
not conclude otherwise.

This still compounds Decision 8: whichever option is chosen for list ownership, an unverified list is
worth materially less, and under CAN-SPAM/CASL a consent record for an address we never confirmed is
weak evidence. Now that the export exists and publishers can actually pull the list, this matters more
than it did last pass, not less. If the marketing proposition is real, **double opt-in is the
prerequisite**, not a refinement.

**Stage 4 — Deterministic Cross-Device Identity Hub. DONE.**

This is the stage where the shipped system matches the document closely, and it is doing real work.

- SHA-256 of the normalized email: `hashEmail` (`gatekeeper.ts:40-42`) — `.toLowerCase().trim()` before
  digest, so the hash is stable across capitalisation and whitespace.
- An `identities` collection keyed by a `globalId`, holding `linkedUsers` (publisher → canonical user),
  `hashedEmail`, and `deviceFingerprints` (`index.ts:757-764`).
- `resolveCanonicalUserId` (`index.ts:204-219`) resolves any device-user to the person's canonical user
  for that publisher.
- On submitting an email already known to that publisher, the device-user is **merged** into the
  canonical one: `mergeIdentities` (`index.ts:752`), the throwaway user is tombstoned with `mergedInto`
  (`index.ts:767-770`), and auth is **re-issued for the canonical user** so the SDK switches identity
  mid-session (`index.ts:773-776`).
- Cross-publisher links stay deliberately independent — a person is not stitched across publishers.

This — not the Keychain — is what delivers *"one entry per person per calendar day across devices"*
(see field 11, where it is one of four independent guards). Worth noting the document's own framing is
right: the hashed email is the master link.

**Stage 5 — Server-Side Referee Logic. DONE.**

Fully matches, and the shipped system is *stronger* than the Master Field List asks for (see field 11,
where the spreadsheet wrongly names the SDK as source of truth).

- Streak arithmetic runs server-side only: `index.ts:1271-1285`.
- `firestore.rules:60-64` locks every counter, consent flag, and ban flag to server writes; clients may
  self-write exactly five telemetry fields (`user_timezone`, `platform_os`, `sdk_version`, `fcmTokens`,
  `updatedAt`).
- Weighted winner selection uses rejection sampling over `crypto.randomBytes` rather than modulo
  (`index.ts:1825-1830`), specifically to avoid a low-value bias — the audit-defensible choice.

One honest caveat: the document says *"the client merely sends a raw timestamp."* Ours sends
`user_timezone`, which the server then uses to compute the day boundary (`index.ts:1177`, `1026`, `1062`).
That is a client-supplied input to an authoritative calculation. The blast radius is bounded — at worst a
user shifts *which* calendar day their single entry lands on, never *how many* they get — but it is not
literally zero client influence, and `user_timezone` is unvalidated at ingest (field 16).

**Stage 6 — BI Layer Quarantine Flag. PARTIAL — and the partial is doing less than it looks.**

What exists: `trackIPUsage` (`antispam.ts:130-181`) writes a `suspiciousFlags` array onto the user doc.
Two detectors are implemented — `ip_mismatch` when a user presents more than three distinct IP hashes in
one day (`antispam.ts:148-151`), and `timezone_drift` when the declared timezone disagrees with the
geo-IP region (`antispam.ts:163-166`). Declared at `types.ts:187`. Flagging is deliberately non-blocking
(`antispam.ts:181-183`).

Three reasons this is **not** stage 6 as written:

1. **Nothing reads the flag.** Grepped `suspiciousFlags` across `functions/src/` and `winr-admin/src/`:
   the only hits are the two writes in `antispam.ts:174,177` and the type declaration at `types.ts:187`.
   There is **no consumer at all**.
2. **It does not quarantine anyone from the sweepstakes pool.** `selectWinner` excludes users on exactly
   three conditions — `optedOut`, `anonymized`, `isBanned` (`index.ts:1813`). `suspiciousFlags` is not
   among them. A flagged user remains fully eligible to win. The document's central claim — *"this
   quarantines potential fraud out of the sweepstakes pool"* — **is not true of the current code.**
   Worse on first inspection: the third of those three conditions did not fire either, because the
   admin ban button wrote `banned` while this line read `isBanned` (see field 2 and follow-up 2), so an
   explicitly, manually banned user was also still in the draw. **That half is now fixed** — a
   deliberate human ban reaches the filter. The automatic quarantine the document describes is still
   not built: `suspiciousFlags` remains unread, and wiring it in is a decision rather than a bug,
   because auto-excluding on suspicion will occasionally catch an innocent VPN user.
3. **The described detector does not exist.** The document specifies flagging *"sub-second, mechanical
   session durations"*. We capture no session duration and no interaction timing anywhere; our two
   signals are both network-derived. Behavioural analysis is not implemented.

It is also not surfaced on any executive dashboard, so the *"keeps KPI dashboards 100% clean"* benefit is
unrealised. The honest summary: **we have the plumbing and the field name; we have neither the detector
nor the consequence.** Closing this is genuinely small — one clause in the `selectWinner` filter plus an
admin column — but it should be a deliberate decision, since auto-excluding on a heuristic means
occasionally disqualifying a legitimate user (a VPN user or a commuter can trip `ip_mismatch`).

### Part B — Domain security & infrastructure (Cloudflare / Porkbun)

**This is infrastructure work, not code.** Nothing in Part B is verifiable against this repository, and
nothing in it is blocked on engineering — it needs Ryan's registrar and DNS access. Reproduced here as a
checklist so it is tracked alongside everything else. The reasoning in the document is sound: a single
root domain is the shared dependency of all four SDKs, so a DNS-level outage or hijack is a total outage.

*Phase 1 — immediate perimeter (Q3 2026, $0):*

- [ ] Create a central company Cloudflare account.
- [ ] Point GoDaddy nameservers at Cloudflare (registration stays at GoDaddy; prepaid balance preserved).
- [ ] Decline GoDaddy's paid security / privacy / SSL upsells — Cloudflare covers these free.
- [ ] Configure API subdomain routing (e.g. `api.winr-sdk.com`) and enable Cloudflare rate limiting.

*Phase 2 — Porkbun migration (from Dec 2026, ahead of Jan 2027 renewals):*

- [ ] Set calendar alerts 30 days before each domain's expiry.
- [ ] Unlock the domain in GoDaddy and obtain the EPP/authorization code.
- [ ] Submit the transfer at Porkbun (ICANN adds a year; no prepaid days are lost).
- [ ] Enable Porkbun free WHOIS privacy and 1-click DNSSEC.

Two engineering notes to fold in when Phase 1 happens:

- **Cloudflare rate limiting sits in front of `antispam.ts`, it does not replace it.** Ours is per-user
  and per-IP-hash at the application layer; Cloudflare's is per-edge. Keep both.
- **Certificate pinning and a Cloudflare proxy interact.** If API traffic is ever proxied through
  Cloudflare rather than hitting `*.cloudfunctions.net` directly, the presented certificate chain
  changes — which would invalidate any pin set built against Google Trust Services. This is one more
  reason follow-up 11 (pin rotation policy) must precede enabling pinning.

### Part C — SLAs, API failure catalogue, and outage protocol

**The error scenario table, scored honestly:**

| Doc scenario | Status | Evidence / gap |
|---|---|---|
| **Network Timeout** — *"server took >3s"*, save locally, auto-retry | **NOT BUILT** (the part that matters) | iOS timeout is **15s**, not 3s (`NetworkClient.swift:258`, `urlRequest.timeoutInterval = 15`). The only retry is a **single** re-issue after a token refresh on an auth failure (`NetworkClient.swift:222-236`) — it does not fire on timeout. **No local save, no background retry.** A timed-out claim is simply lost |
| **Database Unavailable** — engage Offline Mode, cache the entry | **NOT BUILT** | Grepped `offlineQueue\|offlineCache\|pendingEntries\|replayQueue`: **zero hits.** There is no offline mode in any SDK. The promised UI copy *"Your streak is safe!"* would be false |
| **Invalid Authentication** — suppress the SDK window, alert engineering | **PARTIAL** | The *user-facing* half is done and deliberate: `WINRError.invalidAPIKey` and `WINRError.serviceUnavailable` exist (`WINRError.swift:16`, `24`), and `serviceUnavailable` is documented to degrade silently — default-UI integrations present nothing (`WINRError.swift:21-24`). The *"alerts engineering immediately"* half does not exist |
| **Rate Exceeded (Bot Guard)** | **DONE** | `checkRateLimit` (`antispam.ts:19-34`) throws `resource-exhausted` / *"Too many requests. Please try again later."* — close to the document's copy. Enforced per IP, per user, and per auth attempt (`antispam.ts:50`, `61`, `73`) |
| **Identity Conflict** — drop the duplicate, tell the user it is already registered | **DONE** | Four independent guards, see field 11: entry query (`index.ts:1221-1223`), same-day check (`index.ts:1271-1273`), legacy-format equivalent (`index.ts:1255-1256`), and cross-device identity dedup (`index.ts:1185-1200`). Returns `already-exists` |

So: **two of five scenarios are genuinely handled** (both the ones our existing anti-abuse work happened
to cover), one is half-handled, and **the two that require client-side resilience are entirely absent.**

**Uptime and latency targets — no measurement exists.**

The document commits to 99.9% monthly uptime (<43.8 min unplanned downtime) and a 250ms p95 on entry
verification. Neither is instrumented. There is **no status page** (grepped `statuspage|status page`:
zero hits), no synthetic monitoring, no latency histogram, and no error-budget tracking. Cloud Functions
emit default metrics to Google Cloud Operations, but nothing is configured on top of them.

Worth flagging for expectation-setting rather than as a defect: **cold starts make a 250ms p95 ambitious
on Cloud Functions.** A cold `claimDailyEntries` does a Firestore read chain plus, on some paths, a geo
lookup. The target may well be achievable warm; it should be measured before it is contracted.

**P1–P4 severity SLAs — no paging exists.**

The severity table is reasonable and the response times are conventional. But there is no on-call
rotation, no PagerDuty/Opsgenie integration, and no alerting policy in the repository. A P1 commitment of
*"<15 minutes initial response"* is currently backed by whoever happens to notice. Committing to this
externally before the paging exists would be the risky step — the table is a target, not a description.

**Outage protocol (offline caching → alert → data lock → UTC replay) — NOT BUILT, all four steps.**

None of the four stages exists. Specifically, the two engineering-heavy ones:

- **Client-side offline caching.** Would require the SDK to detect three consecutive failures, write a
  signed check-in event to the Keychain / EncryptedSharedPreferences, and show optimistic UI. None of
  this exists. Note the security tension the document does not address: **a locally-signed, client-supplied
  timestamp is exactly the client-authoritative input that stage 5 exists to eliminate.** Building this
  means accepting an offline event whose timestamp we cannot independently verify — so it needs a signing
  key the user cannot extract, a bounded replay window (e.g. reject anything older than 48h), and
  deduplication against the identity graph on replay. It is a real project, not a flag.
- **Server-side UTC replay.** Would need `claimDailyEntries` to accept a trusted client timestamp and
  credit a *past* day — today the day key is computed server-side from `todayDateString()`
  (`gatekeeper.ts:752-763`) and there is no path to write a backdated entry. The dedup guards that make
  field 11 safe would all need to be re-reasoned for backdated writes.

**Structured error contracts — PARTIAL.**

The document's first action item is *"structured JSON error responses across all SDK endpoints."* What we
have is a typed **client-side** enum: `WINRError` (`WINRError.swift:10-29`) with 13 cases and
`LocalizedError` descriptions (`WINRError.swift:31+`). That is genuinely useful to publishers — but it is
a mapping applied *after* the fact on iOS, not a wire contract. The server throws `HttpsError` with
Firebase's standard codes and **free-text English messages** (e.g. *"Email confirmation is required
before you can enter."* `index.ts:1150`). There is no stable machine-readable error code in the payload,
so the other three SDKs cannot map errors as richly, and message text cannot be localised or changed
without breaking any client that string-matches it.

**Ryan's Part C checklist, with honest starting positions:**

- [ ] **Structured error contracts** — PARTIAL. Add a stable `code` field to every `HttpsError` payload,
      then map it in all four SDKs rather than only iOS.
- [ ] **Client-side offline storage** — NOT STARTED. Read the security tension above first; this is the
      largest single item in Part C.
- [ ] **Cloud Monitoring + P1 paging** — NOT STARTED. Cheapest item with the highest credibility return;
      an alerting policy on 5xx rate is roughly a day's work and makes the P1 SLA real.
- [ ] **Server UTC replay logic** — NOT STARTED. Depends on offline storage; do not start first.
- [ ] *(added)* **Publish a status page** — NOT STARTED. The document's outage protocol assumes one exists.

---

## Gaps not in the field list

These are not spreadsheet rows, so nobody is tracking them. Two of the four originally logged here are
now closed; both are kept below with their evidence rather than deleted, because the point of this
section is that untracked work stays untracked unless someone writes down where it went.

### ~~1. The 18+ age attestation is never recorded.~~ **RESOLVED — `4cb48af`, shipped in 2.4.0.**

This was the headline legal exposure of the last two passes: the SDK rendered an 18+ checkbox, and the
user's answer went nowhere. Verified closed on every leg:

- **Transmitted.** `submitEmail` now destructures `ageConfirmed` — `index.ts:615`
  `const { email: rawEmail, ageConfirmed, marketingConsent, emailConsent } = request.data as SubmitEmailData;`
  Declared on the wire type at `types.ts:336`. iOS sends it from
  `WINRAPI.swift:313`/`329` (`SubmitEmailRequest`), driven by
  `WINRV2Screens.swift:368` `onSubmit(email.trimming…, isAdult, wantsMarketing)`.
- **Stored, with a timestamp and the wording.** `index.ts:688-691` writes `consent_text_version`,
  `age_confirmed`, `age_confirmed_ts` and `age_consent_text`. Declared `types.ts:147-148`,
  `types.ts:153`. On a cross-device merge the same fields are carried onto the canonical user
  (`index.ts:741-747`), so the record follows the person rather than the handset.
- **Affirmative by construction.** The box is **unchecked by default** —
  `WINRV2Screens.swift:316-317`, *"Unchecked by default — the age gate requires an affirmative action"* —
  and it **gates the CTA**: `WINRV2Screens.swift:325-327` `canSubmit` is `isAdult && email.contains("@")
  && email.contains(".")`, with the button disabled on `!canSubmit` (`WINRV2Screens.swift:371`). This
  is the correct pairing: the marketing box is unchecked by default (changed Aug 2026 per Decision 5) and does *not* gate, the age box is
  unchecked and does.
- **Auditable.** `age_confirmed`/`age_confirmed_ts`/`consent_text_version` are surfaced in the admin
  user view (`admin.ts:115-117`) and CSV export (`admin.ts:457-459`), and never-captured exports as
  blank rather than `false` (see field 3).
- **Backward compatible.** `ageConfirmed`'s *presence* is the 2.4.0+ client tell (`index.ts:622`
  `const isModernClient = ageConfirmed !== undefined;`). A ≤2.3.3 client is handled exactly as before
  and **no age fields are written for it** — the reasoning at `index.ts:617-621` is worth quoting to
  counsel: fabricating *"an affirmation we never received would poison the audit trail."*

**What remains is a decision, not a gap.** `ageGateEnabled` still defaults to `false`
(`index.ts:3805`), and the Master Field List still contains no age field at all. See Decision 6.

### ~~2. `claimBonusEntries` is an orphaned, publicly-callable entry grant~~ — **RESOLVED (`429c235`)**

**Correction to the earlier characterization of this finding.** Previous passes described it as
*"rewarded-video bonus entries are granted without verifying the ad was watched"*, and recommended
ad-network server-side verification (SSV) as the fix. That framing is now wrong in both halves, because
the rewarded-video experience was removed from the SDKs during the V2 rebuild:

- **No SDK calls it.** Re-grepped `claimBonusEntries` across `WINRSDK/`,
  `winr_android_sdk/winrsdk/src/main/`, `winr_web_sdk/src/` and `winr_flutter_sdk/lib/`: the iOS
  request/response structs (`WINRAPI.swift:440-460`), the Android client method (`WinrApi.kt:168-175`)
  and the Web client method (`api.ts:60-61`) all still exist, but **nothing invokes any of them**. The
  Flutter SDK has no trace beyond a `doublingEnabled` field its own comment marks *"legacy — bonus flow
  is parked"* (`giveaway.dart:19`). `rewardedVideoProvider` was removed from `WINROptions`.
- **So there is no ad to skip and no publisher ad revenue at stake.** The old write-up's damage
  statement ("partners are giving up ad revenue on the assumption the ad ran") describes a product
  feature that no longer ships.

**What is actually true is narrower in scope and worse in kind.** The callable is still deployed with
`invoker: "public"` (`index.ts:1409`), and a live query shows **`doublingEnabled: true` on all three
giveaway docs, including both `active` ones** (`Summer Giveaway 2026`, `Test Skape Giveaway`). Its only
gates are that flag, a prior daily entry, and no prior bonus that day (`index.ts:1426-1428`,
`1484-1486`, `1498-1500`).

That leaves an endpoint which **grants a second batch of entries per person per day, in a live
sweepstakes with a real prize, and which no legitimate client ever calls** — so any traffic reaching it
is by definition illegitimate. The endpoint name is discoverable from the **public** SDK repositories,
and a holder of a valid user token can call it directly. One `RV_Bonus` entry exists in production,
consistent with testing from when the flow still shipped.

**The fix was therefore not SSV — it was deletion.** There was no feature left to verify, so building
ad verification would have been work spent defending a door that should simply be bricked up. Closed in
this order, so production was safe before the code changed:

1. `doublingEnabled` set `false` on all three giveaway docs — the endpoint began refusing every call.
2. The callable removed from `index.ts`, leaving a tombstone comment recording why, so it is not
   reintroduced without server-side proof the reward was earned.
3. The function deleted from the deployed project. **Verified:** it is absent from `functions:list` and
   returns HTTP **404**, while `claimDailyEntries` still returns 401 as a control on the probe.
4. Dead client remnants dropped in the same pass — iOS request/response structs, the Android client
   method, response class and the unreachable `StreakEngine.doubleEntries` (plus its two tests), the
   Web client method, and the orphaned response types in both `winr_web_sdk/src/types.ts` and the
   backend `types.ts`. A final grep across all four SDKs and `functions/src/` returns nothing.

266 backend tests green, 77 web tests green, Android compiles and unit-tests clean, iOS builds with
zero errors. **The shipped 2.4.0 binaries were never at risk** — they contain the dead client code but
never called it, and the endpoint they would have called no longer exists. The source-side cleanup
therefore lands in the next release rather than requiring one.

*Secondary defects in the same function, unchanged and moot if it is deleted:* it writes to the
**device** user (`index.ts:1507`) while `claimDailyEntries` writes to the **canonical** user
(`index.ts:1226`), so the two diverge on a multi-device person; and `index.ts:1509` casts
`streakSnap.data()` with no existence check, throwing at `index.ts:1513` for a device-user with no
streak doc.

### ~~3. Marketing consent is captured, has no consumer, and the publisher cannot reach it.~~ **RESOLVED — `4cb48af`.**

The consent signal now has a distinct field, a named consumer, and a delivery path: the checkbox drives
`marketing_consent_status` (`index.ts:679-682`, declared `types.ts:141-142`), the copy names the
publisher and is resolved server-side (`index.ts:507-510`, `index.ts:567-594`), and
`getPublisherUserExport` (`publisherexport.ts:116-244`) hands publishers a consent-filtered,
server-decrypted, audit-logged CSV wired to a real dashboard button
(`avafli-website/src/app/sdk/dashboard/page.tsx:548`). Full evidence in field 2.

Two residues keep this from being *entirely* finished, both narrow and both recorded under field 2:
`marketingConsentedOnly: false` can still pull the non-consented roster, and there is still no
per-publisher marketing-enabled flag. Decision 8 is correspondingly narrowed — see below.

### 4. PII anonymization has two holes — **STILL OPEN**

Not previously listed here, though it has been in mandate 8 since June, and it belongs in this section
because it is nobody's spreadsheet row either. `anonymizeStalePII` (`index.ts:2138-2194`) caps each
nightly run at 400 users and 400 audit logs with no loop (`index.ts:2162`, `index.ts:2180`), so the
3-year guarantee is not actually bounded at scale; and it never touches `prizeClaims`, whose
`firstName`/`city`/`state`/`story`/photo URL are stored in **plaintext** (`prizeclaim.ts:433-449`).
See follow-up 3.

---

## Decisions needed from Scott

| # | Question | Why it matters |
|---|---|---|
| 1 | Daily streak on a missed day — reset to **0** or **1**? | The sheet says both. We built **1**. Open since June |
| 2 | Weekly reset — **Sunday local** or **Sunday UTC**? | The sheet says both. We built **Monday**. Only bites when weekly ships |
| 3 | Are **US territories** eligible? | Our block message promises them; our code blocks them. Prize-claim accepts PR addresses |
| 4 | **SMS** — build it or drop the fields? | Two mandatory spec fields are dormant with no sender behind them |
| 5 | Does the publisher **pass the user's email** from their login, or does WINR always ask? | Column M says publisher passes it; the SDK refuses it by design. Affects consent provenance |
| 6 | **Age 18+** — should the gate be **on by default** for every publisher? | **Narrowed by 2.4.0.** The record now exists: the attestation is transmitted, timestamped, and stored with the verbatim copy shown (see Gaps §1). What is left is a policy question for counsel — `ageGateEnabled` defaults to `false` (`index.ts:3805`), so a publisher who never touches their SDK config gets no gate and therefore no attestation. Also: the spreadsheet still has no age field, and should gain one |
| 7 | **`user_uid`** — migrate to UUID v4, or amend the spec? | Real primary-key migration vs. a one-line spec edit |
| 8 | **Who owns the email list — WINR or the publisher?** | **Narrowed by 2.4.0.** The mechanism now exists (option B is built); what is open is contractual, plus the two residues under field 2. See below |
| 9 | **Certificate pinning** — accept an unpinned claim path, or fund pin rotation? | Mandate 4. Enabling without a rotation policy risks bricking shipped apps |
| 10 | **Firebase App Check** — build the web perimeter, or accept the risk? | Security doc stage 2. Confirmed absent everywhere; it is the single biggest gap against Scott's pipeline |
| 11 | **Do we commit to the 99.9% / 250ms SLA externally?** | Security doc Part C. The targets are plausible; the *operational apparatus* to honour and evidence them does not exist yet |

### Decision 8 in full — who owns the email list?

*Substantially narrowed since the last version of this document — the engineering half was answered by
building it.*

The question was logged in June as *"marketing consent is collected and unused"*, and sharpened at the
last pass to *"there is no mechanism by which a publisher can obtain a user's email address or consent
status from WINR — not a missing filter, a missing path."*

**That path now exists.** 2.4.0 built **option B** below, and built it against the objection this table
raised at the time: the consent copy the user actually sees now names the publisher, resolved
server-side (`index.ts:507-510`, `index.ts:567-594`), so what the publisher receives matches what the
person agreed to. Audit logging, rate limiting and server-side decryption are all in place
(`publisherexport.ts:190`, `:218-231`, `:47-54`).

The three options are kept for the record, restated against what is now built:

| Option | What it means | Status | Notes |
|---|---|---|---|
| **A. WINR owns the list** | Publishers get engagement and giveaway mechanics; WINR holds the consented email relationship and markets to it | Superseded by B, but still selectable — turning the export off is a config decision, not a rebuild | Would require the *sales* framing and the publisher contract to match |
| **B. Consent-filtered publisher export** | A CSV callable returning only that publisher's users with `marketing_consent_status === true` | **BUILT** — `getPublisherUserExport`, `publisherexport.ts:116-244` | Note the filter is `marketing_consent_status`, **not** `email_consent_status` as this table originally proposed. That correction matters: `email_consent_status` is operational and true for everyone who submitted an email, so filtering on it would have exported people who declined marketing |
| **C. ESP integration (WINR pushes, publisher never holds)** | WINR syncs consented contacts into the publisher's Mailchimp / Klaviyo / Braze; the raw list never transits our API | Not built | Still the best privacy posture, and still available as a later upgrade. A design sketch for the real-time variant exists at `functions/docs/PUBLISHER_WEBHOOK_DESIGN.md` (HMAC-signed POST, retry/backoff, delivery log) — design only, nothing implemented |

**What is genuinely still open on Decision 8 — three things, none of them architectural:**

1. **The contract and the DPA.** Building the export does not authorise using it. Whatever the publisher
   agreement says about who holds the email relationship should now be checked against what the code
   actually hands over.
2. **The two residues under field 2.** `marketingConsentedOnly: false` still returns the non-consented
   roster to any caller with dashboard credentials, and there is still no per-publisher
   marketing-enabled flag of the kind columns M/N assume.
3. **The list is still unverified.** Unchanged, and unaffected by 2.4.0: we never confirm an email
   address is real (security-doc stage 3, still NOT BUILT). A consent-filtered export of unverified
   addresses is a better artefact than before, but *"they typed it in and ticked a box"* remains thin
   evidence under CAN-SPAM/CASL. If the marketing proposition is commercially real, double opt-in is
   the next thing to build, not a refinement.

---

## Recommended engineering follow-ups (no decision required)

Ordered by risk. Most are small; items 3, 4 and 11 are not.

> ~~Add the apostrophe to `validateName`.~~ **DONE — `92f76cb`, deployed.** See field 4–5.
> ~~Expose `emailConsentTs` in the admin user view and CSV export.~~ **DONE — `4cb48af`.** See field 3;
> it arrived with the marketing and age fields in the same two surfaces.

1. Strip the phone before encrypting in `submitUserProfile` (`index.ts:1002`) to match `prizeclaim.ts:317`.
2. ~~**Reconcile the ban flag — one key name has to win.**~~ **RESOLVED — fixed and deployed.**
   `enforceBanCheck` (`antispam.ts:92`) and `selectWinner` (`index.ts:1813`) read `isBanned`;
   `types.ts:186` declares `isBanned`; the admin dashboard wrote `banned`
   (`winr-admin/src/lib/firebase-utils.ts:313-315`) and `publisherexport.ts:174` reads `banned`. A
   banned user was excluded from a publisher export but was **still allowed to claim entries and was
   still in the prize draw** — the ban button did not do what its label said. Predates 2.4.0.
   Both enforcement sites now accept either spelling and `banUser`/`unbanUser` write both, so the two
   halves cannot drift apart again. A live query confirmed **zero** users carry either flag, so no
   backfill was needed and nobody had exploited it. Redeployed `claimDailyEntries`, `claimBonusEntries`,
   `submitPrizeClaim` and `selectWinner` — all four share `enforceBanCheck`. Regression tests added to
   `test/claim.test.ts` and `test/select-winner.test.ts`, both seeding `banned` (the field the admin
   actually writes); verified they fail without the fix. **Root cause worth remembering:** the suite
   already had a ban test, but it seeded `isBanned` — it mirrored the implementation instead of the
   operator's action, so it stayed green across the entire life of the bug.
3. Extend `anonymizeStalePII` to `prizeClaims`, and loop until drained rather than stopping at 400.
4. ~~**Remove `claimBonusEntries`, rather than verifying it.**~~ **DONE — `429c235`.** See gap 2.
5. Point `claimBonusEntries` at the canonical user (`index.ts:1507`) and guard the missing-streak-doc
   cast (`index.ts:1509`).
6. Use `localDayUtcWindow` in `getActiveGiveaway`'s sibling check (`index.ts:1698-1699`).
7. Validate `user_timezone` at ingest, or change column N from "reject" to "fall back to UTC".
8. Add an SDK minimum-version floor. The ingest shape is now canonical (`index.ts:241-242`, field 21),
   so a comparator can finally be trusted; the floor itself is still unbuilt.
9. **Strip `encryptionKey` (and `fcmServiceAccount*`, `stripe*`) from the raw publisher doc returned by
   `publisherLogin` (`index.ts:2814`) and `getPublisherDashboard` (`index.ts:2926`).** Both currently
   return `publisherData as any` unfiltered; `types.ts:60-64` shows what can ride along. Small fix,
   crypto-material blast radius.
10. **Close the publisher-export escape hatch.** `marketingConsentedOnly: false` (`publisherexport.ts:129`,
    `:178`) returns users who declined marketing. The dashboard never sends it, but the callable is
    public. Remove the parameter, or gate `false` behind a WINR-side approval. See field 2.
11. **Define a certificate-pin rotation policy BEFORE enabling pinning anywhere else.** This is the
    prerequisite that all three "Disabled until pin rotation is automated" comments are waiting on
    (`DependencyContainer.swift:48`, `:59`, `PushNotificationManager.swift:106`,
    Android `MainActivity.kt:49`). It is a written decision, not a code change, and it must answer:
    - **Which pins?** Leaf, intermediate, or the CA public key. Pinning the leaf breaks on every
      certificate renewal; pinning the Google Trust Services intermediate is the usual answer for
      Cloud Functions and is what the Flutter SDK already assumes (`network/gts_roots.dart`).
    - **A backup pin, mandatory.** Ship at least two hashes — the current key and the next one — so a
      rotation does not require an app release. A single-pin build is a scheduled outage.
    - **Refresh cadence and lead time.** Who checks the pin set before each release, and how many months
      of validity must remain at ship time. An app binary can stay on a user's phone for a year.
    - **A kill switch.** A server-controlled flag that can disable enforcement remotely, so an
      unexpected CA change is a config push rather than an emergency App Store review.

    Until those four are answered, `enablePinning: false` is the *safer* setting, not an oversight —
    **an expired pin bricks the SDK in the field, in binaries we can no longer change.** The honest
    status is "deliberately deferred, undocumented", and this item is to document and then close it.
12. Housekeeping: wire in or delete `isValidEntrySource` (`gatekeeper.ts:160`); fix stale comments at
    `index.ts:1241` ("max 7"), `types.ts:87` ("6 entries"), `types.ts:203-205` ("Sunday"); delete
    `getSundayOfWeek` (`index.ts:125-130`).

---

## Spec corrections to make in the spreadsheet

Cases where the code is right and the document is wrong:

- **Tech Exec Summary §2** — *"The SDK is the Source of Truth for these counters to prevent API spoofing"*
  is backwards. The server is, and must be, source of truth.
- **Column M, `user_email`** — publishers do not pass email via SSO; the SDK captures it.
- **Field 2** — the sheet describes one flag doing two jobs. It is now two fields with two meanings:
  `email_consent_status` (operational; we hold an address, so we may confirm entry and contact a winner;
  no checkbox) and `marketing_consent_status` (the checkbox; the publisher's permission to market;
  gates the export and nothing else). The row should be split, and the sentence *"consent must be true
  before marketing access is allowed"* should name `marketing_consent_status` explicitly.
- **Field 3 name** — the stored key is camelCase `emailConsentTs`, not `email_consent_ts`. Renaming the
  stored field would need a backfill of every user doc; the sheet is the cheaper side to change.
- **New rows needed** — the sheet has **no age field**. It should gain `age_confirmed`,
  `age_confirmed_ts` and `consent_text_version`, which are now captured (Gaps §1).
- **Field 21 format** — `v1.x.x` → `2.x.x`, and note the stored value is deliberately **without** the
  leading `v`; `registerDevice` strips it at ingest (`index.ts:241-242`).
- **Fields 12/13** — marked FUTURE but already built (and parked); the sheet should say so.
- **Field 19** — enum is not just `iOS / Android`; Web and Flutter ship too.
- **Field 18** — the fence is country-level, not state-level; NY/FL are deliberately eligible.
- **Mandate 4** — cert pinning is impossible in the browser; the Web SDK should be an explicit exception.
  *(Note: this is the only part of mandate 4 where the spec is at fault. The rest of the gap is ours —
  see "Mandate 4 in detail".)*
- **Field 23** — `session_token` is a Firebase ID token, not a bespoke WINR JWT.
- **Fields 4–5 regex** — the sheet's `^[a-zA-Z '-]{1,50}$` is ASCII-only and rejects `José`, `Müller`,
  `Nguyễn`. The code is now Unicode-aware (`/^[\p{L}\s'.\-]+$/u`, `gatekeeper.ts:179`); the sheet should
  adopt the code's regex.
- **Security doc, Part A stage 1** — *"1 physical phone = 1 real human"* overstates what a Keychain UUID
  proves. It survives app deletion but not device reset, and nothing binds it to a person. Our real
  cross-device dedup is the hashed-email identity graph (stage 4), not the hardware anchor. The document
  should credit stage 4, not stage 1, for that guarantee.

---

## Plain-English summary for Scott

**Where we stand: of the 23 data fields in the spreadsheet, 9 are fully built and match the spec, 10 are
built but differ from the spec in some detail, 1 was built differently than written, and 3 need a
decision from you. Of the 9 security mandates, 5 are fully done, 3 are partly done, and 1 needs a
business decision. Of your security document's six stages, 2 are genuinely built, 2 are half-built, and
2 don't exist at all.**

**Those headline counts haven't moved since the last version, and I want to be straight about why: two
of the "differs from the spec in some detail" fields got dramatically better this month without quite
earning a clean tick.** In both cases the machine now exists and one detail still doesn't match the
spreadsheet — which is a very different situation from "the machine doesn't exist", but I'd rather not
round it up.

**Fixed since the last version of this review — four things, and one of them was the item I told you to
act on first.**

- **The "I am 18 or older" box now actually records the answer.** This was my number-one concern last
  time: we showed the checkbox and then threw the answer away, so if anyone ever challenged whether a
  winner was old enough, we had nothing. Now, when someone ticks that box, we save that they ticked it,
  *when* they ticked it, and **the exact sentence they were shown**. The box starts unchecked and you
  cannot press the button until you tick it, so it's a real affirmative act rather than a pre-agreed
  default. One deliberate detail worth knowing: for anyone who signed up on an older version of the app,
  we record *nothing* rather than guessing — a blank is honest, a fabricated "yes" would be worse than
  useless in front of a lawyer.
- **Marketing permission now goes somewhere.** Last time I told you we asked people whether they wanted
  marketing email and then did nothing with the answer, and that a partner had no way to get an email
  address out of WINR at all. Both are fixed. There's now a second checkbox — unchecked until the person ticks it, and ticking it
  off doesn't stop anyone entering or winning — that asks specifically for permission to receive
  marketing from *that named partner*. And there's now a button in the partner dashboard that downloads
  exactly those people, as a spreadsheet. The name in the sentence is filled in by our server, not by
  the partner's app, so what they receive always matches what the person actually agreed to.
- **The consent timestamp is visible again.** Last time I flagged that our main legal proof of consent
  was recorded correctly but invisible — you'd have needed an engineer to dig it out. It's now in the
  admin tool and in the exported spreadsheet, along with the marketing and age answers.
- **The name bug is gone** (from the June list). People called O'Brien, D'Angelo, José, Müller or Nguyễn
  can enter their real name. Written, tested, live.

**Also worth a line:** the admin Users page used to show no origin at all — every row looked identical.
It now shows which partner, which app, and which giveaway each person belongs to. That's not a
compliance item, but it's why several of the "you'd need an engineer to look that up" complaints in the
previous version no longer apply.

The important thing first: **the core protections are real and working.** Only people we can confirm are
in the United States can enter — if we can't confirm the location, we block, we don't guess. One person
gets one entry per day even if they use several phones. Personal information is scrambled in the database
and can only be unscrambled by our servers, never by a phone or a web browser. Nobody can fake their
streak from their phone; the server keeps score.

**Eleven things need a decision from you** — the same eleven as last time, but **numbers 6 and 8 have
shrunk a lot**, because the engineering half of each was built this month. These are business or legal
calls, not engineering problems; we can build whichever way you choose.

1. **When someone misses a day, does their streak go back to zero or back to one?** The spreadsheet says
   both in different places. We currently send them back to one, so they aren't fully punished for a
   single miss. This has been waiting since June.

2. **When does the weekly counter reset — Sunday or Monday?** Again the spreadsheet says both, and it
   also disagrees with itself about whether we use the user's local time or a single global clock. We
   currently reset on Monday. This one isn't urgent: the weekly feature is built but switched off, so it
   affects nothing until we turn it on.

3. **Should people in Puerto Rico, Guam, and the US Virgin Islands be allowed to enter?** Right now we
   tell them they're eligible and then block them — the message on screen promises US territories are
   included, but the code only lets in the 50 states. Awkwardly, if they somehow won, our prize form
   would happily accept their address. We need to pick one answer and make both halves agree.

4. **Do we actually want text messaging?** The spreadsheet requires us to collect permission to text
   people, and we do collect it — but there's no texting system behind it, so those permissions just sit
   there unused. Either we build texting or we remove the fields.

5. **Should the app's own login hand us the user's email address?** The spreadsheet tells our partners to
   pass it to us. We deliberately built the opposite: we always ask the user ourselves. The reason is
   that if we ever have to prove someone agreed to hear from us, we want to be the ones who asked. It's
   a reasonable disagreement and you should settle it.

6. **The "I am 18 or older" checkbox — the record now exists; what's left is one narrow question for
   your lawyer.** The hard part is done: we save the answer, the moment it was given, and the exact
   words the person was shown. The remaining question is whether the checkbox should be **switched on
   for every partner by default**. Today it's off unless a partner turns it on, which means a partner
   who never touches their settings collects no age confirmation at all. My instinct is that eligibility
   evidence shouldn't be optional, but that's a legal judgement rather than an engineering one. Two
   smaller things go with it: the spreadsheet still has no age field and should gain one, and if counsel
   wants the wording changed, changing it is now a settings edit rather than an app release.

7. **The ID number we give each user isn't in the format the spec asked for.** It works perfectly well
   and it's unique — it just looks different from what the document specifies. Changing it now means
   carefully renaming the label on every existing user, which is real work for no user-visible benefit.
   My recommendation is to update the document instead, but it's your call.

8. **Who owns the email list — us or our partners? Much smaller than last time, because we built the
   answer.** Last time this was the largest open question in the review: a partner had no way at all to
   get an email address out of WINR, so any "grow your marketing list" pitch had nothing behind it. Of
   the three options I laid out, we've built the middle one — **the filtered export**. A partner can now
   download a spreadsheet of the people who ticked the marketing box for *their* app, and only those
   people.

   The thing I said would need a lawyer's eye — *"the wording the user agreed to has to name the
   publisher"* — was built in rather than deferred. The sentence people see reads *"I agree to receive
   marketing emails from [partner name]"*, and that name is filled in by our server rather than by the
   partner's own app, so a partner can't quietly change what they're claiming consent for. Every
   download is logged with who pulled it and how many rows, it's capped at five downloads an hour, and
   people who opted out or asked to be deleted are excluded.

   **Three things are still open, and none of them is engineering:**
   - **The contract.** Building the export doesn't authorise using it. Whatever our partner agreement
     says about who holds the email relationship should now be read against what the code actually
     hands over.
   - **One loophole I'd close.** The download defaults to marketing-consented people only, and the
     dashboard button always asks for that — but the underlying function will return the *full* list if
     asked directly, which a partner with a valid login could do. It should not be possible to ask.
   - **We still never check that an email address is real.** Unchanged, and unaffected by any of the
     above. We accept whatever is typed. Your security document proposes fixing this with a confirmation
     link, and I still agree — if anyone challenges a marketing consent, *"they typed it in and ticked a
     box"* is thin evidence. If the marketing proposition is commercially real, that confirmation step
     is the next thing to build.

   Worth knowing there's a further option we sketched but did not build: pushing contacts straight into
   a partner's Mailchimp or Klaviyo so the raw list never passes through their hands. Better privacy
   position, more work. The design is written down so the choice stays available.

9. **Should we turn on the extra encryption lock ("certificate pinning") on our phone apps?** This is a
   correction to what I told you in June. I said the only gap was that web browsers can't support it.
   That was incomplete: **it's also switched off on the main iPhone code path** — the one carrying daily
   entries and prize claims. It *is* switched on for sign-up and login. So we've pinned the front door
   and left the delivery entrance open, which is the wrong way round.

   The reason it's off is legitimate and written in the code: turning it on without a maintenance plan is
   dangerous. This lock works by memorising a specific security certificate. When that certificate is
   replaced — which happens routinely — an app that memorised the old one **stops working completely**,
   for every user, and we cannot fix it remotely because the instruction is baked into an app they
   already downloaded. That's a worse outcome than the risk we're guarding against.

   So the ask isn't "turn it on", it's **"decide to fund the maintenance around it"** — a spare backup
   certificate, a calendar for refreshing them, and a remote off-switch. Once those exist, switching it on
   is trivial. Until then, off is the safer setting, not an oversight.

10. **Your security document's web defence ("App Check") doesn't exist yet — and it's the biggest single
    gap I found.** Your analysis of why is exactly right: on a phone we have a hardware anchor, and in a
    browser we have a text box. Today anyone with a script could hammer our sign-up from a desktop. We do
    have speed limits that cap how fast anyone can hit us, and our location check blocks most overseas
    traffic — but those limit *how much* abuse gets through, they don't tell a real person from a robot.
    Building it is real work, so it's your call whether it lands before or after launch — but it should be
    a decision, not a discovery.

11. **Do we promise our partners the 99.9% uptime guarantee in writing yet?** The targets in your document
    are sensible and the severity levels are standard. My concern is that **none of the machinery behind
    them exists.** There's no status page, no automatic alarm if the system starts failing, and nobody on
    a formal on-call rota — so "we respond within 15 minutes" currently means "whoever happens to notice".
    The good news is the cheapest fix has the biggest credibility payoff: setting up automatic alerts is
    roughly a day's work. I'd do that first, measure ourselves quietly for a month, and only then put the
    number in a contract.

**Two things weren't built that nobody has been tracking**, because they aren't rows in the spreadsheet.
**One of them is now fixed; the other isn't:**

- **A retired feature had left a live door open — now closed.** We used to offer "watch a video for extra
  entries". That feature was removed from all four apps in the redesign — no video, no ad, no button. But
  the server function behind it was still switched on, and still marked as enabled on both live
  giveaways. It handed out a second batch of entries per person per day, and because nothing in our apps
  called it any more, anyone reaching it was by definition not a real user. The function's name is
  visible in our public code, and someone signed into the app normally could have called it directly.
  It has been deleted, the flag turned off everywhere, and the removal verified against the live system.
  No real user ever obtained entries this way — the single record from the old flow is a test entry.

  *A note on how this was reported before, because it matters more than the bug.* Earlier versions of
  this review described it as "bonus entries are granted without verifying the ad was watched" and
  recommended integrating ad-network verification. That description was carried forward from before the
  redesign and was no longer true: there was no ad to skip and no partner ad revenue at stake, and the
  recommended fix would have been engineering effort spent protecting a feature that no longer existed.
  The real answer was to delete it.

- **Our automatic three-year deletion of old personal data has two holes.** It cleans up a fixed amount
  each night, so if we grow quickly the queue could grow faster than we clear it. And it doesn't touch
  the prize-claim records at all — winners' names and addresses currently stay forever.

**On your security document specifically**, here is the honest scorecard, because I'd rather be blunt
than encouraging:

- **Two stages we genuinely have.** Your "hashed identity hub" — stitching someone's phone and laptop
  into one person using a scrambled version of their email — is built and is the thing actually stopping
  people entering twice from different devices. And your "server-side referee" is built: the phone never
  calculates anything that matters, our servers do. These two are real, and together they're the backbone.
- **Two stages that half-exist.** The phone anchor is weaker than the document claims: we do store an ID
  in the phone's secure area, but nothing proves it's a genuine phone rather than a script pretending to
  be one — that would need Apple's and Google's app-verification services, which we haven't integrated.
  And the "suspicious user" flag is stranger than it looks: **we write the flag, and then nothing ever
  reads it.** A user we've flagged is still fully eligible to win. The document says flagged users get
  quarantined out of the prize draw; that isn't true of our code today. It's a small fix, but it's a
  decision, because auto-excluding on suspicion will occasionally catch an innocent person on a VPN.
- **Two stages that don't exist at all.** App Check (decision 10 above), and the email confirmation link
  (folded into decision 8).
- **Your error and outage plan**: two of the five failure situations are properly handled — someone
  hammering us too fast, and a duplicate entry arriving twice. The two that need the *phone app* to cope
  gracefully are missing entirely: **if our server is down, the app has nowhere to save the entry, so the
  user's streak action is simply lost.** The document's promised message "Your streak is safe!" would
  currently be untrue, and I'd rather not ship a reassurance we can't honour. Building that properly is a
  real project, not a switch — it means trusting a timestamp that came from the user's phone, which is
  the exact thing our anti-cheating design exists to avoid, so it needs care.
- **The domain and Cloudflare plan (Part B) is sound and I have no objections.** It's my task list, not
  an engineering one — it needs my registrar access, not code. Keeping the domains at GoDaddy until the
  prepaid money runs out and routing through free Cloudflare in the meantime is the right sequence.

**One bug that isn't tidying, found while checking the new work — now fixed.** The "ban user" button in
our admin tool **didn't actually ban anyone.** It wrote the ban down under one label, and the parts of
the system that decide who may enter and who goes into the prize draw both looked for a *different*
label. So a user banned for cheating could still claim entries every day and could still be drawn as a
winner. Nothing about it was new — it predated all of this month's work — but nobody had noticed, because
the admin screen showed the ban as applied.

It is now corrected and live: the ban button writes both labels, and every place that enforces a ban
accepts either. **Nobody actually slipped through** — we checked the live database and no account has
ever been banned, so this was a trap waiting rather than damage already done. Two tests now cover it.
Worth knowing *why* it survived: the existing test suite tested the ban using the label the code reads,
so it passed while the button that real staff press wrote the other one — a reminder that a test which
mirrors the code instead of the user's action can hide exactly this class of bug.

**A handful of genuinely small bugs**, all quick fixes: phone numbers get saved in two different formats
depending on which screen you're on; and our partner dashboard is handed a bit more of its own account
record than it needs, including an old unused encryption key. Neither has leaked anything — they're
tidying. (The consent-timestamp complaint from last time is gone: it's in the admin tool now.)

**Finally, a few places where the code is right and the documents are wrong.** The most important: the
spreadsheet says the phone app should be the "source of truth" for streak counts. That's backwards — if
the phone keeps score, a determined user can simply tell us they're on day 500. We built it so the server
keeps score, which is the safe way round. The document should be corrected so nobody "fixes" it back.
Smaller, in your security document: "one phone equals one real human" is more than a stored ID can
promise. What actually delivers that guarantee is the hashed-email stage, and the document should give
the credit there instead — otherwise we'll trust a protection that isn't holding the weight we think.

## Addendum — 3.0.0 brand rename: wire-value governance (2026-08-25)

The WINR → Avafli rebrand shipped as a coordinated 3.0.0 breaking release across all four SDKs.
This section is the registry of which wire-level values changed, which deliberately did not, and
what compatibility every future change must preserve. Amend this section — not per-platform code
comments — when any of these values changes again.

**Renamed in 3.0.0 (canonical values now `avafli_*`):**
- Publisher-facing analytics event names: `avafli_registration`, `avafli_experience_opened`,
  `avafli_experience_closed`, `avafli_daily_entry_claimed`, `avafli_bonus_entry_claimed`,
  `avafli_streak_milestone`, `avafli_prize_won`, `avafli_winner_claim_shown`,
  `avafli_prize_claim_submitted`, `avafli_badge_earned`, `avafli_opted_out`,
  `avafli_email_verified`, `avafli_adoption_restaged`. (2.9.x clients still emit `winr_*`;
  the backend neither validates nor aggregates event names, so both coexist harmlessly.)
- Share-link attribution: `utm_medium=avafli_share` (was `winr_share`; no live publisher history
  existed at rename time).
- Guest identity minting: new ids are `avafli_guest_<uuid>`. Persisted `winr_guest_*` ids are
  returned verbatim forever — stored identity is NEVER rewritten.
- API key minting: `avafli_test_` / `avafli_live_` prefixes. Resolution is by database lookup, not
  prefix, so existing `winr_test_` / `winr_live_` keys remain valid indefinitely.
- Sender display names: "Avafli Rewards" (user-facing) / "Avafli Team" (publisher-facing).
  Addresses remain on winrmedia.com until the planned avafli.com email migration.

**Deliberately NOT renamed (stability contracts — do not "fix" these):**
- All on-device persistence: iOS keychain service `com.winr.sdk` + `winr_*` keys/UserDefaults,
  Android `winr_preferences`/`winr_secure_prefs` files + keys, web `winr_*` localStorage keys.
  Renaming any of these orphans identity/streaks/opt-outs on upgrade from 2.9.x.
- Legal-doc URLs: winrmedia.com/sdk/privacy + /sdk/rules are baked into shipped 2.9.x binaries and
  must keep serving until the sdk.avafli.com migration completes AND no referencing binaries remain.
- Delete-bridge signals: the privacy page emits `winr://delete` (native) and `{type:"winr-delete"}`
  (web postMessage). 3.0.0 SDKs accept BOTH old and new (`avafli://delete`, `avafli-delete`)
  signals; the page keeps emitting the old form until 2.9.x is extinct.
- Firebase project id `winr-9c11f`, cloud-functions hostnames, storage bucket — infrastructure ids,
  not brand surfaces.
