---
name: eink-android-tuning
description: Diagnose and speed up refresh on old Android e-ink devices (i.MX EPDC readers, modded Kindles, Boyue/Onyx/Nook/Tolino) — measure panel time on-device, find who picks the waveform, adapt KOReader, fix blurry text after fast refresh. Use when a user asks to make an e-ink Android device faster, clearer, or to adapt KOReader / a reading app to it.
---

# E-ink Android tuning

Read these from the repository root before touching the device:

1. `AGENTS.md` — workflow: identify device → measure panel time → find who decides the waveform → choose global vs per-app → fix visual quality → verify with the user.
2. `docs/pitfalls.md` — known traps (ioctl "success" that does nothing, per-device waveform numbering, dangerous ioctls, KOReader refresh ordering, silent font fallback).
3. `docs/case-study.md` — a full worked example (Kindle Migu KFBJWI, 450 ms → 272 ms).

Rules of thumb:

- Measure before optimizing; trust only panel-side evidence (EPDC LUT activity), never ioctl return codes.
- Change one variable at a time and record how to undo it.
- Screenshots cannot show e-ink artifacts; finish with a user acceptance checklist.
- Talk to the user in their language and explain trade-offs plainly.
