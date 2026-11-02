% Airpuff GlobalTimers configuration code
%
% Configures the timers that control airpuff pressurization and release.
%
% State transition control:
%   GlobalTimer 2 -> pressurization phase
%   GlobalTimer 3 -> release phase
%
% Two ways to call this function:
%
%   Air = AirPuff(pressurizeTime, releaseTime)
%       Original behavior (used by CueConditioning.m and CC_Ver2.m). Timer 2 starts with no delay
%       and sends no valve message; the 'AirPuff_Pressurize' state opens the pressurize valve itself.
%
%   Air = AirPuff(pressurizeTime, releaseTime, pressurizeDelay, pressurizeMsg, pressurizeTTLTimer)
%       Used by CC_Ver3.m. Timer 2 waits pressurizeDelay seconds after it is triggered, then sends
%       serial message pressurizeMsg to ValveModule1 to open the pressurize valve. This lets
%       pressurization run during the odor state, with no separate pressurize state.
%       If pressurizeTTLTimer is given (e.g. 4, the TTL timer), Timer 2 also triggers that timer
%       the moment its delay ends, so a TTL pulse marks the start of pressurization.
%
% SetGlobalTimer reads its arguments by position, so the argument order below must not be changed.

function Air = AirPuff(pressurizeTime, releaseTime, pressurizeDelay, pressurizeMsg, pressurizeTTLTimer)
                                                        % nargin = number of input arguments received
    if nargin < 1
        pressurizeTime = 1.0;   % seconds               % Default pressurize time if none is passed in
    end
    if nargin < 2
        releaseTime = 0.2;      % seconds               % Default release time if none is passed in
    end
    if nargin < 3
        pressurizeDelay = 0;                            % No onset delay: original behavior
    end
    if nargin < 4
        pressurizeMsg = 0;                              % 0 = timer sends no valve message: original behavior
    end
    if nargin < 5
        pressurizeTTLTimer = 0;                         % 0 = Timer 2 triggers no other timer: original behavior
    end

    % --- Define Variables
    Air.PressurizeTime  = pressurizeTime;               % Duration of Global Timer 2 (pressurize valve open time)
    Air.ReleaseTime     = releaseTime;                  % Duration of Global Timer 3 (release valve open time)
    Air.PressurizeDelay = pressurizeDelay;              % Wait between triggering Timer 2 and the pressurize valve opening
    Air.PressurizeMsg   = pressurizeMsg;                % ValveModule1 serial message sent when Timer 2 starts

    if pressurizeTTLTimer > 0                           % If a TTL timer was given,
        Air.PressurizeOnsetTrigger = dec2bin(2^(pressurizeTTLTimer-1)); % Convert its number to a bit string (timer 4 -> '1000')
    else                                                % Otherwise,
        Air.PressurizeOnsetTrigger = 0;                 % Timer 2 triggers no other timer
    end

    if Air.PressurizeMsg > 0                            % If a valve message was given,
        pressurizeChannel = 'ValveModule1';             % Timer 2 sends it to the valve driver module when it starts
    else                                                % Otherwise,
        pressurizeChannel = 'SoftCode';                 % Timer 2 uses an unused virtual channel and sends nothing (original behavior)
    end

    % --- Queue Timers
    Air.TriggerPressurize = {'GlobalTimerTrig', 2};     % Output action that starts Global Timer 2
    Air.TriggerRelease    = {'GlobalTimerTrig', 3};     % Output action that starts Global Timer 3
    Air.ConfigureTimers = @ConfigureTimers;             % Calling Air.ConfigureTimers(sma) adds both timers to the state machine

    % --- Define Timer IDs
    function sma = ConfigureTimers(sma)
        % GlobalTimer 2: pressurization
        sma = SetGlobalTimer(sma, ...
            'TimerID',      2, ...                      % The pressurization timer uses Global Timer ID 2
            'Duration',     Air.PressurizeTime, ...     % Timer 2 runs for S.GUI.AirPuff_Pressurize_Time once it starts
            'OnsetDelay',   Air.PressurizeDelay, ...    % Timer 2 waits this long after being triggered before it starts
            'Channel',      pressurizeChannel, ...      % Where Timer 2 sends its start/end messages
            'OnMessage',    Air.PressurizeMsg, ...      % Sent when Timer 2 starts (after the delay): opens the pressurize valve
            'OffMessage',   0, ...                      % Nothing is sent when Timer 2 ends; the next state handles the valves
            'Loop',         0, ...                      % Timer 2 runs once per trigger
            'SendGlobalTimerEvents', 1, ...             % Timer 2 start/end are recorded in the Bpod data (same as before)
            'LoopInterval', 0, ...                      % Not used (no looping); listed only because arguments are read by position
            'OnsetTrigger', Air.PressurizeOnsetTrigger);% Timers started when Timer 2's delay ends (the TTL timer in CC_Ver3)

        % GlobalTimer 3: release
        sma = SetGlobalTimer(sma, ...
            'TimerID',      3, ...                      % The release timer uses Global Timer ID 3
            'Duration',     Air.ReleaseTime, ...        % Timer 3 runs for S.GUI.AirPuff_Release_Time
            'OnsetDelay',   0, ...                      % Timer 3 starts as soon as it is triggered
            'Channel',      'SoftCode', ...             % Unused virtual channel; the 'AirPuff_Release' state opens the release valve itself
            'OnMessage',    0, ...
            'OffMessage',   0, ...
            'Loop',         0);
    end
end
