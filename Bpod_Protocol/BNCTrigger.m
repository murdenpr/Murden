% Configures Global Timer 6 to send a single short TTL pulse through BNC2 to the fiber photometry system.
% Timer triggering is handled in CueConditioning.m: Global Timer 6 is only triggered in the 'PreOdor' state
% of trial 1 (preodor_actions '110000' or '110001'), so it marks the start of the session in the photometry recording
% Each pulse is also logged in Bpod session data (GlobalTimer6_Start/End events).
%
function BNC = BNCTrigger()                     % Call this function in CueConditioning.m to enable the BNC2 photometry trigger pulse

BNC.TimerID    = 6;                             % Global Timer 6 reserved for BNC sync
BNC.PulseWidth = 0.01;                          % Pulse width in seconds

BNC.ConfigureTimers = @configureTimers;         % Calling BNC.ConfigureTimers(sma) in CueConditioning.m adds this timer to the trial's state machine
BNC.TriggerAction   = {'GlobalTimerTrig', BNC.TimerID};  % Can be used as a state OutputAction to start the timer (not currently used; CueConditioning.m uses a binary 'GlobalTimerTrig' string)

    function sma = configureTimers(sma)                 % Nested function: takes the trial's state machine (sma), adds Global Timer 6, and returns the updated sma
        sma = SetGlobalTimer(sma, ...                   % Defines the parameters of the BNC2 pulse timer
            'TimerID', BNC.TimerID, ...                 % Global Timer tied to the value entered for BNC.TimerID (Global Timer 6)
            'Duration', BNC.PulseWidth, ...             % Pulse lasts 10ms (BNC.PulseWidth)
            'OnsetDelay', 0, ...                        % No delay: pulse starts as soon as the timer is triggered
            'Channel', 'BNC2', ...                      % Output channel (BNC2 is connected to the photometry system)
            'SendGlobalTimerEvents', 1);                % Each pulse is recorded in Bpod system data
    end
end