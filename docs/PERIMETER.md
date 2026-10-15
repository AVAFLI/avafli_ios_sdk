# Browser perimeter defence

Shipped 6 Aug 2026, in **monitor mode**. Nothing is refused yet.

## Why not Firebase App Check

On a phone there is a hardware-backed attestation anchor; in a browser there is a
text box. App Check still does not fit how this SDK is deployed:

1. **None of the four SDKs bundle a Firebase client SDK.** They call our HTTPS
   endpoints directly. App Check would push a Firebase dependency into every
   publisher's app — a large ask of an integrator whose app may not use Firebase.
2. **App Check attests the calling app against OUR project.** Every publisher app
   would need registering in `winr-9c11f` with its bundle id and signing
   certificate, turning a one-line SDK install into a per-publisher, per-platform
   provisioning handshake.

The real gap is the browser. This closes that gap directly, and imposes nothing
on mobile integrators.

**Mobile attestation (App Attest / Play Integrity) remains open** and is a real
decision: worth doing, and it costs every publisher a dependency. Not taken
unilaterally.

## What ships

- **reCAPTCHA Enterprise, score-based** (no challenge, no user-visible badge
  interaction), site key `6Lc5NHgtAAAAAJT6dO3XqcOEL_dDXzO5GvVvC5L_`.
- Web SDK mints a token bound to the `register` action and attaches it to
  `registerDevice`. **It never blocks**: a publisher CSP that forbids Google, an
  offline first load or a slow network all degrade to "no token" and registration
  proceeds.
- Backend scores it and **logs every web registration**, enforcing or not.

## Turning enforcement on

Every web registration already logs a line like:

```
[perimeter] {"event":"web_perimeter","action":"register","reason":"no_token",
             "score":null,"minScore":0.5,"enforcing":false,"wouldRefuse":true}
```

`wouldRefuse` is the exact count of registrations enforcement *would* have refused.
Read that for a week before enforcing — a perimeter that starts by blocking is one
that discovers its false-positive rate on real users.

Then set `config/perimeter`:

```
{ "enforce": true, "minScore": 0.5 }
```

`minScore` is clamped to `(0, 1)`, so a config typo cannot accept everything or
reject everyone. An unreadable config, missing secret, or reCAPTCHA outage all fail
**open** — deliberately, since none of those are the user's fault — which is why
the verdict is logged on every call rather than only on refusal.

## Known limits

- **The site key allows all domains.** We do not know publisher domains in advance.
  Per-publisher domain restriction is possible later and would be a real tightening.
- **Only `registerDevice` is scored.** That is the signup entry point a script would
  hammer. `submitEmail` and `claimDailyEntries` are already behind an authenticated
  session and the fail-closed geo-fence.
- **No mobile attestation** — see above.
