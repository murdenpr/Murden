# Murden

MATLAB code for running a head-fixed mouse odor cue-conditioning task on the [Bpod](https://github.com/sanworks/Bpod_Gen2) platform, and for extracting and analyzing behavioral data (lick detection from video, session exports, and lick rasters).

Every script is annotated line by line with plain-language comments, so the code can be followed without prior MATLAB or Bpod experience.

## Repository structure

### `Bpod_Protocol/` — task control (runs on the Bpod rig)

| File | Purpose |
|---|---|
| `CueConditioning.m` | Main Bpod protocol: probabilistic odor cue-conditioning task with reward, omission, airpuff, and unpredicted-outcome (blank) trials |
| `UrnModel.m` | Builds the session's trial sequence and outcomes ("urn" sampling without replacement, balanced within trial chunks) |
| `PreviewTrialSequence.m` | Prints the planned trial sequence to the command window before the session starts |
| `ExpTimer.m` | Draws each trial's ITI from a truncated exponential distribution with a set mean |
| `AirPuff.m` | Configures the Global Timers that control airpuff pressurization and release |
| `TTLGlobalTimer.m` | TTL pulse timer (BNC1); the number of pulses per trial encodes the outcome type for photometry alignment |
| `BNCTrigger.m` | Photometry trigger pulse (BNC2) at the start of the session |
| `PIB_LED_Flash.m` | IR LED sync flash (camera-visible) plus a matching TTL pulse, used to sync video to Bpod |
| `load_odor_serial_messages.m` | Loads the valve module commands used to open/close odor and airpuff valves |
| `PlotSessionProgress.m` | Live, trial-by-trial session plot during a run |
| `ExpTimerTest.m` | Test script: checks that `ExpTimer.m` produces the target mean ITI |
| `VerifyBlankITIAdjustment.m` | Test script: checks the shortened ITI before Blank trials using recorded session data |

To run the protocol, place these files in `Bpod Local/Protocols/CueConditioning/`.

### `Data_Analysis/` — offline analysis

| File | Purpose |
|---|---|
| `Extract_raw_data.m` | Step 1 of the lick pipeline: syncs video to the Bpod clock using IR LED flashes, extracts motion traces from a lick ROI, and detects Bpod pauses |
| `Analyze_lick_data.m` | Step 2 of the lick pipeline: detects licks, assigns them to trials, and plots cue-aligned rasters and lick rates |
| `plotLickRasterByOdor.m` | Lick rasters by odor, using the Bpod lick port events |
| `ExportSessionChronological.m` | Exports every state and event in a session to a spreadsheet, in chronological order |
| `Convert_Jpeg_To_mp4.m` | Converts a folder of numbered camera frames into an .mp4 video |

**Status:** the video-to-Bpod sync in `Extract_raw_data.m` is working reliably. Separating genuine licks from other motion (whisking, paw movement) is still in active development, so lick detection thresholds and filters will continue to change.

## Requirements

- MATLAB R2023a or later
- Signal Processing Toolbox (`findpeaks`), Statistics and Machine Learning Toolbox (`robustfit`), Image Processing Toolbox (`drawrectangle`, `imshow`)
- [Bpod_Gen2](https://github.com/sanworks/Bpod_Gen2) (for the protocol files)
- [FFmpeg](https://ffmpeg.org/) (for the video-file option in `Extract_raw_data.m`)
- `make_blank_fig.m`: a figure helper called by `CueConditioning.m` that is not included in this repository
- Optional: `cprintf` (MATLAB File Exchange) for colored output in `PreviewTrialSequence.m`; plain text is printed without it

## Credits

- `CueConditioning.m` is built on the `ProtocolTemplate.m` skeleton from the [Sanworks Bpod_Gen2 repository](https://github.com/sanworks/Bpod_Gen2) (© Sanworks LLC, GPL-3.0).
- The original cue-conditioning task code that `CueConditioning.m` and `load_odor_serial_messages.m` were developed from was written by **[ORIGINAL AUTHOR — TO BE CONFIRMED]**. It was substantially extended by Philip Ryan Murden (2025–2026), adding urn-model trial sequencing, airpuff outcomes, truncated-exponential ITIs, TTL outcome encoding, IR LED video sync, and a live session plot.
- Colored command window output uses `cprintf` by Yair Altman (MATLAB File Exchange).
- All other scripts were written by Philip Ryan Murden.

## License

GPL-3.0 — see [LICENSE](LICENSE).
