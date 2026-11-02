function plotLickRasterByOdor()
% Visualize lick bouts as rasters across trials, grouped by odor.
% X-axis = time (seconds)
% Y-axis = trial number (true trial # labels, evenly spaced)
% Background color shows trial states (PreOdor, Odor_x, Trace, ITI)
% Includes legend for state color meanings.
% Licks come from the Bpod lick port events (Port1In/Port1Out), not from video
% Run with no inputs: a file picker asks for a Bpod session .mat file

[filename, pathname] = uigetfile('*.mat', 'Select a Bpod session data file');  % Opens file picker to choose a session file
if isequal(filename,0)                                          % If no file is chosen,
    disp('User canceled file selection.');
    return;
end

dataStruct = load(fullfile(pathname, filename));                % Loads the chosen file
if ~isfield(dataStruct, 'SessionData')                          % Checks that the file contains Bpod SessionData
    error('No SessionData found in file.');
end
Data = dataStruct.SessionData;                                  % Pulls the SessionData struct

%% --- Define state names and colors ---
baseStates = {'PreOdor','Trace','ITI'};                         % States shown in every trial
odorStates = {'Odor_A','Odor_B','Odor_C','Odor_D','Blank_Odor'};  % All possible odor cue states (only one occurs per trial)
allStates = [baseStates, odorStates];                           % Combines both lists

stateColors = containers.Map( ...                               % Assigns a background color to each state
    {'PreOdor','Odor_A','Odor_B','Odor_C','Odor_D','Blank_Odor','Trace','ITI'}, ...
    {[0.85 0.85 0.85], ... % light gray
     [1.0 0.8 0.8], ...   % pinkish red
     [1.0 0.8 0.8], ...
     [1.0 0.8 0.8], ...
     [1.0 0.8 0.8], ...
     [0.9 0.9 1.0], ...   % light blue
     [0.8 0.9 1.0], ...   % blue-tinted
     [1.0 1.0 0.8]});     % pale yellow

%% --- Identify which odors were used ---
nTrials = length(Data.RawEvents.Trial);                         % Total number of trials in the session
odorPerTrial = strings(nTrials,1);                              % Will store which odor was used on each trial

for t = 1:nTrials                                               % For each trial:
    stateNames = fieldnames(Data.RawEvents.Trial{t}.States);    % Pulls the names of all states in this trial's state machine
    odorMatch = intersect(stateNames, odorStates);              % Finds the odor state (CueConditioning.m only adds that trial's odor state)
    if ~isempty(odorMatch)
        odorPerTrial(t) = odorMatch{1};                         % Stores the odor used on this trial
    else
        odorPerTrial(t) = "Unknown";                            % No odor state found
    end
end

odorTypesUsed = unique(odorPerTrial);                           % List of odors used in the session
odorTypesUsed(odorTypesUsed == "Unknown") = [];                 % Removes 'Unknown' from the list

%% --- Main plotting loop ---
for o = 1:length(odorTypesUsed)                                 % Creates one figure per odor:
    odorName = odorTypesUsed{o};
    trialIdxs = find(odorPerTrial == odorName);                 % Trial numbers that used this odor
    if isempty(trialIdxs)
        continue;
    end

    figure('Name', odorName, 'Color', 'w'); hold on;            % New figure named after the odor
    nOdorTrials = numel(trialIdxs);                             % Number of trials for this odor
    yPositions = 1:nOdorTrials;                                 % Rows are evenly spaced (1, 2, 3...) regardless of actual trial number

    % --- Plot each trial for this odor ---
    for tIdx = 1:nOdorTrials
        t = trialIdxs(tIdx);                                    % Actual trial number
        trial = Data.RawEvents.Trial{t};                        % Pulls this trial's states and events
        yBase = yPositions(tIdx);                               % Row position for this trial

        % Shade background states
        for s = 1:length(allStates)                             % For each state:
            sName = allStates{s};
            if isfield(trial.States, sName) && ~isempty(trial.States.(sName))  % If the state exists in this trial,
                sTimes = trial.States.(sName)(1,:);             % Pulls its [start end] times
                if numel(sTimes) == 2 && all(~isnan(sTimes))    % Only shades states that actually occurred (not NaN)
                    fill([sTimes(1) sTimes(2) sTimes(2) sTimes(1)], ...  % Draws a shaded box from state start to state end
                         [yBase-0.4 yBase-0.4 yBase+0.4 yBase+0.4], ...
                         stateColors(sName), 'EdgeColor', 'none', 'FaceAlpha', 0.5);
                end
            end
        end

        % Plot licks (Port1In → Port1Out)
        if isfield(trial.Events, 'Port1In') && isfield(trial.Events, 'Port1Out')  % Only plots licks if both lick onset and offset events exist
            ins = trial.Events.Port1In;                         % Lick onset times (lick port beam broken)
            outs = trial.Events.Port1Out;                       % Lick offset times (beam restored)
            nLicks = min(length(ins), length(outs));            % Pairs onsets with offsets (uses the smaller count in case one is missing)
            for l = 1:nLicks                                    % For each lick:
                x1 = ins(l);
                x2 = outs(l);
                line([x1 x2], [yBase yBase], 'Color', 'k', 'LineWidth', 1.5);  % Draws a black line from lick onset to lick offset
            end
        end
    end

    %% --- Formatting ---
    xlabel('Time (s)');
    ylabel('Trial number');
    title(sprintf('Lick Raster for %s', odorName), 'Interpreter', 'none');
    yticks(yPositions);                                         % One y-axis tick per row
    yticklabels(string(trialIdxs)); % actual trial numbers
    ylim([0 nOdorTrials+1]);                                    % Adds space above and below the rows
    set(gca, 'YDir', 'reverse'); % earliest trial at top
    grid on; box on;

    %% --- Add legend for state colors ---
    legendStates = {'PreOdor', odorName, 'Trace', 'ITI'};       % Legend shows only the states relevant to this odor's figure
    legendPatches = gobjects(length(legendStates),1);           % Pre-allocates legend handles
    for i = 1:length(legendStates)
        c = stateColors(legendStates{i});                       % Pulls the color for each state
        legendPatches(i) = patch([NaN NaN],[NaN NaN], c, ...    % Invisible patches (NaN) used only to show state colors in the legend
            'FaceAlpha',0.5,'EdgeColor','none');
    end
    legend(legendPatches, legendStates, 'Location','eastoutside', 'Box','off');  % Places the legend outside the plot, to the right
end
end