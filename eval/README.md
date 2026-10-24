# Photo check tuning set

Scores the on-device photo check (Apple's classifier, see `docs/decisions/004`) against real photos,
to tune the thresholds. The photos stay on your Mac: `eval/photos/` is gitignored.

## Take about 20 photos

Use the normal iPhone Camera app (back camera) and AirDrop them to the Mac into `eval/photos/`.

| How many | What | `target` | `expect` |
|---|---|---|---|
| 8 | The real target, from a normal distance (2 each: bench, tree, bicycle, street sign) | the target | `accept` |
| 2 | The real target, awkward: far away, half in frame, at dusk | the target | `accept` |
| 4 | A **different** object (a fan, a car, a wall, your shoes) | e.g. `bench` | `target_not_seen` |
| 4 | A photo of the target **on a screen**: a laptop, a TV, another phone; close-up too | the target | `looks_like_screen` |
| 2 | Very dark or very blurry shot of the target | the target | whatever you think is fair |

## Screen close-ups (pixel-pattern check)

The classifier can't tell a real object from the same object on a screen that fills the frame
(24 Oct: "bottle 0.43, screen 0.00"). The pixel-pattern check looks for the screen's pixel grid
instead. Use `"target": "any"` for these photos so only the screen checks count.

| How many | What | `expect` |
|---|---|---|
| 10 | A photo of an object **shown on a screen**, close enough that the screen fills the frame: 3 on a laptop, 3 on another phone, 2 on a TV/monitor, 2 extra close | `looks_like_screen` |
| 5 | **Real** objects close up: water bottle, mug, plant, shoes, fan | `accept` |
| 5 | **Real but regular textures** (the likeliest false alarms): window blinds, a keyboard, striped fabric, a fence or radiator, a brick wall | `accept` |

## Run

```bash
cp eval/cases.example.json eval/cases.json   # then list your photos in it
tools/eval-photos/run.sh
```

It prints each photo's verdict, the confusion matrix (true/false positives and negatives), and where the real targets and screens sat. Use those to adjust `minTargetConfidence` / `maxScreenConfidence` in `PhotoChecks.swift` and the same values in `supabase/functions/_shared/decision.ts`. The sync test fails if only one copy is changed.

Goal: **0 screen photos let through** and **≥ 80% correct overall**. Record the numbers in `docs/PROGRESS.md`.
