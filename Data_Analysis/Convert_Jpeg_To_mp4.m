% Converts a folder of numbered .jpg frames (Ex: from Pylon Viewer image capture) into a single .mp4 video
% Frames are sorted by the frame number at the end of each file name, then written in order at 50 fps
% Output videos are numbered automatically, so existing videos in the output folder are never overwritten
% (Ex: '[folder name] Video Output 1.mp4', '[folder name] Video Output 2.mp4', etc.)
%
folder = 'C:\path\to\image_folder';  % Replace with the folder containing your images
files = dir(fullfile(folder, '*.jpg'));                                                    % Searches folder for jpegs 
                                                             
% Select output folder
outFolder = uigetdir('', ...                                                               % Select output folder
                     'Select output folder');                                              % File browser opens in the current MatLab folder; choose any folder

if outFolder == 0                                                                          % If the folder selection window is closed/cancelled,
    error('User cancelled')                                                                % Stops the script with a cancel message
end

% Extract frame numbers
frameNums = zeros(length(files),1);                                        % Creates empty vector with total length = frames                                       

for i = 1:length(files)                                                    % For each image file:
    tokens = regexp(files(i).name,'_(\d+)\.jpg$','tokens');                % Pulls the frame number from the end of the file name (Ex: 'image_0042.jpg' -> '0042')
    frameNums(i) = str2double(tokens{1}{1});                               % Converts file name frame number to MatLab numeric value
end

% Sort by frame number
[~, idx] = sort(frameNums);                                                % Sorts frame numbers from lowest to highest (idx = new file order)
files = files(idx);                                                        % Reorders the file list by frame number (dir() sorts alphabetically, so '_10' could come before '_2')
[~, sourceName] = fileparts(folder);                                       % Pulls source folder name

% Find existing videos with this naming pattern
pattern = sprintf('%s Video Output *.mp4', sourceName);                    % Search pattern for videos already made from this same image folder
existingFiles = dir(fullfile(outFolder, pattern));                         % Finds any existing videos in the output folder that match the pattern

% Extract existing numbers
nums = zeros(length(existingFiles),1);                                     % Creates an empty vector to store their video numbers

for i = 1:length(existingFiles)                                            % For each existing video:
    tokens = regexp(existingFiles(i).name,'Output (\d+)\.mp4','tokens');   % Pulls the video number from the end of its file name
    if ~isempty(tokens)
        nums(i) = str2double(tokens{1}{1});                                % Converts to MatLab numeric vector
    end
end

% Determine next index
if isempty(nums)                                                           % If no previous videos exist, this is video 1
    nextNum = 1;
else
    nextNum = max(nums) + 1;                                               % Otherwise, uses the next number after the highest existing one
end

outputName = sprintf('%s Video Output %d.mp4', sourceName, nextNum);       % Creates our output file name with +1 name value
outFile = fullfile(outFolder, outputName);                                 % Full path of the new video file

% Create video writer with full path
v = VideoWriter(outFile,'MPEG-4');                                         % Sets script to write mp4 file
v.FrameRate = 50;                                                          % Sets frame rate (50 fps matches the 20ms Pylon capture interval)
v.Quality = 95;                                                            % Sets video quality (0-100; higher = less compression)
open(v)                                                                    % Opens the video file for writing

for k = 1:length(files)                                                    % For all image files,
    img = imread(fullfile(folder, files(k).name));                         % Reads each image, in sorted frame order

    if size(img,3) == 1                                                    % If the image is grayscale (1 color channel),
        img = repmat(img,[1 1 3]);                                         % Copies it into all 3 RGB channels so every frame has the same color format
    end

    writeVideo(v, img)                                                     % Writes video file
end

close(v)                                                                   % Finalizes and saves the video file