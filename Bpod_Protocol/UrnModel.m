% Two-Level Urn Model Without Replacement Code (or multivariate hypergeometric model)
% First level - trial type frequency, Second level - trial outcome probability
%
% Urn-Model Theory (background info, not used by our code):
%
%                m  (Ni)
%               ∏i=1(ki)
% P(k1,...km) = -------    multivariate hypergeometric formula     
%                 (N)
%                 (n)
%
% ∏i=1..m = Product of the binomial coefficients (Ni choose ki) across all m outcome types
% Example - Odor_A has reward/omission, Odor_B has airpuff/omission. 4 total outcome types (Ar, Ao, Bp, Bo), so m = 4
% m = Number of outcome types
% N = Total number of trials
% n = Partial number of trials for a given set N
% Ni = Number of 1st level trial types (number of Odor_A trials, number of Odor_B trials, etc.)
% ki = Partial number of outcome types drawn for a given set of N trials
%
% (a) - this is an example of a binomial coefficient (read as a chooses b)
% (b)
%                                   a!
% Binomial coefficient formula = --------
%                                b!(a-b)!
%
% We can simplify the multivariate hypergeometric formula; for our setup N=n, and we do not use ki. This is because we are not drawing 
% a partial sample from a larger set. We are setting a number of trials, and then executing that entire set N of trials. 
% So we can take the multivariate hypergeometric formula, and simplify it for our purposes to find probability:
%
%                 Ri!Pi!Oi!
% P(OutcomeSeq)i = ---------
%                    Ni!
%
% P(OutcomeSeq)i = Probability of a particular sequence of outcomes for the Ni trials of trial type i
% Ri = Number of reward outcomes for trial type i
% Pi = Number of airpuff outcomes for trial type i 
% Oi = Number of omission outcomes for trial type i
% Ni = Number of trials of trial type i
% We can calculate Ri!Pi!Oi! again for each active trial type in a session (Odor_A, Odor_B, etc.)
% This formula calculates the probability of each possible unique outcome sequence for the Ni trials of type i, undergoing random shuffling.
% (Ni trials can be ordered Ni!/(Ri!Pi!Oi!) unique ways, so each specific ordering has probability Ri!Pi!Oi!/Ni!)
%
% Explanation of the actual calculation UrnModel.m is executing (IMPORTANT):
%
% We do not actually need to use probability theory for our purposes. Instead, it is easier to calculate the number of each trial occurence for a
% given set of N trials, and then use the randperm function to shuffle the set. CueConditioning.m then uses the resulting vector as a guide 
% for the sequence of trials. The formula for this is as follows (1st level of our "urn"): 
%
% Na = ⌊Nt*Fa⌋ (repeat for each active trial)
% Nt = ⌊Na⌋ + ⌊Nb⌋ + ... etc.
%
% Nt = Total number of trials
% Na = Total number of trial type A (calculated by multiplying frequency of A by total number of trials)
% Fa = Frequency of trial type A
% Nb = Total number of trial type B
% ⌊x​⌋ = Rounds down to next lowest integer
%
% In the event of a fractional remainder (total numbers of a trial type are not an integer), the resulting extra trial is allotted
% to the largest remainder (trial type with the highest decimal value). Now, all that's left is to calculate the number of each
% outcome for each active trial type for a given set of N trials using this formula (This is the 2nd level of our "urn"):
%
% Ri​=⌊Ni​pR,i​⌋,Pi​=⌊Ni​pP,i​⌋,Oi​=Ni​−Ri​−Pi​
%
% pR,i = Probability of reward outcome for trial type i (value pulled from entered S.GUI CueConditioning.m values)
% pP,i = Probability of airpuff outcome for trial type i (value pulled from entered S.GUI CueConditioning.m values)
% Number of omission trials for trial type i (Oi) is calculated by subtracting reward and airpuff outcome from Ni
%
% That covers the math, here's the code (UrnModel.m is creating a vector for 1st level modeling and a struct for 2nd level modeling):
                                                                    % Here is where we begin to create the first level of our "urn"
function [TrialSeq, OutcomePools, chunkSizes] = UrnModel(GUI)       % UrnModel is defined as a function that constructs CueConditioning.m trial sequence from pulled GUI settings
% --- Trial types                                                   % Checks enabled trial types and frequency settings, in the event of a fractional remainder, the
                                                                    % extra trial is alotted to the largest remainder, in the event of a fractional remainder tie,
types = {'A','B','C','D','Blank'};                                  % the extra trial is alloted to the first active (and tied) trial type encountered in the vector 
enabled = [GUI.A_enabled, GUI.B_enabled, GUI.C_enabled, ...         % Defines variable 'types' as a cell array of trial types
           GUI.D_enabled, GUI.blank_enabled];                       % Defines variable 'enabled' as a vector of active trial types
freqs = [GUI.A_freq, GUI.B_freq, GUI.C_freq, ...                    % Defines variable 'freqs' as a vector of entered GUI frequencies
         GUI.D_freq, GUI.blank_freq];                               % (all five values are included, even for disabled trial types)

freqs = freqs .* enabled;                                           % Multiplying by 'enabled' (1 or 0) sets disabled trial type frequencies to zero
freqs = freqs / sum(freqs);                                         % Rescales frequencies so they sum to 1 (CueConditioning.m checks the entered values before this)

nTrials = GUI.n_trials;                                             % Pulls total number of trials from GUI
B  = GUI.Trial_Chunk_Size;                                          % Pulls trial chunk size from GUI
C  = ceil(nTrials / B);                                             % Divides total number of trials by desired chunk size, ceil() rounds to the next highest integer
chunkSizes = B * ones(1,C);                                         % Creates a vector with one element per chunk, each equal to the chunk size (B)
chunkSizes(end) = nTrials - B*(C-1);                                % Calculates a smaller last chunk in the event of a fractional remainder (ex: 23N,5B,5C = final chunk size of 3)
                                                                    
% --- Overall trial counts                                          % Creates decimal point counts for each trial-type outcome (multiplies total number of trials by frequency of each trial type)
rawCounts = nTrials * freqs;                                        % Defines variable rawCounts as total number of trials multiplied by trial type frequency
counts = floor(rawCounts);                                          % Defines counts as an integer ('floor' rounds down to nearest integer)
remainder = nTrials - sum(counts);                                  % Defines remainder variable (if no fractional remainder exists, the value is zero)  

% --- Distribute remainder deterministically                            
[~, idx] = sort(rawCounts - counts, 'descend');                     % Sorts the rawCounts vector by largest remainder
counts(idx(1:remainder)) = counts(idx(1:remainder)) + 1;            % Adds one trial to each trial type with the largest remainders, until all leftover trials are assigned 

% --- Distribute total trial counts across chunks; countsPerChunk(c,i) = number of trials of type i in chunk c
countsPerChunk = zeros(C, numel(types));                            % Creates a matrix of all zeroes, with rows = chunks and columns = trial types
for i = 1:numel(types)                                              % Defines i as a loop variable that increases by 1 for each trial type (numel() assigns a number to each trial type)
    Ni = counts(i);                                                 % Defines Ni as the trial count for each trial type  
    if Ni == 0                                                      % if trial type count = 0, no change occurs in the countsPerChunk matrix
        continue
    end                                                             % Now we need to calculate the number of each trial type per chunk, and evenly distribute any existing remainders
    base = floor(Ni / C);                                           % Defines base as trial type count divided by number of chunks (C), rounded down (trials of type i every chunk gets)                                          
    rem  = Ni - base*C;                                             % Defines rem as the trials of type i left over after every chunk gets 'base' trials 

    countsPerChunk(:,i) = base;                                     % For each row in the countsPerChunk matrix base values of active trial types are assigned
    countsPerChunk(1:rem,i) = countsPerChunk(1:rem,i) + 1;          % If any unassigned trials of type{x} remain, one trial is added to each chunk (beginning with the first chunk)
end                                                                 % Once remainder = 0, no additional trials are added; we have now determined the count of each trial type in a given chunk
chunkSizes = sum(countsPerChunk, 2);                                % Recalculates chunk sizes from the trials actually assigned (can differ slightly from Trial_Chunk_Size; used below and by PreviewTrialSequence.m)
% --- Begin to build outputs
TrialSeq     = {};                                                  % Generates an empty trial sequence array
OutcomePools = struct();                                            % Generates empty struct that will contain the second-level (outcome probability) of our "urn"
for i = 1:numel(types)                                              % For each trial type in vector i
    OutcomePools.(types{i}).seq = {};                               % A second-level outcome pool struct is generated (ex: OutcomePools.a.seq) for each trial type
    OutcomePools.(types{i}).idx = 1;                                % Sets each pool's read position (idx) to its first outcome; CueConditioning.m advances it each trial 
end

% --- Build trial sequence chunks from obtained trial type values
for c = 1:C                                                         % Creates loop variable c that increases by one for each trial chunk. All following code is nested inside this for loop.
                                                                    % Therefore all following code will be repeated every time our c value increases by 1 (repeats for every successive chunk)
    chunkN = chunkSizes(c);                                         % Defines chunkN as the number of trials in a given chunk 
                                                                    % Ex: chunkSizes(c) for trial sequence chunk 2 = chunkSizes(2) = the number of trials in chunk 2
    % First-level urn (trial types)
    chunkTypes = {};                                                % Generates empty trial chunk array                                              
    for i = 1:numel(types)                                          % numel() counts the number of elements in the array (possible trial types) and generates a value for each type
        if countsPerChunk(c,i) > 0                                  % If trial type count for chunk c is greater than zero
        chunkTypes = [chunkTypes, repmat(types(i), 1, countsPerChunk(c,i))]; % Then the element for that trial type is replicated by the number of calculated counts per chunk  
        end                                                         % Ex: types(i) for trial type "B" corresponds to types(2). Let's say a remainder occured and 4 trials were calculated for 
    end                                                             % chunk 1, while 3 trials were calculated for chunk 2. Therefore, types(2) for c=1 is 4, and types(2) for c=2 is 3. Repmat
                                                                    % replicates i by c, so for chunk 1,'B' becomes ['B','B','B','B'], and for chunk 2, ['B','B','B']. Process runs for each
    chunkTypes = chunkTypes(randperm(numel(chunkTypes)));           % active trial type and adds to the c=1 chunkTypes array (ex: ['A','A','B','B','C']). Process repeats for all chunks. Randperm
    TrialSeq   = [TrialSeq, chunkTypes];                            % shuffles each generated chunkTypes c array, and the final TrialSeq product is now fully randomized and divided into chunks.

    % Second-level urn (outcomes)
    for i = 1:numel(types)                                          % For each trial type element i
        Ni = countsPerChunk(c,i);                                   % Ni is assigned the value of trial type count for each chunk
        if Ni == 0                                                  % if trial type count for a chunk = 0, no outcomes are generated for that type in this chunk
            continue
        end

        type = types{i};                                            % Trial type variable will be generated for each active trial type

        switch type                                                 % Reads GUI trial outcome probabilities
            case 'A'                                                % Ex: for types{'A'}, types{i} = types{1}. i.e. trial type 'A' has a value of 1
                pR = GUI.A_reward_prob;                             % If trial type 'A' is active, retrieves probability inputs from CueConditioning.m GUI          
                pP = GUI.A_airpuff_prob;                            % Inputs will be used to calculate number of each outcome for OutcomePools.A 
            case 'B'                                                % Repeats process for all trial types
                pR = GUI.B_reward_prob;
                pP = GUI.B_airpuff_prob;
            case 'C'
                pR = GUI.C_reward_prob;
                pP = GUI.C_airpuff_prob;
            case 'D'
                pR = GUI.D_reward_prob;
                pP = GUI.D_airpuff_prob;
            case 'Blank'
                pR = GUI.blank_reward_prob;
                pP = GUI.blank_airpuff_prob;
        end
                                                                    % Computes number of each outcome for each trial type chunk
        nR = floor(Ni * pR + 1e-9);                                 % Multiplies trial type chunk count by entered reward probability, then rounds down (floor)
        nP = floor(Ni * pP + 1e-9);                                 % Same for airpuff; omission count = total count minus reward and airpuff outcomes; (1e-9 allows for small floating point errors)
        nO = Ni - nR - nP;                                          % Because outcomes are calculated this way, any existing remainder generates an additional omission outcome
                                                                    % Ex: number of chunk 1 trial 'A' rewards = chunk 1 trial type 'A' count * 'A' reward probability
        outcomes = [ ...                                            % Number of each outcome is now converted to rew_state 'StateChangeConditions'. This will be used by the 
            repmat({'Reward'},  1, nR), ...                         % 'Trace' state in CueConditioning.m to govern the next state change. repmat() takes all calculated, non-zero
            repmat({'AirPuff_Pressurize'}, 1, nP), ...              % outcome counts and replicates their respective elements to create OutcomePool.(type) string arrays
            repmat({'ITI'},     1, nO)];                            % Similar to first-level array generation, the only difference here is that outputs are separated into
                                                                    % pools containing 'StateChangeConditions' directions (they take the same format as a vector, however) 
        outcomes = outcomes(randperm(numel(outcomes)));             % Shuffles all trial outcomes in a chunk via random permutation for each OutcomePool.(type)

        OutcomePools.(type).seq = [OutcomePools.(type).seq, outcomes];  % Sequentially adds onto each OutcomePool.(type).seq until the chunk loop is complete 
    end
end

% Simple example of what is pulled from CueConditioning.m, generated in UrnModel.m, and then passed back to the state machine:
%
% GUI.n_trials = 4, only A and B enabled
% GUI.A_reward_prob = 0.5, GUI.A_airpuff_prob = 0
% GUI.B_reward_prob = 0, GUI.B_airpuff_prob = 0.5
%
% TrialSeq might look like: {'A','B','A','B'}
%
% OutcomePools.A.seq = {'Reward','ITI'}
% OutcomePools.B.seq = {'ITI', 'AirPuff_Pressurize'}
%
% Now, for the first trial, the trial type is 'A' (the first element in the TrialSeq vector). This directs the state machine
% to OutcomePools.A.seq, where it pulls the first element in the array ('Reward'). CueConditioning.m continues this reading 
% sequence until the last trial (in this example: trial type 'B' with an 'AirPuff_Pressurize' outcome).

% Build and shuffle trial sequence
%TrialSeq = cell(1,nTrials);                                         % Defines TrialSeq as a vector containing the total number of trials
%k = 1;                                                              % Tells MatLab to start writing the vector at the first value, then continue forward
%for i = 1:numel(types)                                              % numel() counts the number of elements in the array (possible trial types)
%    if counts(i) > 0                                                % Adds only trial types that have an occurence greater than zero to the array
%        TrialSeq(k:k+counts(i)-1) = repmat(types(i), 1, counts(i)); % For each active trial type, repmat() replicates trial type by the number of counts to produce a vector
%        k = k + counts(i);                                          % Ex: if counts for 'A' = 3, then repmat(types('A'),1,counts('A')) returns ['A','A','A']
%    end                                                             % Runs count/repmat process for all active types, generating a complete vector for nTrials                                                          
%end
%TrialSeq = TrialSeq(randperm(nTrials));                             % Randomizes the generated vector for 1:nTrials (shuffles the urn)