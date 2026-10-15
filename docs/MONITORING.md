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

## Alerts → ryannapp@gmail.com, rnapolitano@avafli.com, spopowitz@avafli.com

| Policy | Fires on | Why it exists |
|---|---|---|
| Health check failing | `/healthz` non-200 for 5 min, from 3 US regions | Catches geo/Firestore degradation that leaves the service superficially up |
| Entry path erroring | Non-2xx rate > 0.2/s for 10 min on `claimDailyEntries`, `submitEmail`, `submitPrizeClaim` | The paths a user feels: earning entries, giving an address, claiming a prize |
| Scheduled job failed | Any ERROR from `anonymizeStalePII` or `sendStreakReminders` | These jobs have no user-visible symptoms when they stop; a missed retention run breaks the 3-year deletion commitment |
| Geo-fence degraded | `geo_fence_inconclusive` or a `[geo] CRITICAL` log line | Direct signal for geo data-source failure, faster than the 5-minute uptime window |

Each policy carries runbook text in its `documentation` field — visible in the alert
email itself, so the first thing to check is in front of whoever is woken up.

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
