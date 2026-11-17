# Go live

Ordered steps for CF. Nothing in this file is a secret, and none of these steps have been run for you. Do not take a real payment until the last smoke test passes.

The binary version in `project.yml` is **1.4.0**. `notarize-dmg.sh` therefore writes `SimpleDictation-1.4.0.dmg`. That build is the paid line (14-day trial, $4.20 Stripe unlock, v1 users grandfathered). Publish it as the **v1.4.0** release. Do not tag it `v2.0.0` unless you also change `MARKETING_VERSION`, or the DMG name and the tag will disagree.

## What the purchase path does

1. `site/buy.html` sends the buyer to the Stripe Payment Link `https://buy.stripe.com/4gMdR987h9mtchK2sCg360q`.
2. Stripe POSTs `checkout.session.completed` (and, for a delayed payment method, later `checkout.session.async_payment_succeeded`) to the Worker.
3. The Worker checks the signature, that the event is live mode, that `payment_link` is the `plink_` id you configured, and that `payment_status` is `paid`. One session inserts one `SD42-…` key.
4. Resend emails the key. The redirect lands on `thanks.html`, which reads Stripe's `session_id` query parameter and polls `GET /v1/order`.
5. The buyer pastes the key into Settings, License. The app calls `POST /v1/activate` once, checks the returned `SD1-` token offline (Ed25519, embedded public key), and stores it.

A card sale is fulfilled on `checkout.session.completed`. A bank debit or other delayed method sends `checkout.session.completed` while still unpaid (the Worker ignores it) and `checkout.session.async_payment_succeeded` when the money clears (the Worker mints the key). Subscribe to both.

## Sparkle

Sparkle is **not shipped**. `project.yml` has no Sparkle package. There is no `SUFeedURL`, no `SUPublicEDKey`, no appcast, and no Check for Updates menu. This launch does not add any of that. A buyer gets a later version by downloading a new DMG. v1.3.0 has no updater either, so it cannot be nagged into the paid build.

## 1. Deploy the Worker that is in this repo

The webhook code is not live until you deploy it. From a checkout of this branch, after it is merged:

```bash
cd license/worker
npx wrangler d1 execute simpledictation-licenses --remote --file=schema.sql
```

That re-applies `schema.sql`. It is idempotent. It creates `idx_licenses_stripe_note` if the remote database was created before that index existed, so one checkout session cannot mint two keys.

Set these secrets with `npx wrangler secret put <NAME>`. Paste the value when prompted. Do not write the values into a file in this repo.

| Name | Required for a paid key to arrive | What it is |
| --- | --- | --- |
| `ED25519_PRIVATE_KEY_B64` | yes, to sign the token | Already set if Reddit keys activate. base32 PKCS8 from `gen-keys.mjs`. |
| `STRIPE_WEBHOOK_SECRET` | yes | `whsec_…` signing secret of the **live** endpoint you create in step 2. |
| `STRIPE_PAYMENT_LINK` | yes | `plink_…` id of the $4.20 Payment Link. Not the `buy.stripe.com` URL and not the slug `4gMdR987h9mtchK2sCg360q`. |
| `RESEND_API_KEY` | yes | Resend API key. |
| `ALERT_FROM` | yes | A sender on a domain you have verified in Resend, for example `SimpleDictation <keys@yourdomain>`. The default `onboarding@resend.dev` only delivers to the Resend account owner, not to buyers. |
| `ALERT_EMAIL` | yes | Your inbox. Used when a buyer email does not send. |
| `ADMIN_TOKEN` | to look a key up by hand | Already set if the admin page works. |
| `IP_SALT` | no | Hashes IPs in the activation log. |
| `PUBLIC_KEY` | no | Makes `POST /v1/validate` check signatures. The app does not call that route. |

Do **not** set `STRIPE_ALLOW_TEST_MODE`. Unset, the Worker ignores `livemode: false` so a test-mode endpoint pointed at production cannot mint keys.

Public vars already in `wrangler.jsonc` (not secrets): `KID`, `SKU`, `ALLOWED_ORIGINS`, `RATE_LIMIT_PER_MIN`, `DOWNLOAD_URL`. `ALLOWED_ORIGINS` already includes `https://cfranci.github.io`. Add any other site origin or the thank-you page cannot read the key.

`DOWNLOAD_URL` is `https://github.com/cfranci/SimpleDictation/releases/latest`. Leave it if step 5 has already made v1.4.0 the Latest release. If a sale can happen before that, set `DOWNLOAD_URL` to the v1.4.0 asset URL so the email does not hand the buyer the free v1.3.0 DMG.

Then publish this repo's Worker:

```bash
npx wrangler deploy
```

`secret put` also rolls a deployment. Run `deploy` last so the script that is live is the one in this repo.

## 2. Register the Stripe webhook in live mode

In the Stripe Dashboard, switch the toggle to **Live**, then Developers, Webhooks, Add endpoint.

- Endpoint URL: `https://simpledictation-licenses.api-king.workers.dev/v1/stripe/webhook`
- Events: `checkout.session.completed` and `checkout.session.async_payment_succeeded`
- Copy that endpoint's signing secret into `STRIPE_WEBHOOK_SECRET` (step 1) and deploy again if you created the endpoint after the first deploy.

Use the live-mode secret. A test-mode endpoint has a different secret and will not verify. After the live payment in step 7, the endpoint should show a 200 response whose body is `fulfilled`.

## 3. Confirm the Payment Link

On the same **Live** toggle, open the Payment Link behind `https://buy.stripe.com/4gMdR987h9mtchK2sCg360q`.

- Mode is live. A test-mode link's URL contains `/test/`. This URL does not, and the dashboard toggle still has to say Live while you edit it.
- Price is **$4.20 USD**, one time. Not a subscription.
- Email address is required. The Worker emails `customer_details.email`.
- After payment, redirect to `https://cfranci.github.io/SimpleDictation/thanks.html`. Leave Stripe's `session_id` query parameter on. That page reads `session_id`. A Stripe-hosted confirmation page alone never shows our key.
- Copy the Payment Link's `plink_…` id into `STRIPE_PAYMENT_LINK`.

Do this before you publish the site, or the redirect target 404s. The canonical URLs in `site/index.html` and `site/buy.html` already point at `https://cfranci.github.io/SimpleDictation/`, which 404s until step 7.

## 4. Sign, notarize, and staple the DMG

On your Mac, with a Developer ID Application certificate in the keychain. One time:

```bash
xcrun notarytool store-credentials SD-notary \
  --apple-id YOU@EXAMPLE.COM \
  --team-id TEAMID \
  --password APP_SPECIFIC_PASSWORD
```

The release command is `notarize-dmg.sh`. It builds Release, signs with Developer ID and hardened runtime (`SimpleDictation-dist.entitlements`, which already includes the library-validation exception), submits to the notary service, staples the app, builds the DMG, and staples the DMG:

```bash
./notarize-dmg.sh SD-notary
```

Check the ticket and Gatekeeper:

```bash
xcrun stapler validate SimpleDictation-1.4.0.dmg
spctl -a -vvv -t install SimpleDictation-1.4.0.dmg
```

`./build-dmg.sh` is the other script. It builds an ad-hoc DMG and clears quarantine on that Mac. It does **not** notarize. Do not upload that file.

The public site does not say the download is notarized. Put that sentence back only after step 7 shows no Gatekeeper warning. The sentence, for the "Is this on the Mac App Store?" answer in `site/index.html`:

> v1.4.0 is notarized and Developer ID signed, so it opens with no security warning.

## 5. Publish the v1.4.0 release and mark v1.3.0 as legacy

Create a GitHub Release.

- Tag: `v1.4.0` (this becomes Latest only if it is not a prerelease).
- Title: `SimpleDictation 1.4.0`
- Asset: the stapled `SimpleDictation-1.4.0.dmg` from step 4. Not the `build-dmg.sh` output.
- Notes: 14-day trial, then Apple Speech stays free. $4.20 once unlocks Whisper, Moonshine, and Whistle on two Macs. v1.3.0 users who already used the app stay unlocked. Not a subscription. Link the buy page once the site is up.

Mark v1.3.0 as legacy without removing it:

- Leave the tag `v1.3.0` and the asset `SimpleDictation-1.3.0.dmg` in place: https://github.com/cfranci/SimpleDictation/releases/tag/v1.3.0
- Edit that release's notes so the first lines say it is the last fully free build, it is not notarized, it is not a trial, and the maintained build is 1.4.0.
- Do not delete it, do not draft it, and do not mark 1.4.0 as a prerelease. Publishing 1.4.0 moves GitHub's Latest badge off 1.3.0.

## 6. Publish the site

GitHub Pages' branch source only serves `/` or `/docs`. The site lives in `site/`, which is why `https://cfranci.github.io/SimpleDictation/` 404s.

1. Repo Settings, Pages, Build and deployment, Source: **GitHub Actions**.
2. After step 5, run the **Deploy site** workflow (`.github/workflows/pages.yml`, `workflow_dispatch`). It uploads `site/` as the Pages root. It does not run on every push, so the site does not go live before the DMG exists.
3. Confirm these return 200, not 404:
   - `https://cfranci.github.io/SimpleDictation/`
   - `https://cfranci.github.io/SimpleDictation/buy.html`
   - `https://cfranci.github.io/SimpleDictation/thanks.html`

## 7. Clean-Mac smoke test

Use a Mac that has never built this app. Download the release DMG in a browser. Do not copy a build off the machine that notarized it.

1. Open the DMG, drag SimpleDictation to Applications, and open it from Applications. There is no "developer cannot be verified" warning. If there is, the asset is not the stapled DMG. Stop and redo step 4.
2. Grant Microphone, Accessibility, and Speech Recognition.
3. A premium engine runs during the trial.
4. Pay $4.20 on the live Payment Link with a real card. You land on `thanks.html?session_id=cs_live_…` and the key is on the page within a few seconds. The same key arrives by email. Stripe's webhook delivery for that event is 200 `fulfilled`.
5. Settings, License, paste the key, Activate. Quit, turn Wi-Fi off, open the app again. It stays licensed.
6. https://github.com/cfranci/SimpleDictation/releases/tag/v1.3.0 still downloads.

A grandfather check needs a Mac that already ran v1 and wrote a real preference (`dictationLocale`, `floatingMicSize`, `incrementalMode`, `clipboardCyclingEnabled`, or `enabledModifiers`). That Mac should be licensed with no key. A factory-fresh Mac should not be.

## Tests before you deploy

```bash
node --test license/worker/purchase.test.mjs
```

That drives a signed `checkout.session.completed` through key minting, the buyer email, `/v1/order`, `/v1/activate`, and the offline token check the app performs.
