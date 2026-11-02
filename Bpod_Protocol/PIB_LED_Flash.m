% Configures a looping GlobalTimer used to flash an LED at a fixed interval.
% The LED is controlled by the Port Interface Board (PIB) connected to the Bpod.
% The timer produces repeated short pulses (defined by LED.PulseWidth) separated by OFF periods (defined by LED.Interval).
% 
% GlobalTimer usage:
%   GlobalTimer 1 -> LED flash loop
%   GlobalTimer 5 -> TTL pulse loop on BNC1 (pulses at the same time as each LED flash)
%
% Timer triggering is handled externally in the CueConditioning.m trial loop. Essentially, the timer lasts for 30ms (LED.PulseWidth), at which point
% the timer ends and does not trigger again until the duration set for LED.Interval has elapsed, at which point the loop begins again.
%
% Replaced visible light LED (DigiKey - VAOL-3LWY4) with IR LED (DigiKey - TSTS7100). Visible light LED ran on 20mA
% current. IR LED is rated for max current of 250mA. Increased PIB potentiometer to provide 50mA current to LED to
% provide robust light within a safe range.

function LED = PIB_LED_Flash(interval)                      % 'LED' function receives parameters (S.GUI.LEDFlashInterval) and
                                                            % defines interval as value received from CueConditioning.m GUI
LED.TimerID    = 1;                                         % Ties LED flash to Global Timer 1
LED.TTLID      = 5;                                         % Ties TTL pulse to Global Timer 5
LED.Interval   = interval;                                  % Defines the LED struct flash interval 
LED.PulseWidth = 0.03;                                      % Sets duration of the LED ON pulse (seconds)

LED.ConfigureTimers = @configureTimers;                     % Calling LED.ConfigureTimers(sma) in CueConditioning.m adds both timers
LED.TriggerAction   = {'GlobalTimerTrig', LED.TimerID};     % (LED flash + TTL) to that trial's state machine. LED.TriggerAction can start
                                                            % the LED timer on its own, but is not currently used: CueConditioning.m instead
                                                            % starts timers 1 and 5 together with a binary 'GlobalTimerTrig' string in 'PreOdor'
    function sma = configureTimers(sma)                     % Nested function: takes the trial's state machine (sma) from CueConditioning.m,
                                                            % adds the two Global Timers defined below, and returns the updated sma
        sma = SetGlobalTimer(sma, ...                       % Defines the parameters of the LED flash timer
            'TimerID', LED.TimerID, ...                     % Global Timer tied to the value entered for LED.TimerID (Global Timer 1) 
            'Duration', LED.PulseWidth,...                  % Sets the duration of the LED ON pulse
            'OnsetDelay', 0, ...                            % No delay: timer starts as soon as it is triggered
            'Channel', 'PWM2', ...                          % Defines output channel (PWM2 is the channel used by the PIB LED)
            'PulseWidthByte', 255, ...                      % Sets brightness of LED flash (255 is maximum)
            'PulseOffByte', 0, ...                          % LED fully off between pulses
            'LoopMode', 1, ...                              % Value of 1 = ON (tells the Global Timer to continuously loop)
            'SendGlobalTimerEvents', 0,...                  % LED timer events are not logged (the TTL timer below logs each pulse instead)
            'LoopInterval',LED.Interval);                   % The length of the loop is defined in the CueConditioning.m GUI
        sma = SetGlobalTimer(sma, ...                       % Defines the parameters of the TTL pulse timer
            'TimerID', LED.TTLID, ...                       % Global Timer tied to the value entered for LED.TTLID (Global Timer 5) 
            'Duration', LED.PulseWidth,...                  % Sets the duration of the TTL High pulse
            'OnsetDelay', 0, ...                            % This timer has the same characteristics as the LED timer
            'Channel', 'BNC1', ...                          % So when an LED flash occurs, a TTL pulse is also sent through BNC1                        
            'PulseWidthByte', 1, ...                        % Pulse on                    
            'PulseOffByte', 0, ...                          % Pulse off
            'LoopMode', 1, ...                              % Loops continuously, same as the LED timer
            'SendGlobalTimerEvents', 1,...                  % Each pulse is recorded in Bpod system data
            'LoopInterval',LED.Interval);                   % Same loop interval as the LED, so each TTL pulse lines up with an LED flash
          
    end
end
