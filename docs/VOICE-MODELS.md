# SimpleDictation — New Voice Model Research (Nov 2026)

Research captured on branch `feature/dictation-engine-upgrades`. No app code changed
yet — this is the plan to build against.

Current engines wired today: **Apple Speech**, **Whisper** (tiny/base/small/medium,
distil-large-v3, large-v3-turbo via WhisperKit/CoreML), **Moonshine** (tiny-en),
**Whistle** (Cactus Needle).

---

## Latest & greatest speech-to-text models

macOS dictation engines are on-device ASR models. The 2026 landscape has moved well
past Whisper — six open models now beat Whisper on the Open ASR Leaderboard. Ranked
by fit for THIS app (native Swift, on-device, low latency):

### Tier 1 — build this

**NVIDIA Parakeet TDT 0.6B v3** — the standout for a Swift menu bar app.
- ~6.18% avg WER (English Open ASR Leaderboard, Oct 2026); #1 for *throughput*.
- 25 European languages + Japanese.
- **Native Swift path: FluidAudio** (`github.com/FluidInference/FluidAudio`) — a
  CoreML SDK that runs Parakeet TDT v3 **on the Apple Neural Engine**
  (`computeUnits = .cpuAndNeuralEngine`, no GPU fallback). Reported **2.6× faster
  than MLX** on the same model. CoreML weights at
  `huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml`.
- Why it fits: a Swift Package with CoreML models — same shape as the existing
  WhisperKit integration. Faster + more accurate than Whisper large-v3-turbo. Highest
  impact engine to add; several Mac dictation apps made Parakeet v3 their *default*
  model in 2026.
- Caveat: batch/chunk model, not token-by-token streaming (fine — the app already
  transcribes-on-stop for Whisper/Moonshine and runs a parallel Apple recognizer for
  live captions).

### Tier 2 — strong, heavier or multilingual

**NVIDIA Canary-Qwen 2.5B** — #1 *accuracy* (~5.63–5.94% WER), English. Best raw
accuracy open-source. 2.5B params = heavier RAM/latency than Parakeet. Good as an
optional "max accuracy" model.

**Qwen3-ASR (0.6B / 1.7B)** — Alibaba, Jan 2026. Beats Whisper-large-v3 across many
languages/datasets. Runs on Apple Silicon via `mlx-qwen3-asr` (MLX, not CoreML/ANE —
slower than the FluidAudio path). Best pick if multilingual accuracy is the goal.

### Tier 3 — true streaming (live dictation / captions)

**Mistral Voxtral Mini 4B Realtime** — transcribes *while you talk*, configurable
delay 80ms–1200ms (Mistral recommends 480ms). Voxtral 3 family shipped Oct 2026. MLX
port exists. The one to watch if we want the caption HUD to stream from the main
engine instead of the parallel Apple recognizer.

**Kyutai STT** — streaming, CC-BY-4.0. 1B en/fr @ 0.5s delay; 2.6B en @ 2.5s delay
(6.4 WER). Clean streaming option, smaller than Voxtral.

### Tier 4 — already have / footprint king

**Moonshine** — already wired (tiny-en). Still the on-device *latency/size* leader
(smallest model ~27MB). Could add Moonshine Base for a small accuracy bump.

---

## Recommendation

Add **Parakeet TDT 0.6B v3 via FluidAudio** as a new engine (ANE, fast, SOTA-ish,
Swift-native, mirrors the WhisperKit pattern). Optionally expose **Canary-Qwen** as a
"max accuracy" model and keep **Voxtral Realtime** on the roadmap for streaming
captions.

Sources: Hugging Face Open ASR Leaderboard; `FluidInference/FluidAudio`;
`nvidia/parakeet-tdt-0.6b-v3`; MarkTechPost "Best Open ASR Models 2026";
Mistral Voxtral 3 (Oct 2026); Kyutai STT.

---

## Whistle (bundled now) vs Parakeet TDT (proposed) — they're complementary

The app already bundles **Cactus Whistle** (`WhistleManager`, a 16.9 MB `.cact`
through the Needle C engine). It is the opposite end of the spectrum from Parakeet
TDT — keep both, don't replace.

| | **Cactus Whistle** (bundled) | **Parakeet TDT 0.6B v3** (proposed) |
|---|---|---|
| Size | **16.9 MB**, bundled, no download | ~600M params, hundreds of MB, downloaded |
| Compute | **CPU-only** — runs on *any* Mac incl. Intel | Apple **Neural Engine** via FluidAudio (Apple Silicon only) |
| Architecture | log-mel → conv stem → 8 conformer encoder + 8 Needle decoder blocks (gated cross-attention), 2–4-bit quant | FastConformer encoder + **TDT** (Token-and-Duration Transducer) decoder |
| Accuracy | 4.31% WER LibriSpeech test-clean (beats Whisper *base*) | ~1.93% on that same set; 6.18% avg on the hard 8-dataset leaderboard (beats Whisper *large-v3*) |
| Latency | first token ~**11 ms** on a 10s clip | huge real-time factor on ANE (~3,000×+), ~2.6× faster than MLX |
| Languages | 7 (en/de/fr/es/it/nl/pl) | 25 European + Japanese |
| Deps | none — single `.cact` | FluidAudio Swift package + CoreML weights |

**What "TDT" is:** Token-and-Duration Transducer. Unlike Whisper (autoregressive
transformer, steps frame-by-frame, can hallucinate text in silence), TDT predicts
each token *plus how many audio frames it spans* and jumps ahead by that duration —
~10× faster, silent during silence, native word timestamps. Whistle is also
conformer-based on the encoder, but its decoder is Cactus's Needle cross-attention
decoder, not a transducer.

**Verdict:** keep **Whistle** as the zero-dependency universal default/fallback
(the only engine needing no download and no Apple Silicon); add **Parakeet TDT** as
the premium high-accuracy engine for Apple Silicon. Lineup becomes:
Apple (system) · Whistle (tiny/universal) · Parakeet TDT (accurate/Apple Silicon) ·
Whisper/Moonshine (legacy options).

Sources (comparison): Cactus Whistle (hyper.ai, Cactus-Compute/whistle);
Parakeet TDT vs Whisper (MacParakeet); `nvidia/parakeet-tdt-0.6b-v3`.

---

> Copy-on-select is a separate feature tracked on its own branch
> `feature/copy-on-select` (`docs/COPY-ON-SELECT.md`).
