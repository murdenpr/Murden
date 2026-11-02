function lickTable = Analyze_lick_data(rawDataFile)
% Script 2 of 2 - Lick detection and analysis
% Loads pre-extracted raw data from Extract_raw_data.m and runs analysis
% Run this script repeatedly to tune thresholds if needed
% Output list:
%   lickNumber - Numerically ordered lick index
%   frameIndex - Video frame of lick onset
%   videoTime_s - Video timestamps for recorded lick frames
%   bpodTime_s - Lick time in relation to Bpod clock
%   trialNumber - Bpod trial index
%   odorID - Odor_A, Odor_C, Blank_Odor, etc.
%   outcome - Reward, AirPuff, None
%   timeFromTrialOn - Elapsed time from trial onset
%   timeFromCueOn - Elapsed time from cue onset via GT4_Start(1)
%   timeFromOutcome - Elapsed time from outcome delivery via GT4_Start(2/3)
%                   = GT4(2) - water valve open on reward trials
%                   = GT4(3) - airpuff release valve open on airpuff trials
%                   = NaN on no-outcome trials
%   timeFromTrialEnd - Elapsed time from trial end
%                      Negative values = licking during preceding trial end state
%   isAnticipatoryLick  - True if lick occurs between cue onset and outcome delivery
%   timeFromITIWindowStart - Elapsed time from ITI anticipatory window start
%   isITILick - True if lick occurs within ITI anticipatory window
%   itiWindowPauseContaminated - True if this lick's trial has an ITI window overlapping Bpod pause
%   rewardHistory_last5 - Fraction of last 5 trials that were reward outcomes

%% Load raw data
if nargin < 1 || isempty(rawDataFile)                                       % If no file path was passed in,
    [rfile, rpath] = uigetfile('*.mat', 'Select raw data .mat file from Extract_raw_data.m');  % Opens file picker
    if isequal(rfile, 0), error('No file selected.'); end
    rawDataFile = fullfile(rpath, rfile);                                   % Full path of the chosen file
end

fprintf('Loading raw data: %s\n\n', rawDataFile);
raw = load(rawDataFile);                                                    % Loads all variables saved by Extract_raw_data.m
robustMAD = @(x) median(abs(x - median(x)));                                % MAD calculation

% Unpack all variables from struct into local workspace
motionTrace       = raw.motionTrace;
motionZ           = raw.motionZ;
ledTrace          = raw.ledTrace;
ledZ              = raw.ledZ;
ledZ_sharp        = raw.ledZ_sharp;
timestamps        = raw.timestamps;
fps               = raw.fps;
sessionDuration_s = raw.sessionDuration_s;
ledVideoTimes     = raw.ledVideoTimes;
ledFrames         = raw.ledFrames;
syncCoeffs        = raw.syncCoeffs;
syncValid         = raw.syncValid;
videoAnchors      = raw.videoAnchors;
bpodAnchors       = raw.bpodAnchors;
videoToBpod       = raw.videoToBpod;
TrialOnset_s      = raw.TrialOnset_s;
CueOn_s           = raw.CueOn_s;
Outcome_s         = raw.Outcome_s;
TrialEnd_s        = raw.TrialEnd_s;
TTLFlash_s        = raw.TTLFlash_s;
AnticipatoryEnd_s = raw.AnticipatoryEnd_s;
ITIWindowStart_s  = raw.ITIWindowStart_s;
ITIWindowEnd_s    = raw.ITIWindowEnd_s;
ITILickOffset_s   = raw.ITILickOffset_s;
odorID            = raw.odorID;
outcome           = raw.outcome;
uniqueOdors       = raw.uniqueOdors;
rewardHistory     = raw.rewardHistory;
nTrials           = raw.nTrials;
inputSourceName   = raw.inputSourceName;
roi               = raw.roi;
ledRoi            = raw.ledRoi;
pauseMask         = raw.pauseMask;                                          % True for video frames recorded while Bpod was paused (used to reject licks)
pauseAfterTrial   = raw.pauseAfterTrial;                                    % Trial(s) after which a Bpod pause occurred
pauseVideoStart_s = raw.pauseVideoStart_s;                                  % Pause start times in video time (for plot shading)
pauseVideoEnd_s   = raw.pauseVideoEnd_s;                                    % Pause end times in video time
motionProfile     = raw.motionProfile;                                      % Motion per frame for each lick ROI column (frames x columns)

if ~syncValid                                                               % Extract could not sync video to Bpod
    warning(['This raw data file has no valid sync — Bpod times are raw video ' ...
             'times and trial assignments will be wrong. Re-run Extract_raw_data.m.']);
end

clear raw;                                                                  % Remove the struct now that variables are unpacked
%% 1 - Lick detection parameters
% Adjust parameters as needed; peaks are detected on the smoothed motion Z-score (motionZ)
% lickAmpThresh: minimum Z-score to count as a lick
%   Raise to reduce false positives (whiskers, background noise)
%
% lickAmpMax: maximum Z-score — rejects paw movement
%   Paw events produce much larger pixel changes than tongue licks
%   Raise if genuine licks are being cut off at the top
%
% lickMinDist_fr: minimum frames between detected licks (80ms = 4 frames at 50fps)
%   Prevents tongue extension + retraction from counting as 2 separate licks
lickAmpThresh = 15;                                                         % Minimum Z-score threshold
lickAmpMax = 75;                                                            % Maximum Z-score threshold
lickMinDist_fr = round(0.080 * fps);                                        % 80ms refractory period        

%% 2 - Lick detection
[peakHeights, lickFrames] = findpeaks(motionZ, ...                          % Pulls frame timestamps that:
    'MinPeakHeight',   lickAmpThresh, ...                                   % Breach minimum threshold
    'MinPeakDistance', lickMinDist_fr);                                     % And are at least 80ms apart

% Apply maximum threshold as post-processing filter -removes peaks above lickAmpMax (paw intrusions)
nAboveMin = numel(peakHeights);                                             % Total peaks above minimum threshold

% Filter 1 - maximum threshold (paw intrusions, large body movements)
validPeaks  = peakHeights <= lickAmpMax;                                    % Finds peaks below max threshold
nRejected   = sum(~validPeaks);                                             % Peaks rejected by max threshold
lickFrames  = lickFrames(validPeaks);                                       % Retains only events between min and max
peakHeights = peakHeights(validPeaks);                                      % Peak heights for retained events

% Filter 2 - Bpod pause (box open, experimenter hands in frame)
inPause        = pauseMask(lickFrames);                                     % Which surviving peaks fall inside a pause window
nPauseRejected = sum(inPause);                                              % Count for the summary printout
lickFrames     = lickFrames(~inPause);                                      % Drop them
peakHeights    = peakHeights(~inPause);
nRetained      = numel(lickFrames);                                         % Recount after both filters

fprintf('Lick detection:\n');
fprintf('  Peaks above min threshold (Z=%g):   %d\n', lickAmpThresh, nAboveMin);
fprintf('  Retained after both filters:        %d\n', nRetained);
fprintf('  Rejected by max filter:             %d\n', nRejected);
fprintf('  Rejected during Bpod pause:         %d\n\n', nPauseRejected);

% Spatial motion metrics — used to separate licks from whisker movement
% A lick sweeps the tongue across most of the ROI in one direction, then retracts.
% Whisking oscillates back and forth within a small part of the ROI at 10-15Hz.
colIdx      = (1:size(motionProfile,2))';                                   % Column indices, 1 = left edge of ROI
totalMotion = sum(motionProfile, 2);                                        % Total motion per frame
centroidX   = (motionProfile * colIdx) ./ max(totalMotion, eps);            % Horizontal centre of mass of motion, in ROI columns
centroidX(totalMotion < median(totalMotion)) = NaN;                         % Centroid is meaningless when there is no motion

colThresh = median(motionProfile(:)) + 3*robustMAD(motionProfile(:));       % What counts as "this column moved"

nWin = 4;                                                                   % Frames before the peak to measure the sweep over
directionality = nan(numel(lickFrames), 1);                                 % +1 = clean rightward sweep, 0 = jitter, -1 = leftward
spatialExtent  = nan(numel(lickFrames), 1);                                 % Fraction of ROI columns moving at the peak

for i = 1:numel(lickFrames)
    f   = lickFrames(i);
    seg = centroidX(max(1, f-nWin) : f);                                    % Centroid path over the rising phase only
    seg = seg(~isnan(seg));                                                 % Drops low-motion frames
    if numel(seg) >= 3
        netDisp = seg(end) - seg(1);                                        % How far the centroid actually travelled
        pathLen = sum(abs(diff(seg)));                                      % How far it moved in total, including reversals
        directionality(i) = netDisp / max(pathLen, eps);                    % Ratio near 1 = straight sweep, near 0 = back-and-forth
    end
    spatialExtent(i) = mean(motionProfile(f,:) > colThresh);                % Wide for a tongue, narrow for whiskers
end

%% 3 - Assign lick times to trials
lickVideoTimes = timestamps(lickFrames);                                    % Converts lick frame indices to video timestamps
lickBpodTimes  = videoToBpod(lickVideoTimes);                               % Converts video timestamps to synced Bpod clock time
nLicks = numel(lickFrames);                                                 % Total number of detected lick events

trialNumber = nan(nLicks, 1);                                               % Licks per trial
lickOdorID = repmat("", nLicks, 1);                                         % Licks per odor per trial
lickOutcome = repmat("", nLicks, 1);                                        % Licks per outcome per trial
timeFromTrialOn = nan(nLicks, 1);                                           % Licks from trial start
timeFromCueOn = nan(nLicks, 1);                                             % Licks from cue start
timeFromOutcome = nan(nLicks, 1);                                           % Licks from outcome
isAnticipatoryLick = false(nLicks, 1);                                      % Licks in anticipatory trace window
timeFromITIWindowStart = nan(nLicks, 1);                                    % Licks from ITI window start
isITILick = false(nLicks, 1);                                               % Licks in anticipatory ITI window
lickRewardHistory = nan(nLicks, 1);                                         % Moving window of lick reward history
timeFromTrialEnd = nan(nLicks, 1);                                          % Licks after trial end

% Flags trials whose ITI window overlaps a Bpod pause -the pause falls between one trial's end and the next trial's start
itiPauseContaminated = false(nTrials, 1);                                   % One flag per trial
for p = 1:numel(pauseAfterTrial)                                            % For each detected pause
    pStart = TrialEnd_s(pauseAfterTrial(p));                                % Pause window in Bpod time
    pEnd   = TrialOnset_s(pauseAfterTrial(p) + 1);
    itiPauseContaminated = itiPauseContaminated | ...                       % Standard interval-overlap test
        (ITIWindowStart_s < pEnd & ITIWindowEnd_s > pStart);
end

for i = 1:nLicks                                                            % For every lick,
    preceding = find(TrialOnset_s <= lickBpodTimes(i));                     % Find most recent trial start timestamp and pair with trial
    if isempty(preceding), continue; end                                    % Licks recorded before session start are discarded
    tn = preceding(end);                                                    % Most recent trial onset before this lick

    trialNumber(i) = tn;                                                    % Populates each trial with lick number
    lickOdorID(i) = odorID(tn);                                             % Populates licks per odor type
    lickOutcome(i) = outcome(tn);                                           % Populates licks per outcome type
    timeFromTrialOn(i) = lickBpodTimes(i) - TrialOnset_s(tn);               % Records exact lick time in relation to trial start

    if ~isnan(CueOn_s(tn))                                                  % If odor timestamp exists,
        timeFromCueOn(i) = lickBpodTimes(i) - CueOn_s(tn);                  % Then calculates licking in relation to odor timestamp
    end
    if ~isnan(Outcome_s(tn))                                                % If trial outcome timestamp exists,
        timeFromOutcome(i) = lickBpodTimes(i) - Outcome_s(tn);              % Then calculates licking in relation to outcome timestamp
    end
    if ~isnan(TrialEnd_s(tn))                                               % If trial end timestamp exists,
        timeFromTrialEnd(i) = lickBpodTimes(i) - TrialEnd_s(tn);            % Then calculates licking in relation to trial end timestamp
    end
    % Odor anticipatory window
    if ~isnan(CueOn_s(tn)) && ~isnan(AnticipatoryEnd_s(tn))                 % If odor and AnticipatoryEnd (outcome/no outcome) timestamp exsts, 
        isAnticipatoryLick(i) = ...                                         % Then an anticipatory lick is defined as:
            lickBpodTimes(i) >= CueOn_s(tn) && ...                          % Happening after start of odor state
            lickBpodTimes(i) <  AnticipatoryEnd_s(tn);                      % And before outcome (or ITI start on no outcome)
    end
    % ITI window
    if ~isnan(ITIWindowStart_s(tn))                                         % If ITI start timestamp exists,
        timeFromITIWindowStart(i) = lickBpodTimes(i) - ITIWindowStart_s(tn);% Then calculates licking in relation to ITI window start
        
        if ~isnan(ITIWindowEnd_s(tn))                                       % If ITI window end timestamp exists, 
            isITILick(i) = lickBpodTimes(i) >= ITIWindowStart_s(tn) && ...  % Then calculates ITI lick as after ITI window start and
                lickBpodTimes(i) <  ITIWindowEnd_s(tn);                     % Before ITI window end (start of odor state of next trial)
        end
    end
    lickRewardHistory(i) = rewardHistory(tn);                               % Reward history at the time of the current trial's lick
end
lickITIContaminated = false(nLicks, 1);                                     % Per-lick copy of the trial-level flag, for the output table
valid = ~isnan(trialNumber);                                                % Licks that were assigned to a trial
lickITIContaminated(valid) = itiPauseContaminated(trialNumber(valid));      % Flags licks whose trial has a pause-inflated ITI window 

%% 4 - Build output table
lickTable = table( ...
    (1:nLicks)',            lickFrames(:),          lickVideoTimes(:), ...  % Pulls out variables/timestamps we've made previously...
    lickBpodTimes(:),       trialNumber,            lickOdorID, ...
    lickOutcome,            timeFromTrialOn,        timeFromCueOn, ...
    timeFromOutcome,        timeFromTrialEnd,       isAnticipatoryLick, ...
    timeFromITIWindowStart, isITILick, lickITIContaminated, lickRewardHistory, ...
    'VariableNames', { ...                                                  % And creates formatted table
    'lickNumber',           'frameIndex',           'videoTime_s', ...
    'bpodTime_s',           'trialNumber',          'odorID', ...
    'outcome',              'timeFromTrialOn',      'timeFromCueOn', ...
    'timeFromOutcome',      'timeFromTrialEnd',     'isAnticipatoryLick', ...
    'timeFromITIWindowStart','isITILick','itiWindowPauseContaminated','rewardHistory_last5'});

fprintf('Detected %d lick events.\n', nLicks);
for k = 1:numel(uniqueOdors)                                                % For each odor used:
    mask = lickOdorID == uniqueOdors(k);
    fprintf('  %-14s  %d licks\n', uniqueOdors(k), sum(mask));              % Prints number of licks for this odor
end
fprintf('\n');
disp(lickTable(1:min(10, height(lickTable)), :));                           % Displays first 10 rows of output table

%% 5 - Save output table
[saveFile, savePath] = uiputfile('lick_times_bpod.csv');                    % Opens file save dialogue
if ~isequal(saveFile, 0)                                                    % If a save location was chosen,
    writetable(lickTable, fullfile(savePath, saveFile));                    % Writes the lick table to .csv
    fprintf('Saved to %s\n', fullfile(savePath, saveFile));
end

%% 6 - Diagnostic figures
odorColors = lines(numel(uniqueOdors));                                     % Assigns a unique color per odor identity
                                                                            % Used consistently across all plots
% Figure 1: Lick detection + sync diagnostics
fig1 = figure('Name','Lick Detection + Sync Diagnostics', ...
       'NumberTitle','off','Position',[60 60 1300 900]);
movegui(fig1,'center');                                                     % Repositions so the whole window (title bar included) is on-screen

% P1 - Full session motion trace + detected licks raster plot
% Primary quality check — lick dots should sit on genuine motion spikes
% Threshold lines show min and max detection boundaries
subplot(2,2,[1 2]);
plot(timestamps, motionZ, 'Color',[0.2 0.5 0.8], 'LineWidth',0.7);          % Full-session smoothed motion Z-score trace
hold on;
hLeg = gobjects(0);                                                         % Populates legend with only what was used in the session
for k = 1:numel(uniqueOdors)                                                % Overlays detected licks colored by odor identity
    mask = lickOdorID == uniqueOdors(k);
    if any(mask)
        hLeg(end+1) = scatter(lickVideoTimes(mask), motionZ(lickFrames(mask)), ... 
                35, odorColors(k,:), 'filled', 'DisplayName', uniqueOdors(k));
    end
end
for p = 1:numel(pauseVideoStart_s)                                          % Shades each Bpod pause window in grey
    hp = xregion(pauseVideoStart_s(p), pauseVideoEnd_s(p), ...              % Marks where licks were excluded
            'FaceColor',[0.6 0.6 0.6], 'FaceAlpha',0.4, 'DisplayName','Bpod pause');
    if p == 1, hLeg(end+1) = hp; end                                        % One entry regardless of how many pauses
end

yline(lickAmpThresh, 'r--', sprintf('Min threshold = %g', lickAmpThresh));  % Minimum threshold line
yline(lickAmpMax,    'g--', sprintf('Max threshold = %g', lickAmpMax));     % Maximum threshold line
xlabel('Video time (s)'); ylabel('Motion Z-score');
title(sprintf('Frame-Difference Motion  —  %d Licks Detected', nLicks));
if ~isempty(hLeg)                                                           % AutoUpdate off stops the yline/xline objects
    legend(hLeg, 'Location','northeast', 'AutoUpdate','off');               % Skips the legend if nothing was plotted for a dataset
end

% P2 - Lick raster — cue aligned, colored by odor identity
% Each row = one trial, each dot = one lick
% Anticipatory licking appears as dots before the cue onset line
% CS+ vs CS- differences visible as divergence in pre-outcome licking
subplot(2,2,3);
hold on;
hLegP2 = gobjects(0);                                                       % Collects only the scatter handles
for k = 1:numel(uniqueOdors)                                                % For all trial types
    mask = lickOdorID == uniqueOdors(k) & ~isnan(timeFromCueOn);            % Tracks licks from cue onset
    if any(mask)
        hLegP2(end+1) = scatter(timeFromCueOn(mask), trialNumber(mask), ... % Separates by each trial
                12, odorColors(k,:), 'filled', 'DisplayName', uniqueOdors(k));
    end
end
xline(0,'k--','Cue on','LabelVerticalAlignment','bottom');                  % Cue onset reference                                                      
xline(1,'k:','Cue off','LabelVerticalAlignment','bottom');                  % Cue offset (end of 1s odor state)
xline(3,'b:','Outcome','LabelVerticalAlignment','bottom');                  % Outcome delivery reference
xlabel('Time from cue onset (s)'); ylabel('Trial #');
title('Lick Raster — Cue Aligned');
if ~isempty(hLegP2)
    legend(hLegP2, 'Location','northeast', 'AutoUpdate','off');
end

% P3 - Peri-cue lick rate by odor identity
% Converts raster to rate curves for quantitative comparison
% Anticipatory licking visible in [-1, 0] pre-cue window and trace period [1, 3]
subplot(2,2,4);
edges = -2 : 0.1 : 8;                                                       % 100ms bins
centres = edges(1:end-1) + 0.05;                                            % Bin centers (middle of each 100ms bin)
hold on;
hLegP3 = gobjects(0);                                                       % Collects only the plot handles
for k = 1:numel(uniqueOdors)
    mask = lickOdorID == uniqueOdors(k) & ~isnan(timeFromCueOn);            % Finds all session cue types
    nT = sum(odorID == uniqueOdors(k));                                     % Trial count for this odor 
    if nT == 0 || ~any(mask), continue; end                                 % Ignore unused trial types
    h = histcounts(timeFromCueOn(mask), edges);                             % Counts licks in each bin
    hLegP3(end+1) = plot(centres, h / (nT * 0.1), 'Color', odorColors(k,:), ...% Divides by trial count x bin width (0.1s) = average lick rate per trial (Hz)
         'LineWidth', 1.6, 'DisplayName', uniqueOdors(k));
end
xline(0,'k--','Cue'); xline(1,'k:'); xline(3,'b:','Outcome');
xlabel('Time from cue onset (s)'); ylabel('Lick rate (Hz)');
title('Peri-Cue Lick Rate by Odor Identity');
if ~isempty(hLegP3)
    legend(hLegP3, 'Location','northeast', 'AutoUpdate','off');
end
xlim([-2 8]);

% Figure 2: Anticipatory licking + ITI lick analysis
figure('Name','Anticipatory + ITI Lick Analysis', ...
       'NumberTitle','off','Position',[60 60 1300 500]);

% P1 - Anticipatory lick raster — cue aligned
% Shows licking from cue onset through outcome delivery, includes licking during odor state and trace period
% isAnticipatoryLick variable used to isolate this window
subplot(1,3,1);
hold on;
hLegF2P1 = gobjects(0);                                                     % Collects only the scatter handles
for k = 1:numel(uniqueOdors)                                                % Odor onset + trace cue aligned raster plot
    mask = lickOdorID == uniqueOdors(k) & isAnticipatoryLick;
    if any(mask)
        hLegF2P1(end+1) = scatter(timeFromCueOn(mask), trialNumber(mask), ...
                12, odorColors(k,:), 'filled', 'DisplayName', uniqueOdors(k));
    end
end
xline(0,'k--','Cue on','LabelVerticalAlignment','bottom');
xline(1,'k:','Cue off','LabelVerticalAlignment','bottom');
xline(3,'b:','Outcome','LabelVerticalAlignment','bottom');
xlabel('Time from cue onset (s)'); ylabel('Trial #');
title('Anticipatory Lick Raster');
if ~isempty(hLegF2P1)
legend(hLegF2P1,'Location','northeast', 'AutoUpdate','off');
end
xlim([-0.5 4]);

% P2 - ITI anticipatory lick raster
% Shows licking during the ITI anticipatory window, window starts at ITI onset + ITILickOffset_s 
% Window ends at cue onset of the next trial - Can adjust 6 second window start in section 1
subplot(1,3,2);
hold on;
hLegF2P2 = gobjects(0);                                                     % Collects only the scatter handles
for k = 1:numel(uniqueOdors)
    mask = lickOdorID == uniqueOdors(k) & isITILick;                        % ITI window licking per trial
    if any(mask)
        hLegF2P2(end+1) = scatter(timeFromITIWindowStart(mask), trialNumber(mask), ...
                12, odorColors(k,:), 'filled', 'DisplayName', uniqueOdors(k));
    end
end
xline(0,'k--',sprintf('ITI +%.0fs', ITILickOffset_s),'LabelVerticalAlignment','bottom');
meanWindowDur = mean(ITIWindowEnd_s - ITIWindowStart_s, 'omitnan');         % Mean window duration varies due to variable ITI
xline(meanWindowDur,'b:','Next cue (mean)','LabelVerticalAlignment','bottom');
xlabel(sprintf('Time from ITI +%.0fs (s)', ITILickOffset_s));
ylabel('Trial #');
title(sprintf('ITI Anticipatory Lick Raster  (window starts ITI +%.0fs)', ITILickOffset_s));
if ~isempty(hLegF2P2)
    legend(hLegF2P2, 'Location','northeast', 'AutoUpdate','off');
end

% P3 - ITI lick rate vs recent reward history 
% Tests whether ITI licking tracks recent reward experience
subplot(1,3,3);
histBins = 0 : 0.2 : 1.0;                                                  % Bins reward history into 20% increments
binCentres = histBins(1:end-1) + 0.1;                                       % Bin centers for plotting
itiLickRate = nan(numel(binCentres), 1);                                    % ITI lick rate for each reward history bin
if any(itiPauseContaminated)
    fprintf('ITI windows overlapping a Bpod pause (excluded from ITI rate): %s\n\n', ...
            mat2str(find(itiPauseContaminated).'));
end

for b = 1:numel(binCentres)
    if b == numel(binCentres)                                               % Last bin includes 1.0 exactly
        trialMask = rewardHistory >= histBins(b) & rewardHistory <= histBins(b+1) ...
                    & ~itiPauseContaminated;                                % Skips ITI windows spanning a pause
    else
        trialMask = rewardHistory >= histBins(b) & rewardHistory < histBins(b+1) ...
                    & ~itiPauseContaminated;
    end
    if sum(trialMask) == 0, continue; end                                   % Skips empty bins
    lickMask = isITILick & ismember(trialNumber, find(trialMask));          % Finds ITI licks on those trials
    totalITITime = sum(ITIWindowEnd_s(trialMask)...
        - ITIWindowStart_s(trialMask), 'omitnan');                          % Normalizes by total ITI window time
    if totalITITime > 0
        itiLickRate(b) = sum(lickMask) / totalITITime;                      % Converts to Hz
    end
end
bar(binCentres, itiLickRate, 0.15, 'FaceColor',[0.35 0.70 0.40], 'EdgeColor','none');  % Bar plot of ITI lick rate per reward history bin
xlabel('Recent reward fraction (last 5 trials)');
ylabel('ITI lick rate (Hz)');
title('ITI Lick Rate vs Reward History');
xticks(binCentres);
xticklabels({'0-20%','20-40%','40-60%','60-80%','80-100%'});

% Figure 3: Trial-level lick validation
% Shows raw and smoothed motion traces with detected licks and Bpod state boundaries
bpodToVideo = @(t) (t - syncCoeffs(1)) / syncCoeffs(2);                     % Inverse sync for converting Bpod times to video times
rawBaseline = median(motionTrace);                                          % Session-wide baseline for raw threshold lines
rawMADval = robustMAD(motionTrace);                                         % Session-wide MAD for raw threshold lines

% Compute all peaks above min threshold for rejected peak display
[allPeakVals_full, allPeakFrames_full] = findpeaks(motionZ, ...             % Finds all peaks above min threshold (before max/pause filters)
    'MinPeakHeight',   lickAmpThresh, ...
    'MinPeakDistance', lickMinDist_fr);
allPeakTimes_full = timestamps(allPeakFrames_full);                         % Video timestamps of those peaks

% Create figure with navigation controls
hFig = figure('Name','Trial Lick Validation — Use buttons to navigate', ...
              'NumberTitle','off','Position',[100 50 1200 750]);

% Store shared state in figure UserData so button callbacks can access it
% This avoids using global variables while keeping all data accessible to callbacks
ud.currentTrial      = 1;
ud.nTrials           = nTrials;
ud.timestamps        = timestamps;
ud.motionTrace       = motionTrace;
ud.motionZ           = motionZ;
ud.lickFrames        = lickFrames;
ud.lickVideoTimes    = lickVideoTimes;
ud.TrialOnset_s      = TrialOnset_s;
ud.TrialEnd_s        = TrialEnd_s;
ud.CueOn_s           = CueOn_s;
ud.Outcome_s         = Outcome_s;
ud.odorID            = odorID;
ud.outcome           = outcome;
ud.lickAmpThresh     = lickAmpThresh;
ud.lickAmpMax        = lickAmpMax;
ud.lickMinDist_fr    = lickMinDist_fr;
ud.rawBaseline       = rawBaseline;
ud.rawMADval         = rawMADval;
ud.bpodToVideo       = bpodToVideo;
ud.allPeakVals_full  = allPeakVals_full;
ud.allPeakTimes_full = allPeakTimes_full;
ud.pauseMask = pauseMask;
ud.allPeakFrames_full = allPeakFrames_full;
set(hFig, 'UserData', ud);

% Navigation buttons
btnHeight = 0.06;                                                           % Button height (fraction of figure height)
btnY      = 0.01;                                                           % Button vertical position (bottom of figure)

uicontrol('Style','pushbutton','String','◀  Prev Trial', ...               % Step back one trial
    'Units','normalized','Position',[0.02 btnY 0.15 btnHeight], ...
    'FontSize',11,'Callback',@(~,~) navigateTrial(hFig, -1));

uicontrol('Style','pushbutton','String','Next Trial  ▶', ...               % Step forward one trial
    'Units','normalized','Position',[0.19 btnY 0.15 btnHeight], ...
    'FontSize',11,'Callback',@(~,~) navigateTrial(hFig, +1));

uicontrol('Style','text','String','Go to trial:', ...                       % Jump to trial label
    'Units','normalized','Position',[0.38 btnY 0.10 btnHeight], ...
    'FontSize',11,'HorizontalAlignment','right');
hTrialInput = uicontrol('Style','edit','String','1', ...                    % Trial number input box
    'Units','normalized','Position',[0.49 btnY 0.07 btnHeight], ...
    'FontSize',11,'Tag','trialInput');
uicontrol('Style','pushbutton','String','Go', ...                           % Jump to trial button
    'Units','normalized','Position',[0.57 btnY 0.05 btnHeight], ...
    'FontSize',11,'Callback',@(~,~) jumpToTrial(hFig, hTrialInput));

uicontrol('Style','text','String',sprintf('Trial 1 / %d', nTrials), ...    % Trial counter display
    'Units','normalized','Position',[0.65 btnY 0.15 btnHeight], ...
    'FontSize',11,'HorizontalAlignment','center','Tag','trialCounter');

uicontrol('Style','pushbutton','String','Next Reward ▶', ...               % Skip to next reward trial
    'Units','normalized','Position',[0.82 btnY 0.16 btnHeight], ...
    'FontSize',10,'ForegroundColor',[0.1 0.6 0.1], ...
    'Callback',@(~,~) navigateToOutcome(hFig, 'Reward'));

% Draw initial trial (trial 1)
drawValidationTrial(hFig, 1);

%% Removed for now - will possibly used for directional lick filter (in addition to motionZ)
% Figure 4: Lick vs whisker separation — exploratory
% Each point is one detected peak. If licks and whisking form distinct clusters,
% the cutoffs for a directional/spatial filter will be visible here.
%figure('Name','Lick vs Whisker Separation','NumberTitle','off');
%scatter(abs(directionality), spatialExtent, 25, peakHeights, 'filled');
%colorbar; xlabel('|Directionality|  (1 = straight sweep)');
%ylabel('Spatial extent  (fraction of ROI columns moving)');
%title('Colour = peak Z-score');

% --- Nested callback functions ---
% Nested functions share the workspace of the parent function
% This allows them to access variables without being passed as arguments

    function navigateTrial(hFig, direction)
        % Moves forward or backward by one trial
        ud       = get(hFig, 'UserData');
        newTrial = ud.currentTrial + direction;                             % Steps one trial forward (+1) or back (-1)
        newTrial = max(1, min(ud.nTrials, newTrial));                       % Clamps to valid range
        drawValidationTrial(hFig, newTrial);
    end

    function jumpToTrial(hFig, hInput)
        % Jumps to trial number entered in text box
        val = str2double(get(hInput, 'String'));                            % Reads the number typed in the box
        ud  = get(hFig, 'UserData');
        if isnan(val) || val < 1 || val > ud.nTrials
            set(hInput, 'String', num2str(ud.currentTrial));               % Resets to current trial if invalid entry
            return
        end
        drawValidationTrial(hFig, round(val));
    end

    function navigateToOutcome(hFig, targetOutcome)
        % Jumps to the next trial of a specific outcome type
        % Wraps around to the beginning of the session if not found forward
        ud         = get(hFig, 'UserData');
        searchFrom = ud.currentTrial + 1;
        if searchFrom > ud.nTrials, searchFrom = 1; end                    % Wrap to beginning

        for t = searchFrom : ud.nTrials                                     % Search forward from current position
            if ud.outcome(t) == targetOutcome
                drawValidationTrial(hFig, t);
                return
            end
        end
        for t = 1 : ud.currentTrial                                         % Wrap around to beginning if not found
            if ud.outcome(t) == targetOutcome
                drawValidationTrial(hFig, t);
                return
            end
        end
        fprintf('No %s trials found in session.\n', targetOutcome);
    end

    function drawValidationTrial(hFig, trialNum)
        % Draws the validation plot for a given trial number
        % Called on initial draw and by all navigation callbacks
        % Clears previous axes and redraws — buttons are preserved

        ud              = get(hFig, 'UserData');
        ud.currentTrial = trialNum;
        set(hFig, 'UserData', ud);

        % Update trial counter and input box displays
        hCounter = findobj(hFig, 'Tag','trialCounter');                     % Finds the trial counter text
        set(hCounter, 'String', sprintf('Trial %d / %d  |  %s  |  %s', ...
            trialNum, ud.nTrials, ud.odorID(trialNum), ud.outcome(trialNum)));
        hInput = findobj(hFig, 'Tag','trialInput');                         % Finds the trial input box
        set(hInput, 'String', num2str(trialNum));

        % Convert Bpod trial boundaries to video time
        % bpodToVideo is the inverse of videoToBpod: t_video = (t_bpod - intercept) / slope
        tStart_v   = ud.bpodToVideo(ud.TrialOnset_s(trialNum));
        tEnd_v     = ud.bpodToVideo(ud.TrialEnd_s(trialNum));
        tCue_v     = ud.bpodToVideo(ud.CueOn_s(trialNum));
        tOutcome_v = ud.bpodToVideo(ud.Outcome_s(trialNum));               % NaN if no outcome
        if isnan(tStart_v) || isnan(tEnd_v)                                 % Trial boundaries missing from Bpod data
            warning('Trial %d has no start/end timestamp — nothing to plot.', trialNum);
            return
        end

        % Get video frames within this trial window
        trialMask       = ud.timestamps >= tStart_v & ud.timestamps <= tEnd_v;  % Video frames that fall within this trial
        t_trial         = ud.timestamps(trialMask);
        rawMotion_trial = ud.motionTrace(trialMask);
        motionZ_trial   = ud.motionZ(trialMask);

        % Threshold lines in raw pixel units
        % Converts Z-score thresholds back to raw pixel change units for P1 display
        rawThreshMin = ud.rawBaseline + ud.lickAmpThresh * ud.rawMADval;
        rawThreshMax = ud.rawBaseline + ud.lickAmpMax    * ud.rawMADval;

        % Detected licks within this trial window
        lickMask_t   = ud.lickVideoTimes >= tStart_v & ud.lickVideoTimes <= tEnd_v;  % Detected licks within this trial
        lickTimes_t  = ud.lickVideoTimes(lickMask_t);
        lickFrames_t = ud.lickFrames(lickMask_t);

        % Rejected peaks (above max threshold) within this window
        % These are shown in red in P2 so you can see what the max filter removed
        inWin         = ud.allPeakTimes_full >= tStart_v & ud.allPeakTimes_full <= tEnd_v;
        peakTimes_win = ud.allPeakTimes_full(inWin);
        peakVals_win  = ud.allPeakVals_full(inWin);
        peakFrames_win = ud.allPeakFrames_full(inWin);                      % Frame indices of peaks in this window
        pauseRejected  = ud.pauseMask(peakFrames_win);                      % Peaks dropped by the Bpod pause filter
        rejectedMask   = peakVals_win > ud.lickAmpMax & ~pauseRejected;     % Max-threshold rejections only

        % Clear previous axes content while preserving navigation buttons
        axList = findobj(hFig, 'Type','axes');                              % Finds all existing plot axes
        delete(axList);                                                     % Deletes them (buttons are uicontrols, not axes, so they are kept)

        plotAreaBottom = 0.10;                                              % Bottom margin reserved for navigation buttons

        % P1 - Raw motion trace
        % Shows unsmoothed signal — what the camera actually captured
        % Genuine licks appear as sharp brief spikes
        % Paw events appear as larger, often broader spikes
        ax1 = axes('Parent',hFig,'Position',[0.08 0.55 0.88 0.40]);         % Top plot area
        plot(ax1, t_trial, rawMotion_trial, 'Color',[0.2 0.5 0.8], 'LineWidth',0.8);
        hold(ax1,'on');
        yline(ax1, rawThreshMin, 'r--', sprintf('Min (Z=%g)', ud.lickAmpThresh), ...
              'LabelHorizontalAlignment','left');
        yline(ax1, rawThreshMax, 'g--', sprintf('Max (Z=%g)', ud.lickAmpMax), ...
              'LabelHorizontalAlignment','left');
        if ~isempty(lickTimes_t)
            scatter(ax1, lickTimes_t, ud.motionTrace(lickFrames_t), ...
                    60, [0.1 0.7 0.1], 'filled', 'DisplayName','Detected licks');
        end
        xline(ax1, tStart_v, 'k-',  'PreOdor',   'LabelVerticalAlignment','bottom');
        xline(ax1, tCue_v,   'b--', 'Cue on',    'LabelVerticalAlignment','bottom');
        if ~isnan(tOutcome_v)
            xline(ax1, tOutcome_v, 'm--', 'Outcome', 'LabelVerticalAlignment','bottom');
        end
        xline(ax1, tEnd_v,   'k-',  'Trial end', 'LabelVerticalAlignment','bottom');
        xlabel(ax1,'Video time (s)'); ylabel(ax1,'Raw motion (pixel change)');
        title(ax1, sprintf('Trial %d — Raw Motion  |  Odor: %s  |  Outcome: %s  |  %d licks detected', ...
              trialNum, ud.odorID(trialNum), ud.outcome(trialNum), sum(lickMask_t)));
        xlim(ax1,[tStart_v tEnd_v]);

        % P2 - Smoothed Z-score trace
        % Shows what the detection algorithm actually runs on
        % Compare with P1 to see effect of smoothing on peak shapes
        % Green dots = detected licks (passed both thresholds)
        % Red dots = rejected peaks (above max threshold — paw/large movement events)
        % Grey dots = peaks recorded while Bpod was paused (box open, hands in frame)
        ax2 = axes('Parent',hFig,'Position',[0.08 plotAreaBottom+0.04 0.88 0.40]);  % Bottom plot area
        plot(ax2, t_trial, motionZ_trial, 'Color',[0.2 0.5 0.8], 'LineWidth',0.8);
        hold(ax2,'on');
        hLeg2 = gobjects(0);                                                % Collects only the handles that belong in the legend
        yline(ax2, ud.lickAmpThresh, 'r--', sprintf('Min = %g', ud.lickAmpThresh), ...
              'LabelHorizontalAlignment','left');
        yline(ax2, ud.lickAmpMax,    'g--', sprintf('Max = %g', ud.lickAmpMax), ...
              'LabelHorizontalAlignment','left');
        if ~isempty(lickTimes_t)
            hLeg2(end+1) = scatter(ax2, lickTimes_t, ud.motionZ(lickFrames_t), ...
                    60, [0.1 0.7 0.1], 'filled', 'DisplayName','Detected licks');
        end
        if any(rejectedMask)
            hLeg2(end+1) = scatter(ax2, peakTimes_win(rejectedMask), peakVals_win(rejectedMask), ...
                    60, [0.9 0.1 0.1], 'filled', 'DisplayName','Rejected (paw/movement)');
        end
        if any(pauseRejected)
            hLeg2(end+1) = scatter(ax2, peakTimes_win(pauseRejected), peakVals_win(pauseRejected), ...
                    60, [0.5 0.5 0.5], 'filled', 'DisplayName','Rejected (Bpod pause)');
        end
        xline(ax2, tStart_v, 'k-',  'PreOdor',   'LabelVerticalAlignment','bottom');
        xline(ax2, tCue_v,   'b--', 'Cue on',    'LabelVerticalAlignment','bottom');
        if ~isnan(tOutcome_v)
            xline(ax2, tOutcome_v, 'm--', 'Outcome', 'LabelVerticalAlignment','bottom');
        end
        xline(ax2, tEnd_v,   'k-',  'Trial end', 'LabelVerticalAlignment','bottom');
        xlabel(ax2,'Video time (s)'); ylabel(ax2,'Motion Z-score (smoothed)');
        title(ax2, sprintf('%d peaks above min  |  %d rejected (max)  |  %d rejected (pause)', ...
              numel(peakVals_win), sum(rejectedMask), sum(pauseRejected)));
        if ~isempty(hLeg2) 
            legend(ax2, hLeg2, 'Location','northeast','AutoUpdate','off');  % Only the scatters — keeps the unnamed motionZ line out
        end 
        xlim(ax2,[tStart_v tEnd_v]);
        drawnow;                                                            % Forces immediate figure update
    end
end