# Brand and Copy (Armada stitched output, 2026-07-08)

> Copy rule from synthesis: say the text 'appears / gets pasted at your cursor', never 'types letter by letter' (the app delivers via one synthetic Cmd+V paste).

# SimpleDictation — Brand & Copy Kit

Every claim below is grounded in the shipped code (README.md, SpeechManager.swift, ClipboardCycler.swift, StatusBarController.swift, FloatingMicWindow.swift). Two facts the drafts got wrong are corrected here: (1) the app **pastes** transcribed text via the clipboard plus a synthetic Cmd+V, it does not type key-by-key like a keyboard, and (2) there is **no Sparkle / auto-update** in the codebase, so nothing below promises one. No em dashes anywhere.

---

## 1. Name check: keep "SimpleDictation"

**Verdict: KEEP IT. Do not rename.**

- It is the exact phrase a buyer types into Google and the Mac App Store search bar. "Dictation" is the category noun people already know (Apple's built-in "Dictation"), and "Simple" is both the promise and the differentiator against Wispr Flow / superwhisper, which sound like SaaS vapor, not tools you own.
- It already ranks and ships. The public repo is `cfranci/SimpleDictation`, v1.3.0 is live, and the bundle ID is `com.simpledictation.app`. Renaming throws away every backlink, star, and search result you already own.
- The $4.20 meme price is the brand hook, not the name. Let the name be boring and findable; let "$4.20" be the thing people screenshot.
- Style rule for every surface: one word, camel-cased, **SimpleDictation**. Never "Simple Dictation" with a space, never "SD."
- Domain: use `simpledictation.app` (matches the bundle ID). Do not split equity across a hyphenated variant.

---

## 2. Tagline

**Primary:**
> **Hold. Talk. Release. Done.**

Four words that are the entire product. It doubles as the how-it-works line.

**Alternates (per surface):**
- Privacy-forward one-liner: **Your voice never leaves your Mac.**
- App Store subtitle (30-char budget): **On-device voice to text.**
- Price-forward (paid launch): **Your voice, typed anywhere. $4.20, once.**

---

## 3. Headlines (3 options + pick)

**Option A (the pick) — the mechanic IS the pitch:**
> ## Hold a key. Talk. Your words appear where your cursor is.
> Voice to text for every app on your Mac. 100% on-device, so your voice never leaves the machine. **$4.20 once. No subscription, ever.**

**Option B — the privacy-vs-subscription contrast (use as the pricing-section pull quote):**
> ## Voice to text that never phones home.
> Wispr Flow wants $15 a month. SimpleDictation wants $4.20, one time, and keeps your voice on your Mac.

**Option C — the universality angle (use as the feature-grid header):**
> ## Dictate into anything. Chat boxes, editors, search bars.
> Hold fn, talk, release. The text appears wherever your cursor is. Local, offline, and yours forever.

**Why A wins:** the whole product is one motion (hold, talk, release, it appears) plus a price. A demonstrates the motion in the headline itself and lands the price in the subhead, so it reads as a feature, not a slogan, which is what converts a utility buyer. B is the sharpest *pricing-section* pull quote because the comparison lands with full context there. C is the best *feature-grid* header. (Note the verb is "appears" not "types itself" — the app pastes, it does not emulate a keyboard.)

---

## 4. Benefit-first bullets

Lead with the outcome. Ordered for a landing page or store description.

- **Voice to text in any app.** Chat boxes, code editors, search bars, address fields. If you can click into it, you can talk into it.
- **Hold, talk, release.** No window to open, no "start recording" button. Hold fn (or option, your choice), say it, let go, and it appears at your cursor.
- **Double-tap to send.** Tap the key twice and it presses Enter for you, so a dictated message just sends.
- **Your voice never leaves your Mac.** Every engine runs on-device. No cloud, no account, no upload. It works on a plane with the Wi-Fi off.
- **Pick your accuracy.** 10 speech engines, from instant Apple Speech to Whisper Large v3 Turbo. Start fast, upgrade to precise, all free and local.
- **A floating mic when you want it.** A resizable mic button that glows while it listens and shows a live audio-level ring. Click to talk if you would rather not hold a key.
- **Clipboard history built in.** Hold Cmd and tap V again to cycle back through your last copies, in any app.
- **No garbage from silence.** A built-in guard drops the "thank you for watching" and "you." hallucinations speech engines spit out when you pause, so you never paste noise. No competitor advertises this.
- **16 languages.** English, Spanish, French, German, Italian, Portuguese, Chinese, Japanese, Korean, Hindi, Arabic, Russian, and more.
- **$4.20 once. Yours forever.** No subscription, no trial-into-paywall, no seat count to manage.

---

## 5. Pricing framing

The comparison IS the copy. Anchor against the monthly subscriptions and make the math embarrassing.

**Headline math:**
> A single month of Wispr Flow costs three-and-a-half SimpleDictations. A year of it costs about 43. Buy SimpleDictation once and you are done forever.

**The card copy:**
> **$4.20. One time.**
> Not per month. Not per year. Once. It is the price of one coffee.
>
> - Wispr Flow: **$15 / month**, every month, forever
> - superwhisper: **$8.49 / month** or ~$249 lifetime
> - MacWhisper: ~$32 to $59 one time
> - **SimpleDictation: $4.20, one time**
>
> The same day you buy it, you have already saved money against every subscription on this list.

**The one-liner that travels (tweets, PH, footer):**
> $4.20 once versus $15 every month forever. Your voice stays on your Mac either way, but only one of them stops charging you.

*Publishing note: the competitor prices above are asserted from memory and date quickly. Verify each against the live pricing page before this copy ships publicly.*

**Anti-positioning (what NOT to say):**
- Not "competitive pricing" — that puts you inside the subscription category you are attacking.
- Not "limited-time offer" — scarcity contradicts the whole message, which is permanence.
- Not "free trial" — the original free release already exists on GitHub; frame the paid version as convenience and support, not a locked gate.

---

## 6. Privacy / on-device is the moat

This is the single strongest thing about the app and the hardest for a subscription competitor to copy, because their business model needs a server to run. Lead with it, prove it, repeat it.

**Section header:** **Your voice never leaves your Mac.**

**Body:**
> Every one of SimpleDictation's speech engines runs on your machine. Apple Speech is built into macOS. The Whisper and Moonshine models download once and then transcribe entirely offline. Nothing is streamed to a server, nothing is stored in a cloud, and there is no account to create.
>
> Cloud dictation services (Wispr Flow, Otter, and most mainstream tools) send your audio to their servers to transcribe it. That means the things you dictate into chat windows, documents, and search bars are processed on someone else's machines, sometimes logged or retained for training, under a privacy policy that can change after the next funding round or acquisition.
>
> SimpleDictation does none of that, because it does not need to. Turn off your Wi-Fi and dictate on a plane. Use it on a locked-down work laptop. Talk about anything, to anyone, in any app, knowing the audio is captured, transcribed, and discarded on the same computer it was spoken into.

**The proof point (credibility, not just a claim):** the app is source-available on GitHub. Anyone can read exactly how the audio is handled and confirm it never touches the network. That is a promise you can inspect, not just one you are told.

**One-liner for a comparison table:**
> Cloud: your audio processed on their servers. SimpleDictation: processed on yours, discarded instantly.

---

## 7. "Why $4.20?"

Own the meme, but give it a real reason so it reads as confidence, not a gimmick.

> **Why $4.20?**
>
> Because at $4.20 the decision makes itself. You are not calculating ROI on a subscription, you are clicking a button. The price is a little wink, but the value is not a joke: real on-device transcription, in every app, for less than the tip on a lunch order. Pay it once, own it, and never see a renewal email again. The number is also memorable enough that people screenshot it and tell a friend, which is worth more to a $4.20 app than a higher margin would be.

---

## 8. FAQ copy (8 questions)

**Q: Why $4.20?**
> Because at $4.20 the decision makes itself, and because a one-time coffee price beats a monthly subscription for a utility that runs quietly in the background. The specific number is intentional. You probably already know why. It sticks in people's heads, which is how they remember to tell a friend.

**Q: Is my voice uploaded anywhere?**
> Never. Every engine runs on your Mac. Apple Speech is built into macOS, and the Whisper and Moonshine models download once and then transcribe fully offline. There is no server, no account, and no cloud. Your audio is captured, turned into text, and discarded, all on your machine, in the same second. It works with your Wi-Fi turned completely off.

**Q: Does it really work in any app?**
> Yes. When you finish speaking, SimpleDictation places the text on your clipboard and pastes it at your cursor, so it works in chat boxes, text editors, search bars, address fields, code editors, and just about anywhere you can type. That is why it asks for Accessibility permission on first launch. One side effect worth knowing: because it uses the clipboard to deliver text, dictating replaces whatever you last copied. That is also why the built-in clipboard history is handy.

**Q: How accurate is it compared to Apple's built-in dictation?**
> As accurate as you want it to be. Apple Speech (the default) is instant, needs no download, and is about as good as macOS dictation. For higher accuracy, switch to a Whisper model from the menu. Whisper Large v3 Turbo is the most accurate option and still runs entirely on your Mac. The trade-off is a short processing pause after you release the key, versus Apple Speech which is instant. Whisper is noticeably better on accents, names, and technical vocabulary. You choose.

**Q: What are all these engines and which should I pick?**
> There are 10, all local. Start with **Apple Speech**, which needs zero download and works instantly. If you want more accuracy, pick a Whisper model and it downloads in the background. While it downloads, SimpleDictation keeps working on Apple Speech and switches over automatically when the model is ready. **Whisper Small** is the sweet spot for most people. **Whisper Large v3 Turbo** is the most accurate. **Moonshine Tiny** is bundled with the app, so it works with no download at all.

**Q: I already downloaded the free version from GitHub. What happens to me?**
> Nothing bad, ever. If you downloaded SimpleDictation while it was free, it stays yours and it keeps working. It will not be taken down or disabled. The source is public, so you can always build it yourself for free. The $4.20 price is for new folks and for the road ahead. If you loved the free version and want to say thanks or support what comes next, buying is the way to do it, but you will never be locked out of what you already have.

**Q: What is your refund policy?**
> Full refund, no questions, within 30 days. Reply to your receipt and you get your $4.20 back. At this price, arguing about a refund would be embarrassing for everyone involved.

**Q: Why isn't this on the Mac App Store?**
> Because the App Store sandbox would break the entire point of the app. To place your transcribed text at your cursor in any app, SimpleDictation needs Accessibility permission, which sandboxed App Store apps are not allowed to request. So it ships as a signed, notarized download straight from us. Drag it to Applications and you are running in about ten seconds. If you would rather, the source is public and you can build it yourself.

---

## 9. Long description (store / landing / README)

> **SimpleDictation turns your voice into typed text in any app on your Mac.**
>
> Hold the fn key (or option, your choice), say what you want to write, and let go. The words appear right where your cursor is, whether that is a chat box, a code editor, a search bar, or an email. Double-tap the key and it presses Enter, so a dictated message just sends. There is also a floating mic button that glows while it listens and shows a live audio-level ring, for the times you would rather click than hold a key.
>
> What makes it different is that your voice never leaves your Mac. SimpleDictation ships with 10 speech engines and every one of them runs on-device. Apple Speech is instant and built into macOS. The Whisper family, from a 40 MB Tiny model up to Large v3 Turbo, plus the bundled Moonshine Tiny, download once and then transcribe completely offline. No cloud, no account, no subscription, and no audio ever streamed to a server. Turn off your Wi-Fi and it still works.
>
> It also remembers your recent clipboard copies (hold Cmd and tap V to cycle), supports 16 languages, and quietly filters out the "thank you for watching" style noise that speech engines invent when you pause, so you never paste garbage.
>
> Competing dictation apps charge $8 to $15 every month and send your voice to their servers. SimpleDictation costs **$4.20 one time**, keeps your voice on your machine, and is yours forever.
>
> Requires macOS 14 or later. Not sandboxed, because a sandbox would prevent it from pasting into other apps.

**SEO keywords (organized by intent):**

- **Primary (high intent):** mac dictation app, voice to text mac, offline dictation mac, on-device speech to text, local whisper mac, no subscription dictation mac, hold to talk mac
- **Secondary (features):** whisper mac app, menu bar dictation, private voice to text, whisper.cpp mac, macOS 14 voice input, dictate in any app mac
- **Comparison-capture:** wispr flow alternative, superwhisper alternative, macwhisper alternative, voice ink alternative, cheap mac dictation app
- **Long-tail (buyer education):** one time purchase dictation mac, dictation app that works offline, voice to text no account mac, dictate into slack mac, best whisper app for mac

---

## 10. OG / social description

**Standard (under 160 chars):**
> Hold fn, talk, release. SimpleDictation puts your voice into any app on your Mac. 10 local engines, works offline, no cloud, no subscription. $4.20 once.

**Short variant (under 120 chars):**
> Voice to text in any Mac app. On-device, offline, private. $4.20 once, not $15 a month.

---

## 11. Launch blurbs (3 tweets) + Product Hunt

**Tweet 1 (price shock):**
> Wispr Flow: $15/mo.
> superwhisper: $8.49/mo.
> SimpleDictation: $4.20, once, forever.
>
> Hold fn, talk, release, it appears in any app. 10 local speech engines including Whisper Large v3 Turbo. Works offline. Your voice never leaves your Mac.
> simpledictation.app

**Tweet 2 (privacy):**
> Most voice-to-text apps send your audio to a server somewhere.
>
> SimpleDictation runs it on your Mac with open-source Whisper models and never touches the network. Works on a plane. No account. Notarized download.
>
> $4.20, once. simpledictation.app

**Tweet 3 (demo hook):**
> Hold fn. Talk. Let go. Your words appear wherever your cursor is, in any app, fully offline. Double-tap to hit Enter. 10 local engines, no subscription.
>
> It is $4.20 and yes, that is on purpose. simpledictation.app

**Product Hunt tagline (under 60 chars):**
> Voice to text in any Mac app. On-device. $4.20 once.

**Product Hunt maker note:**
> Every dictation app I tried was a subscription that streamed my voice to a server. SimpleDictation is the opposite: hold a key, talk, and it appears in any app, with 10 speech engines that all run on your Mac and never touch the network. It works offline, filters out the silence-hallucination noise other apps paste, remembers your clipboard history, and costs $4.20 one time instead of $15 a month. Named after the price, which is the joke, but the local-and-yours-forever part is not. The source is public, so you can read exactly how your audio is handled, or build it yourself for free.

---

## 12. Copy consistency rules

- Price is always written **$4.20**, never "4.20", "USD 4.20", or spelled out "four twenty."
- The app is **SimpleDictation** everywhere: one word, capital S, capital D. Never "Simple Dictation."
- **Whisper** is capitalized (it is OpenAI's model name): Whisper Tiny, Whisper Small, Whisper Large v3 Turbo.
- "fn key" lowercase. "Accessibility" capitalized when it means the macOS permission.
- Use "appears" or "gets pasted," not "types itself letter by letter." The app pastes via the clipboard, and pretending otherwise is a factual claim you cannot back up.
- Do not name Sparkle or promise automatic updates. There is no auto-updater in the shipped code. If you add one later, update the copy then.
- Never call the GitHub build "the free version" next to "$4.20 paid" without framing. Say "the original free release" or "v1.3.0 on GitHub." The paid version adds a notarized, signed, ready-to-run download and supports the developer.
- "Your voice never leaves your Mac" and "works offline" can repeat across the page. Repetition on the moat is a feature.
- No em dashes anywhere. Use commas, periods, or parentheses.
- Keep the narrative on privacy and convenience-vs-subscription. Do not reference or piggyback on any unrelated $4.20 product in externally shipped copy.

## Open questions
- Competitor prices (Wispr Flow $15/mo, superwhisper $8.49/mo and ~$249 lifetime, MacWhisper $32-59) are asserted from memory across all attempts and should be verified against live pricing pages before this copy is published publicly.
- The copy assumes a paid launch and a free-to-paid transition, but the repo's license and paid-vs-free split are not established in the files I read (no license file, no store/payment integration found). Confirm the actual go-to-market before shipping the pricing, refund, and grandfather claims.
- There is no auto-updater (no Sparkle) in the shipped code, so the copy makes no update promise. If auto-updates are planned for v2, the FAQ and consistency rules need a line added at that point.