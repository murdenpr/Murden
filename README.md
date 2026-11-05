# Ryan Murden - Bpod and Data Analysis Code

MATLAB code for running a head-fixed mouse odor cue-conditioning task on the [Bpod](https://github.com/sanworks/Bpod_Gen2) platform, and for extracting and analyzing behavioral data (ROI pixel data from video, session/timing exports, and lick analysis).

Every script is annotated line by line with plain-language comments, so the code can be followed/understood without prior MATLAB or Bpod experience.

## Repository structure

### `Bpod_Protocol/` — task control (runs on the Bpod rig)

| File | Purpose |
|---|---|
| `CueConditioning.m` | Main Bpod protocol: probabilistic multiple-odor cue-conditioning task with reward, omission, airpuff, and unpredicted-outcome (blank) trials |
| `CC_Ver2.m` | Main Bpod protocol: Similar task structure to CueConditioning.m, with trace period removed and added option to overlap odor cue state with airpuff pressurize state, allowing for faster transition from cue to aversive outcome |
| `AirPuff.m` | Configures the Global Timers that control airpuff pressurization and release states |
| `BNCTrigger.m` | Photometry trigger pulse (BNC2) at the start of the session |
| `ExpTimer.m` | Draws each trial's ITI from a truncated exponential distribution with a set mean |
| `ExpTimerTest.m` | Test script: checks that `ExpTimer.m` produces the target mean ITI |
| `load_odor_serial_messages.m` | Loads valve module bit commands used to open/close odor and airpuff valves |
| `PIB_LED_Flash.m` | IR LED sync flash (camera-visible) plus a matching TTL pulse, used to sync video to Bpod |
| `PlotSessionProgress.m` | Live, trial-by-trial session plot during a run |
| `PreviewTrialSequence.m` | Prints the planned trial sequence to the command window before the session starts |
| `TTLGlobalTimer.m` | TTL pulse timer (BNC1); the number of pulses per trial encodes the outcome type for photometry alignment |
| `UrnModel.m` | Builds the session's trial sequence and outcomes ("urn" sampling without replacement, balanced within trial chunks) |
| `VerifyBlankITIAdjustment.m` | Test script: checks the shortened ITI before Blank trials using recorded session data |

To run the selected protocol, place these files in `Bpod Local/Protocols/CueConditioning/`.

### `Data_Analysis/` — offline analysis

| File | Purpose |
|---|---|
| `Extract_raw_data.m` | Step 1 of the lick pipeline: extracts motion and intensity pixel data from chosen ROI, syncs video to the Bpod clock using IR LED flashes and checks for accuracy using regression analysis and residual error, and detects/removes Bpod pauses from data collection (ffmpeg install required) |
| `Analyze_lick_data.m` | Step 2 of the lick pipeline: detects licks, assigns them to trials, and plots cue-aligned rasters and lick rates |
| `Convert_Jpeg_To_mp4.m` | Converts a folder of numbered camera frames into an .mp4 video |
| `ExportSessionChronological.m` | Exports every state and event in a session to a spreadsheet, in chronological order |
| `plotLickRasterByOdor.m` | Lick rasters by odor, using the Bpod lick port events |

**Status:** the video-to-Bpod sync in `Extract_raw_data.m` is working reliably. Separating genuine licks from other motion (whisking, paw movement) is still in active development, so lick detection methods, thresholds, and filters will continue to change.

## Requirements

- MATLAB R2023a or later
- Signal Processing Toolbox (`findpeaks`), Statistics and Machine Learning Toolbox (`robustfit`), Image Processing Toolbox (`drawrectangle`, `imshow`)
- [Bpod_Gen2](https://github.com/sanworks/Bpod_Gen2) (for the protocol files)
- [FFmpeg](https://ffmpeg.org/) (for the video-file option in `Extract_raw_data.m`)
- Optional: `cprintf` (MATLAB File Exchange) for colored output in `PreviewTrialSequence.m`; plain text is printed without it

## Credits

- `CueConditioning.m` and 'CC_ver2.m' is built on the `ProtocolTemplate.m` skeleton from the [Sanworks Bpod_Gen2 repository](https://github.com/sanworks/Bpod_Gen2) (© Sanworks LLC, GPL-3.0).
- The original cue-conditioning task code that `CueConditioning.m` and `load_odor_serial_messages.m` were developed from was written by **[ORIGINAL AUTHOR — TO BE CONFIRMED]**. Substantially altered/extended by Ryan Murden (2025–2026) for use at the FBRI Amo Lab - adding urn-model trial sequencing, additional customization options, airpuff outcomes, truncated-exponential ITIs, TTL-pulse cue/outcome encoding, IR LED video sync, and a live session plot.
- Colored command window output uses `cprintf` by Yair Altman (MATLAB File Exchange).
- All other scripts were written by Ryan Murden.

## License

GPL-3.0 — see [LICENSE](LICENSE).
