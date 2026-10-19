# Production monitoring

Health checks and alerting for the Avafli backend. Set up 6 Aug 2026.

## Health endpoint

`GET https://healthz-755bc53xgq-uc.a.run.app` — unauthenticated, no secrets in the
body. Returns **200** healthy / **503** degraded.

```json
{"status":"ok","checks":{"geo":{"ok":true,"maxmindLoaded":true,"lastFailureReason":null},
 "firestore":{"ok":true}},"at":"2026-08-06T02:02:31.825Z"}
```

It deliberately checks the **geo subsystem**, not just liveness. The geo-fence fails
closed, so a geo data-source failure denies every claim while the functions themselves
still answer normally — a plain ping stays green. This endpoint reports that state
as degraded.

## Alerts → `alertWebhook` → admin dashboard (Monitoring page + Command Center)

Since 15 Oct 2026 the four Cloud Monitoring policies deliver to the `alertWebhook`
function (token in Secret Manager), which writes `incidents/{id}`; the admin shows open
incidents on the Monitoring page and as a Command Center attention item. The personal
Gmail channel was removed the same day. Ops email for claims/draws/expiries is separate
(`emailbrand.ts getOpsRecipients`, overridable in `config/notifications`).

| Policy | Fires on | Why it exists |
|---|---|---|
| Health check failing | `/healthz` non-200 for 5 min, from 3 US regions | Catches geo/Firestore degradation that leaves the service superficially up |
| Entry path erroring | Non-2xx rate > 0.2/s for 10 min on `claimDailyEntries`, `submitEmail`, `submitPrizeClaim` | The paths a user feels: earning entries, giving an address, claiming a prize |
| Scheduled job failed | Any ERROR from `anonymizeStalePII` or `sendStreakReminders` | These jobs have no user-visible symptoms when they stop; a missed retention run breaks the 3-year deletion commitment |
| Geo-fence degraded | `geo_fence_inconclusive` or a `[geo] CRITICAL` log line | Direct signal for geo data-source failure, faster than the 5-minute uptime window |

Each policy carries runbook text in its `documentation` field — visible in the alert
email itself, so the first thing to check is in front of whoever is woken up.

## The Monitoring page (admin.avafli.com/monitoring)

Since 15 Oct 2026 the page is fed by `adminGetOpsMetrics` (contract:
`functions/docs/OPS_METRICS_SPEC.md`): per-hot-path traffic from Cloud Monitoring, vCPU
in use vs the regional Cloud Run quota, SendGrid/Twilio health, a last-hour funnel,
alert acknowledgement (`adminAckIncident`, audit-logged), scheduler next-run + per-job
run history, SDK version drift and backup/PITR state. Each section degrades to an inline
note when its probe fails; nothing there replaces the alert policies above.

## Known gaps

- **No public status page.** Alerts reach us; they do not tell publishers anything.
- **Admin monitoring page** at `/monitoring` in the admin dashboard shows live health,
  scheduled-job freshness, anti-fraud counters and the draw policy. It is a read
  surface for a human reacting to an alert, not a replacement for the alerts.
- **No paging.** Email only — no SMS, no rota, no escalation. Fine for one person on
  one timezone; not an SLA.
- **Delivery is proven for ryannapp@gmail.com** — a test alert was fired and landed
  (6 Aug 2026). `rnapolitano@avafli.com` and `spopowitz@avafli.com` were added
  afterwards and have NOT been confirmed end to end; unlike the first, they are not
  the project owner's address, so if GCP requires verification it will be for these.
  Fire one test alert and confirm all three receive it.

Run this for a month and measure before putting a 99.9% number in a contract.

## Changing it

Policies live in Cloud Monitoring, not in this repo — edit in the console or via the
`monitoring.googleapis.com/v3` API. They were created by API rather than by hand so
they can be recreated from this document.

## Launch pre-warm SOP (large publisher pushes)

Measured in `functions/docs/LOAD_TEST_RESULTS.md` runs 5–7: the only thing that fails under
a 0 → N step of traffic is Cloud Run instance start-up. Warm instances answer
`getActiveGiveaway` at ~25–28 req/s each; a cold instance takes several seconds to start
(MaxMind load + module init) and the overflow is refused with 429/500 "no available
instance". The SDKs (web ≥3.2.2, Flutter/iOS/Android ≥3.2.1) retry those refusals on a
jittered 1/2/4/8 s schedule, so a user sees a short delay rather than an error — but the
right answer is to not be cold.

Before any publisher push notification or campaign start:

1. Estimate first-minute request rate per hot path (`registerDevice`, `refreshToken`,
   `getActiveGiveaway`, `claimDailyEntries`, `submitEmail`). Rule of thumb: pushed users ×
   open rate ÷ 60 s, and every open calls `getActiveGiveaway` once.
2. Set `minInstances` on each hot path to **expected RPS ÷ 25**, rounded up, at least an
   hour ahead (`HOT_PATH` in `functions/src/index.ts`, then deploy those five functions).
   Cloud Run's per-service ceiling is 200 instances (`maxInstances`); above ~5,000 RPS per
   path a quota increase is required first.
3. Confirm the deploy actually applied the setting on every one of the five (Firebase's
   mutation quota can silently skip functions): `gcloud run services describe <fn>
   --region us-central1 --format 'value(spec.template.metadata.annotations)'`.
4. After the spike, lower `minInstances` back to 0 — each warm instance bills about $7 a month
   even when idle (ten of them tripped the $20 project budget in October 2026). The first
   request after an idle period then pays a 2–5 s cold start, which the SDKs' retry absorbs.
