# SimpleDictation docs

Index of the planning and operations docs. These were produced during the v2 commercialization pass.

**Launch procedure:** [GO_LIVE.md](GO_LIVE.md). Payments are the Stripe Payment Link, fulfilled by the license Worker. Lemon Squeezy is not used. Sparkle is not in the app. The DMG is not notarized yet. Price is $4.20 once, the trial is 14 days, and v1.3.0 users are grandfathered.

## Launch and strategy
- [GO_LIVE.md](GO_LIVE.md) - the ordered checklist to take real payments. Start here.
- [LAUNCH.md](LAUNCH.md) - July launch plan. Where it disagrees with GO_LIVE.md, GO_LIVE.md wins.
- [DISTRIBUTION.md](DISTRIBUTION.md) - why direct download and not the Mac App Store, with the launch checklist.
- [BRAND-COPY.md](BRAND-COPY.md) - name, taglines, feature copy, pricing framing, FAQ, launch blurbs.
- [SYNTHESIS.md](SYNTHESIS.md) - cross-section reconciliation and open questions from the armada pass.

## Payments and licensing
- [LICENSE-SYSTEM.md](LICENSE-SYSTEM.md) - the shipped key system: deploy and operate runbook (D1 + Worker + admin page).
- [LICENSING-PAYMENTS.md](LICENSING-PAYMENTS.md) - July design notes. The shipped provider is Stripe, not Lemon Squeezy. Sparkle was not added.

## Marketing ops
- [REDDIT-LAUNCH.md](REDDIT-LAUNCH.md) - the 100-key giveaway playbook: distribution, post copy, reply templates.
- [ASSETS-RUNBOOK.md](ASSETS-RUNBOOK.md) - how the screenshots and demo video were captured.

## Operations
- [CRONS.md](CRONS.md) - scheduled jobs the system needs (rate-limit sweep, redemption digest, backups, health).
