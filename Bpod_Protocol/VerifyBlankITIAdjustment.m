% Verifies that the ITI-before-Blank-trial adjustment (-3s when the next
% trial is a Blank odor cue) is being applied correctly in CueConditioning.m,
% using Bpod's actual recorded state timestamps as ground truth.
%
% Two checks are performed:
%   1) HARD BOUNDS CHECK (deterministic): ExpTimer.m guarantees raw ITI
%      draws fall within [ExpTimerBounds(1), ExpTimerBounds(2)] seconds.
%      So if the code is working correctly:
%         - trials followed by a Blank trial must have recorded ITI in
%           [ExpTimerBounds(1)-BlankShift, ExpTimerBounds(2)-BlankShift]
%         - all other trials must have recorded ITI in
%           [ExpTimerBounds(1), ExpTimerBounds(2)]
%      Any violation is a definitive bug indicator, not just noise.
%   2) DISTRIBUTION OVERLAY: since which trials precede a Blank trial is
%      fixed by the pre-generated TrialSeq (independent of each trial's own
%      random ITI draw), shifting the "precedes-Blank" ITIs by +BlankShift
%      should make their distribution closely overlap the "other trials"
%      distribution.
%
% Usage:
%   VerifyBlankITIAdjustment(BpodSystem.Data)
%   VerifyBlankITIAdjustment(BpodSystem.Data, 'ExpTimerBounds', [8 18], 'BlankShift', 3)

function results = VerifyBlankITIAdjustment(Data, varargin)

p = inputParser;                                                % Creates an input parser to read the optional Name-Value arguments
addParameter(p, 'ExpTimerBounds', [8 18]);                      % ExpTimer.m ITI bounds [a b] (update here if ExpTimer.m is changed)
addParameter(p, 'BlankShift', 3);                               % Seconds subtracted from the ITI before a Blank trial
parse(p, varargin{:});                                          % Reads any arguments passed in
bounds = p.Results.ExpTimerBounds;
shift  = p.Results.BlankShift;

nTrials = numel(Data.RawEvents.Trial);                          % Number of completed trials
if nTrials < 2                                                  % Each check compares a trial with the trial after it, so at least 2 are needed
    fprintf('Not enough completed trials to check (need at least 2).\n');
    results = struct();
    return
end

itiDur        = nan(1, nTrials-1);                              % ITI duration of each trial (the last trial has no 'next trial', so it is left out)
precedesBlank = false(1, nTrials-1);                            % True if the next trial is a Blank trial

for i = 1:(nTrials-1)                                           % For each trial except the last:
    states = Data.RawEvents.Trial{i}.States;                    % Pulls this trial's recorded state timestamps
    if ~isfield(states, 'ITI') || isempty(states.ITI) || any(isnan(states.ITI))
        continue   % skip trials with no valid ITI entry (shouldn't happen)
    end
    itiDur(i) = states.ITI(end) - states.ITI(1);                % Recorded ITI duration = ITI end time - ITI start time

    nextStates = Data.RawEvents.Trial{i+1}.States;              % Pulls the next trial's state timestamps
    precedesBlank(i) = isfield(nextStates, 'Blank_Odor') && ...  % Next trial is a Blank trial if its 'Blank_Odor' state occurred
        ~isempty(nextStates.Blank_Odor) && ~any(isnan(nextStates.Blank_Odor));
end

valid         = ~isnan(itiDur);                                 % Keeps only trials with a valid ITI
itiDur        = itiDur(valid);
precedesBlank = precedesBlank(valid);
trialIdx      = find(valid);                                    % Original trial numbers of the kept trials

blankITI    = itiDur(precedesBlank);                            % ITIs of trials followed by a Blank trial
blankTrials = trialIdx(precedesBlank);                          % Their trial numbers
otherITI    = itiDur(~precedesBlank);                           % ITIs of all other trials
otherTrials = trialIdx(~precedesBlank);                         % Their trial numbers

% --- Hard bounds violation check
tol = 1e-6;                                                     % Small tolerance (1 microsecond) so tiny rounding differences aren't flagged
blankLo = bounds(1) - shift; blankHi = bounds(2) - shift;       % Expected bounds for trials followed by a Blank trial (ExpTimer bounds - shift)
blankViolations = blankTrials(blankITI < blankLo - tol | blankITI > blankHi + tol);  % Trial numbers whose ITI falls outside the Blank-adjusted bounds
otherViolations = otherTrials(otherITI < bounds(1) - tol | otherITI > bounds(2) + tol);  % Trial numbers whose ITI falls outside the normal bounds

fprintf('=== Blank-Trial ITI Adjustment Verification ===\n');   % Prints the results to the command window
fprintf('Trials preceding a Blank trial: %d  (expected range [%.1f, %.1f]s)\n', ...
    numel(blankITI), blankLo, blankHi);
if ~isempty(blankITI)
    fprintf('  Mean: %.3fs | Median: %.3fs | Range: [%.3f, %.3f]\n', ...
        mean(blankITI), median(blankITI), min(blankITI), max(blankITI));
end
fprintf('  Bounds violations: %d', numel(blankViolations));
if ~isempty(blankViolations)
    fprintf('  -> Trial(s): %s', mat2str(blankViolations));
end
fprintf('\n');

fprintf('\nAll other trials: %d  (expected range [%.1f, %.1f]s)\n', ...
    numel(otherITI), bounds(1), bounds(2));
if ~isempty(otherITI)
    fprintf('  Mean: %.3fs | Median: %.3fs | Range: [%.3f, %.3f]\n', ...
        mean(otherITI), median(otherITI), min(otherITI), max(otherITI));
end
fprintf('  Bounds violations: %d', numel(otherViolations));
if ~isempty(otherViolations)
    fprintf('  -> Trial(s): %s', mat2str(otherViolations));
end
fprintf('\n');

if ~isempty(blankITI) && ~isempty(otherITI)                     % Mean difference should be close to the Blank shift
    fprintf('\nMean difference (other - blank): %.3fs  (expected ~%.1fs)\n', ...
        mean(otherITI) - mean(blankITI), shift);
end

if isempty(blankViolations) && isempty(otherViolations)         % PASS only if no trials fall outside their expected bounds
    fprintf('\nResult: PASS - all trials within expected bounds.\n');
else
    fprintf('\nResult: FAIL - see violations above.\n');
end

% --- Visual comparison: shift blank-preceding ITIs by +shift and overlay
if ~isempty(blankITI) && ~isempty(otherITI)                     % Overlay plot only if both groups have trials
    figure('Name', 'Blank ITI Adjustment Check');
    hold on
    histogram(otherITI, 'BinWidth', 0.5, 'FaceAlpha', 0.5, 'DisplayName', 'Other trials (raw)');  % Histogram of normal ITIs (0.5s bins)
    histogram(blankITI + shift, 'BinWidth', 0.5, 'FaceAlpha', 0.5, ...  % Histogram of Blank-preceding ITIs, shifted back up by the Blank shift
        'DisplayName', sprintf('Blank-preceding trials (+%.0fs shifted)', shift));
    xlabel('ITI (s)'); ylabel('Trial count');
    title('Overlap check: shifted blank-preceding ITIs vs. other trials');
    legend('Location', 'best');
    hold off
end

% --- Return results for programmatic use / further analysis
results.blankITI         = blankITI;                            % Returns the results as a struct for further analysis
results.blankTrials      = blankTrials;
results.otherITI         = otherITI;
results.otherTrials      = otherTrials;
results.blankViolations  = blankViolations;
results.otherViolations  = otherViolations;

end
