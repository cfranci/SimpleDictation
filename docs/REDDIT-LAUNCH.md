# SimpleDictation Reddit Launch (100-key giveaway)

Adapted from the armada marketing-ops section to the system we actually built: self-issued SD42 codes in your own Cloudflare D1, redeemed once against your Worker, tracked in your admin page. Keys look like `SD42-XXXX-XXXX-XXXX`, each good for 2 Macs.

## Distribution: hybrid, not a raw dump

Do not paste all 100 codes in the post. They get scraped in minutes and drained by a few greedy grabs, and you learn nothing. Instead:

- Post about 10 codes publicly, labeled "first come, these go fast." This proves the giveaway is real and rewards fast readers.
- Hold the other ~90 behind "comment and I will reply with a code." One human, one code, visible username, and every redemption shows up in your admin page.
- When the batch runs low, edit the post: "All giveaway keys claimed, thank you. v1.3.0 is free forever, or grab the maintained build for $4.20." Do not delete the post, it becomes a search asset.

Your real backstop is not secrecy. Each code caps at 2 activations server-side, redemptions are visible in your admin page, and you can revoke a code (stops future activations, never bricks an already-activated Mac). At $4.20 with a free version one click away, the goal is reach and goodwill, so do not sweat the occasional greedy grab.

## Where and when

- r/macapps is the anchor. Post there first, Saturday 9 to 11am ET. Stay in the thread the first 2 hours and reply fast.
- Then stagger r/MacOS (lead with the workflow), r/apple (lead with privacy, only if you actively participate there), and r/productivity (lead with the outcome) over the next 2 to 3 days. Rewrite the title each time, never paste the same title twice.
- Do NOT cross-post to r/deals or r/freebies. App giveaways there read as hostile marketing.

## The post (r/macapps)

```
Title: I made SimpleDictation, on-device voice to text for Mac. $4.20 once, and I am giving away 100 free keys

Hey r/macapps,

SimpleDictation is a tiny menu bar app for macOS. You hold a key, you talk, and your
words appear right at your cursor in whatever app is focused: Slack, Notes, a code
editor, a browser text box, anywhere. No window to switch to, no cloud.

The part I actually care about: your voice never leaves your Mac. All ten speech engines
run 100 percent on-device and fully offline. Nothing is uploaded, there is no account,
and there is no telemetry. Turn off Wi-Fi and it works exactly the same. It even filters
out the "thank you for watching" style noise other engines invent when you pause, so you
never paste garbage.

When you finish speaking it puts the text on your clipboard and pastes it at your cursor
with a single Cmd+V, which is how it drops text into basically any app. That is also why
it asks for Accessibility permission on first launch.

It is $4.20 one time. Not a subscription. Wispr Flow is $15 a month and sends your voice
to the cloud. I wanted the opposite: one coffee, once, and your voice stays on your Mac.
It is also source-available, so you do not have to take my word on the privacy claim, you
can read it.

Giveaway: I have 100 free license keys for launch. Here are the first ones, first come
first served, these go fast. Each key works on up to 2 of your Macs.

    SD42-XXXX-XXXX-XXXX
    SD42-XXXX-XXXX-XXXX
    (about 10 real codes here, four-space indented so Reddit renders them monospace)

If one above is already claimed, comment below and I will reply with a fresh one while
they last.

How to redeem a key:
1. Download the build at https://cfranci.github.io/SimpleDictation
2. Click the menu bar mic icon, choose Enter License
3. Paste your SD42 code and click Activate. It activates once online, then works
   offline forever.

Prefer no key? v1.3.0 is free forever at https://github.com/cfranci/SimpleDictation/releases,
and you can build the current app from source for free.

macOS 14 or later. Happy to answer anything about the on-device models, the privacy
design, or why the price is $4.20. Support is chaseefrancis1@gmail.com.
```

## Alternate titles (rewrite per sub, space 24 to 48h apart)

- r/MacOS: `Hold a key, talk, and the text appears at your cursor in any app. Fully offline, $4.20, free keys inside`
- r/apple: `On-device voice to text for Mac, your audio never leaves the machine. Source-available, $4.20`
- r/productivity: `I dictate into every app now instead of typing. On-device, no subscription, giving away launch keys`

## Comment replies to keep ready

- Trust / keylogger question: "Fair question for anything that pastes into your apps. It is fully on-device, your audio never leaves the Mac, and the whole app is source-available so you can read every place it touches the clipboard. https://github.com/cfranci/SimpleDictation"
- Handing out a key: "Here you go: SD42-XXXX-XXXX-XXXX. Download at https://cfranci.github.io/SimpleDictation, menu bar mic, Enter License, paste, Activate. Each key works on 2 Macs."
- A key did not activate: "That one may have hit its 2-Mac cap or been claimed. Reply and I will send a fresh one, or email chaseefrancis1@gmail.com."

## Operator flow

1. Deploy the Worker + D1 and seed the 100 keys (see LICENSE-SYSTEM.md). Nothing below works until the keys are live in D1.
2. Open the admin page, confirm 100 unused keys, use "Copy all unused as Reddit list" to grab codes, and paste about 10 into the post.
3. As people comment, copy a fresh unused code per person. Watch redemptions climb in the admin page.
4. Revoke any code that is obviously being resold (future activations only).

## Before you post

- The keys only work after the Worker is deployed and D1 is seeded. Do not post codes before that.
- Commit a LICENSE (PolyForm Noncommercial) before claiming "build it yourself is free," or soften to "source is public."
- v2 needs the Enter License menu item shipped (this build adds LicenseManager and the menu wiring; it still needs to be compiled into the release DMG).
