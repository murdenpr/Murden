% Test code for ExpTimer.m to verify accuracy
% Draws N ITI values from ExpTimer.m and checks that their average matches the target mean (m)
% Prints summary stats to the command window and plots a histogram of all draws

function ExpTimerTest
rng();           % optional: rng(0) uses a fixed seed (same 'random' draws every run, for reproducible results)
                 % rng('shuffle') uses a new seed each run; rng() on its own does not change the seed
N = 1e6;         % number of ITI draws to simulate (1e6 = 1 million)
m = 11;        % target mean ITI (s). Must stay above the ExpTimer.m lower bound and below the midpoint of its bounds
               % (8-13s with the current 8-18s limits). Lower and upper limits can be changed in ExpTimer.m

S = arrayfun(@(k) ExpTimer(m), 1:N);  % calls ExpTimer.m N times (one ITI draw per call)

fprintf('Target mean: %.2f\n', m);                          % Prints target mean
fprintf('Empirical mean: %.4f\n', mean(S));                 % Prints actual mean of all draws (should be very close to m)
fprintf('Min: %.4f, Max: %.4f\n', min(S), max(S));          % Prints smallest/largest draws (should stay within ExpTimer.m bounds)

% Percentages below / above mean (carried over from the median version; with a mean target these won't be 50/50,
% since the truncated exponential has more draws below its mean than above)
pctBelow = mean(S <= m) * 100;                              % Percent of draws at or below m
pctAbove = mean(S >  m) * 100;                              % Percent of draws above m
fprintf('Below mean: %.2f%%\n', pctBelow);
fprintf('Above mean: %.2f%%\n', pctAbove);
fprintf('Mean error: %.4f\n', mean(S) - m);                 % Difference between actual and target mean (should be close to 0)

% Plot
histogram(S,'BinWidth',0.5)                                 % Histogram of all draws (0.5s bins)
hold on
xline(m, 'r', 'LineWidth', 2);                              % Red line marks the target mean
hold off

xlabel('T');
ylabel('Counts');
title(sprintf('Truncated exponential samples (m = %.1f)', m));

% Annotate plot
txt = sprintf('Below m: %.2f%%\nAbove m: %.2f%%', pctBelow, pctAbove);
text(0.02, 0.98, txt, ...                                   % Prints the below/above percentages in the top-left corner of the plot
    'Units','normalized', ...
    'VerticalAlignment','top', ...
    'FontSize', 10, ...
    'BackgroundColor','w');
end
