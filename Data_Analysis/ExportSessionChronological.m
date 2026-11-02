function ExportSessionChronological(Data, filename)
% Exports a Bpod session to a spreadsheet with every state start and event listed in chronological order
% Each row = one state start or event, with session time, trial number, state name, and event label
% GlobalTimer and lick port events are renamed to readable labels (Ex: GlobalTimer2_Start -> AIRPUFF_PRESSURIZE_ON)
%
% Import desired session data into the workspace
% Then use this command to export to excel:
% ExportSessionChronological(SessionData, 'ChronologicalSession.xlsx');
% Open in excel, to zero timestamps enter time 1 into empty column,
% Then select time column, paste special, and choose subtract
% Now select Column A, go to Data -> Filter, and select your negative value
% Select all and then delete to remove all negative values
% Select all and then hide extra blank rows for easier viewing

% For Doric timestamps - open blank excel workbook. Go to Data -> Load .csv
% Open in a PivotTable, then go to Data -> Queries and Connections. Load your
% data set. Unselect all zero values, and change row selection rule from
% "and" to "or". Hit Close/Load, right click on your dataset in Queries and
% Connections, then choose "Load To". Load to table to retrieve filtered data.
allTime   = [];                                             % Creates empty arrays that will collect every row of the output table
allTrial  = [];                                             % Trial number for each row
allState  = {};                                             % State name for each row (blank for event rows)
allEvent  = {};                                             % Event label for each row ('STATE_START' for state rows)

nTrials = length(Data.RawEvents.Trial);                     % Total number of trials in the session

for i = 1:nTrials                                           % For each trial in the session:
    
    trialStart = Data.TrialStartTimestamp(i);               % Absolute start time of this trial (session clock)
    trial = Data.RawEvents.Trial{i};                        % Pulls this trial's recorded states and events
    
    %% ---------- STATES ----------
    stateNames = fieldnames(trial.States);                  % Pulls the names of all states in this trial
    
    for s = 1:length(stateNames)                            % For each state:
        times = trial.States.(stateNames{s});               % [start end] times of the state (relative to trial start)
        
        if ~isempty(times) && ~any(isnan(times))            % Skips states that did not occur this trial (NaN)
            stateStart = trialStart + times(1);             % Converts state start time to session time (start only)
            
            allTime  = [allTime; stateStart];               % Adds a row for this state start
            allTrial = [allTrial; i];
            allState = [allState; stateNames(s)];
            allEvent = [allEvent; {'STATE_START'}];
        end
    end
    
    %% ---------- EVENTS ----------
    eventNames = fieldnames(trial.Events);                  % Pulls the names of all events in this trial
    
    for e = 1:length(eventNames)                            % For each event type:
        
        name = eventNames{e};
        times = trial.Events.(name);                        % All timestamps for this event (an event can occur more than once per trial)
        
        if isempty(times) || any(isnan(times))              % Skips event types with no valid timestamps
            continue
        end
        
        times = times(:);                                   % Makes sure timestamps are a column vector
        
        for k = 1:length(times)                             % For each occurrence of this event:
            
            sessionTime = trialStart + times(k);            % Converts event time to session time
            label = name;                                   % Uses the Bpod event name as the label unless renamed below
            
            % ---- Rename GlobalTimers ----
            % Global Timer numbers match CueConditioning.m (1 = LED, 2/3 = airpuff, 4 = state TTL, 5 = LED TTL, 6 = fiber trigger)
            switch name
                case 'GlobalTimer1_Start'
                    label = 'LED_ON';
                case 'GlobalTimer1_End'
                    label = 'LED_OFF';
                    
                case 'GlobalTimer2_Start'
                    label = 'AIRPUFF_PRESSURIZE_ON';
                case 'GlobalTimer2_End'
                    label = 'AIRPUFF_PRESSURIZE_OFF';

                case 'GlobalTimer3_Start'
                    label = 'AIRPUFF_RELEASE_ON';
                case 'GlobalTimer3_End'
                    label = 'AIRPUFF_RELEASE_OFF';

                case 'GlobalTimer4_Start'
                    label = 'State_TTL_Pulse_ON';
                case 'GlobalTimer4_End'
                    label = 'State_TTL_Pulse_OFF';

                case 'GlobalTimer5_Start'
                    label = 'TTL_LED_ON';
                case 'GlobalTimer5_End'
                    label = 'TTL_LED_OFF';

                case 'GlobalTimer6_Start'
                    label = 'TTL_FIBER_TRIGGER_ON';
                case 'GlobalTimer6_End'
                    label = 'TTL_FIBER_TRIGGER_OFF';

                case 'Port1In'                              % Port1 = lick port
                    label = 'LICK_ON';
                case 'Port1Out'
                    label = 'LICK_OFF';
            end
            
            allTime  = [allTime; sessionTime];              % Adds a row for this event
            allTrial = [allTrial; i];
            allState = [allState; {''}];                    % Event rows have no state name
            allEvent = [allEvent; {label}];
        end
    end
end

%% ---------- SORT ----------
[sortedTime, idx] = sort(allTime);                          % Sorts all rows by session time (earliest first); idx = new row order

T = table(sortedTime, ...                                   % Builds the output table, reordering every column to match the sorted times
          allTrial(idx), ...
          allState(idx), ...
          allEvent(idx), ...
          'VariableNames', {'Time','Trial','State','Event'});

writetable(T, filename);                                    % Writes the table to the chosen file (Ex: .xlsx)

end