function Extract_raw_data(bpodSessionFile)
% Script 1 of 2 - Raw data extraction for lick detection pipeline
% Run this script once per session (~20 min for large image folders)
% Output is saved as a .mat  file and loaded by Analyze_lick_data.m
%
% Global timer list:
%   GT1 — IR LED flash, loops entire session (camera-visible)
%   GT2 — airpuff pressurize solenoid
%   GT3 — airpuff release solenoid
%   GT4 — TTL pulse on BNC1:
%            GT4_Start(1) = odor valve open
%            GT4_Start(2/3) = outcome delivery TTL (2 for reward, 3 for airpuff)
%            Only GT4_Start(1) present on no-outcome trials
%   GT5 — trial start TTL pulse BNC1 (triggered together with the GT1 LED flash; video sync anchor)
%   GT6 — photometry TTL trigger BNC2

% FFmpeg configuration — set these if FFmpeg is not on the system path
FFMPEG_EXE  = 'ffmpeg';                                                     % Full path to ffmpeg.exe if not on path
FFPROBE_EXE = 'ffprobe';                                                    % Full path to ffprobe.exe if not on path
KEEP_RAW_FILES = false;                                                     % true keeps the intermediate .raw files for debugging
%% Load Bpod session data
if nargin < 1 || isempty(bpodSessionFile)                                   % If input file path is empty:
    [bfile, bpath] = uigetfile('*.mat', 'Select Bpod session .mat file');   % Opens file explorer
    if isequal(bfile, 0), error('No Bpod file selected.'); end              % Error if no file path chosen
    bpodSessionFile = fullfile(bpath, bfile);                               % Load chosen file path
end

bpod = load(bpodSessionFile);                                               % Chosen session file is loaded
SessionData = bpod.SessionData;                                             % Pulls SessionData struct from chosen file
nTrials = SessionData.nTrials;                                              % Pulls session trial count from struct
fprintf('Loaded Bpod session: %d trials\n', nTrials);                       % Command window confirmation of SessionData load

%% 1 - Extract Bpod timestamps (runs for each trial in a session)
TrialOnset_s = nan(nTrials, 1);                                             % Sets all timestamp values to NaN by default - these will be updated
CueOn_s = nan(nTrials, 1);                                                  % GT4(1) start
Outcome_s = nan(nTrials, 1);                                                % GT4(2 - reward, 3 - airpuff)
TrialEnd_s = nan(nTrials, 1);                                               % Trial end timestamp
TTLFlash_s = nan(nTrials, 1);                                               % (GT5) - LED timestamp used to sync SessionData info to video file
AnticipatoryEnd_s = nan(nTrials, 1);                                        % GT4(2/3) or ITI onset for no-outcome trials
ITIWindowStart_s = nan(nTrials, 1);                                         % ITI onset + offset (for ITI anticipatory licking window)
ITIWindowEnd_s = nan(nTrials, 1);                                           % ITI window end (ends at start of odor state of next trial)

odorID = repmat("Unknown", nTrials, 1);                                     % Default labels (all trials 'Unknown' odor / 'None' outcome)
outcome = repmat("None", nTrials, 1);                                       % These values are overwritten by the following code
                                                                            % But this is good to have in case session unexpectedly ends/errors
% ITI anticipatory window parameters - Set the start of the ITI anticipatory licking window here:
ITILickOffset_s = 6.0;                                                      % Seconds after ITI onset (6.0 = window starts 6s into the ITI)

for n = 1:nTrials                                                           % For all trials in a session:
    tStart = SessionData.TrialStartTimestamp(n);                            % Defines tStart variable as trial start timestamps (vector value)
    states = SessionData.RawEvents.Trial{n}.States;                         % Defines states variable as SessionData.mat state info (array value)
    events = SessionData.RawEvents.Trial{n}.Events;                         % Defines events variable as SessionData.mat event info (array value)

    TrialOnset_s(n) = tStart;                                               % Inputs all trial start timestamps into the TrialOnset_s vector

    % Video sync anchor - GT5 trial-start TTL pulse
    if isfield(events, 'GlobalTimer5_Start')                                % If LED flash is recorded,
        TTLFlash_s(n) = tStart + events.GlobalTimer5_Start(1);              % Then recorded absolute flash timing as trial start + pulse delay
    end                                                                     % In Bpod, there is a .1ms delay between state transition and GT start

    % Cue identity - Odor_X or blank odor
    stateNames = fieldnames(states);                                        % Pulls the names of all states in this trial
    odorStates = stateNames(startsWith(stateNames, 'Odor_') | ...           % Keeps state names that begin with 'Odor_' or equal 'Blank_Odor',
                             strcmp(stateNames, 'Blank_Odor'));             % Then value is assigned to odorStates variable
    for k = 1:numel(odorStates)                                             % For each odor state found:
        sv = states.(odorStates{k});                                        % sv = [start end] times of that odor state
        if ~isnan(sv(1))                                                    % If the odor state actually occurred this trial (not NaN),
            odorID(n) = string(odorStates{k});                              % Then OdorID(n) is equal to cue type (pulled from SessionData)
            if isfield(events, 'GlobalTimer4_Start')                        % If GT4 occurs in a trial (the odor cue TTL pulse)
                gt4 = events.GlobalTimer4_Start;                            % Then gt4 = timestamp pulled from SessionData
                CueOn_s(n) = tStart + gt4(1);                               % CueOn_s = trial start absolute timestamp + GT4 onset relative timestamp
            else                                                            % This value is computed for each trial
                CueOn_s(n) = tStart + sv(1);                                % If GT4 onset is not present, revert to recorded odor state start time
            end                                                             % This may add better timing precision for data analysis
            break                                                           % We could just use the recorded odor state start values for all trials
        end                                                                 % But there is a very tiny hardware delay between the state transition and
    end                                                                     % the time at which the odor valve opens. Since GT4 occurs at the exact
                                                                            % same time that the solenoid valve opens, we use this
    % Trial end
    if isfield(states, 'TrialEnd') && ~isnan(states.TrialEnd(1))            % If TrialEnd state exists in a trial and has a timestamp
        TrialEnd_s(n) = tStart + states.TrialEnd(2);                        % TrialEnd_s defined as end of TrialEnd state
    end

    % Outcome type
    if isfield(states, 'Reward') && ~isnan(states.Reward(1))                % If state = 'Reward' then outcome defined as reward
        outcome(n) = "Reward";
    elseif isfield(states, 'AirPuff_Release') && ~isnan(states.AirPuff_Release(1))
        outcome(n) = "AirPuff";                                             % If state = 'AirPuff_Release' then outcome defined as airpuff
    end

    % Outcome delivery timestamp — GT4 pulse count depends on outcome type:
    %   None    = 1 pulse  (cue onset only)
    %   Reward  = 2 pulses (cue onset, water valve open)
    %   AirPuff = 3 pulses (cue onset, pressurize valve, release valve)
    outcomeState_s = NaN;                                                   % Bpod state onset that defines the outcome
    if outcome(n) == "Reward"                                               % If this trial was rewarded,
        outcomeState_s = states.Reward(1);                                  % Water valve opens
    elseif outcome(n) == "AirPuff"                                          % If this trial had an airpuff,
        outcomeState_s = states.AirPuff_Release(1);                         % Airpuff hits the mouse (NOT pressurize)
    end
    if ~isnan(outcomeState_s) && isfield(events, 'GlobalTimer4_Start')      % If an outcome occurred and GT4 pulses were recorded,
        gt4 = events.GlobalTimer4_Start;                                    % All GT4 pulses in this trial
        [dt, k4] = min(abs(gt4 - outcomeState_s));                          % The pulse closest to that state onset
        if dt < 0.05                                                        % Within 50ms — this is the matching pulse
            Outcome_s(n) = tStart + gt4(k4);                                % TTL time (exact moment the valve opened)
        else                                                                % No pulse found near the state
            Outcome_s(n) = tStart + outcomeState_s;                         % Fall back to the state timestamp
        end
        AnticipatoryEnd_s(n) = Outcome_s(n);                                % Anticipatory window runs cue onset -> outcome
    end
    if outcome(n) == "None" && isfield(states, 'ITI') && ~isnan(states.ITI(1))  % If no outcome occurred (omission trial),
        AnticipatoryEnd_s(n) = tStart + states.ITI(1);                      % Omission trials: anticipatory window ends at ITI onset
    end                                                                     % On omission trials 'Trace' goes straight to 'ITI', so ITI
                                                                            % onset is the moment the outcome would have been delivered

    % ITI window timestamps
    if isfield(states, 'ITI') && ~isnan(states.ITI(1))                      % If ITI start has a timestamp in session data,
        ITIWindowStart_s(n) = tStart + states.ITI(1) + ITILickOffset_s;     % Then ITI window starts at ITI + chosen offset
    end
end

% ITI window end set as cue onset of the next trial
for n = 1:nTrials-1                                                         % For all trials (except the last one)
    if ~isnan(CueOn_s(n+1))                                                 % If the next trial's cue onset exists,
        ITIWindowEnd_s(n) = CueOn_s(n+1);                                   % Then ITIWindowEnd = cue onset of next trial
    end
    if ITIWindowEnd_s(n) <= ITIWindowStart_s(n)                             % If ITI window is shortened (CC_Ver2 blank-odor trials)
        ITIWindowStart_s(n) = NaN;                                          % Then ITI is shorter than ITILickOffset_s
        ITIWindowEnd_s(n)   = NaN;                                          % NaN excludes the trial rather than contributing negative time
    end
end

% Rolling reward history — fraction of previous trials that were rewarded
historyWindow = 5;                                                          % Size of moving reward history window - can change
rewardHistory = nan(nTrials, 1);                                            % Creates empty reward history array
for n = 1:nTrials                                                           % For all trials,
    windowStart = max(1, n - historyWindow);                                % First trial of the history window (can't go below trial 1)
    precedingTrials = windowStart : n-1;                                    % The up-to-5 trials before the current trial
    if ~isempty(precedingTrials)                                            % If precedingTrials is not empty (previous trials exist),
        rewardHistory(n) = sum(outcome(precedingTrials) == "Reward") / ...  % Then reward history equals number of reward outcomes
                           numel(precedingTrials);                          % Divided by number of preceding trials (fewer than 5 at the start of the session)
    end
end

% Session summary
uniqueOdors = unique(odorID);                                               % Finds all unique odors used in a trial session
fprintf('\nOdor identities:\n');                                            % Prints all odors used in a trial session
for k = 1:numel(uniqueOdors)                                                % For each odor used:
    nOdor = sum(odorID == uniqueOdors(k));                                  % Counts occurrences of each odor
    nRew = sum(odorID == uniqueOdors(k) & outcome == "Reward");             % Counts rewards for each odor
    nAP = sum(odorID == uniqueOdors(k) & outcome == "AirPuff");             % Counts airpuffs for each odor
    fprintf('  %-14s  %3d trials  (Reward: %d  AirPuff: %d  None: %d)\n', ...
        uniqueOdors(k), nOdor, nRew, nAP, nOdor-nRew-nAP);                 % Aligns odor/outcome summary into columns
end
fprintf('Sync anchors  (GT5): %d / %d trials\n', sum(~isnan(TTLFlash_s)), nTrials);  % Number of trials with a GT5 sync pulse
fprintf('Outcome TTLs  (GT4): %d / %d outcome trials\n\n', ...              % Number of outcome trials with an outcome TTL
    sum(~isnan(Outcome_s)), sum(outcome ~= "None"));

% Bpod pause detection — used to exclude periods when the box was opened
% Bpod does not record a pause flag, but a pause leaves a large, easily identifiable trial gap
% Normal transitions are ~0.1s; a pause for injection is multiple seconds
pauseGapThresh_s = 5.0;                                                     % Any inter-trial gap longer than this counts as a pause
interTrialGap = TrialOnset_s(2:end) - TrialEnd_s(1:end-1);                  % Gap between each trial's end and the next trial's start
pauseAfterTrial = find(interTrialGap > pauseGapThresh_s);                   % Trial numbers followed by a pause
pauseStart_s = TrialEnd_s(pauseAfterTrial);                                 % Pause window start, in Bpod time
pauseEnd_s = TrialOnset_s(pauseAfterTrial + 1);                             % Pause window end, in Bpod time

if isempty(pauseAfterTrial)                                                 % If no pauses were found,
    fprintf('No Bpod pauses detected (longest inter-trial gap %.2f s)\n\n', max(interTrialGap));
else                                                                        % Otherwise, prints each pause window
    fprintf('Bpod pauses detected: %d\n', numel(pauseAfterTrial));
    for p = 1:numel(pauseAfterTrial)                                        % For each pause:
        fprintf('  after trial %3d: %.2f s to %.2f s Bpod time (%.1f s long)\n', ...
                pauseAfterTrial(p), pauseStart_s(p), pauseEnd_s(p), pauseEnd_s(p)-pauseStart_s(p));
    end
    fprintf('\n');
end

%% Sections 2-4 - Load video/image folder
% Section A - Video option; Section B - Image option - Both paths produce identical motionTrace, ledTrace, and timestamps 
% Sections 5 onwards run identically regardless of input.
robustMAD = @(x) median(abs(x - median(x)));                                % MAD (median abs. deviation) calculation

inputChoice = questdlg('Select input source type:', ...                     % Dialogue box to choose input type
    'Input Source','Video file (mp4/avi/mov)', ...                          % Option 1 - video file
    'Image folder (jpg)', 'Image folder (jpg)');                            % Option 2 - image folder

if isempty(inputChoice), error('No input source selected.'); end

% Section 2A - Video file via FFmpeg 
if strcmp(inputChoice, 'Video file (mp4/avi/mov)')                          % If chosen file is video format,
    [file, path] = uigetfile({'*.mp4;*.avi;*.mov','Video Files'});          % Loads file picker - supported video types listed
    if isequal(file,0), error('No file selected.'); end                     % Error if no file chosen
    videoPath = fullfile(path, file);                                       % Full path of the chosen video
    inputSourceName = file;                                                 % Saves input source name for .mat file record

    % Confirm FFmpeg is reachable 
    [st, ~] = system(sprintf('"%s" -version', FFMPEG_EXE));                 % Checks system for FFmpeg install + valid path
    if st ~= 0                                                              % If FFmpeg could not be run, stops with install instructions
        error(['Could not run "%s". Install FFmpeg (winget install Gyan.FFmpeg, ' ...
               'then reopen the terminal), or set FFMPEG_EXE at the top of this ' ...
               'script to the full path of ffmpeg.exe.'], FFMPEG_EXE);
    end

    % Video metadata from ffprobe — NOT from VideoReader
    fprintf('Probing video (counts every frame — takes ~1 min for a full session)...\n');
    probeCmd = sprintf(['"%s" -v error -select_streams v:0 -count_frames ' ...  % ffprobe command: reads width, height, and frame rate, and counts every decoded frame
                        '-show_entries stream=width,height,r_frame_rate,nb_read_frames ' ...
                        '-of default=nw=1 "%s"'], FFPROBE_EXE, videoPath);
    [st, probeTxt] = system(probeCmd);                                      % Runs ffprobe and captures its text output
    if st ~= 0, error('ffprobe failed:\n%s', probeTxt); end

    vidW = str2double(regexp(probeTxt,'(?<=width=)\d+','match','once'));    % Width and Height variables pass frame resolution info to FFmpeg
    vidH = str2double(regexp(probeTxt,'(?<=height=)\d+','match','once'));   % Done to ensure chosen ROI locations are faithfully conserved
    nFramesFF = str2double(regexp(probeTxt,'(?<=nb_read_frames=)\d+','match','once')); % Decoded frame count checked against original mp4
    rateStr = regexp(probeTxt,'(?<=r_frame_rate=)[\d/]+','match','once');   % Pulls the frame rate as ffprobe reports it, a fraction (Ex: '50/1')
    rateParts = sscanf(rateStr,'%f/%f');                                    % Splits the fraction into [numerator; denominator]
    fps = rateParts(1) / rateParts(2);                                      % Exact rational frame rate
    captureInterval_s = 1 / fps;                                            % Calculates duration of each frame in seconds
    sessionDuration_s = nFramesFF / fps;                                    % Calculates session length from the counted frames
    if any(isnan([vidW vidH nFramesFF fps]))                                % Stops early if any field failed to parse
        error('ffprobe output could not be parsed:\n%s', probeTxt);
    end
    fprintf('Loaded: %s  |  %dx%d  |  %.2f s  |  %.2f fps  |  %d frames\n\n', ...
        file, vidW, vidH, sessionDuration_s, fps, nFramesFF);               % Prints extracted frame rate info in command window

    % Section 3A - Select ROIs
    previewPng = fullfile(path, 'roi_preview.png');                         % Temp image used only for ROI selection
    prevCmd = sprintf('"%s" -v error -i "%s" -frames:v 1 -y "%s"', ...      % -frames:v 1 grabs the first frame; -y overwrites without asking
        FFMPEG_EXE, videoPath, previewPng);
    [st, txt] = system(prevCmd);                                            % Runs FFmpeg to save the first frame as a .png
    if st ~= 0, error('Preview frame extraction failed:\n%s', txt); end
    firstFrame = imread(previewPng);                                        % Reads the preview frame for ROI selection
    if size(firstFrame,3) > 1, firstFrame = rgb2gray(firstFrame); end       % Converts to greyscale if needed

    figure; imshow(firstFrame, []);                                         % Displays preview frame
    title({'Draw ROI around tongue extension zone', ...                     % Displays directions for ROI choice
        'Double-click to confirm'});
    roiObj = drawrectangle;                                                 % MatLab function to draw ROI
    wait(roiObj);                                                           % Blocks until the user double-clicks inside the rectangle
    roi = round(roiObj.Position);                                           % Converts chosen ROI to a set of whole pixel counts
    close;

    figure; imshow(firstFrame, []);                                         % Same process repeats, this time for IR LED
    title('Draw ROI around IR LED — double-click to confirm');
    ledRoiObj = drawrectangle;
    wait(ledRoiObj);
    ledRoi = round(ledRoiObj.Position);
    close;

    roi    = clampRoi(roi,    vidW, vidH);                                  % Keeps ROIs inside the frame and at least 2px wide
    ledRoi = clampRoi(ledRoi, vidW, vidH);
    fprintf('Lick ROI: [%d %d %d %d]   LED ROI: [%d %d %d %d]\n', roi, ledRoi);  % Prints chosen ROI coordinates [x y width height]

    % Section 4A - Extract ROI pixels with FFmpeg, then process data in MATLAB
    spoutRaw = fullfile(path, 'tmp_spout_roi.raw');                         % Temp file for lick ROI pixels
    ledRaw = fullfile(path, 'tmp_led_roi.raw');                             % Temp file for LED ROI pixels

    % Filtergraph - the recipe FFmpeg follows for each frame. Read it as a chain:
    %   format=gray        convert to 8-bit greyscale (equivalent to rgb2gray)
    %   split=2[a][b]      duplicate the stream into two copies, labelled [a] and [b]
    %   [a]crop=...        copy 'a' is cropped to the lick ROI, output labelled [spout]
    %   [b]crop=...        copy 'b' is cropped to the LED ROI, output labeled [led]
    % [0:v] translates to "input file number 0, video stream" - It's how the FFmpeg filtergraph names its input
    fc = sprintf(['[0:v]format=gray,split=2[a][b];' ...
                  '[a]crop=%d:%d:%d:%d[spout];' ...                         % Lick ROI kept at full pixel resolution 
                  '[b]crop=%d:%d:%d:%d[led]'], ...                          % LED ROI kept at full resolution
                  roi(3),    roi(4),    roi(1)-1,    roi(2)-1, ...          % Lick ROI:  width, height, x, y (x/y minus 1: FFmpeg pixels start at 0, MatLab at 1)
                  ledRoi(3), ledRoi(4), ledRoi(1)-1, ledRoi(2)-1);          % LED ROI:   width, height, x, y

    % Full FFmpeg command: -f rawvideo writes pixel values so MatLab can read it with fread() function
    extractCmd = sprintf(['"%s" -v error -i "%s" -filter_complex "%s" ' ...  
                          '-map "[spout]" -f rawvideo -pix_fmt gray -y "%s" ' ... % First output file: lick ROI
                          '-map "[led]"   -f rawvideo -pix_fmt gray -y "%s"'], ... % Second output file: LED ROI
                          FFMPEG_EXE, videoPath, fc, spoutRaw, ledRaw);

    fprintf('Extracting ROI pixels with FFmpeg...\n');
    tic; [st, txt] = system(extractCmd); tExtract = toc;                    % tic/toc times the extraction; system() runs FFmpeg outside MatLab
    if st ~= 0, error('FFmpeg extraction failed:\n%s', txt); end            % Prints error code if FFmpeg decode fails
    fprintf('  done in %.1f s\n', tExtract);

    % LED trace 
    L = readRawGray(ledRaw, ledRoi(3), ledRoi(4));                          % 3D array: ledH x ledW x nFrames, uint8
    nFrames = size(L, 3);                                                   % Frame count from the third dimension
    if nFrames ~= nFramesFF                                                 % Cross-check against the count ffprobe measured earlier
        error(['LED trace has %d frames but ffprobe counted %d. ' ...       % A mismatch means FFmpeg quit partway through
               'Extraction is incomplete — do not use this data.'], nFrames, nFramesFF);
    end
    ledTrace = zeros(nFrames, 1);                                           % One mean intensity value per frame
    chunkSz = 5000;                                                         % Same block size used for the motion trace below
    for k0 = 1:chunkSz:nFrames                                              % Averaged in blocks to limit peak memory
        k1 = min(k0 + chunkSz - 1, nFrames);                                % Last frame of this block (or the final frame of the session)
        ledTrace(k0:k1) = squeeze(mean(mean(double(L(:,:,k0:k1)), 1), 2));  % Mean over rows then columns, kept in double precision
    end
    clear L                                                                 % Frees the LED block before the lick ROI is loaded

    % Lick ROI 
    V = readRawGray(spoutRaw, roi(3), roi(4));                              % 3D array: roiH x roiW x nFrames, uint8 (every pixel of every frame)
    if size(V,3) ~= nFrames                                                 % Third dimension is the frame count
        error('Lick ROI has %d frames but LED trace has %d.', size(V,3), nFrames);
    end

    % Motion trace — calculates mean frame-to-frame difference - same calculation as the image folder branch, 
    % just done in blocks instead of one frame at a time since the whole session file is too large to pass to MatLab at once
    motionTrace = zeros(nFrames, 1);                                        % Creates empty array with length = total number of frames
    motionProfile = zeros(nFrames, roi(3));                                 % Per-column motion — one row per frame, one column per ROI pixel column
    timestamps  = (0:nFrames-1)' * captureInterval_s;                       % Timestamps from frame index 
    fprintf('Computing motion trace');
    for k0 = 2:chunkSz:nFrames                                              % Starts at frame 2 — frame 1 has nothing before it to compare against
        k1  = min(k0 + chunkSz - 1, nFrames);                               % End of this block, or the last frame if on last block
        blk = int16(V(:,:, k0-1:k1));                                       % Pulls this block of frames, starting one frame early so the
                                                                            % first frame in the block still has a predecessor to compare to.
        dif = abs(diff(blk, 1, 3));                                         % diff subtracts each frame from the next; abs makes all intensity change count equally
        motionTrace(k0:k1) = squeeze(mean(mean(double(dif), 1), 2));        % Averages over rows then columns, leaving one value per frame
        motionProfile(k0:k1,:) = squeeze(mean(double(dif), 1)).';           % Averages over rows only — keeps the horizontal distribution of motion
        fprintf('.');                                                       % One dot per block as a progress indicator
    end
    fprintf(' done.\n');
    clear V blk dif                                                         % Frees the pixel block before the rest of the script runs

    if ~KEEP_RAW_FILES                                                      % Unless KEEP_RAW_FILES is true,
        delete(spoutRaw); delete(ledRaw); delete(previewPng);               % Removes intermediate files
    end

    % Decode validity checks — ensures decode errors such as in VideoReader() aren't happening
    % Check 1: duplicate frames - If a frame is an exact copy of the one before it, the difference between them is exactly 0 
    % Real video always has sensor noise, so genuine zeros should be very rare
    zeroFrac = mean(motionTrace(2:end) == 0);                               % Fraction of frames with exactly zero change (skips frame 1)
    fprintf('\nDecode check — zero-motion frames: %.2f%%  (VideoReader produced ~26%%)\n', ...
            100*zeroFrac);
    if zeroFrac > 0.02                                                      % More than 2% duplicates means something is wrong
        warning('%.1f%% zero-motion frames — decode may not be clean.', 100*zeroFrac);
    end

    % Check 2: periodicity check - the VideoReader bug repeated every third frame, which put a strong rhythm at fps/3 (16.67Hz at 50fps) into motionTrace 
    % A Fourier transform converts the trace from "value over time" into "how much of each rhythm is present", making that error easy to spot
    xDet = motionTrace - mean(motionTrace);                                 % Removes the average so the flat offset doesn't dominate the transform
    Pdet = abs(fft(xDet)).^2;                                               % Power at each frequency (squared magnitude of the transform)
    fDet = (0:nFrames-1)' * fps / nFrames;                                  % The actual frequency in Hz that each entry of Pdet corresponds to
    halfIdx = 2:floor(nFrames/2);                                           % Only the first half is meaningful (the rest mirrors it); index 1 is skipped
                                                                            % because it holds the offset we just removed
    [~, kPk] = max(Pdet(halfIdx));                                          % Finds the strongest frequency
    fPk = fDet(halfIdx(kPk));                                               % Converts its position back into Hz
    fprintf('Decode check — dominant motionTrace frequency: %.2f Hz', fPk);
    if abs(fPk - fps/3) < 0.5                                               % If the strongest rhythm sits at fps/3, the artifact is still there
        fprintf('\n');
        warning('Dominant frequency is fps/3 (%.2f Hz) — the decoder artifact is still present.', fps/3);
    else
        fprintf('  (artifact would be %.2f Hz)\n\n', fps/3);                % Otherwise print what the bad value would have been, for reference
    end

else

    % Section 2B - Image folder option
    imgFolder = uigetdir('', 'Select folder containing session images');    % Opens image folder picker
    if isequal(imgFolder, 0), error('No folder selected.'); end

    imgFiles = dir(fullfile(imgFolder, '*.jpg'));                           % Finds all .jpegs in chosen folder
    if isempty(imgFiles), error('No .jpg files found in selected folder.'); end

    frameIndices = zeros(numel(imgFiles), 1);                               % Creates an empty vector to store each image's frame number
    for f = 1:numel(imgFiles)                                               % For all .jpegs,
        parts = strsplit(imgFiles(f).name, '_');                            % Splits filename at underscores
        frameIndices(f) = str2double(parts{end});                           % Pulls the frame index number from the end of each file name
    end
    [~, sortOrder] = sort(frameIndices);                                    % Sorts by frame index value
    imgFiles = imgFiles(sortOrder);                                         % Reorders file list chronologically
    nFrames = numel(imgFiles);                                              % Total frame count

    captureInterval_s = 0.020;                                              % 20ms between each frame capture (set in Pylon Viewer)
                                                                            % Update this value if camera capture rate is ever changed
    fps = 1 / captureInterval_s;                                            % Calculates FPS
    sessionDuration_s = (nFrames - 1) * captureInterval_s;                  % Calculates total length of capture session
    inputSourceName   = imgFolder;                                          % Saves input source name for .mat file record

    fprintf('Loaded image folder: %s\n', imgFolder);
    fprintf('Images found:        %d frames\n', nFrames);
    fprintf('Capture interval:    %.1f ms  (%.1f fps)\n', captureInterval_s*1000, fps);
    fprintf('Session duration:    %.2f s  (%.1f min)\n\n', sessionDuration_s, sessionDuration_s/60);

    % Section 3B - Select ROIs (image folder)
    firstFrame = imread(fullfile(imgFolder, imgFiles(1).name));             % Reads first image for ROI selection
    figure; imshow(firstFrame, []);
    title({'Draw ROI around tongue extension zone','Double-click to confirm'});
    roiObj = drawrectangle;
    wait(roiObj);                                                           % Blocks until the user double-clicks inside the rectangle
    roi = round(roiObj.Position);
    close;

    figure; imshow(firstFrame, []);
    title('Draw ROI around IR LED — double-click to confirm');
    ledRoiObj = drawrectangle;
    wait(ledRoiObj);
    ledRoi = round(ledRoiObj.Position);
    close;

    % Section 4B - Extract motion + LED traces (image folder)
    prevCrop = [];                                                          % Variable saves previous frame info to compare to next frame (motion detection)
    motionTrace = zeros(nFrames, 1);                                        % Creates empty array with length = total number of frames
    motionProfile = zeros(nFrames, roi(3));                                 % Per-column motion — one row per frame, one column per ROI pixel column
    ledTrace = zeros(nFrames, 1);                                           % Three arrays created to store motion, LED, and timestamp data
    timestamps = zeros(nFrames, 1);                                         % Arrays will be updated with info during image read
    fprintf('Reading %d frames', nFrames);
    progressStep = max(1, round(nFrames / 20));                             % Print a dot every 5% of frames

    for frameIdx = 1:nFrames
        frame = imread(fullfile(imgFolder, imgFiles(frameIdx).name));       % Reads current image
        if size(frame,3) > 1, frame = rgb2gray(frame); end                  % If frame is RGB coded, converts to greyscale
        frame = double(frame);                                              % Converts frame from 8-bit integers (uint8) to double precision
                                                                            % Needed because uint8 can't go below 0, so subtracting frames would clip negative changes to 0

        % Spout ROI — motion detection code (frame differencing)
        crop = frame(roi(2):roi(2)+roi(4)-1, roi(1):roi(1)+roi(3)-1);       % Crops frame reference to chosen lick ROI
        if isempty(prevCrop)                                                % Frame zero is empty, so frame 1 has no comparison value (sets value to 0)
            motionTrace(frameIdx) = 0;
            motionProfile(frameIdx,:) = 0;                                  % Per-column motion is also 0 for frame 1
        else
            colDiff = mean(abs(crop - prevCrop), 1);                        % Mean absolute change per column (1 x roiW)
            motionTrace(frameIdx) = mean(colDiff);                          % Mean over all columns = mean change for the whole ROI
            motionProfile(frameIdx,:) = colDiff;                            % Stores per-column change (used for lick vs whisker metrics in Analyze_lick_data.m)
        end
        prevCrop = crop;

        % LED ROI — mean intensity change
        ledCrop = frame(ledRoi(2):ledRoi(2)+ledRoi(4)-1, ...
                                   ledRoi(1):ledRoi(1)+ledRoi(3)-1);
        ledTrace(frameIdx) = mean(ledCrop(:));                              % Mean brightness of the LED ROI in this frame (instead of motion)
        timestamps(frameIdx) = (frameIdx - 1) * captureInterval_s;          % Timestamp from frame index and known capture interval

        if mod(frameIdx, progressStep) == 0, fprintf('.'); end
    end
    fprintf(' done.\n\n');
end

%% 5 - Normalize + smooth
if robustMAD(ledTrace) == 0                                                 % Guards against a divide-by-zero in the Z-score calculation
    error('robustMAD(ledTrace) is zero — the LED trace has no variation');          
end
motionZ = (motionTrace - median(motionTrace)) / robustMAD(motionTrace);     % Converts motion values to robust Z-score
ledZ = (ledTrace - median(ledTrace)) / robustMAD(ledTrace);                 %     (pixel value - median)
                                                                            % z = ---------------------
% 3-frame window = 60ms at 50fps — preserves lick transients                %       median abs deviation
motionZ = movmean(motionZ, 3);                                              % Median is better than mean since licks/flashes are outliers
ledZ = movmean(ledZ, 3);                                                    % Creates mean sliding window to reduce camera noise

%% 6 - Motion peak height histogram 
% Run this to assess ROI quality, suggested threshold lines are starting points — adjust in Analyze_lick_data.m
lickMinDist_fr_preview = round(0.140 * fps);                                % 140ms refractory period (default - adjust if needed, i.e. blinks)
[allPeakVals, ~] = findpeaks(motionZ, 'MinPeakHeight', 1, ...               % Finds Z-score heights for all peaks in session
                              'MinPeakDistance', lickMinDist_fr_preview);

figure('Name','Motion Peak Distribution (Raw Data Quality Check)', ...
       'NumberTitle','off','Position',[100 100 800 500]);
histogram(allPeakVals, 100, 'FaceColor',[0.2 0.5 0.8], 'EdgeColor','none');
hold on;
xline(4,  'r--', 'Z=4  (suggested min start)');                            % Suggested starting minimum threshold
xline(20, 'g--', 'Z=20 (suggested max start)');                            % Suggested starting maximum threshold
xlabel('Peak Z-score'); ylabel('Count');
title({'Motion Peak Height Distribution — Raw Data Quality Check', ...
       'Use to assess ROI quality and guide threshold selection in Analyze\_lick\_data.m'});
fprintf('Peak distribution summary:\n');
fprintf('  Total peaks above Z=1:   %d\n',   numel(allPeakVals));
fprintf('  Peaks above Z=4:         %d\n',   sum(allPeakVals > 4));
fprintf('  Peaks above Z=20:        %d\n',   sum(allPeakVals > 20));
fprintf('  Peaks above Z=60:        %d\n\n', sum(allPeakVals > 60));

%% 7 - LED flash detection and Video to Bpod clock sync (linear regression)
% Rising edge detection on unsmoothed signal to ensure accurate frame timestamp
% GT5 (Trial start TTL) paired with LED flash (video) as anchor points
% robustfit regression line used to match video time to Bpod session clock
% It takes matched points (LED flash + trial start TTL) along the session
% timeline to create a regression line that accurately maps video time to Bpod time
% The regression slope coefficient accounts for any clock drift between camera and Bpod
ledBaseline = movmedian(ledTrace, round(10 * fps));                         % Baseline — tracks drift across the session
ledAboveBase = ledTrace - ledBaseline;                                      % Intensity above local baseline, in counts

[pkVals, ~] = findpeaks(ledAboveBase, 'MinPeakDistance', round(2 * fps));   % All well-separated peaks in the trace
pkVals = sort(pkVals, 'descend');                                           % Largest first — the real flashes
nTop = max(5, min(numel(pkVals), round(nTrials/2)));                        % Use the top half of the expected flash count
flashAmp = median(pkVals(1:nTop));                                          % Typical flash height for recording, in counts
ledAbsThresh = 0.30 * flashAmp;                                             % DETECTION THRESHOLD — Raise if false positives persist,
fprintf('LED flash amplitude ~%.1f counts  |  threshold %.1f counts\n', flashAmp, ledAbsThresh);% lower if real flashes are missed
dLed = [0; diff(ledAboveBase)];                                             % Frame-to-frame derivative, in counts
ledCandidates = find(ledAboveBase > ledAbsThresh & dLed > 0.5*ledAbsThresh);% Flashes must be above threshold AND sharply rising

ledMinDist_fr = round(5 * fps);                                             % 5s refractory period, full trials much longer
                                                                            % Also suppresses any second-frame detection from a 2-frame flash
ledFrames = [];                                                             % Empty LED frames vector
lastLED = -inf;                                                             % Tracks last recorded LED flash
for i = 1:length(ledCandidates)                                             % For all flash candidates:
    if ledCandidates(i) - lastLED > ledMinDist_fr                           % Detected flash must be > set refractory period
        ledFrames(end+1) = ledCandidates(i);                                % Record timestamp
        lastLED = ledCandidates(i);                                         % Update last recorded flash
    end
end

ledVideoTimes = timestamps(ledFrames);                                      % Pulls timestamps for LED flash events
ledZ_sharp = (ledTrace - median(ledTrace)) / robustMAD(ledTrace);           % Unsmoothed LED Z-score, saved to the .mat file (not used by the plots below)
fprintf('Video LED flashes: %d  |  Bpod trials: %d\n', numel(ledVideoTimes), nTrials);

% Default values — these stand if sync cannot be completed
syncValid = false;                                                          % Tracks if sync is completed, only returns True if it is
videoToBpod = @(t) t;                                                       % If sync fails, video timestamps used instead
videoAnchors = [];                                                          % Creates empty arrays for video and Bpod timestamps
bpodAnchors = [];                                                           % Arrays fill with matched pairs below
matchedTrials = [];                                                         % Trial numbers that produced a usable anchor
missedTrials = [];                                                          % Trial numbers whose flash was not found in the video
nSpurious = 0;                                                              % Detections that matched no Bpod flash
syncCoeffs = [0; 1];                                                        % Default coefficients [intercept; slope]

bpodTrialIdx = find(~isnan(TTLFlash_s));                                    % Trial numbers that have a GT5 timestamp
bpodFlash = TTLFlash_s(bpodTrialIdx);                                       % Their absolute Bpod times

if numel(ledVideoTimes) >= 3 && numel(bpodFlash) >= 3                       % Need at least 3 of each for a meaningful fit
    bRel = bpodFlash - bpodFlash(1);                                        % Bpod flash times relative to the first flash
    vRel = ledVideoTimes(:);                                                % Video flash times (already relative to video start)

    minIFI_s = min(diff(bpodFlash));                                        % Shortest gap between consecutive Bpod flashes
    matchTol_s = min(0.25, 0.2 * minIFI_s);                                 % Match tolerance (so a missed flash won't cause the next to be incorrectly assigned)

    % Stage 1 — Clock offset - Every correctly matching pair gives nearly the same video-minus-Bpod difference
    % Mismatched pairs scatter randomly. So the most common difference across ALL possible pairings is the true offset.
    D = vRel - bRel.';                                                      % Every video time minus every Bpod time (nVid x nBpod grid)
    binW = 0.05;                                                            % 50ms histogram bins
    edges1 = floor(min(D(:))) : binW : ceil(max(D(:))) + binW;              % Bin edges spanning the full range of differences
    counts1 = histcounts(D(:), edges1);                                     % How many pairs fall in each bin
    [~, kMax] = max(counts1);                                               % The fullest bin holds the true offset
    offset = edges1(kMax) + binW/2;                                         % Bin centre = starting estimate of the offset
    slope = 1;                                                              % Starting estimate — assumes no clock drift yet

    % Stage 2 — Refine by repeatedly matching then refitting
    % Each pass predicts where every Bpod flash should be video time, then keeps only the video flashes close to a prediction
    keep = false(size(vRel));                                               % Which video flashes are confidently matched
    j = zeros(size(vRel));                                                  % Which Bpod flash each video flash matched to
    dmin = inf(size(vRel));                                                 % How far each video flash sits from its match
    for it = 1:10                                                           % Up to 10 match/refit passes
        pred = offset + slope * bRel;                                       % Predicted video time for each Bpod flash
        [dmin, j] = min(abs(vRel - pred.'), [], 2);                         % Nearest prediction for each video flash
        keep = dmin < matchTol_s;                                           % Discard anything too far from any prediction
        if nnz(keep) < 3, break; end                                        % Not enough matches to refit — stop
        c = robustfit(bRel(j(keep)), vRel(keep));                           % Refit offset and slope on the matched pairs only
        if abs(c(1)-offset) < 1e-9 && abs(c(2)-slope) < 1e-12, break; end   % Stop once the fit stops changing
        offset = c(1);  slope = c(2);                                       % Otherwise update and go round again
    end

    % One video flash per Bpod flash — if two matched the same trial, keep the closer one
    for u = unique(j(keep)).'                                               % For each Bpod flash that was matched:
        hits = find(keep & j == u);                                         % All video flashes claiming this Bpod flash
        if numel(hits) > 1
            [~, best] = min(dmin(hits));                                    % Index of the closest one
            hits(best) = [];                                                % Remove it from the discard list
            keep(hits) = false;                                             % Drop the rest
        end
    end

    videoAnchors = ledVideoTimes(keep);                                     % Video times of the confidently matched flashes
    bpodAnchors = bpodFlash(j(keep));                                       % Their correctly paired Bpod times
    matchedTrials = bpodTrialIdx(j(keep));                                  % Which trials those anchors came from
    missedTrials = setdiff(bpodTrialIdx, matchedTrials);                    % Trials whose flash was never found
    nSpurious = sum(~keep);                                                 % Detections that matched no Bpod flash at all
end

if numel(videoAnchors) >= 3                                                 % Fit only if enough anchors survived matching
    syncCoeffs = robustfit(videoAnchors, bpodAnchors);                      % RobustFit fits regression line to matched points
    videoToBpod = @(t) syncCoeffs(1) + syncCoeffs(2) .* t;                  % If no/minimal drift is occuring between Bpod and video,
    syncValid = true;                                                       % Then regression slope should be approximately 1
    driftPct = abs(syncCoeffs(2) - 1.0) * 100;                              % Calculates drift percentage, should be very close to zero

    residCheck_ms = (bpodAnchors - videoToBpod(videoAnchors)) * 1000;       % Residuals in milliseconds
    nBadResid = sum(abs(residCheck_ms) > 1000/fps);                         % Count of anchors off by more than one frame

    fprintf('Matched %d of %d Bpod flashes  |  %d unmatched trials  |  %d spurious detections\n', ...
            numel(videoAnchors), numel(bpodFlash), numel(missedTrials), nSpurious);
    fprintf('Sync: BpodTime = %.6f + %.9f * VideoTime\n', syncCoeffs(1), syncCoeffs(2));
    fprintf('Clock drift: %.5f%%  |  Residuals: RMS %.2f ms, max %.2f ms  (1 frame = %.1f ms)\n', ...
            driftPct, rms(residCheck_ms), max(abs(residCheck_ms)), 1000/fps);

    if ~isempty(missedTrials)                                               % List any trials with no usable anchor
        fprintf('Unmatched trials: %s\n', mat2str(missedTrials(:).'));      % Sync is still valid — these just contribute no anchor
    end
    if driftPct > 0.01                                                      % Real camera/Bpod drift is far below this
        warning(['Slope is %.6f (%.4f%% from 1). Genuine clock drift is much ' ...
                 'smaller than this — check the flash pairing before trusting ' ...
                 'the sync.'], syncCoeffs(2), driftPct);
    end
    if nBadResid > 0                                                        % Individual anchors that do not fit the line
        warning('%d anchor(s) are off by more than one frame — inspect the residual plot.', nBadResid);
    end
    fprintf('\n');
else
    warning('Fewer than 3 matched sync pairs — using raw video timestamps.'); % Produce message if sync error occurs
end

% Builds a frame mask covering each Bpod pause (camera keeps recording during pause)
% Frames inside the gap still show the box being opened, so they are flagged and excluded from LED and motion trace
pauseMask = false(nFrames, 1);                                              % True for frames recorded while Bpod was paused
pauseVideoStart_s = nan(size(pauseStart_s));                                % Pause windows converted to video time
pauseVideoEnd_s = nan(size(pauseEnd_s));
if syncValid && ~isempty(pauseStart_s)                                      % If sync worked and pauses were found,
    pauseVideoStart_s = (pauseStart_s - syncCoeffs(1)) / syncCoeffs(2);     % Inverse of videoToBpod
    pauseVideoEnd_s = (pauseEnd_s - syncCoeffs(1)) / syncCoeffs(2);
    for p = 1:numel(pauseVideoStart_s)                                      % For each pause:
        pauseMask = pauseMask | ...                                         % Flags every frame inside this pause window
            (timestamps >= pauseVideoStart_s(p) & timestamps <= pauseVideoEnd_s(p));
    end
    for p = 1:numel(pauseVideoStart_s)                                      % Reports pause windows in video time as well as Bpod time
        fprintf('  pause %d: Bpod %.2f-%.2f s  =  video %.2f-%.2f s\n', ... % The two clocks differ by the sync intercept (syncCoeffs(1))
                p, pauseStart_s(p), pauseEnd_s(p), ...
                pauseVideoStart_s(p), pauseVideoEnd_s(p));
    end
    fprintf('Pause frames flagged: %d (%.2f%% of session)\n\n', ...
            sum(pauseMask), 100*mean(pauseMask));
end

%% 8 - Plot diagnostic figures
% P1: LED intensity trace + detected flash markers - Every red dot should sit on an intensity spike
figure('Name','LED Flash Detection','NumberTitle','off', ...                
       'Position',[100 100 1100 600]);
subplot(2,2,1);
plot(timestamps, ledAboveBase, 'Color',[0.2 0.5 0.8], 'LineWidth', 0.8);    % Intensity above local baseline, in counts
hold on;
if ~isempty(ledFrames)                                                      % If LED flashes exist,
    scatter(ledVideoTimes, ledAboveBase(ledFrames), 60, 'r', 'filled', ...  % Then they are plotted
            'DisplayName', 'Detected flashes');
end
yline(ledAbsThresh, 'r--', sprintf('Threshold = %.1f counts', ledAbsThresh)); % Threshold line
xlabel('Time (s)');
ylabel('Intensity above baseline (counts)');
title(sprintf('LED Flash Detection  —  %d Flashes Detected  (expected %d)', ...
              numel(ledVideoTimes), nTrials));
legend('LED intensity','Detected flashes','Threshold','Location','northeast');

% P2: Inter-flash intervals - Each interval should match the duration of one complete trial
subplot(2,2,2);
if numel(ledVideoTimes) > 1                                                 % If more than one flash was detected,
    IFI = diff(ledVideoTimes);                                              % Calculates time between consecutive flashes (inter-flash interval)
    plot(1:numel(IFI), IFI, 'o-', 'Color',[0.2 0.6 0.3], 'LineWidth', 1.2);
    hold on;
    yline(mean(IFI), 'r--', sprintf('Mean = %.2fs', mean(IFI)));            % mean inter-flash interval line
    xlabel('Flash number');
    ylabel('Inter-flash interval (s)');
    title(sprintf('Inter-Flash Intervals  —  (mean = %.2fs)', ...
                  mean(IFI)));
else
    text(0.5, 0.5, 'Insufficient flashes for interval plot', ...            % Error if no flashes recorded
         'Units','normalized', 'HorizontalAlignment','center');
    axis off;
end

% P3: Sync residuals
% Each point = difference between predicted and actual LED flash time, points should cluster tightly around zero 
% Red dotted lines = 1 frame width — points outside suggest sync issues
subplot(2,2,3);
if syncValid && ~isempty(videoAnchors)                                      % If sync worked,
    residuals_ms = (bpodAnchors - videoToBpod(videoAnchors)) * 1000;        % Calculates residuals in milliseconds
    scatter(1:numel(videoAnchors), residuals_ms, 25, [0.1 0.6 0.3], 'filled');  % One point per matched anchor
    hold on;
    yline(0,'k--');                                                         % Zero residual reference line
    yline( 1000/fps, 'r:', '1 frame');                                      % Upper 1-frame boundary
    yline(-1000/fps, 'r:');                                                 % Lower 1-frame boundary
    xlabel('Trial index'); ylabel('Residual (ms)');
    title(sprintf('Sync Residuals  (RMS = %.2f ms,  1 frame = %.1f ms)', ...
                  rms(residuals_ms), 1000/fps));
else
    text(0.5,0.5,'Sync not applied','Units','normalized', ...
         'HorizontalAlignment','center','FontSize',12);
    title('Sync Residuals (unavailable)'); axis off;
end

% P4 - Session-wide lick rate
% Overview of licking across the whole session
subplot(2,2,4);
binW = 10;                                                                  % 10 second bins
edges2 = 0 : binW : ceil(sessionDuration_s);
[~, allPeakTimes_rate] = findpeaks(motionZ, ...                             % Peak frame indices — heights aren't needed here
    'MinPeakHeight',   1, ...
    'MinPeakDistance', round(0.140 * fps));                                 % 140ms refractory period (default - adjust if needed, i.e. blinks)
bar(edges2(1:end-1)+binW/2, ...                                             % timestamps() converts peak frame indices to seconds before binning
    histcounts(timestamps(allPeakTimes_rate), edges2)/binW, ...             % Calculates lick rate per histogram bin
    'FaceColor',[0.35 0.70 0.40], 'EdgeColor','none');
xlabel('Video time (s)'); ylabel('Lick rate (Hz)');
title(sprintf('Session Lick Rate (tentative) %ds bins', binW));

%% 9 - Save .mat data file
% Saves all variables needed by Analyze_lick_data.m
% videoToBpod is saved as a function handle — loads correctly since syncCoeffs (which it depends on) is also saved
[saveFile, savePath] = uiputfile('*.mat', 'Save raw data .mat file', 'raw_data.mat');
if isequal(saveFile, 0)
    warning('Raw data not saved — rerun will require full reprocessing.');
else
    savePath_full = fullfile(savePath, saveFile);
    save(savePath_full, ...
        'motionTrace','motionZ','ledTrace','ledZ','ledZ_sharp','timestamps','fps','sessionDuration_s', ...
        'ledVideoTimes','ledFrames','syncCoeffs','syncValid', 'videoAnchors','bpodAnchors','videoToBpod', ...
        'TrialOnset_s','CueOn_s','Outcome_s','TrialEnd_s','TTLFlash_s','AnticipatoryEnd_s','ITIWindowStart_s','ITIWindowEnd_s', ...
        'ITILickOffset_s','odorID','outcome','pauseMask','pauseVideoStart_s','pauseVideoEnd_s','pauseAfterTrial', ...
        'uniqueOdors','rewardHistory','nTrials','inputSourceName','roi','ledRoi','motionProfile');
    fprintf('Raw data saved to: %s\n', savePath_full);
    fprintf('Load this file in Analyze_lick_data.m to run lick detection and analysis.\n');
end

end

% Local functions (video branch only)
function r = clampRoi(r, vidW, vidH)                                        % Keeps an ROI inside the video frame (see notes below)
r = round(r);                                                               % Keeps a [x y w h] ROI inside the frame and at least 2px in each dimension
r(1) = max(1, min(r(1), vidW-1));                                           % FFmpeg errors out on a crop that runs past the frame edge, so this is
r(2) = max(1, min(r(2), vidH-1));                                           % checked here rather than letting the extraction fail after a long decode
r(3) = max(2, min(r(3), vidW - r(1) + 1));                                  % Width: at least 2px, and can't extend past the right edge
r(4) = max(2, min(r(4), vidH - r(2) + 1));                                  % Height: at least 2px, and can't extend past the bottom edge
end

function A = readRawGray(rawPath, w, h)                                     % Reads raw 8-bit grayscale written by FFmpeg
fid = fopen(rawPath, 'r');                                                  % ROI read at full resolution
if fid < 0, error('Could not open %s', rawPath); end                        % Stops if the file can't be opened
raw = fread(fid, inf, 'uint8=>uint8');                                      % Reads every byte (one byte = one pixel)
fclose(fid);                                                                % Closes the file
n = numel(raw) / (w*h);                                                     % Number of frames = total pixels / pixels per frame
if mod(n, 1) ~= 0                                                           % If that isn't a whole number,
    error(['Byte count %d is not a multiple of %dx%d — crop dimensions do not ' ...
           'match the file.'], numel(raw), w, h);
end
if w == 1 && h == 1                                                         % Single-pixel ROI (not possible after clampRoi, which enforces 2px minimum)
    A = double(raw);                                                        % LED trace: one byte per frame
else
    A = permute(reshape(raw, w, h, n), [2 1 3]);                            % FFmpeg writes rows left-to-right, top-to-bottom
end
end