% Displays a live, trial-by-trial summary plot of the current Bpod session.
%
% Replaces plotTrialEvents2 in CueConditioning.m's main trial loop. Instead of
% showing raw GlobalTimer/event traces for a single trial, this plots the
% session's cue/outcome history as a scrolling raster: one row per cue type,
% one point per completed trial, with outcome encoded by marker shape/color.
%
% Usage (drop-in replacement inside the CueConditioning.m trial loop):
%   PlotSessionProgress(BpodSystem.Data, 'Figure', event_fig);
%
% Optional Name-Value arguments:
%   'Figure'      - figure handle to draw into (creates one if omitted/invalid)
%   'WindowSize'  - number of most recent trials to display (default 50)

function PlotSessionProgress(Data, varargin)

% --- Parse inputs
p = inputParser;                                                % Creates an input parser to read the optional Name-Value arguments
addParameter(p, 'Figure', []);                                  % 'Figure' defaults to empty (a new figure is made below)
addParameter(p, 'WindowSize', 50);                              % 'WindowSize' defaults to the 50 most recent trials
parse(p, varargin{:});                                          % Reads any arguments passed in from CueConditioning.m
fig        = p.Results.Figure;
windowSize = p.Results.WindowSize;

if isempty(fig) || ~ishandle(fig)                               % If no valid figure was passed in,
    fig = figure('Name', 'Session Progress');                   % Then creates a new one
end
figure(fig);                                                    % Makes this figure the active figure
clf(fig);                                                       % Clears the figure so it can be redrawn with the latest trial

nTrials = numel(Data.RawEvents.Trial);                          % Number of completed trials so far
if nTrials == 0                                                 % Nothing to plot before the first trial finishes
    return
end

% --- Cue type definitions (states match odor_name values set in CueConditioning.m)
cueStates = {'Odor_A', 'Odor_B', 'Odor_C', 'Odor_D', 'Blank_Odor'};  % State names to look for in each trial
cueLabels = {'A', 'B', 'C', 'D', 'Blank'};                      % Short labels shown on the y-axis
cueColors = [0.85 0.20 0.20;   % A - red
             0.20 0.40 0.85;   % B - blue
             0.20 0.70 0.30;   % C - green
             0.90 0.60 0.10;   % D - orange
             0.55 0.25 0.75];  % Blank - purple

% --- Classify each completed trial's cue type and outcome
trialCue     = nan(1, nTrials);                                 % Cue type index (1-5) for each trial; NaN if no cue state is found
trialOutcome = strings(1, nTrials);   % "Reward" | "AirPuff" | "Omission"

for i = 1:nTrials                                               % For each completed trial:
    states = Data.RawEvents.Trial{i}.States;                    % Pulls this trial's recorded state timestamps

    % Cue type: whichever odor state has a valid (non-NaN) timestamp
    for c = 1:numel(cueStates)                                  % Checks each possible cue state
        name = cueStates{c};
        if isfield(states, name) && ~isempty(states.(name)) && ~any(isnan(states.(name)))  % A state that did not occur this trial has NaN timestamps
            trialCue(i) = c;                                    % Stores the cue type index for this trial
            break                                               % Stops once the cue is found (only one cue per trial)
        end
    end

    % Outcome: Reward / AirPuff / Omission, by the same valid-timestamp check
    if isfield(states, 'Reward') && ~isempty(states.Reward) && ~any(isnan(states.Reward))  % 'Reward' state occurred -> reward trial
        trialOutcome(i) = "Reward";
    elseif isfield(states, 'AirPuff_Release') && ~isempty(states.AirPuff_Release) && ~any(isnan(states.AirPuff_Release))  % 'AirPuff_Release' state occurred -> airpuff trial (both CueConditioning.m and CC_Ver2.m have this state)
        trialOutcome(i) = "AirPuff";
    else
        trialOutcome(i) = "Omission";                           % Neither occurred -> omission
    end
end

% --- Plot
ax = axes(fig);                                                 % Creates plot axes inside the figure
hold(ax, 'on');                                                 % Keeps all scatter points on the same axes

for c = 1:numel(cueStates)                                      % For each cue type (one row of the raster):
    idx = find(trialCue == c);                                  % Finds all trials that used this cue
    if isempty(idx)                                             % Skips cue types not used so far
        continue
    end

    rIdx = idx(trialOutcome(idx) == "Reward");                  % Trials with a reward outcome
    pIdx = idx(trialOutcome(idx) == "AirPuff");                 % Trials with an airpuff outcome
    oIdx = idx(trialOutcome(idx) == "Omission");                % Trials with an omission

    if ~isempty(rIdx)
        scatter(ax, rIdx, c*ones(size(rIdx)), 60, cueColors(c,:), 'filled', ...  % Reward = large filled circle in cue color (black outline)
            'Marker', 'o', 'MarkerEdgeColor', 'k');
    end
    if ~isempty(pIdx)
        scatter(ax, pIdx, c*ones(size(pIdx)), 80, cueColors(c,:), ...  % AirPuff = large X in cue color
            'Marker', 'x', 'LineWidth', 2);
    end
    if ~isempty(oIdx)
        scatter(ax, oIdx, c*ones(size(oIdx)), 22, [0.55 0.55 0.55], 'filled', ...  % Omission = small grey filled circle
            'Marker', 'o');
    end
end

% --- Highlight most recent trial
xline(ax, nTrials, 'k--', 'LineWidth', 1);                      % Dashed vertical line marks the most recent trial

% --- Axis formatting
yticks(ax, 1:numel(cueStates));                                 % One y-axis tick per cue type
yticklabels(ax, cueLabels);                                     % Labels ticks A, B, C, D, Blank
ylim(ax, [0.5, numel(cueStates) + 0.5]);                        % Adds a little space above and below the rows
xlim(ax, [max(1, nTrials - windowSize + 1), nTrials + 1]);      % Scrolling window: shows only the most recent 'windowSize' trials
xlabel(ax, 'Trial Number');
ylabel(ax, 'Cue Type');
title(ax, sprintf('Session Progress \x2014 Trial %d', nTrials));  % \x2014 prints an em dash in the title
grid(ax, 'on');
box(ax, 'on');

% --- Legend (outcome shapes, dummy points so it doesn't depend on what's visible)
h1 = scatter(ax, nan, nan, 60, [0 0 0], 'filled', 'Marker', 'o');  % Reward legend entry (invisible NaN point)
h2 = scatter(ax, nan, nan, 80, [0 0 0], 'Marker', 'x', 'LineWidth', 2);  % AirPuff legend entry (invisible NaN point)
h3 = scatter(ax, nan, nan, 22, [0.55 0.55 0.55], 'filled', 'Marker', 'o');  % Omission legend entry (invisible NaN point)
legend(ax, [h1 h2 h3], {'Reward', 'AirPuff', 'Omission'}, 'Location', 'eastoutside');  % Places the legend outside the plot, to the right

% --- Current-trial info panel
lastStates = Data.RawEvents.Trial{end}.States;                  % Pulls state timestamps for the most recent trial
infoStr = sprintf('Trial %d\nCue: %s\nOutcome: %s', nTrials, cueLabels{trialCue(end)}, trialOutcome(end));  % Builds the info panel text (trial #, cue, outcome)
if isfield(lastStates, 'Trace') && ~any(isnan(lastStates.Trace))  % If the 'Trace' state occurred,
    traceDur = lastStates.Trace(end) - lastStates.Trace(1);     % Trace duration = end time - start time
    infoStr = sprintf('%s\nTrace: %.3fs', infoStr, traceDur);   % Adds trace duration to the info panel
end
if isfield(lastStates, 'ITI') && ~any(isnan(lastStates.ITI))    % Same for the 'ITI' state
    itiDur = lastStates.ITI(end) - lastStates.ITI(1);
    infoStr = sprintf('%s\nITI: %.2fs', infoStr, itiDur);
end
annotation(fig, 'textbox', [0.78 0.72 0.20 0.22], 'String', infoStr, ...  % Draws the info panel as a text box in the upper right of the figure
    'FitBoxToText', 'on', 'BackgroundColor', 'w', 'EdgeColor', 'k', 'FontSize', 9);

hold(ax, 'off');                                                % Releases the axes hold
drawnow;                                                        % Forces the figure to update now (otherwise MatLab may wait until the trial loop pauses)

end
