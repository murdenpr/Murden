% Configures Global Timer 4 to send a short TTL pulse through BNC1 each time it is triggered.
% CueConditioning.m triggers this timer at cue onset (odor valve open), at reward delivery, and in both airpuff
% states (pressurize and release), so the number of pulses in a trial encodes the outcome:
%   1 pulse = omission, 2 pulses = reward, 3 pulses = airpuff
% These pulses let behavioral events be aligned with photometry data.
%
function TTL = TTLGlobalTimer()                 % Call this script in CueConditioning.m to enable TTL pulses

                                                
TTL.TimerID    = 4;                             % Global Timer 4 reserved for TTL sync
TTL.PulseWidth = 0.01;                          % Pulse width in seconds

TTL.ConfigureTimers = @configureTimers;         % Calling TTL.ConfigureTimers(sma) in CueConditioning.m adds this timer to the trial's state machine
TTL.TriggerAction   = {'GlobalTimerTrig', TTL.TimerID};  % Can be used as a state OutputAction to start the timer; CueConditioning.m uses TTL.TimerID directly instead

    function sma = configureTimers(sma)                 % Nested function: takes the trial's state machine (sma), adds Global Timer 4, and returns the updated sma
        sma = SetGlobalTimer(sma, ...                   % Defines the parameters of the TTL pulse timer
            'TimerID', TTL.TimerID, ...                 % Global Timer tied to the value entered for TTL.TimerID (Global Timer 4)
            'Duration', TTL.PulseWidth, ...             % Pulse lasts 10ms (TTL.PulseWidth)
            'OnsetDelay', 0, ...                        % No delay: pulse starts as soon as the timer is triggered
            'Channel', 'BNC1', ...                      % Output channel (BNC1, same channel as the LED sync TTL in PIB_LED_Flash.m)
            'SendGlobalTimerEvents', 1);                % Each pulse is recorded in Bpod system data (GlobalTimer4_Start/End events)
    end
end
