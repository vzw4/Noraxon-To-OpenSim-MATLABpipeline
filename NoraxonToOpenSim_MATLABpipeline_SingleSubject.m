% 2.13.2026
% Batch run model scaling, inverse kinematics, inverse dynamics, joint
% reactions, and body kinematics (analysis tool)
% Note: this code assumes that you have generated proper .trc and .mot
% files, from the NORAXON SYSTEM ONLY. May need to first use the
% MATLAB_fullPipeline_CSVtoTRCMOT.m code to convert Noraxon exported CSVs to usable TRC and MOT files.

% Data Structure:
    % Parent folder
        % One copy of the base, unscaled model for analysis
        % Template Scaling, IK, ID, Analysis XMLs
        % Subject subfolders
            % All subject trial .CSVs
            % subjectData.mat <-- has subjectMass, subjectName

% Code will add to each subfolder:
    % Marker coordinates [.trc] 
    % Kinematics [_ik.mot]
    % Kinematics errors [_ik_marker_errors.sto]
    % Kinetics [_ID.sto]

%% SETUP
clear
close all

import org.opensim.modeling.* % Set up proper OpenSim stuff

samplingRate = input('Enter sampling rate of the Noraxon equipment: ');
samplingPeriod = 1/samplingRate;
%% FUNCTIONS

% Read data from the Noraxon .csv files
function trial_data = readNoraxon(trial_read, trajectoriesFixed, trajectoriesOriginal, forces, samplingRate)
    % Read time data
    csvData.time = table2array(trial_read(:, 'time'));
    for i = 1:length(trajectoriesOriginal) % Read virtual marker data
        csvData.(trajectoriesFixed{i}) = table2array(trial_read(:, trajectoriesOriginal{i}));
    end
        
    for i = 1:length(forces) % Read insole data
        csvData.(forces{i}) = table2array(trial_read(:, forces(i)));
    end

    % Moving average (boxcar) downsample
    targetRate  = 100;
    
    if samplingRate == targetRate
        fprintf('Data is already at 100 Hz. Returning as-is.\n');
        trial_data = csvData;
        return;
    end
    
    if mod(samplingRate, targetRate) ~= 0
        error('samplingRate (%d Hz) must be an integer multiple of 100 Hz.', samplingRate);
    end

    decimFactor = samplingRate / targetRate;   % e.g. 1000/100 = 10
    fields      = fieldnames(csvData);
    nSamples    = length(csvData.time);

    % Number of output samples
    nOut = floor(nSamples / decimFactor);

    fprintf('Downsampling from %d Hz to %d Hz (factor %d)...\n', ...
        samplingRate, targetRate, decimFactor);

    downsampledData = struct();

    for f = 1:length(fields)
        field = fields{f};
        data  = csvData.(field);

        if strcmp(field, 'time')
            % Recompute time vector cleanly at 100 Hz from the original start time
            tStart = data(1);
            downsampledData.time = tStart + (0:nOut-1)' / targetRate;

        else
            % Moving average (boxcar) over decimFactor samples for anti-aliasing,
            % then pick every decimFactor-th sample
            smoothed = movmean(data, decimFactor, 'Endpoints', 'shrink');
            downsampledData.(field) = smoothed(1:decimFactor:nOut*decimFactor);
        end
    end

    trial_data = downsampledData;
end

% Noraxon insoles offset on the x axis by 1.8" - correct for this
% Also, change NaNs to zeros, and make corresponding GRF also zero
function [fixCoPx, fixCoPy, fixGRF] = fixCoPNaNs(rawCoPx, rawCoPy, rawGRF)
    fixCoPx = rawCoPx;
    fixCoPy = rawCoPy;
    fixGRF = rawGRF;
    for t = 1:length(rawCoPx)
        if isnan(rawCoPx(t))
            fixCoPx(t) = 0;
            fixCoPy(t) = 0;
            fixGRF(t) = 0;
        else
            fixCoPx(t) = rawCoPx(t) - 50;
            fixCoPy(t) = rawCoPy(t) - 50;
        end
    end
end

% Switch y and z, then negate the new z
function rotated_data = rotateAroundX(trial_data, trajectories)
        rotated_data = trial_data;
        for i = 1:length(trajectories)
            if contains(trajectories{i}, '_y')
                markerName = erase(trajectories{i}, '_y');
                YZmarkers = {};
                YZmarkers{1} = append(markerName, '_y');
                YZmarkers{2} = append(markerName, '_z');
                tempY = trial_data.(YZmarkers{1});
                tempZ = trial_data.(YZmarkers{2});
                rotated_data.(YZmarkers{1}) = tempZ;
                rotated_data.(YZmarkers{2}) = -tempY;
            end
        end
    end

function trialTimes = getTrialTimeBounds(subjectCSVTrials)
% getTrialTimeBounds
% Opens a GUI window allowing the user to enter start and stop times
% for each trial listed in subjectCSVTrials.
%
% Input:
%   subjectCSVTrials  - cell array of trial name strings
%
% Output:
%   trialTimes        - struct array with fields:
%                         .trial  (string)
%                         .start  (string, e.g. '0.5' or 'start')
%                         .stop   (string, e.g. '10.2' or 'end')
%
% Usage:
%   times = getTrialTimeBounds(subjectCSVTrials);

    nTrials = length(subjectCSVTrials);

    %% --- FIGURE SETUP ---
    rowHeight   = 30;
    headerH     = 40;
    buttonBarH  = 55;
    padding     = 12;
    labelW      = 280;
    fieldW      = 100;
    colGap      = 10;
    figW        = labelW + 2*fieldW + 2*colGap + 2*padding;
    figH        = headerH + nTrials*rowHeight + buttonBarH + 2*padding;
    figH        = max(figH, 250);  % minimum height

    fig = figure( ...
        'Name',           'Set Trial Time Bounds', ...
        'NumberTitle',    'off', ...
        'MenuBar',        'none', ...
        'ToolBar',        'none', ...
        'Resize',         'off', ...
        'Position',       [300, 200, figW, figH], ...
        'Color',          [0.96 0.96 0.96], ...
        'CloseRequestFcn', @onClose);

    %% --- COLUMN HEADERS ---
    uicontrol('Parent', fig, 'Style', 'text', ...
        'String',   'Trial', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'Position', [padding, figH - headerH, labelW, 24]);

    uicontrol('Parent', fig, 'Style', 'text', ...
        'String',   'Start', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'HorizontalAlignment', 'center', ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'Position', [padding + labelW + colGap, figH - headerH, fieldW, 24]);

    uicontrol('Parent', fig, 'Style', 'text', ...
        'String',   'Stop', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'HorizontalAlignment', 'center', ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'Position', [padding + labelW + 2*colGap + fieldW, figH - headerH, fieldW, 24]);

    %% --- TRIAL ROWS ---
    startFields = gobjects(nTrials, 1);
    stopFields  = gobjects(nTrials, 1);

    for i = 1:nTrials
        yPos = figH - headerH - padding - i*rowHeight + 4;

        % Alternating row background
        if mod(i, 2) == 0; rowColor = [0.91 0.91 0.91]; else; rowColor = [0.96 0.96 0.96]; end
        uicontrol('Parent', fig, 'Style', 'text', ...
            'String',   '', ...
            'BackgroundColor', rowColor, ...
            'Position', [1, yPos - 2, figW - 2, rowHeight - 2]);

        % Trial name label
        uicontrol('Parent', fig, 'Style', 'text', ...
            'String',   subjectCSVTrials{i}, ...
            'HorizontalAlignment', 'left', ...
            'FontSize',  9, ...
            'BackgroundColor', rowColor, ...
            'TooltipString', subjectCSVTrials{i}, ...
            'Position', [padding, yPos, labelW, 22]);

        % Start time field
        startFields(i) = uicontrol('Parent', fig, 'Style', 'edit', ...
            'String',   'start', ...
            'FontSize',  9, ...
            'HorizontalAlignment', 'center', ...
            'BackgroundColor', [1 1 1], ...
            'Position', [padding + labelW + colGap, yPos, fieldW, 22]);

        % Stop time field
        stopFields(i) = uicontrol('Parent', fig, 'Style', 'edit', ...
            'String',   'end', ...
            'FontSize',  9, ...
            'HorizontalAlignment', 'center', ...
            'BackgroundColor', [1 1 1], ...
            'Position', [padding + labelW + 2*colGap + fieldW, yPos, fieldW, 22]);
    end

    %% --- BUTTON BAR ---
    btnY = padding;

    % "Set All to Start/End" button
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
        'String',   'Set All: start → end', ...
        'FontSize',  9, ...
        'TooltipString', 'Reset every row to start=''start'' and stop=''end''', ...
        'Position', [padding, btnY + 24, 160, 26], ...
        'Callback', @setAllStartEnd);

    % Confirm button
    uicontrol('Parent', fig, 'Style', 'pushbutton', ...
        'String',   'Confirm', ...
        'FontSize',  9, ...
        'FontWeight', 'bold', ...
        'BackgroundColor', [0.3 0.65 0.3], ...
        'ForegroundColor', [1 1 1], ...
        'Position', [figW - padding - 90, btnY + 24, 90, 26], ...
        'Callback', @onConfirm);

    % Hint text
    uicontrol('Parent', fig, 'Style', 'text', ...
        'String',   'Enter numeric times (s) or ''start'' / ''end''', ...
        'FontSize',  8, ...
        'ForegroundColor', [0.45 0.45 0.45], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', [0.96 0.96 0.96], ...
        'Position', [padding, btnY, figW - 2*padding, 18]);

    %% --- OUTPUT STORAGE ---
    trialTimes = [];

    %% --- WAIT FOR USER ---
    uiwait(fig);

    %% --- NESTED CALLBACKS ---

    function setAllStartEnd(~, ~)
        for k = 1:nTrials
            set(startFields(k), 'String', 'start');
            set(stopFields(k),  'String', 'end');
        end
    end

    function onConfirm(~, ~)
        % Build output struct array
        results(nTrials) = struct('trial', '', 'start', '', 'stop', '');
        for k = 1:nTrials
            results(k).trial = subjectCSVTrials{k};
            results(k).start = strtrim(get(startFields(k), 'String'));
            results(k).stop  = strtrim(get(stopFields(k),  'String'));
        end
        trialTimes = results;
        uiresume(fig);
        delete(fig);
    end

    function onClose(~, ~)
        % User closed window without confirming — return empty
        trialTimes = [];
        uiresume(fig);
        delete(fig);
    end

end

%% SELECT WORKING DIRECTORY

% Read directory of current subject
% parentDirectory = uigetdir('', 'Select the parent folder that contains all subject subfolders'); % Select parent directory
% cd(parentDirectory);
parentDirectory = cd;
a = dir(parentDirectory); b = [a.isdir]; c = a(b); d = {c.name}; 
subjectSubfoldersList = d(:, 3:end); % Get list of all subject subfolders in the parent directory
clear("a", "b", "c", "d");

%% LOAD TEMPLATE FILES

load("NoraxonTrajectoriesAndForcesAll.mat") % Loads trajectory and force names with original and fixed names
templateTRCname = fullfile(parentDirectory, "NoraxonMarkerBlank.txt");
templateMOTname = fullfile(parentDirectory, "grf_motBLANK.txt");

kinematicsTool = InverseKinematicsTool("KinematicsTemplate.xml");
kineticsTool = InverseDynamicsTool("KineticsTemplate.xml");
baseModel = Model("LFB_v2.osim");
baseModel.initSystem();

%% PICK SUBJECT TO ANALYZE

subjectFolder = uigetdir(cd, 'Pick the folder for the subject to be analyzed');
cd(subjectFolder); % Set current directory to this subject subfolder

%% CREATE TRC FILES

fprintf('\nCreating .TRC files from Noraxon .CSVs...\n')

load('subjectData.mat'); % Load the subject data (name and mass)

% Get list of all .csv trials
a = dir('*.csv');
subjectCSVTrials = {a.name}; clear("a");

% Add in functionality to set start and stop times for each trial
trialTimes = getTrialTimeBounds(subjectCSVTrials);
trialStartArray = {trialTimes.start};
trialStopArray = {trialTimes.stop};

for j = 1:length(subjectCSVTrials) % Loop through the trials
    csvName = subjectCSVTrials{j};
    trialID = csvName(1:end-4);
    startTime = trialStartArray{1,j};
    stopTime = trialStopArray{1,j};
    data_read = readtable(subjectCSVTrials{j});

    currentMarkerSet = {};

    trial_trc = readcell(templateTRCname);

    csvData = readNoraxon(data_read, trajectoriesFixed, trajectoriesOriginal, forces, samplingRate);    
    rotated_data = rotateAroundX(csvData, trajectoriesFixed);

    % Set up .trc files

    % Set up header info
    trial_trcName = append(subjectName, '_', trialID, '.trc');
    dataCount = length(rotated_data.time);

    % Add specific header info
    trial_trc{2,4} = trial_trcName;
    trial_trc{4,3} = dataCount;
    trial_trc{4,8} = dataCount;

    % Truncate to start and stop time
    if strcmp(startTime, 'start')
        startIndex = 1;
        startTime = rotated_data.time(1);
    else
        startIndex = round((str2double(startTime) + 0.01)/0.01);
        trialStartArray{2,j} = startIndex;
    end
    if strcmp(stopTime, 'end')
        stopIndex = dataCount;
        stopTime = rotated_data.time(end);
    else
        stopIndex = round((str2double(stopTime) + 0.01)/0.01);
        trialStopArray{2,j} = stopIndex;
    end

    % Add frame, time, and marker coordinate data
    for i = startIndex:stopIndex
        trial_trc{i+6,1} = i; % Frame#
        trial_trc{i+6,2} = i*0.01-0.01; % Time
        for k = 1:length(trajectoriesFixed) % Marker coordinate data
            trial_trc{i+6,k+2} = rotated_data.(trajectoriesFixed{k})(i);
        end
    end

    % Remove <missing> in cells
    mask = cellfun(@(x) any(isa(x,'missing')), trial_trc);
    trial_trc(mask) = {[]}; % or whatever value you want to use

    % Write marker trc files
    trial_fileName = trial_trcName(1:end-4);
    fullfilePath = fullfile(trial_fileName);
    writecell(trial_trc(2:end,1:end), fullfilePath, 'Delimiter', '\t');

    % Change files from .txt to .trc
    file1 = append(fullfilePath, '.txt');
    file2 = strrep(file1,'.txt','.trc');
    copyfile(file1,file2);
    delete(file1);
    fprintf(['Wrote ' trial_fileName '.trc\n'])
end

%% SCALING PERFORMS ONCE FOR EACH SUBJECT
% For each trial in each subject subfolder in the parent directory

% Get list of all .trc trials
a = dir('*.trc');
subjectTRCTrials = {a.name}; clear("a");

%% SCALING
% Couldn't get the MATLAB API calls to work properly, so this edits the
% XML directly, saves it as a new one, and then executes it to scale
% the model for each subject

xmlPath = fullfile(parentDirectory, "NoraxonScaleTemplate.xml"); % Read in template XML
xmlFile = xmlread(xmlPath);

lfbAddress = fullfile(parentDirectory, "LFB_v2.osim"); % Set the base model
xmlFile.getElementsByTagName('model_file').item(0).setTextContent(lfbAddress);

scaleTimeRange = append(num2str(startTime), ' ', num2str(startTime + 0.01)); % Set the first 0.01 time for scaling
xmlFile.getElementsByTagName('time_range').item(0).setTextContent(scaleTimeRange);

noraxonMarkersAddress = fullfile(parentDirectory, "LFB_Noraxon_Markers.xml"); % Assign marker set
xmlFile.getElementsByTagName('marker_set_file').item(0).setTextContent(noraxonMarkersAddress);

trialForScale = subjectTRCTrials{1}; % Use whatever first trial as pseudostatic to scale
% Note: for CATT participants, may want to instead use the walking
% calibration as pseudostatic
trialScaleAddress = fullfile(cd, trialForScale);
xmlFile.getElementsByTagName('marker_file').item(0).setTextContent(trialScaleAddress);
xmlFile.getElementsByTagName('marker_file').item(1).setTextContent(trialScaleAddress);

xmlFile.getElementsByTagName('mass').item(0).setTextContent(num2str(subjectMass)); % Set subject mass

outputModelName = append(subjectName, '_scaledModel.osim'); % Set the scaled model output
xmlFile.getElementsByTagName('output_model_file').item(0).setTextContent(outputModelName);

scaleXMLName = [subjectName '_scaleTool.xml'];
xmlwrite(scaleXMLName, xmlFile); % Save the edited XML

% Check if a scaled model already exists
existingModels = dir('*.osim');
temp = size(existingModels);
if temp(1) == 1
    scaledModel = Model(outputModelName);
    scaledModel.initSystem(); % Load and initialize the new scaled model
else
    scaleTool = ScaleTool(scaleXMLName);
    fprintf(['Scaling ' subjectName '...\n']);
    scaleTool.run(); % Execute the new scaling XML
    
    scaledModel = Model(outputModelName);
    scaledModel.initSystem(); % Load and initialize the new scaled model
    delete(scaleXMLName);
end

for j = 1:length(subjectTRCTrials) % Loop through the trials

    startTime = trialStartArray{1,j};
    stopTime = trialStopArray{1,j};
    startIndex = trialStartArray{2,j};
    stopIndex = trialStopArray{2,j};

    % Truncate to start and stop time
    if strcmp(startTime, 'start')
        startIndex = 1;
        startTime = rotated_data.time(1);
    else
        startIndex = round((str2double(startTime) + 0.01)/0.01);
    end
    if strcmp(stopTime, 'end')
        stopIndex = dataCount;
        startTime = rotated_data.time(end);
    else
        stopIndex = round((str2double(stopTime) + 0.01)/0.01);
    end

    %% IK
    kinematicsTool.setModel(scaledModel);

    % Get the name of the file for this trial
    markerFile = subjectTRCTrials{j};

    % Create name of trial from .trc file name
    trialName = regexprep(markerFile,'.trc','');

    % Get trc data to determine time range
    markerData = MarkerData(markerFile);

    % Get initial and intial time 
    initial_time = markerData.getStartFrameTime();
    final_time = markerData.getLastFrameTime();

    % Setup the kinematicsTool for this trial
    kinematicsTool.setName(trialName);
    kinematicsTool.setMarkerDataFileName(markerFile);
    kinematicsTool.setStartTime(initial_time);
    kinematicsTool.setEndTime(final_time);
    outputIK = [trialName '_ik.mot'];
    kinematicsTool.setOutputMotionFileName(outputIK);
    fprintf(['Performing IK on ' trialName '\n']);
    kinematicsTool.run();

    storage = Storage(outputIK);
    % 2. Check if it's currently in degrees
    if storage.isInDegrees()
        labels = storage.getColumnLabels(); 
        numCols = labels.getSize() - 1; % Subtract 1 for Time

        % 3. Loop through every row (time point)
        for k = 0:storage.getSize()-1
            stateVec = storage.getStateVector(k);
            data = stateVec.getData();

            % Loop through every column in that row
            for h = 0:numCols-1
                label = char(labels.get(h+1)); % +1 because 0 is Time

                % ONLY scale if it's NOT a translation (tx, ty, tz)
                % This identifies rotations by looking for 'flexion', 'tilt', 'rotation', etc.
                % Or more simply: anything NOT ending in 'tx', 'ty', 'tz'
                if isempty(regexp(label, 't[xyz]$', 'once'))
                    currentVal = data.get(h);
                    data.set(h, currentVal * (pi/180));
                end
            end
        end        
        % Ensure the internal flag is explicitly set to false
        storage.setInDegrees(false);

        % 3. Rename and save the "Radian" version
        storage.print(outputIK);
        fprintf('Converted %s to Radians\n', outputIK);
    end
    

    % Edit ExternalLoads xml
    xmlPath = fullfile(parentDirectory, "GRFLocalTemplate.xml"); % Read in template XML
    xmlFile = xmlread(xmlPath);
    grfName = [trialName '_GRF.mot'];
    xmlFile.getElementsByTagName('datafile').item(0).setTextContent(grfName);
    xmlFile.getElementsByTagName('data_source_name').item(0).setTextContent(grfName);
    xmlFile.getElementsByTagName('data_source_name').item(1).setTextContent(grfName);
    grfXMLName = [trialName '_GRF.xml'];
    xmlwrite(grfXMLName, xmlFile); % Save the edited XML


    %% ADJUST GRF COP LOCATIONS TO BE PROJECTED FROM THE HEEL MARKER POINTS
    % Get list of all .csv trials
    temp = strrep(trialName, [subjectName '_'], '');
    csvName = [temp '.csv'];
    data_read = readtable(csvName);

    currentMarkerSet = {};

    MOTtemplate = readcell(templateMOTname);
    
    csvData = readNoraxon(data_read, trajectoriesFixed, trajectoriesOriginal, forces, samplingRate);    
    dataCount = length(csvData.time);
    rotated_data = rotateAroundX(csvData, trajectoriesFixed);
    
    %% ROTATE AND TRANSLATE CENTER OF PRESSURE
    
    % Get rid of NaNs in CoP data
    [rotated_data.noNaN_CoP_LT_x, rotated_data.noNaN_CoP_LT_y, rotated_data.noNaN_GRF_LT] = fixCoPNaNs(rotated_data.Insole_LTInsole_CenterOfPressure_x_mm_, rotated_data.Insole_LTInsole_CenterOfPressure_y_mm_, rotated_data.LTInsole_Total___);
    [rotated_data.noNaN_CoP_RT_x, rotated_data.noNaN_CoP_RT_y, rotated_data.noNaN_GRF_RT] = fixCoPNaNs(rotated_data.Insole_RTInsole_CenterOfPressure_x_mm_, rotated_data.Insole_RTInsole_CenterOfPressure_y_mm_, rotated_data.RTInsole_Total___);

    % Convert from mm to m
    rotated_data.CoP_LT_y = repmat(-0.1, dataCount, 1);
    rotated_data.CoP_RT_y = repmat(-0.1, dataCount, 1);

    rotated_data.CoP_LT_x = (rotated_data.noNaN_CoP_LT_y + 2) / 1000;
    rotated_data.CoP_LT_z = rotated_data.noNaN_CoP_LT_x / 1000; 
    rotated_data.CoP_RT_x = (rotated_data.noNaN_CoP_RT_y - 2) / 1000;
    rotated_data.CoP_RT_z = rotated_data.noNaN_CoP_RT_x / 1000; 
    
    % CONVERT GRFS TO NEWTONS
    rotated_data.GRF_LT = (rotated_data.noNaN_GRF_LT ./ 100) .*subjectMass.*9.81;
    rotated_data.GRF_RT = (rotated_data.noNaN_GRF_RT ./ 100) .*subjectMass.*9.81;
    
    % CALCULATE GROUND REACTION MOMENTS
    rotated_data.M_LT_x = rotated_data.GRF_LT.*rotated_data.CoP_LT_z;
    % rotated_data.M_LT_y = 0;
    rotated_data.M_LT_z = rotated_data.GRF_LT.*rotated_data.CoP_LT_x;
    rotated_data.M_RT_x = rotated_data.GRF_RT.*rotated_data.CoP_RT_z;
    % rotated_data.M_RT_y = 0;
    rotated_data.M_RT_z = rotated_data.GRF_RT.*rotated_data.CoP_RT_x;

    % SET UP .MOT FILE
    % Set up header info
    trial_motName = append(trialName, '_GRF', '.mot');

    % Add specific header info
    MOTtemplate{1,1} = trial_motName;
    MOTtemplate{3,1} = append('nRows=',num2str(dataCount));

    % Add frame, time, and marker coordinate data
    for p = startIndex:stopIndex
        MOTtemplate{p+7,1} = p*0.01-0.01; % Time
        MOTtemplate{p+7,2} = 0; % Left GRF x
        MOTtemplate{p+7,3} = rotated_data.GRF_LT(p); % Left GRF y
        MOTtemplate{p+7,4} = 0; % Left GRF z
        MOTtemplate{p+7,5} = rotated_data.CoP_LT_x(p); % Left CoP x
        MOTtemplate{p+7,6} = rotated_data.CoP_LT_y(p); % Left CoP y
        MOTtemplate{p+7,7} = rotated_data.CoP_LT_z(p); % Left CoP z
        %
        MOTtemplate{p+7,8} = 0; % Right GRF x
        MOTtemplate{p+7,9} = rotated_data.GRF_RT(p); % Right GRF y
        MOTtemplate{p+7,10} = 0; % Right GRF z
        MOTtemplate{p+7,11} = rotated_data.CoP_RT_x(p); % Right CoP x
        MOTtemplate{p+7,12} = rotated_data.CoP_RT_y(p); % Right CoP y
        MOTtemplate{p+7,13} = rotated_data.CoP_RT_z(p); % Right CoP z
        %
        MOTtemplate{p+7,14} = rotated_data.M_LT_x(p); % Left Moment x
        MOTtemplate{p+7,15} = 0; % Left Moment y
        MOTtemplate{p+7,16} = rotated_data.M_LT_z(p); % Left Moment z
        %
        MOTtemplate{p+7,17} = rotated_data.M_RT_x(p); % Right Moment x
        MOTtemplate{p+7,18} = 0; % Right Moment y
        MOTtemplate{p+7,19} = rotated_data.M_RT_z(p); % Right Moment z
    end

    % Remove <missing> in cells
    mask = cellfun(@(x) any(isa(x,'missing')), MOTtemplate);
    MOTtemplate(mask) = {[]};

    % WRITE GRF MOT FILE
    trial_fileName = trial_motName(1:end-4);
    fullfilePath = fullfile(trial_fileName);
    writecell(MOTtemplate, fullfilePath, 'Delimiter', '\t');

    % Change files from .txt to .mot
    file1 = append(fullfilePath, '.txt');
    file2 = strrep(file1,'.txt','.mot');
    copyfile(file1,file2);
    delete(file1);
    fprintf(['Wrote ' trial_fileName '.mot\n'])            

    %% ID
    kineticsTool.setModel(scaledModel);

    kineticsTool.setExternalLoadsFileName(grfXMLName);
    kineticsTool.setCoordinatesFileName(outputIK);

    % 4. Set Time Range and Output
    kineticsTool.setStartTime(initial_time);
    kineticsTool.setEndTime(final_time);
    outputID = [trialName '_ID.sto'];
    kineticsTool.setResultsDir(cd);
    outputIDpath = fullfile(cd, outputID);
    kineticsTool.setOutputGenForceFileName(outputIDpath);

    kineticsTool.setLowpassCutoffFrequency(6.0); % Filter data    

    fprintf(['Performing ID on ' trialName '\n']);
    kineticsTool.run();
end
%%
fprintf(append('Finished OpenSim Pipeline for ', subjectName, '\n'))
cd(parentDirectory)