# Scheduled jobs (crons) SimpleDictation needs

Two are already wired into the license Worker. The rest are recommended, with the schedule and what each needs, in priority order. Times are UTC (09:00 ET = 13:00 UTC).

## Already wired (Cloudflare Cron Triggers on the license Worker)

These live in `license/worker/worker.js` (the `scheduled` handler) and `license/worker/wrangler.jsonc` (`triggers.crons`). They activate automatically when the Worker is deployed. The email ones no-op until you set the `RESEND_API_KEY` and `ALERT_EMAIL` secrets, so they ship dark.

- **Rate-limit sweep** — hourly (`0 * * * *`). Deletes expired rows from the `rate_limits` table so it cannot grow without bound. Pure D1, no config, always runs. (The Worker also sweeps opportunistically on each activation; this covers quiet periods.)
- **Low-inventory key alert** — hourly (`0 * * * *`). When unused keys drop to `LOW_KEY_THRESHOLD` (default 10) or below, emails you so you can generate more from the admin page or edit the Reddit post before the giveaway runs dry.
- **Daily redemption digest** — 09:00 ET (`0 13 * * *`). Emails how many keys were redeemed in the last 24 hours and how many remain. Your giveaway pulse.

To turn the email jobs on after deploy:
```
cd license/worker
npx wrangler secret put RESEND_API_KEY     # your Resend key (RESEND_API_KEY_APIKING)
npx wrangler secret put ALERT_EMAIL        # chaseefrancis1@gmail.com
# optional: npx wrangler secret put ALERT_FROM   # a verified Resend sender; default is onboarding@resend.dev
# optional: set LOW_KEY_THRESHOLD in wrangler.jsonc vars (default 10)
```

## Recommended next (not yet built)

### 1. D1 database backup (P0 before you promote the giveaway)
D1 is the single source of truth for which keys exist and who redeemed them, and the free plan has no self-serve point-in-time restore you would want to rely on. A daily job should export `licenses` + `activations` and stash them off-database.
- Where: add to the Worker `scheduled` daily branch, writing a CSV/JSON snapshot to an R2 bucket (add an R2 binding to wrangler.jsonc), or a small local launchd job that calls `/admin/export.csv` and commits the file somewhere private.
- Schedule: daily, `0 13 * * *` (piggyback the digest tick).
- Needs: an R2 bucket on API KING, or a local cron with the admin token.

### 2. Health check (P1)
Catch a broken site, buy link, or Worker before a customer does.
- What: fetch the site root, `buy.html`, the Stripe link, and the Worker `/` health route; alert on any non-200.
- Where: cleanest as a separate tiny Worker or an external monitor (UptimeRobot, or your existing endpoints health pattern), so it does not depend on the thing it is checking. Could also be the license Worker hitting the others.
- Schedule: every 15 to 30 minutes.
- Needs: the same Resend secret, or a monitoring service.

### 3. Stripe to license delivery (P1 once paid sales matter)
Right now a $4.20 Stripe purchase charges the card and thanks the buyer, but does not auto-send a key. The correct primary mechanism is a Stripe webhook (event-driven, not a cron). A reconciliation cron is the safety net.
- What: poll Stripe for `checkout.session.completed` in the last hour, and for any paid session without an issued key, mint one (a `paid` batch code) and email it.
- Where: the Worker, or a dedicated small Worker with the Stripe secret key.
- Schedule: every 15 minutes as a backstop to the webhook, or hourly.
- Needs: Stripe secret key as a Worker secret, and the license mint path (already in the Worker).

### 4. Sparkle appcast reachability (P2, once auto-update is live)
A broken appcast silently stops every user from updating.
- What: fetch the appcast XML and the latest DMG URL, verify 200 and that the enclosure parses.
- Schedule: daily.
- Needs: the appcast URL (once Sparkle ships).

### 5. Credential expiry reminders (P2)
- Apple Developer ID cert and notarization credentials expire annually; the API KING Cloudflare token and the Resend key can be rotated. A monthly job that checks expiry dates and reminds you avoids a surprise broken release.
- Schedule: monthly, `0 13 1 * *`.
- Needs: nothing beyond the dates; simplest as a local reminder or a calendar entry.

## What does NOT need a cron
- License verification in the app is fully offline after the one-time activation, so there is no server round-trip to schedule.
- Whisper model downloads happen on-device from Hugging Face on demand; no server job.
- Rate-limit sweeping during active traffic is already opportunistic in the Worker.

## Note on Cloudflare limits
The free plan allows a handful of cron triggers per account. All the Worker-side jobs above share the single `scheduled` handler and branch on `event.cron`, so they count as the schedules listed in `triggers.crons`, not one per task.
