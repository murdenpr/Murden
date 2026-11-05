function CC_Ver2

% CC_Ver2: Cue conditioning with no Trace state.
%
% Trial structure: PreOdor -> Odor -> Outcome (Reward / AirPuff_Release / ITI on omission) -> ITI -> TrialEnd
%
% The outcome starts at the moment the odor state ends, for every outcome type. On airpuff trials,
% Global Timer 2 is triggered at odor onset with an onset delay of (Odor - AirPuff_Pressurize_Time),
% so the pressurize valve opens partway through the odor and pressurization finishes exactly when
% the odor state ends. The trial then moves straight into 'AirPuff_Release'.
%
% Example: Odor = 1 s, AirPuff_Pressurize_Time = 0.5 s
%   0.0 s  odor valve opens, Timer 2 triggered (waiting)
%   0.5 s  Timer 2 starts, pressurize valve opens
%   1.0 s  odor state ends, Timer 2 ends, trial enters 'AirPuff_Release'

global BpodSystem % Imports the BpodSystem object to the function workspace

% Global timer list:
%   GT1 — IR LED flash, loops entire session (camera-visible)
%   GT2 — airpuff pressurize solenoid
%   GT3 — airpuff release solenoid
%   GT4 — TTL pulse on BNC1:
%            GT4_Start(1) = odor valve open
%            GT4_Start(2) = water valve open (reward) or airpuff pressurize (airpuff)
%            GT4_Start(3) = airpuff release (airpuff trials only)
%            Only GT4_Start(1) present on no-outcome trials
%   GT5 — trial start TTL pulse BNC1
%   GT6 — photometry TTL trigger BNC2

%% Setup (runs once before the first trial)
maxTrials = 400; % Set to some sane value (replaced below by the n_trials value entered in the GUI)

%--- Define parameters and trial structure
S = BpodSystem.ProtocolSettings;        % Loads settings file chosen in launch manager into current workspace as a struct called 'S'
if isempty(fieldnames(S))               % If chosen settings file was an empty struct, populate struct with default settings
    S.OdorIdentities = randperm(8);     % Can use this to randomize our valves (use different odors for different mice, change in cur_trial_type settings)

    S.GUI.PreOdor = 2;                % The following S.GUI commands set our default GUI values (can be changed in the pre-trial GUI)
    S.GUI.Odor = 1;                   % Odor duration; on airpuff trials pressurization happens inside this window
    S.GUI.ITI_exp_mean = 11;          % Mean ITI (s) passed to ExpTimer.m
    S.GUI.RewardSize = 5;             % Reward volume (µL); converted to water valve open time by GetValveTimes
    S.GUI.n_trials = 400;             % Total number of trials in the session
    S.GUI.Trial_Chunk_Size = 20;      % Trials per chunk; UrnModel.m balances trial types/outcomes within each chunk
    S.GUI.LEDFlashEnable = 1;         % Turns the IR LED sync flash (PIB_LED_Flash.m) on/off
    S.GUIMeta.LEDFlashEnable.Style = 'checkbox';
    S.GUI.LEDFlashInterval = 30;      % Time between LED flashes (s), set longer than single trial max duration if only trial start flash is wanted
    S.GUIMeta.LEDFlashInterval.Style = 'edit';
    S.GUI.AirPuff_Pressurize_Time = 0.5;                                            % Must be <= Odor (pressurization has to fit inside the odor state)
    S.GUIMeta.AirPuff_Pressurize_Time.Style = 'edit';
    S.GUI.AirPuff_Release_Time = 0.2;  % Airpuff release duration (s)
    S.GUIMeta.AirPuff_Release_Time.Style = 'edit';

    S.GUI.A_enabled = 1;              % Each trial type (A-D, Blank) has the same settings: enabled = checkbox to include it,
    S.GUIMeta.A_enabled.Style = 'checkbox';
    S.GUI.A_freq = 0.5;               % freq = fraction of all trials that are this type (enabled freqs must sum to 1),
    S.GUI.A_reward_prob = 0.9;        % reward_prob = probability of a reward outcome,
    S.GUI.A_airpuff_prob = 0;         % airpuff_prob = probability of an airpuff outcome (anything left over = omission)

    S.GUI.B_enabled = 1;
    S.GUIMeta.B_enabled.Style = 'checkbox';
    S.GUI.B_freq = 0.5;
    S.GUI.B_reward_prob = 0;
    S.GUI.B_airpuff_prob = 0;

    S.GUI.C_enabled = 0;
    S.GUIMeta.C_enabled.Style = 'checkbox';
    S.GUI.C_freq = 0.5;
    S.GUI.C_reward_prob = 0.9;
    S.GUI.C_airpuff_prob = 0;

    S.GUI.D_enabled = 0;
    S.GUIMeta.D_enabled.Style = 'checkbox';
    S.GUI.D_freq = 0.5;
    S.GUI.D_reward_prob = 0;
    S.GUI.D_airpuff_prob = 1.0;

    S.GUI.blank_enabled = 0;
    S.GUIMeta.blank_enabled.Style = 'checkbox';
    S.GUI.blank_freq = 0.5;
    S.GUI.blank_reward_prob = 0.9;
    S.GUI.blank_airpuff_prob = 0;

    S.GUIPanels.Odor_A = {'A_enabled','A_freq','A_reward_prob','A_airpuff_prob'};       % S.GUIPanels commands decide the layout/ordering of our GUI
    S.GUIPanels.Odor_B = {'B_enabled','B_freq','B_reward_prob','B_airpuff_prob'};
    S.GUIPanels.Odor_C = {'C_enabled','C_freq','C_reward_prob','C_airpuff_prob'};
    S.GUIPanels.Odor_D = {'D_enabled','D_freq','D_reward_prob','D_airpuff_prob'};
    S.GUIPanels.Blank = {'blank_enabled','blank_freq','blank_reward_prob','blank_airpuff_prob'};
    S.GUIPanels.General = {'PreOdor','Odor','ITI_exp_mean','RewardSize','n_trials','Trial_Chunk_Size','LEDFlashEnable','LEDFlashInterval','AirPuff_Pressurize_Time','AirPuff_Release_Time'};

end

%--- Initialize plots and start USB connections to any modules
BpodParameterGUI('init', S);                                                        % Initialize parameter GUI plugin

load_odor_serial_messages;                                                          % Loads bit commands for the valve driver module (used for opening/closing valves)
% A = BpodAnalogIn(BpodSystem.ModuleUSB.AnalogIn1);
% LoadSerialMessages('AnalogIn1', {['L' 1], ['L' 0]});                              % No AnalogIn module - removed module and LoadSerialMessages call
%load_arduino_commands                                                              % Loads the command list for arduino output commands (Ex: send timestamps to cameras/photometry system)

BpodSystem.Status.Pause = 1;                                                        % Pauses the bpod system upon CueConditioning GUI load
HandlePauseCondition;                                                               % User must press play to continue
S = BpodParameterGUI('sync', S);                                                    % Pulls the current entered GUI values
BpodSystem.ProtocolSettings=S;                                                      % And loads them into the Bpod 'S' struct
SaveBpodProtocolSettings();                                                         % Saves the current settings so they can undergo frequency check in the next block of code
maxTrials = S.GUI.n_trials;                                                         % Defines variable maxTrials as the value entered in the GUI for n_trials

%check frequencies add to 1
total_freq = S.GUI.A_enabled*S.GUI.A_freq+S.GUI.B_enabled*S.GUI.B_freq+S.GUI.C_enabled*S.GUI.C_freq+S.GUI.D_enabled*S.GUI.D_freq+S.GUI.blank_enabled*S.GUI.blank_freq;
while abs(total_freq - 1) > 1e-9                                                    % Checks that the enabled frequencies add to 1 (allows for tiny rounding errors, Ex: 0.7+0.2+0.1)
    disp('Trial frequencies do not add to 1');                                      % If frequency values do not add to 1, display this error message
    BpodSystem.Status.Pause = 1;                                                    % The system will remain paused until valid frequencies are entered
    HandlePauseCondition;                                                           % Once frequencies sum to 1, you can now hit play to continue
    S = BpodParameterGUI('sync', S);                                                % Pulls the current entered GUI values
    BpodSystem.ProtocolSettings=S;                                                  % And loads them into the Bpod 'S' struct
    SaveBpodProtocolSettings();                                                     % Saves the current settings a final time now that trial type frequency check is complete
    total_freq = S.GUI.A_enabled*S.GUI.A_freq+S.GUI.B_enabled*S.GUI.B_freq+S.GUI.C_enabled*S.GUI.C_freq+S.GUI.D_enabled*S.GUI.D_freq+S.GUI.blank_enabled*S.GUI.blank_freq;
end
%check pressurization fits inside the odor state (only matters if enabled trial has a possible airpuff outcome)
airpuff_used = @(S) S.GUI.A_enabled*S.GUI.A_airpuff_prob + S.GUI.B_enabled*S.GUI.B_airpuff_prob + ...
    S.GUI.C_enabled*S.GUI.C_airpuff_prob + S.GUI.D_enabled*S.GUI.D_airpuff_prob + ...
    S.GUI.blank_enabled*S.GUI.blank_airpuff_prob > 0;                               % True if any enabled trial type has a nonzero airpuff probability
while airpuff_used(S) && S.GUI.AirPuff_Pressurize_Time > S.GUI.Odor                 % Pressurization must finish by the end of the odor state, so it can't be longer than the odor
    disp('ERROR: AirPuff_Pressurize_Time must be ≤ Odor');                         % If it is longer, display this error message
    BpodSystem.Status.Pause = 1;                                                    % The system will remain paused until valid times are entered
    HandlePauseCondition;                                                           % Once fixed, press play to continue
    S = BpodParameterGUI('sync', S);                                                % Pulls the newly entered GUI values
    BpodSystem.ProtocolSettings=S;                                                  % And loads them into the Bpod 'S' struct
    SaveBpodProtocolSettings();                                                     % Saves the corrected settings
end
%check outcome probabilities for each enabled trial type
outcomeTypes = {'A','B','C','D','blank'};                                           % GUI name prefixes for each trial type (Ex: 'A' -> S.GUI.A_reward_prob)
outcomeError = true;                                                                % Starts as true so the check below runs at least once
while outcomeError                                                                  % Repeats until every enabled trial type has valid outcome probabilities
    outcomeError = false;                                                           % Assumes values are valid until a problem is found
    for k = 1:numel(outcomeTypes)                                                   % Loops through each trial type (A, B, C, D, blank)
        t = outcomeTypes{k};                                                        % Defines t as the current trial type prefix
        if S.GUI.([t '_enabled']) && ...                                            % Only enabled trial types are checked; for each one, reward + airpuff
                S.GUI.([t '_reward_prob']) + S.GUI.([t '_airpuff_prob']) > 1        % probabilities must not add up to more than 1 (leftover = omission)
            disp(['ERROR: ' t '_reward_prob + ' t '_airpuff_prob must not add up to more than 1']); % Names the trial type that needs fixing
            outcomeError = true;                                                    % Flags the error so the system pauses below
        end
    end
    if outcomeError                                                                 % If any trial type had invalid values:
        BpodSystem.Status.Pause = 1;                                                % The system will remain paused until valid probabilities are entered
        HandlePauseCondition;                                                       % Once values are corrected in the GUI, hit play to re-check
        S = BpodParameterGUI('sync', S);                                            % Pulls the corrected GUI values
        BpodSystem.ProtocolSettings=S;                                              % And loads them into the Bpod 'S' struct
        SaveBpodProtocolSettings();                                                 % Saves the corrected settings; the while loop then checks them again
    end
end
event_fig = make_blank_fig;                                                         % Generates a blank figure that will be filled out as the trial loop progresses

%% Main loop (runs once per trial)
S = BpodParameterGUI('sync', S);                                    % Pulls the final GUI values before the trial sequence is built
[TrialSeq, OutcomePools, chunkSizes] = UrnModel(S.GUI);             % Calls UrnModel.m to generate trial sequence and outcomes using entered CueConditioning.m GUI settings
PreviewTrialSequence(TrialSeq, OutcomePools, chunkSizes);           % Commands PreviewTrialSequence.m to generate a trial sequence matrix from UrnModel.m results in the command window
disp('==Press PLAY to begin trials==')                              % This message displays in the command window once valid trial session parameters are locked in
disp('==============================')
BpodSystem.Status.Pause = 1;                                        % Upon pressing play once PreviewTrialSequence.m will generate a trial session matrix for user to view
HandlePauseCondition;                                               % Pressing play a second time will begin the trial session run

for currentTrial = 1:maxTrials                                      % Trial loop: everything below repeats once per trial
    
    %select trial type
    cur_trial_type = TrialSeq{currentTrial};                        % Defines variable cur_trial_type as the current trial in the TrialSeq vector array (generated by UrnModel.m)
    switch cur_trial_type                                           % Sets the cur_trial_type variable to have the following settings for each case type (used in the 'odor_name' state)
        case 'A'                                                    % For example, if the current trial in the TrialSeq vector array is trial type 'A':
            odor_name = 'Odor_A';                                   % Then the 'Odor_A' name will display in the Bpod GUI window for the 'odor_name' state,
            valve_command = 2; %S.OdorIdentities(1)+1;
            %arduino_command = 8;                                   % Arduino commands are currently disabled (load_arduino_commands is commented out above)
        case 'B'
            odor_name = 'Odor_B';                                   % This list sets the parameters for all 'odor_name' states for use in the trial loop
            valve_command = 3; %S.OdorIdentities(2)+1;
            %arduino_command = 9;
        case 'C'
            odor_name = 'Odor_C';
            valve_command = 4; %S.OdorIdentities(3)+1;
            %arduino_command = 10;
        case 'D'
            odor_name = 'Odor_D';
            valve_command = 5; % S.OdorIdentities(4)+1;
            %arduino_command = 11;
        case 'Blank'
            odor_name = 'Blank_Odor';
            valve_command = 1;                                      % Valve command 1 will close all valves
            %arduino_command = 33;
    end

    pool = OutcomePools.(cur_trial_type);                                           % Pulls the outcome pool for the current trial type (built by UrnModel.m)
    rew_state = pool.seq{pool.idx};                                                 % Outcome for this trial: 'Reward', 'AirPuff_Pressurize' (airpuff), or 'ITI' (omission)
    OutcomePools.(cur_trial_type).idx = pool.idx + 1;                               % Advances that pool's index, so the next trial of this type gets the next outcome

    water_valve_time = GetValveTimes(S.GUI.RewardSize,1);                           % Converts the GUI reward size (µL) into how long the water valve needs to stay open,
                                                                                    % using the valve calibration table. The valve closes when the 'Reward' state ends
    ITI_length = ExpTimer(S.GUI.ITI_exp_mean);                                      % calls function ExpTimer.m to calculate ITI length for each trial

    if currentTrial < maxTrials && strcmp(TrialSeq{currentTrial+1}, 'Blank')        % If the next trial exists and is a blank odor cue,
        ITI_length = ITI_length - 3;                                                % Then 3 seconds are subtracted from the ITI of the current trial
    end                                                                             % Makes the timing of blank trials less predictable

    pressurize_delay = max(S.GUI.Odor - S.GUI.AirPuff_Pressurize_Time, 0);         % Time from odor onset to pressurize valve opening, so pressurization ends with the odor

    %--- Assemble state machine
        sma = NewStateMachine();                                                    % For each trial in a loop, a new state machine is generated and will progress as follows until 'TrialEnd'
        TTL = TTLGlobalTimer();                                                     % TTL sync pulse timer (Global Timer 4); created first so AirPuff can link to it
        sma = TTL.ConfigureTimers(sma);                                             % Adds it to this trial's state machine; pulses mark cue onset, reward, pressurize, and release
                                                                                    % (pulse count per trial encodes the outcome: 1 = omission, 2 = reward, 3 = airpuff)
        pressurize_msg = valve_command + 9;                                         % Valve message that opens the pressurize valve AND keeps this trial's odor valve open
                                                                                    % (messages 10-18 in load_odor_serial_messages; plain message 8 would close the odor valve)
        Air = AirPuff(S.GUI.AirPuff_Pressurize_Time, S.GUI.AirPuff_Release_Time, ...
                      pressurize_delay, pressurize_msg, TTL.TimerID);               % Timer 2 waits pressurize_delay, then sends pressurize_msg
                                                                                    % and fires a TTL pulse at that same moment
        sma = Air.ConfigureTimers(sma);                                             % Initializes 'Air' timers defined in AirPuff.m
        BNC = BNCTrigger();                                                         % Creates the photometry trigger timer defined in BNCTrigger.m (Global Timer 6, BNC2)
        sma = BNC.ConfigureTimers(sma);                                             % Adds it to this trial's state machine (see preodor_actions below for when it is triggered)
        LED = [];                                                                   % LED flash set to off by default
        if S.GUI.LEDFlashEnable                                                     % Tells code to check if LED flash is enabled in GUI
            LED = PIB_LED_Flash(S.GUI.LEDFlashInterval);                            % Passes entered flash interval time to PIB_LED_Flash.m
            sma = LED.ConfigureTimers(sma);                                         % Initializes PIB_LED_Flash.m
        end

        % GlobalTimerTrig binary strings are read right to left: the rightmost digit is Global Timer 1,
        % the next digit is Timer 2, and so on (Ex: '010001' = Timers 1 and 5)
        preodor_actions = {'GlobalTimerTrig', '010000'};                            % Default: GlobalTimer 5
        if currentTrial == 1 && S.GUI.LEDFlashEnable
            preodor_actions = {'GlobalTimerTrig', '110001'};                        % Trial 1 + LED flash: timers 1, 5, 6
        elseif currentTrial == 1
            preodor_actions = {'GlobalTimerTrig', '110000'};                        % Trial 1 only: timers 5 and 6
        elseif S.GUI.LEDFlashEnable
            preodor_actions = {'GlobalTimerTrig', '010001'};                        % LED flash only: timers 1 and 5
        end

        odor_timer_trig = TTL.TimerID;                                              % Default: odor onset only triggers the TTL sync pulse (Global Timer 4)
        odor_next_state = rew_state;                                                % Default: odor goes straight to 'Reward' or 'ITI' (omission)
        if strcmp(rew_state, 'AirPuff_Pressurize')                                  % If this trial has an airpuff outcome:
            odor_timer_trig = '1010';                                               % Odor onset triggers Global Timers 2 (pressurize) and 4 (TTL)
            odor_next_state = 'AirPuff_Release';                                    % And the odor state goes straight to the release state
        end                                                                         % (UrnModel still labels airpuff outcomes 'AirPuff_Pressurize'; only the state name changes here)

        sma = AddState(sma, 'Name', 'PreOdor', ...                                  % 'PreOdor' is the first state in the trial loop
            'Timer', S.GUI.PreOdor,...                                              % State duration is defined by the value entered in the CueConditioning GUI
            'StateChangeConditions', {'Tup', odor_name},...                         % 'StateChangeConditions' defines what the next state will be, and is decided by UrnModel.m
            'OutputActions', preodor_actions);                                      % Upon start of the 'PreOdor' state, defined 'preodor_actions' will execute; 'AnalogIn1',1 removed
        sma = AddState(sma, 'Name', odor_name, ...                                  % The second state is the Odor state, parameters for each odor are set by cur_trial_type
            'Timer', S.GUI.Odor,...                                                 % Same duration on every trial type, so cue-to-outcome time is always S.GUI.Odor
            'StateChangeConditions', {'Tup', odor_next_state},...                   % Goes straight to the outcome: 'Reward', 'AirPuff_Release', or 'ITI' (omission)
            'OutputActions', {'ValveModule1',valve_command,'GlobalTimerTrig', odor_timer_trig}); % Opens the odor valve; triggers TTL (and Timer 2 on airpuff trials)
        sma = AddState(sma, 'Name', 'Reward', ...                                   % Upon reward outcome, the 'Reward' state follows the odor state
            'Timer', water_valve_time,...                                           % State duration = water valve open time (from GetValveTimes above)
            'StateChangeConditions', {'Tup', 'ITI'},...                             % Sets the following state to 'ITI'
            'OutputActions', {'ValveModule1',1,'ValveState',2,'GlobalTimerTrig', TTL.TimerID}); % Closes the odor valve, opens water valve 2, and fires the TTL timer (marks reward)
        sma = AddState(sma, 'Name', 'AirPuff_Release', ...                          % Upon airpuff outcome, 'AirPuff_Release' follows the odor state
            'Timer', 0, ...                                                         % Timer not used here (no 'Tup' transition); duration is determined by AirPuff.m
            'StateChangeConditions', {'GlobalTimer3_End','ITI'}, ...                % State ends upon Global Timer 3 (set by Airpuff.m) completion and enters 'ITI'
            'OutputActions', {'ValveModule1', 9, 'GlobalTimerTrig', '1100'});       % Opens the release valve only (closes the odor and pressurize valves at odor end); starts Timers 3 and 4
        sma = AddState(sma, 'Name', 'ITI', ...                                      % 'ITI' will follow the odor state (omission), 'Reward', or 'AirPuff_Release'
            'Timer', ITI_length,...                                                 % Duration determined by ExpTimer.m and then passed to state machine
            'StateChangeConditions', {'Tup', 'TrialEnd'},...                        % Following 'ITI' the state machine will enter 'TrialEnd'
            'OutputActions', {'ValveModule1',1});                                   % Closes all valves (closes the odor valve on omission trials)
        sma = AddState(sma, 'Name', 'TrialEnd', ...                                 % 'TrialEnd' state lasts 10 ms and prepares the state machine to restart the loop
            'Timer', 0.01,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {});   

    SendStateMachine(sma);                                                          % Send state machine to the Bpod state machine device
    RawEvents = RunStateMachine;                                                    % Collects/stores all timestamps and transition events

    disp(['Completed trials:' num2str(currentTrial)])                               % Displays number of trials completed in the command window each trial loop
    %AnalogData = A.getData;

    %--- Package and save the trial's data, update plots
    if ~isempty(fieldnames(RawEvents))                                              % If events were recorded in your trial session,
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents);                % Adds raw events to a readable data struct
        BpodSystem.Data.TrialSettings(currentTrial) = S;                            % Adds the settings used for the current trial to the Data struct
        SaveBpodSessionData;                                                        % Saves the field BpodSystem.Data to the current data file
        %save_analogdata(AnalogData,strrep(BpodSystem.Path.CurrentDataFile,'.mat','.h5'),currentTrial)
        PlotSessionProgress(BpodSystem.Data, 'Figure', event_fig);                  % Calls PlotSessionProgress.m for display of real-time data
    end

    %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
    HandlePauseCondition;                                                           % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end
