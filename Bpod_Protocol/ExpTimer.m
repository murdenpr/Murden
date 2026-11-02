% Inverse Exponential Cumulative Distribution Function (iCDF) (50% a-m, 50% m-b)
% A CDF can be visualized as the area under a probability density function (PDF) curve
% It denotes the probability an event has occured (ITI state ending), with probability increasing with time
% 
% e = base of natural logarithm and exponential function
% In MatLab, exp(x) = e^x (e is Euler's constant = 2.718)
%
% CDF formula - F(t) = P(T≤t) = 1−e^−λt
% At t=zero, F(0) = 0; at t=infinity, F(infinity) = 1
% Expressed differently: at time zero, the probability an event has occured is 0%, at time infinity, the probability an event has occured is 100%
% 
% F(t) = probability that a random time variable T will take a value less than or equal to t (in our case, t = m)
% P = probability (value between 0 and 1) increases with time (t)
% λ = exponential rate parameter (inverse of the mean); in this script, λ is not set, instead it is solved for
% to fit our truncated inverse CDF distribution (with set median)
%
% This script uses inverse-CDF sampling to calculate ITI length. In other words, for each trial, a random number U, between 0 and 1, is drawn
% (probability). This value is then used to calculate the length of ITI. Therefore, U = F(t), and we solve for t, or the time of the ITI.
% The resulting value is passed to CueConditioning.m
%
% We are also truncating our exponential CDF bounds; i.e. setting a minimum and maximum value (ITI values cannot be less than a or greater than b). 
% So the equation now becomes:
%
%                         F(t) − F(a)    e^−λa − e^−λt​
% P(T≤t ∣ a≤T≤b) = F(t) = ------------ = --------------
%                         F(b) - F(a)    e^−λa − e^−λb
%
% So now, at t = a, F(a) = 0, and at t = b, F(b) = 1
%
% Our second major parameter that we are implementing is that we want 50% of trial ITI's below our selected m and 50% above m.
% To enforce this, we impose the parameter: P(T≤m) = 0.5, or alternatively expressed, we want to calculate a value for lambda 
% such that F(m) - 0.5 = 0.
% 
%                                                e^−λa − e^−λm
% Written mathematically, this is:  F(m) - 0.5 = ------------- - 0.5 = 0
%                                                e^−λa − e^−λb
%
% Once lambda is calculated using the above formula in ExpTimer.m, it can then used in this following formula 
% to calculate per trial ITI length from a random probability ("U") draw. This is the inverse CDF formula. 
% We can use it to calculate a time value from our obtained lambda value and a random probability draw:
%
%                 1
% ITI Length = - --- * ln(e^−λa - U(e^−λa - e^−λb))
%                 λ          
%                             
% If you would like to test the accuracy of this function, you can open ExpTimerTest.m, set your desired paramaters, and run it in MatLab.
% It produces a plot of sample trials comparing chosen median with resulting target median.
%
% THIS CODE HAS BEEN UPDATED TO CALCULATE MEAN INSTEAD OF MEDIAN
%                          -λa              -λb    
%              ( a + 1/λ)e^    - (b + 1/λ)e^      
% ITI Length = --------------------------------
%                        -λa      -λb
%                      e^    -  e^

function T = ExpTimer(m)            % Defines ExpTimer as a function that outputs a scalar T (time) value
                                    % The value of variable "m" is passed from the CueConditioning.m GUI
    a = 8;                          % "a" defines the lowest boundary for ITI duration (can be changed here to alter minimum ITI length)
    b = 18;                         % "b" defines the highest boundary for ITI duration (can be changed here to alter maximum ITI length)

    % --- Solve for lambda (exponential rate parameter)
    fun = @(lambda) ...                                                                 % "fun" tells MatLab to solve for lamda using the following function
        ((a + 1./lambda).*exp(-lambda*a) - (b + 1./lambda).*exp(-lambda*b)) ...         % This is the F(m) function (to solve for lambda) written as code
        ./ (exp(-lambda*a) - exp(-lambda*b)) - m;                                       % This tells MatLab to find a value for lambda, starting at 0.1, that will
                                                                                        % produce an F(ExpTimer(m)) outcome that is equal to zero when U = 0.5
    lambda = fzero(fun, 0.1);                                                            
    % --- Select random draw for ITI length                                             % The calculated lambda value is used in the following equation
    U = rand();                                                                         % Draws a random number between 0-1
    T = -(1/lambda) * log(exp(-lambda*a) - U*(exp(-lambda*a) - exp(-lambda*b)));        % Inverse CDF formula - calculates ITI with our previously chosen value for
                                                                                        % lambda, and our randomly drawn value for U. The resulting T value is
    %T = round(T*2)/2;                                                                  % passed to CueConditioning.m to assign per trial ITI length
    %T = min(max(T, a), b);                                                             % Last two lines ensure T is rounded to whole or half second ITI outcomes      
end                                                                                     % Rounding is for camera/photometry syncing ease of use
                                                                                        