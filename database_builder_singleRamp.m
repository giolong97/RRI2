% DATABASE BUILDER RRI2 - SR/DR, FILE SINGOLA RAMPA
%
% Output:
%   - una riga per ciascun file analizzato
%   - stessa struttura SR/DR del database_builder_Ramp:
%       Rotor 1: T1, Q1, RPM1, Ct1, Cq1, ...
%       Rotor 2: T2, Q2, RPM2, Ct2, Cq2, ...
%
% Convenzione:
%   - SR/IR: viene analizzato il powertrain indicato da activeSRPowertrain
%   - DR: vengono analizzati entrambi i rotori

clear; close all; clc;

%% ========================== INPUT =======================================
D   = 20*0.0254;      
svflg = false;
makePlots = true;

% true:
%   anche nei casi SR salva entrambi i canali, utile per diagnosi cross-talk.
% false:
%   nei casi SR salva solo il canale attivo e riempie il passivo con NaN.
alwaysComputeBothChannels = true;

sr = 20;     % s/r = metti NaN nel caso SR/IR, sennò cambia sr sotto 
pw = 2;      % pwt attivo SR/IR: 1 o 2. DR: valore ignorato.
conf = 'DR';

inpath  = 'E:\APC_Prove\20x13\29_04_26';
outpath = 'E:\APC_Prove\20x13\Analisi\database_29_04_26\';

cases = table();

cases.MP_number = [
    204
    205
    206
    207
    208
    209
    210
    211
];

% cases.filename = [
%     "APC_20x13EP_SR_RPM1000_mot1.csv"
%     "APC_20x13EP_SR_RPM1500_mot1.csv"
%     "APC_20x13EP_SR_RPM2000_mot1.csv"
%     "APC_20x13EP_SR_RPM2500_mot1.csv"
%     "APC_20x13EP_SR_RPM3000_mot1.csv"
%     "APC_20x13EP_SR_RPM3500_mot1.csv"
%     "APC_20x13EP_SR_RPM4000_mot1.csv"
%     "APC_20x13EP_SR_RPM4500_mot1.csv"
% ];

cases.filename = [
    "APC_20x13_DR_RPM1000_SR20.csv"
    "APC_20x13_DR_RPM1500_SR20.csv"
    "APC_20x13_DR_RPM2000_SR20.csv"
    "APC_20x13_DR_RPM2500_SR20.csv"
    "APC_20x13_DR_RPM3000_SR20.csv"
    "APC_20x13_DR_RPM3500_SR20.csv"
    "APC_20x13_DR_RPM4000_SR20.csv"
    "APC_20x13_DR_RPM4500_SR20.csv"
];


cases.RPM_target = [
    1000
    1500
    2000
    2500
    3000
    3500
    4000
    4500
];

if strcmp(conf, 'DR')
    cases.conf = repmat("DR",length(cases.filename), 1);
elseif strcmp(conf, 'SR') || strcmp(conf, 'IR')
    cases.conf = repmat("IR",length(cases.filename), 1);
end

% SR/IR: 1 o 2. DR: valore ignorato.
cases.activeSRPowertrain = pw*ones((length(cases.filename)),1);
cases.s_over_R = sr*ones((length(cases.activeSRPowertrain)),1);


%% Outilier detection

% Gli outlier vengono sostituiti con NaN.
% Nessuna interpolazione.
% Le medie vengono calcolate con omitnan.

cleaned_T   = true;
cleaned_Q   = true;
cleaned_RPM = true;

baseOutlierOpts.useGlobal = true;
baseOutlierOpts.useLocal  = true;

% Soglie iniziali ragionevoli
baseOutlierOpts.globalThreshold = 6.0;
baseOutlierOpts.localThreshold  = 4.5;
baseOutlierOpts.localWindow_s   = 0.20;   % [s]

outlierOpts_T   = baseOutlierOpts;
outlierOpts_Q   = baseOutlierOpts;
outlierOpts_RPM = baseOutlierOpts;

%% Tare / zero correction

applyTareCorrection = true;

tareWindow_s = 0.80;      % usa 0.8 s su 1 s disponibile
tareGuard_s  = 0.05;      % evita i bordi del file

tareRPMmax = 30;          % [rpm] soglia motore spento
tarePWMmax = 1000;        % [us] modifica se il tuo minimo non è 1100

tareUseEndZero = true;    % usa anche lo zero finale

%% Finestra di filtraggio

sampleDuration = 60;       % [s]
settleTime     = 0;        % [s]
avgDuration    = sampleDuration - settleTime;

% "firstCommand", "maxPWM", "fromFileStart", "manual"
windowStartMode = "maxPWM";

%% Paramentri fisici

rho = 1.225;          % [kg/m^3]
kgf2N = 9.80665;

useAbsTorqueForCoeff = true;
useAbsTorqueForPower = true;

% "measured", "target", "targetIfBad"
rpmCoeffPolicy = "targetIfBad";
rpmBadTolAbs = 100;      % [rpm]
rpmBadTolRel = 0.05;     % [-]

%% Colonne CSV

if ~exist(outpath, 'dir')
    mkdir(outpath);
end

figpath = fullfile(outpath, 'Figures');
if makePlots && ~exist(figpath, 'dir')
    mkdir(figpath);
end

col.t = 1;

% Powertrain / load cell 1
col.pwm1 = 2;
col.T1   = 3;    % [kgf]
col.Q1   = 4;    % [Nm]
col.V1   = 5;
col.A1   = 6;
col.rpm1 = 7;    % [RPM]

% Powertrain / load cell 2
col.pwm2 = 15;
col.T2   = 16;   % [kgf]
col.Q2   = 17;   % [Nm]
col.V2   = 18;
col.A2   = 19;
col.rpm2 = 20;   % [RPM]


%% ============================ MAIN ======================================

cases = normalizeCasesTable(cases);

DB = table();

for ic = 1:height(cases)

    filename = string(cases.filename(ic));
    filepath = fullfile(inpath, filename);

    if ~isfile(filepath)
        error('File not found: %s', filepath);
    end

    fprintf('\nProcessing %d/%d: %s\n', ic, height(cases), filename);

    d = importdata(filepath);

    if ~isstruct(d) || ~isfield(d, 'data')
        error('File %s was not imported as a structure with .data.', filename);
    end

    data = d.data;

    if size(data,2) < col.t
        error('File %s does not contain the time column.', filename);
    end

    t = data(:,col.t);

    conf = string(cases.conf(ic));
    confUpper = upper(conf);

    isDR = contains(confUpper, "DR");

    if isDR
        nRotors = 2;
        activeSRPowertrain = NaN;
    else
        nRotors = 1;
        activeSRPowertrain = cases.activeSRPowertrain(ic);

        if isnan(activeSRPowertrain)
            error(['For SR/IR file %s, activeSRPowertrain must be 1 or 2. ', ...
                   'For DR files use conf = "DR".'], filename);
        end

        if activeSRPowertrain ~= 1 && activeSRPowertrain ~= 2
            error('activeSRPowertrain for file %s must be 1 or 2.', filename);
        end
    end

    rpmTarget = cases.RPM_target(ic);

    tStart = detectWindowStart(t, data, col, nRotors, activeSRPowertrain, windowStartMode);
    tAvgStart = tStart + settleTime;
    tAvgEnd   = tAvgStart + avgDuration;

    idx = t >= tAvgStart & t <= tAvgEnd;

    if ~any(idx)
        warning('No samples found in selected window for %s.', filename);
    end

    row = struct();

    [~, baseName, ext] = fileparts(filename);

    row.filename = filename;
    row.basename = string([baseName ext]);
    row.conf = conf;
    row.mode = parseModeFromConf(conf);
    row.RPM_target = rpmTarget;
    row.s_over_R = cases.s_over_R(ic);
    row.activeSRPowertrain = activeSRPowertrain;
    row.MP_number = cases.MP_number(ic);

    row.t_start_s = tStart;
    row.t_avg_start_s = tAvgStart;
    row.t_avg_end_s = tAvgEnd;
    row.sampleDuration_s = sampleDuration;
    row.settleTime_s = settleTime;
    row.N_samples_window = sum(idx);
    row.windowStartMode = string(windowStartMode);

    % ============================================================
    % Decide quali rotori calcolare
    % ============================================================

    if alwaysComputeBothChannels
        computeRotor1 = true;
        computeRotor2 = true;
    else
        if nRotors == 2
            computeRotor1 = true;
            computeRotor2 = true;
        else
            computeRotor1 = activeSRPowertrain == 1;
            computeRotor2 = activeSRPowertrain == 2;
        end
    end

    % Nei casi SR/IR il rotore passivo NON deve usare RPM_target.
    rpmTarget_R1 = rpmTarget;
    rpmTarget_R2 = rpmTarget;

    if nRotors == 1
        if activeSRPowertrain == 1
            rpmTarget_R2 = NaN;
        elseif activeSRPowertrain == 2
            rpmTarget_R1 = NaN;
        end
    end

    % ============================================================
    % Rotor 1
    % ============================================================

    if computeRotor1

        R1 = rotorStatsSingleRamp( ...
            t, data, idx, col.T1, col.Q1, col.rpm1, col.V1, col.A1, ...
            rpmTarget_R1, NaN, rho, D, kgf2N, ...
            useAbsTorqueForCoeff, useAbsTorqueForPower, ...
            rpmCoeffPolicy, rpmBadTolAbs, rpmBadTolRel, ...
            cleaned_T, cleaned_Q, cleaned_RPM, ...
            outlierOpts_T, outlierOpts_Q, outlierOpts_RPM);

        row = writeRotorToRow(row, R1, 1);

    else

        row = writeRotorNaN(row, 1);
        R1.RPM_used = NaN;

    end

    % ============================================================
    % Rotor 2
    % ============================================================

    if computeRotor2

        if nRotors == 2
            rpmFallback = R1.RPM_used;
        else
            rpmFallback = NaN;
        end

        R2 = rotorStatsSingleRamp( ...
            t, data, idx, col.T2, col.Q2, col.rpm2, col.V2, col.A2, ...
            rpmTarget_R2, rpmFallback, rho, D, kgf2N, ...
            useAbsTorqueForCoeff, useAbsTorqueForPower, ...
            rpmCoeffPolicy, rpmBadTolAbs, rpmBadTolRel, ...
            cleaned_T, cleaned_Q, cleaned_RPM, ...
            outlierOpts_T, outlierOpts_Q, outlierOpts_RPM);

        row = writeRotorToRow(row, R2, 2);

    else

        row = writeRotorNaN(row, 2);

    end

    % ============================================================
    % Grandezze combinate DR 
    % ============================================================

    row.T_total_N = NaN;
    row.P_total_W = NaN;
    row.Q_abs_total_Nm = NaN;

    row.Ct_mean_rotors = NaN;
    row.Cq_mean_rotors = NaN;

    row.Ct_total = NaN;
    row.Cq_total = NaN;

    row.Ct_mean_rotors_std = NaN;
    row.Cq_mean_rotors_std = NaN;

    row.Ct_total_std = NaN;
    row.Cq_total_std = NaN;

    if nRotors == 2

        row.T_total_N = row.T1_mean_N + row.T2_mean_N;
        row.P_total_W = row.P1_mean_W + row.P2_mean_W;
        row.Q_abs_total_Nm = row.Q1_abs_mean_Nm + row.Q2_abs_mean_Nm;

        row.Ct_mean_rotors = 0.5*(row.Ct1 + row.Ct2);
        row.Cq_mean_rotors = 0.5*(row.Cq1 + row.Cq2);

        row.Ct_total = row.Ct1 + row.Ct2;
        row.Cq_total = row.Cq1 + row.Cq2;

        row.Ct_mean_rotors_std = 0.5*(row.Ct1_std + row.Ct2_std);
        row.Cq_mean_rotors_std = 0.5*(row.Cq1_std + row.Cq2_std);

        row.Ct_total_std = row.Ct1_std + row.Ct2_std;
        row.Cq_total_std = row.Cq1_std + row.Cq2_std;

    end

    % ============================================================
    % Diagnostica SR: canale attivo vs canale passivo
    % ============================================================

    row.activeRotorID = activeSRPowertrain;
    row.passiveRotorID = NaN;

    row.T_active_N = NaN;
    row.T_passive_N = NaN;
    row.RPM_active_mean = NaN;
    row.RPM_passive_mean = NaN;

    row.passive_T_on_active_percent = NaN;
    row.passive_T_abs_on_active_abs_percent = NaN;

    if nRotors == 1

        if activeSRPowertrain == 1

            row.passiveRotorID = 2;

            row.T_active_N = row.T1_mean_N;
            row.T_passive_N = row.T2_mean_N;

            row.RPM_active_mean = row.RPM1_mean;
            row.RPM_passive_mean = row.RPM2_mean;

        elseif activeSRPowertrain == 2

            row.passiveRotorID = 1;

            row.T_active_N = row.T2_mean_N;
            row.T_passive_N = row.T1_mean_N;

            row.RPM_active_mean = row.RPM2_mean;
            row.RPM_passive_mean = row.RPM1_mean;

        end

        if isfinite(row.T_active_N) && row.T_active_N ~= 0

            row.passive_T_on_active_percent = ...
                100 * row.T_passive_N / row.T_active_N;

            row.passive_T_abs_on_active_abs_percent = ...
                100 * abs(row.T_passive_N) / abs(row.T_active_N);

        end

    end

    % ============================================================
    % Diagnostica DR: bilanciamento tra i due rotori
    % ============================================================

    row.RPM12_mismatch_percent = NaN;
    row.T12_mismatch_percent = NaN;

    if nRotors == 2

        RPM_mean_pair = mean([row.RPM1_mean, row.RPM2_mean], 'omitnan');
        T_mean_pair   = mean([row.T1_mean_N, row.T2_mean_N], 'omitnan');

        if isfinite(RPM_mean_pair) && RPM_mean_pair ~= 0
            row.RPM12_mismatch_percent = ...
                100 * (row.RPM1_mean - row.RPM2_mean) / RPM_mean_pair;
        end

        if isfinite(T_mean_pair) && T_mean_pair ~= 0
            row.T12_mismatch_percent = ...
                100 * (row.T1_mean_N - row.T2_mean_N) / T_mean_pair;
        end

    end

    rowTable = struct2table(row);

    %Se il database è vuoto, crealo con questa riga. Se esiste già, attacca la nuova riga in fondo
    if isempty(DB)
        DB = rowTable;
    else
        DB = [DB; rowTable];
    end

    % ============================================================
    % Stampa base
    % ============================================================

    if nRotors == 1

        if activeSRPowertrain == 1
            fprintf('  SR/IR | PT1 | %.2f-%.2f s | RPM target %.0f | RPM mean %.1f | Ct %.5g | Cq %.5g\n', ...
                tAvgStart, tAvgEnd, rpmTarget, row.RPM1_mean, row.Ct1, row.Cq1);
        else
            fprintf('  SR/IR | PT2 | %.2f-%.2f s | RPM target %.0f | RPM mean %.1f | Ct %.5g | Cq %.5g\n', ...
                tAvgStart, tAvgEnd, rpmTarget, row.RPM2_mean, row.Ct2, row.Cq2);
        end

    else

        fprintf('  DR | %.2f-%.2f s | RPM target %.0f | RPM1 %.1f | RPM2 %.1f | Ct1 %.5g | Ct2 %.5g\n', ...
            tAvgStart, tAvgEnd, rpmTarget, row.RPM1_mean, row.RPM2_mean, row.Ct1, row.Ct2);

    end

    % ============================================================
    % Stampa diagnostica outlier
    % ============================================================

    if computeRotor1
        fprintf(['  R1 cleaning | ', ...
                 'T out %.4f%% | dTmean %.4f%% | ', ...
                 'Q out %.4f%% | dQabsmean %.4f%% | ', ...
                 'RPM out %.4f%% | dRPMmean %.4f%% | dCt %.4f%% | RPM source %s\n'], ...
            100*row.frac_T1_outliers, row.T1_clean_minus_raw_percent, ...
            100*row.frac_Q1_outliers, row.Q1_abs_clean_minus_raw_percent, ...
            100*row.frac_RPM1_outliers, row.RPM1_clean_minus_raw_percent, ...
            row.Ct1_clean_minus_raw_percent, ...
            string(row.RPM1_used_source));
    end

    if computeRotor2
        fprintf(['  R2 cleaning | ', ...
                 'T out %.4f%% | dTmean %.4f%% | ', ...
                 'Q out %.4f%% | dQabsmean %.4f%% | ', ...
                 'RPM out %.4f%% | dRPMmean %.4f%% | dCt %.4f%% | RPM source %s\n'], ...
            100*row.frac_T2_outliers, row.T2_clean_minus_raw_percent, ...
            100*row.frac_Q2_outliers, row.Q2_abs_clean_minus_raw_percent, ...
            100*row.frac_RPM2_outliers, row.RPM2_clean_minus_raw_percent, ...
            row.Ct2_clean_minus_raw_percent, ...
            string(row.RPM2_used_source));
    end

    % ============================================================
    % Plot
    % ============================================================

    if makePlots

        plotSingleRampFile(t, data, col, nRotors, activeSRPowertrain, ...
            alwaysComputeBothChannels, ...
            tAvgStart, tAvgEnd, baseName, figpath, ...
            cleaned_T, cleaned_Q, cleaned_RPM, ...
            outlierOpts_T, outlierOpts_Q, outlierOpts_RPM);

    end

end

%% ===================== SAVE ==================================

if svflg

    outCSV_all = fullfile(outpath, 'database_RRI2_singleRamp_SR_DR_allMP.csv');
    outMAT_all = fullfile(outpath, 'database_RRI2_singleRamp_SR_DR_allMP.mat');

    writetable(DB, outCSV_all);
    save(outMAT_all, 'DB', 'cases', 'rho', 'D', 'kgf2N', ...
        'sampleDuration', 'settleTime', 'rpmCoeffPolicy', ...
        'windowStartMode', 'col', ...
        'cleaned_T', 'cleaned_Q', 'cleaned_RPM', ...
        'outlierOpts_T', 'outlierOpts_Q', 'outlierOpts_RPM');

    fprintf('\nSaved complete database:\n  %s\n  %s\n', outCSV_all, outMAT_all);

    MP_values = unique(DB.MP_number);
    MP_values = MP_values(~isnan(MP_values));

    for iMP = 1:numel(MP_values)

        MP = MP_values(iMP);

        DB_MP = DB(DB.MP_number == MP, :);

        outCSV_MP = fullfile(outpath, sprintf('MP_%d_database.csv', MP));
        outMAT_MP = fullfile(outpath, sprintf('MP_%d_database.mat', MP));

        writetable(DB_MP, outCSV_MP);
        save(outMAT_MP, 'DB_MP', 'cases', 'rho', 'D', 'kgf2N', ...
            'sampleDuration', 'settleTime', 'rpmCoeffPolicy', ...
            'windowStartMode', 'col', ...
            'cleaned_T', 'cleaned_Q', 'cleaned_RPM', ...
            'outlierOpts_T', 'outlierOpts_Q', 'outlierOpts_RPM');

        fprintf('Saved MP database:\n  %s\n  %s\n', outCSV_MP, outMAT_MP);

    end

end

fprintf('\nDone. Processed %d files.\n', height(DB));

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function cases = normalizeCasesTable(cases)

    if isempty(cases)
        error('The cases table is empty. Add at least one input file.');
    end

    n = height(cases);

    if ~ismember('filename', cases.Properties.VariableNames)
        error('cases must contain a filename column.');
    end

    cases.filename = string(cases.filename);

    if ~ismember('MP_number', cases.Properties.VariableNames)
        error('cases must contain an MP_number column.');
    end

    cases.MP_number = double(cases.MP_number);

    if ~ismember('conf', cases.Properties.VariableNames)
        cases.conf = strings(n,1);
        for i = 1:n
            cases.conf(i) = parseConfFromFilename(cases.filename(i));
        end
    else
        cases.conf = string(cases.conf);
        for i = 1:n
            if strlength(cases.conf(i)) == 0 || ismissing(cases.conf(i))
                cases.conf(i) = parseConfFromFilename(cases.filename(i));
            end
        end
    end

    if ~ismember('RPM_target', cases.Properties.VariableNames)
        cases.RPM_target = NaN(n,1);
        for i = 1:n
            cases.RPM_target(i) = parseRPMFromFilename(cases.filename(i));
        end
    end

    if ~ismember('activeSRPowertrain', cases.Properties.VariableNames)
        cases.activeSRPowertrain = NaN(n,1);
    end

    if ~ismember('s_over_R', cases.Properties.VariableNames)
        cases.s_over_R = NaN(n,1);
    end

    if ~ismember('t_start_s', cases.Properties.VariableNames)
        cases.t_start_s = NaN(n,1);
    end

end

function conf = parseConfFromFilename(filename)

    fname = upper(string(filename));

    if contains(fname, 'DR')
        conf = "DR";
    elseif contains(fname, 'IR1')
        conf = "IR1";
    elseif contains(fname, 'IR2')
        conf = "IR2";
    elseif contains(fname, 'IR')
        conf = "IR";
    elseif contains(fname, 'SR')
        conf = "SR";
    else
        conf = "UNKNOWN";
    end

end

function mode = parseModeFromConf(conf)

    confUpper = upper(string(conf));

    if contains(confUpper, "DR")
        mode = "DR";
    elseif contains(confUpper, "IR1")
        mode = "IR1";
    elseif contains(confUpper, "IR2")
        mode = "IR2";
    elseif contains(confUpper, "IR")
        mode = "IR";
    elseif contains(confUpper, "SR")
        mode = "SR";
    else
        mode = "";
    end

end

function rpm = parseRPMFromFilename(filename)

    token = regexp(char(filename), 'RPM(\d+)', 'tokens', 'once');

    if isempty(token)
        rpm = NaN;
    else
        rpm = str2double(token{1});
    end

end

function tStart = detectWindowStart(t, data, col, nRotors, activeSRPowertrain, mode)

    mode = string(mode);

    if nRotors == 2
        pwmRef = getColumn(data, col.pwm1);
    else
        if activeSRPowertrain == 1
            pwmRef = getColumn(data, col.pwm1);
        else
            pwmRef = getColumn(data, col.pwm2);
        end
    end

    switch mode

        case "firstCommand"

            idx = find(~isnan(pwmRef), 1, 'first');

            if isempty(idx)
                tStart = t(1);
            else
                tStart = t(idx);
            end

        case "maxPWM"

            valid = find(~isnan(pwmRef));

            if isempty(valid)
                tStart = t(1);
            else
                [~, iLocal] = max(pwmRef(valid));
                tStart = t(valid(iLocal));
            end

        case "fromFileStart"

            tStart = t(1);

        case "manual"

            error('windowStartMode = "manual" requires cases.t_start_s to be non-NaN.');

        otherwise

            error('Unknown windowStartMode: %s', mode);

    end

end

function x = getColumn(data, colID, idx)

    if nargin < 3
        idx = true(size(data,1),1);
    end

    if isempty(colID) || isnan(colID) || colID < 1 || colID > size(data,2)
        x = NaN(sum(idx),1);
    else
        tmp = data(:,colID);
        x = tmp(idx);
    end

end

function value = valueAtOrAfter(t, x, t0)

    idx = find(~isnan(x) & t >= t0, 1, 'first');

    if isempty(idx)
        value = NaN;
    else
        value = x(idx);
    end

end

function R = rotorStatsSingleRamp(t, data, idx, colT, colQ, colRPM, colV, colA, ...
                                  rpmTarget, rpmFallback, rho, D, kgf2N, ...
                                  useAbsTorqueForCoeff, useAbsTorqueForPower, ...
                                  rpmCoeffPolicy, rpmBadTolAbs, rpmBadTolRel, ...
                                  cleaned_T, cleaned_Q, cleaned_RPM, ...
                                  outlierOpts_T, outlierOpts_Q, outlierOpts_RPM)

    t_win = t(idx);

    T_kgf_raw = getColumn(data, colT,   idx);
    Q_raw     = getColumn(data, colQ,   idx);
    RPM_raw   = getColumn(data, colRPM, idx);
    V_raw     = getColumn(data, colV,   idx);
    A_raw     = getColumn(data, colA,   idx);

    % ============================================================
    % Raw statistics
    % ============================================================

    T_raw_valid = T_kgf_raw(isfinite(T_kgf_raw));
    Q_raw_valid = Q_raw(isfinite(Q_raw));

    RPM_raw_finite   = RPM_raw(isfinite(RPM_raw));
    RPM_raw_positive = RPM_raw(isfinite(RPM_raw) & RPM_raw > 0);

    R.T_mean_kgf_raw = mean(T_raw_valid, 'omitnan');
    R.T_std_kgf_raw  = std(T_raw_valid,  'omitnan');
    R.T_mean_N_raw   = R.T_mean_kgf_raw * kgf2N;
    R.T_std_N_raw    = R.T_std_kgf_raw  * kgf2N;

    R.Q_mean_Nm_raw     = mean(Q_raw_valid, 'omitnan');
    R.Q_std_Nm_raw      = std(Q_raw_valid,  'omitnan');
    R.Q_abs_mean_Nm_raw = mean(abs(Q_raw_valid), 'omitnan');
    R.Q_abs_std_Nm_raw  = std(abs(Q_raw_valid),  'omitnan');

    R.RPM_mean_raw = mean(RPM_raw_positive, 'omitnan');
    R.RPM_std_raw  = std(RPM_raw_positive,  'omitnan');

    R.N_T_raw_valid = numel(T_raw_valid);
    R.N_Q_raw_valid = numel(Q_raw_valid);
    R.N_RPM_raw_valid = numel(RPM_raw_finite);
    R.N_RPM_raw_positive = numel(RPM_raw_positive);

    % Campi sempre inizializzati per evitare errori nei canali passivi
    R.Ct_raw_from_rawRPM = NaN;
    R.Cq_raw_from_rawRPM = NaN;
    R.Ct_clean_minus_raw_percent = NaN;
    R.Cq_clean_minus_raw_percent = NaN;

    if isfinite(R.RPM_mean_raw) && R.RPM_mean_raw > 0

        n_raw = R.RPM_mean_raw / 60;

        R.Ct_raw_from_rawRPM = ...
            R.T_mean_N_raw / (rho*n_raw^2*D^4);

        if useAbsTorqueForCoeff
            R.Cq_raw_from_rawRPM = ...
                R.Q_abs_mean_Nm_raw / (rho*n_raw^2*D^5);
        else
            R.Cq_raw_from_rawRPM = ...
                R.Q_mean_Nm_raw / (rho*n_raw^2*D^5);
        end

    end

    % ============================================================
    % Outlier cleaning: T, Q, RPM
    % ============================================================

    [T_kgf_used, outT] = cleanSignalForStatsNaN(t_win, T_kgf_raw, cleaned_T, outlierOpts_T);
    [Q_used,     outQ] = cleanSignalForStatsNaN(t_win, Q_raw,     cleaned_Q, outlierOpts_Q);
    [RPM_used_signal, outRPM] = cleanSignalForStatsNaN(t_win, RPM_raw, cleaned_RPM, outlierOpts_RPM);

    R.T_cleaning_enabled   = cleaned_T;
    R.Q_cleaning_enabled   = cleaned_Q;
    R.RPM_cleaning_enabled = cleaned_RPM;

    R.N_T_outliers = outT.N_outliers;
    R.N_Q_outliers = outQ.N_outliers;
    R.N_RPM_outliers = outRPM.N_outliers;

    R.frac_T_outliers = outT.frac_outliers;
    R.frac_Q_outliers = outQ.frac_outliers;
    R.frac_RPM_outliers = outRPM.frac_outliers;

    R.N_T_global_outliers = outT.N_global;
    R.N_Q_global_outliers = outQ.N_global;
    R.N_RPM_global_outliers = outRPM.N_global;

    R.N_T_local_outliers = outT.N_local;
    R.N_Q_local_outliers = outQ.N_local;
    R.N_RPM_local_outliers = outRPM.N_local;

    % ============================================================
    % Final valid vectors
    % ============================================================

    T_kgf = T_kgf_used(isfinite(T_kgf_used));
    Q     = Q_used(isfinite(Q_used));

    RPM_finite = RPM_used_signal(isfinite(RPM_used_signal));
    RPM_valid  = RPM_used_signal(isfinite(RPM_used_signal) & RPM_used_signal > 0);

    V = V_raw(isfinite(V_raw));
    A = A_raw(isfinite(A_raw));

    R.N_T = numel(T_kgf);
    R.N_Q = numel(Q);
    R.N_RPM_raw = numel(RPM_finite);
    R.N_RPM = numel(RPM_valid);
    R.N_V = numel(V);
    R.N_A = numel(A);

    R.N_RPM_nonpositive_after_cleaning = ...
        sum(isfinite(RPM_used_signal) & RPM_used_signal <= 0);

    % ============================================================
    % Final T statistics
    % ============================================================

    R.T_mean_kgf = mean(T_kgf, 'omitnan');
    R.T_std_kgf  = std(T_kgf,  'omitnan');

    R.T_mean_N = R.T_mean_kgf * kgf2N;
    R.T_std_N  = R.T_std_kgf  * kgf2N;

    if isfinite(R.T_mean_N_raw) && R.T_mean_N_raw ~= 0
        R.T_clean_minus_raw_percent = ...
            100 * (R.T_mean_N - R.T_mean_N_raw) / R.T_mean_N_raw;
    else
        R.T_clean_minus_raw_percent = NaN;
    end

    % ============================================================
    % Final Q statistics
    % ============================================================

    R.Q_mean_Nm = mean(Q, 'omitnan');
    R.Q_std_Nm  = std(Q,  'omitnan');

    R.Q_abs_mean_Nm = mean(abs(Q), 'omitnan');
    R.Q_abs_std_Nm  = std(abs(Q),  'omitnan');

    if isfinite(R.Q_mean_Nm_raw) && R.Q_mean_Nm_raw ~= 0
        R.Q_clean_minus_raw_percent = ...
            100 * (R.Q_mean_Nm - R.Q_mean_Nm_raw) / R.Q_mean_Nm_raw;
    else
        R.Q_clean_minus_raw_percent = NaN;
    end

    if isfinite(R.Q_abs_mean_Nm_raw) && R.Q_abs_mean_Nm_raw ~= 0
        R.Q_abs_clean_minus_raw_percent = ...
            100 * (R.Q_abs_mean_Nm - R.Q_abs_mean_Nm_raw) / R.Q_abs_mean_Nm_raw;
    else
        R.Q_abs_clean_minus_raw_percent = NaN;
    end

    % ============================================================
    % V, A
    % ============================================================

    R.V_mean = mean(V, 'omitnan');
    R.V_std  = std(V,  'omitnan');

    R.A_mean = mean(A, 'omitnan');
    R.A_std  = std(A,  'omitnan');

    % ============================================================
    % Final RPM statistics
    % ============================================================

    if R.N_RPM > 0
        R.RPM_mean = mean(RPM_valid, 'omitnan');
        R.RPM_std  = std(RPM_valid,  'omitnan');
    else
        R.RPM_mean = NaN;
        R.RPM_std  = NaN;
    end

    if isfinite(R.RPM_mean_raw) && R.RPM_mean_raw ~= 0
        R.RPM_clean_minus_raw_percent = ...
            100 * (R.RPM_mean - R.RPM_mean_raw) / R.RPM_mean_raw;
    else
        R.RPM_clean_minus_raw_percent = NaN;
    end

    % ============================================================
    % RPM used for coefficients
    % ============================================================

    hasTarget   = ~isnan(rpmTarget)   && rpmTarget   > 0;
    hasMeasured = ~isnan(R.RPM_mean)  && R.RPM_mean  > 0;
    hasFallback = ~isnan(rpmFallback) && rpmFallback > 0;

    if hasTarget && hasMeasured
        rpmBadTol = max(rpmBadTolAbs, rpmBadTolRel*rpmTarget);
        R.RPM_bad_for_coeff = abs(R.RPM_mean - rpmTarget) > rpmBadTol;
    elseif hasTarget && ~hasMeasured
        R.RPM_bad_for_coeff = true;
    else
        R.RPM_bad_for_coeff = false;
    end

    rpmCoeffPolicy = string(rpmCoeffPolicy);

    R.RPM_used = NaN;
    R.RPM_used_source = "";

    switch rpmCoeffPolicy

        case "measured"

            if hasMeasured
                R.RPM_used = R.RPM_mean;
                R.RPM_used_source = "measured_clean";
            elseif hasFallback
                R.RPM_used = rpmFallback;
                R.RPM_used_source = "fallback";
            elseif hasTarget
                R.RPM_used = rpmTarget;
                R.RPM_used_source = "target_no_measured";
            else
                R.RPM_used = NaN;
                R.RPM_used_source = "missing";
            end

        case "target"

            if hasTarget
                R.RPM_used = rpmTarget;
                R.RPM_used_source = "target";
            elseif hasMeasured
                R.RPM_used = R.RPM_mean;
                R.RPM_used_source = "measured_clean_no_target";
            elseif hasFallback
                R.RPM_used = rpmFallback;
                R.RPM_used_source = "fallback";
            else
                R.RPM_used = NaN;
                R.RPM_used_source = "missing";
            end

        case "targetIfBad"

            if hasTarget && R.RPM_bad_for_coeff
                R.RPM_used = rpmTarget;
                R.RPM_used_source = "target_if_bad";
            elseif hasMeasured
                R.RPM_used = R.RPM_mean;
                R.RPM_used_source = "measured_clean";
            elseif hasFallback
                R.RPM_used = rpmFallback;
                R.RPM_used_source = "fallback";
            elseif hasTarget
                R.RPM_used = rpmTarget;
                R.RPM_used_source = "target_no_measured";
            else
                R.RPM_used = NaN;
                R.RPM_used_source = "missing";
            end

        otherwise

            error('Unknown rpmCoeffPolicy: %s', rpmCoeffPolicy);

    end

    % Inizializzo sempre
    R.P_mean_W = NaN;
    R.Ct       = NaN;
    R.Ct_std   = NaN;
    R.Cq       = NaN;
    R.Cq_std   = NaN;

    if isnan(R.RPM_used) || R.RPM_used <= 0
        return;
    end

    % ============================================================
    % Coefficients using cleaned signals
    % ============================================================

    n = R.RPM_used/60;     % [rev/s]

    if useAbsTorqueForPower
        Q_power = mean(abs(Q), 'omitnan');
    else
        Q_power = mean(Q, 'omitnan');
    end

    R.P_mean_W = 2*pi*n*Q_power;

    if useAbsTorqueForCoeff
        Q_coeff = abs(Q);
    else
        Q_coeff = Q;
    end

    R.Ct     = R.T_mean_N / (rho*n^2*D^4);
    R.Ct_std = R.T_std_N  / (rho*n^2*D^4);

    R.Cq     = mean(Q_coeff, 'omitnan') / (rho*n^2*D^5);
    R.Cq_std = std(Q_coeff,  'omitnan') / (rho*n^2*D^5);

    % ============================================================
    % Clean vs raw coefficient sensitivity
    % ============================================================

    if isfinite(R.Ct_raw_from_rawRPM) && R.Ct_raw_from_rawRPM ~= 0
        R.Ct_clean_minus_raw_percent = ...
            100 * (R.Ct - R.Ct_raw_from_rawRPM) / R.Ct_raw_from_rawRPM;
    end

    if isfinite(R.Cq_raw_from_rawRPM) && R.Cq_raw_from_rawRPM ~= 0
        R.Cq_clean_minus_raw_percent = ...
            100 * (R.Cq - R.Cq_raw_from_rawRPM) / R.Cq_raw_from_rawRPM;
    end

end

function row = writeRotorToRow(row, R, rotorID)

    s = num2str(rotorID);

    % T final
    row.(sprintf('T%s_mean_kgf',s)) = R.T_mean_kgf;
    row.(sprintf('T%s_std_kgf',s))  = R.T_std_kgf;
    row.(sprintf('T%s_mean_N',s))   = R.T_mean_N;
    row.(sprintf('T%s_std_N',s))    = R.T_std_N;

    % T raw
    row.(sprintf('T%s_mean_kgf_raw',s)) = R.T_mean_kgf_raw;
    row.(sprintf('T%s_std_kgf_raw',s))  = R.T_std_kgf_raw;
    row.(sprintf('T%s_mean_N_raw',s))   = R.T_mean_N_raw;
    row.(sprintf('T%s_std_N_raw',s))    = R.T_std_N_raw;

    row.(sprintf('T%s_cleaning_enabled',s)) = R.T_cleaning_enabled;
    row.(sprintf('N_T%s_raw_valid',s)) = R.N_T_raw_valid;
    row.(sprintf('N_T%s_outliers',s)) = R.N_T_outliers;
    row.(sprintf('N_T%s_global_outliers',s)) = R.N_T_global_outliers;
    row.(sprintf('N_T%s_local_outliers',s)) = R.N_T_local_outliers;
    row.(sprintf('frac_T%s_outliers',s)) = R.frac_T_outliers;
    row.(sprintf('T%s_clean_minus_raw_percent',s)) = R.T_clean_minus_raw_percent;

    % Q final
    row.(sprintf('Q%s_mean_Nm',s)) = R.Q_mean_Nm;
    row.(sprintf('Q%s_std_Nm',s)) = R.Q_std_Nm;
    row.(sprintf('Q%s_abs_mean_Nm',s)) = R.Q_abs_mean_Nm;
    row.(sprintf('Q%s_abs_std_Nm',s)) = R.Q_abs_std_Nm;

    % Q raw
    row.(sprintf('Q%s_mean_Nm_raw',s)) = R.Q_mean_Nm_raw;
    row.(sprintf('Q%s_std_Nm_raw',s)) = R.Q_std_Nm_raw;
    row.(sprintf('Q%s_abs_mean_Nm_raw',s)) = R.Q_abs_mean_Nm_raw;
    row.(sprintf('Q%s_abs_std_Nm_raw',s)) = R.Q_abs_std_Nm_raw;

    row.(sprintf('Q%s_cleaning_enabled',s)) = R.Q_cleaning_enabled;
    row.(sprintf('N_Q%s_raw_valid',s)) = R.N_Q_raw_valid;
    row.(sprintf('N_Q%s_outliers',s)) = R.N_Q_outliers;
    row.(sprintf('N_Q%s_global_outliers',s)) = R.N_Q_global_outliers;
    row.(sprintf('N_Q%s_local_outliers',s)) = R.N_Q_local_outliers;
    row.(sprintf('frac_Q%s_outliers',s)) = R.frac_Q_outliers;
    row.(sprintf('Q%s_clean_minus_raw_percent',s)) = R.Q_clean_minus_raw_percent;
    row.(sprintf('Q%s_abs_clean_minus_raw_percent',s)) = R.Q_abs_clean_minus_raw_percent;

    % RPM final
    row.(sprintf('RPM%s_mean',s)) = R.RPM_mean;
    row.(sprintf('RPM%s_std',s)) = R.RPM_std;
    row.(sprintf('RPM%s_used',s)) = R.RPM_used;
    row.(sprintf('RPM%s_used_source',s)) = string(R.RPM_used_source);
    row.(sprintf('RPM%s_bad_for_coeff',s)) = R.RPM_bad_for_coeff;

    % RPM raw
    row.(sprintf('RPM%s_mean_raw',s)) = R.RPM_mean_raw;
    row.(sprintf('RPM%s_std_raw',s)) = R.RPM_std_raw;

    row.(sprintf('RPM%s_cleaning_enabled',s)) = R.RPM_cleaning_enabled;
    row.(sprintf('N_RPM%s_raw_valid',s)) = R.N_RPM_raw_valid;
    row.(sprintf('N_RPM%s_raw_positive',s)) = R.N_RPM_raw_positive;
    row.(sprintf('N_RPM%s_outliers',s)) = R.N_RPM_outliers;
    row.(sprintf('N_RPM%s_global_outliers',s)) = R.N_RPM_global_outliers;
    row.(sprintf('N_RPM%s_local_outliers',s)) = R.N_RPM_local_outliers;
    row.(sprintf('frac_RPM%s_outliers',s)) = R.frac_RPM_outliers;
    row.(sprintf('RPM%s_clean_minus_raw_percent',s)) = R.RPM_clean_minus_raw_percent;
    row.(sprintf('N_RPM%s_nonpositive_after_cleaning',s)) = R.N_RPM_nonpositive_after_cleaning;

    % V, A
    row.(sprintf('V%s_mean',s)) = R.V_mean;
    row.(sprintf('V%s_std',s))  = R.V_std;
    row.(sprintf('A%s_mean',s)) = R.A_mean;
    row.(sprintf('A%s_std',s))  = R.A_std;

    % Power and coefficients
    row.(sprintf('P%s_mean_W',s)) = R.P_mean_W;

    row.(sprintf('Ct%s',s))     = R.Ct;
    row.(sprintf('Ct%s_std',s)) = R.Ct_std;
    row.(sprintf('Cq%s',s))     = R.Cq;
    row.(sprintf('Cq%s_std',s)) = R.Cq_std;

    row.(sprintf('Ct%s_raw_from_rawRPM',s)) = R.Ct_raw_from_rawRPM;
    row.(sprintf('Cq%s_raw_from_rawRPM',s)) = R.Cq_raw_from_rawRPM;

    row.(sprintf('Ct%s_clean_minus_raw_percent',s)) = R.Ct_clean_minus_raw_percent;
    row.(sprintf('Cq%s_clean_minus_raw_percent',s)) = R.Cq_clean_minus_raw_percent;

    % Number of final samples
    row.(sprintf('N_T%s',s)) = R.N_T;
    row.(sprintf('N_Q%s',s)) = R.N_Q;
    row.(sprintf('N_RPM%s',s)) = R.N_RPM;
    row.(sprintf('N_RPM%s_raw',s)) = R.N_RPM_raw;
    row.(sprintf('N_V%s',s)) = R.N_V;
    row.(sprintf('N_A%s',s)) = R.N_A;

end

function row = writeRotorNaN(row, rotorID)

    s = num2str(rotorID);

    row.(sprintf('T%s_mean_kgf',s)) = NaN;
    row.(sprintf('T%s_std_kgf',s)) = NaN;
    row.(sprintf('T%s_mean_N',s)) = NaN;
    row.(sprintf('T%s_std_N',s)) = NaN;

    row.(sprintf('T%s_mean_kgf_raw',s)) = NaN;
    row.(sprintf('T%s_std_kgf_raw',s)) = NaN;
    row.(sprintf('T%s_mean_N_raw',s)) = NaN;
    row.(sprintf('T%s_std_N_raw',s)) = NaN;

    row.(sprintf('T%s_cleaning_enabled',s)) = false;
    row.(sprintf('N_T%s_raw_valid',s)) = NaN;
    row.(sprintf('N_T%s_outliers',s)) = NaN;
    row.(sprintf('N_T%s_global_outliers',s)) = NaN;
    row.(sprintf('N_T%s_local_outliers',s)) = NaN;
    row.(sprintf('frac_T%s_outliers',s)) = NaN;
    row.(sprintf('T%s_clean_minus_raw_percent',s)) = NaN;

    row.(sprintf('Q%s_mean_Nm',s)) = NaN;
    row.(sprintf('Q%s_std_Nm',s)) = NaN;
    row.(sprintf('Q%s_abs_mean_Nm',s)) = NaN;
    row.(sprintf('Q%s_abs_std_Nm',s)) = NaN;

    row.(sprintf('Q%s_mean_Nm_raw',s)) = NaN;
    row.(sprintf('Q%s_std_Nm_raw',s)) = NaN;
    row.(sprintf('Q%s_abs_mean_Nm_raw',s)) = NaN;
    row.(sprintf('Q%s_abs_std_Nm_raw',s)) = NaN;

    row.(sprintf('Q%s_cleaning_enabled',s)) = false;
    row.(sprintf('N_Q%s_raw_valid',s)) = NaN;
    row.(sprintf('N_Q%s_outliers',s)) = NaN;
    row.(sprintf('N_Q%s_global_outliers',s)) = NaN;
    row.(sprintf('N_Q%s_local_outliers',s)) = NaN;
    row.(sprintf('frac_Q%s_outliers',s)) = NaN;
    row.(sprintf('Q%s_clean_minus_raw_percent',s)) = NaN;
    row.(sprintf('Q%s_abs_clean_minus_raw_percent',s)) = NaN;

    row.(sprintf('RPM%s_mean',s)) = NaN;
    row.(sprintf('RPM%s_std',s)) = NaN;
    row.(sprintf('RPM%s_used',s)) = NaN;
    row.(sprintf('RPM%s_used_source',s)) = "not_computed";
    row.(sprintf('RPM%s_bad_for_coeff',s)) = false;

    row.(sprintf('RPM%s_mean_raw',s)) = NaN;
    row.(sprintf('RPM%s_std_raw',s)) = NaN;

    row.(sprintf('RPM%s_cleaning_enabled',s)) = false;
    row.(sprintf('N_RPM%s_raw_valid',s)) = NaN;
    row.(sprintf('N_RPM%s_raw_positive',s)) = NaN;
    row.(sprintf('N_RPM%s_outliers',s)) = NaN;
    row.(sprintf('N_RPM%s_global_outliers',s)) = NaN;
    row.(sprintf('N_RPM%s_local_outliers',s)) = NaN;
    row.(sprintf('frac_RPM%s_outliers',s)) = NaN;
    row.(sprintf('RPM%s_clean_minus_raw_percent',s)) = NaN;
    row.(sprintf('N_RPM%s_nonpositive_after_cleaning',s)) = NaN;

    row.(sprintf('V%s_mean',s)) = NaN;
    row.(sprintf('V%s_std',s)) = NaN;
    row.(sprintf('A%s_mean',s)) = NaN;
    row.(sprintf('A%s_std',s)) = NaN;

    row.(sprintf('P%s_mean_W',s)) = NaN;

    row.(sprintf('Ct%s',s)) = NaN;
    row.(sprintf('Ct%s_std',s)) = NaN;
    row.(sprintf('Cq%s',s)) = NaN;
    row.(sprintf('Cq%s_std',s)) = NaN;

    row.(sprintf('Ct%s_raw_from_rawRPM',s)) = NaN;
    row.(sprintf('Cq%s_raw_from_rawRPM',s)) = NaN;

    row.(sprintf('Ct%s_clean_minus_raw_percent',s)) = NaN;
    row.(sprintf('Cq%s_clean_minus_raw_percent',s)) = NaN;

    row.(sprintf('N_T%s',s)) = NaN;
    row.(sprintf('N_Q%s',s)) = NaN;
    row.(sprintf('N_RPM%s',s)) = NaN;
    row.(sprintf('N_RPM%s_raw',s)) = NaN;
    row.(sprintf('N_V%s',s)) = NaN;
    row.(sprintf('N_A%s',s)) = NaN;

end

function plotSingleRampFile(t, data, col, nRotors, activeSRPowertrain, ...
                            alwaysComputeBothChannels, ...
                            tAvgStart, tAvgEnd, baseName, figpath, ...
                            cleaned_T, cleaned_Q, cleaned_RPM, ...
                            outlierOpts_T, outlierOpts_Q, outlierOpts_RPM)

    fig = figure('Color','w','Name',char(baseName));
    tiledlayout(3,1,'Padding','compact','TileSpacing','compact');

    idxWin = t >= tAvgStart & t <= tAvgEnd;

    showR1 = nRotors == 2 || activeSRPowertrain == 1 || alwaysComputeBothChannels;
    showR2 = nRotors == 2 || activeSRPowertrain == 2 || alwaysComputeBothChannels;

    % ============================================================
    % RPM
    % ============================================================

    nexttile;
    hold on; grid on; box on;

    if showR1
        RPM1 = getColumn(data,col.rpm1);
        plotRawCleanOutliers(t, RPM1, idxWin, cleaned_RPM, outlierOpts_RPM, ...
            [0.65 0.65 0.65], 'k', ...
            'RPM1 raw', 'RPM1 clean', 'RPM1 outliers');
    end

    if showR2
        RPM2 = getColumn(data,col.rpm2);
        plotRawCleanOutliers(t, RPM2, idxWin, cleaned_RPM, outlierOpts_RPM, ...
            [1.00 0.55 0.55], 'r', ...
            'RPM2 raw', 'RPM2 clean', 'RPM2 outliers');
    end

    xline(tAvgStart, '--b', 'HandleVisibility','off');
    xline(tAvgEnd, '--b', 'DisplayName','analysis window');

    ylabel('RPM');
    title(strrep(char(baseName),'_','\_'));
    legend('Location','best','Fontsize',10);

    % ============================================================
    % Thrust
    % ============================================================

    nexttile;
    hold on; grid on; box on;

    if showR1
        T1 = getColumn(data,col.T1);
        plotRawCleanOutliers(t, T1, idxWin, cleaned_T, outlierOpts_T, ...
            [0.65 0.65 0.65], 'k', ...
            'T1 raw', 'T1 clean', 'T1 outliers');
    end

    if showR2
        T2 = getColumn(data,col.T2);
        plotRawCleanOutliers(t, T2, idxWin, cleaned_T, outlierOpts_T, ...
            [1.00 0.55 0.55], 'r', ...
            'T2 raw', 'T2 clean', 'T2 outliers');
    end

    xline(tAvgStart, '--b', 'HandleVisibility','off');
    xline(tAvgEnd, '--b', 'HandleVisibility','off');

    ylabel('T [kgf]');
    legend('Location','best','Fontsize',10);

    % ============================================================
    % Torque
    % ============================================================

    nexttile;
    hold on; grid on; box on;

    if showR1
        Q1 = getColumn(data,col.Q1);
        plotRawCleanOutliers(t, Q1, idxWin, cleaned_Q, outlierOpts_Q, ...
            [0.65 0.65 0.65], 'k', ...
            'Q1 raw', 'Q1 clean', 'Q1 outliers');
    end

    if showR2
        Q2 = getColumn(data,col.Q2);
        plotRawCleanOutliers(t, Q2, idxWin, cleaned_Q, outlierOpts_Q, ...
            [1.00 0.55 0.55], 'r', ...
            'Q2 raw', 'Q2 clean', 'Q2 outliers');
    end

    xline(tAvgStart, '--b', 'HandleVisibility','off');
    xline(tAvgEnd, '--b', 'HandleVisibility','off');

    ylabel('Q [Nm]');
    xlabel('t [s]');
    legend('Location','best','Fontsize',10);

    outFile = fullfile(figpath, string(baseName) + "_singleRamp_check_cleaned.png");
    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotRawCleanOutliers(t, x, idxWin, doClean, opts, ...
                              rawColor, cleanColor, ...
                              rawLabel, cleanLabel, outlierLabel)

    t = t(:);
    x = x(:);
    idxWin = idxWin(:);

    idxRawValid = isfinite(t) & isfinite(x);

    plot(t(idxRawValid), x(idxRawValid), '-', ...
        'Color', rawColor, ...
        'LineWidth', 0.5, ...
        'Marker', 'none', ...
        'DisplayName', rawLabel);

    if ~doClean
        return;
    end

    t_win = t(idxWin);
    x_win = x(idxWin);

    if numel(x_win) < 10
        return;
    end

    [x_clean_win, out] = robustOutlierCleanNaN(t_win, x_win, opts);

    idxRawWinValid = isfinite(t_win) & isfinite(x_win);

    plot(t_win(idxRawWinValid), x_win(idxRawWinValid), '.', ...
        'Color', rawColor, ...
        'MarkerSize', 3, ...
        'HandleVisibility', 'off');

    idxCleanValid = isfinite(t_win) & isfinite(x_clean_win);

    plot(t_win(idxCleanValid), x_clean_win(idxCleanValid), '-', ...
        'Color', cleanColor, ...
        'LineWidth', 1.5, ...
        'Marker', 'none', ...
        'DisplayName', sprintf('%s | removed %.3g%%', ...
            cleanLabel, 100*out.frac_outliers));

    maskOut = out.mask_combined;

    if any(maskOut)
        plot(t_win(maskOut), x_win(maskOut), 'o', ...
            'MarkerSize', 5, ...
            'LineWidth', 1.2, ...
            'Color', cleanColor, ...
            'MarkerFaceColor', 'y', ...
            'DisplayName', sprintf('%s | N=%d', outlierLabel, out.N_outliers));
    end

end

function [x_used, out] = cleanSignalForStatsNaN(t, x, doClean, opts)

    if doClean
        [x_used, out] = robustOutlierCleanNaN(t, x, opts);
    else
        x_used = x(:);

        N = numel(x_used);
        mask_false = false(N,1);
        z_nan = nan(N,1);

        out = buildOutlierStruct(mask_false, mask_false, mask_false, ...
                                 z_nan, z_nan, z_nan, z_nan, ...
                                 isfinite(x_used));
    end

end

function [x_clean, out] = robustOutlierCleanNaN(t, x, opts)

    t = t(:);
    x = x(:);

    if numel(t) ~= numel(x)
        error('t and x must have the same number of samples.');
    end

    N = numel(x);

    opts = setOutlierDefault(opts, 'useGlobal', true);
    opts = setOutlierDefault(opts, 'useLocal', true);
    opts = setOutlierDefault(opts, 'globalThreshold', 8.0);
    opts = setOutlierDefault(opts, 'localThreshold', 6.0);
    opts = setOutlierDefault(opts, 'localWindow_s', 0.20);

    x_clean = x;

    mask_global = false(N,1);
    mask_local  = false(N,1);

    z_global = nan(N,1);
    z_local  = nan(N,1);

    local_median = nan(N,1);
    local_sigma  = nan(N,1);

    valid = isfinite(t) & isfinite(x);

    if nnz(valid) < 10

        mask_combined = false(N,1);

        out = buildOutlierStruct(mask_global, mask_local, mask_combined, ...
                                 z_global, z_local, local_median, local_sigma, valid);
        return;

    end

    % Global robust detector
    if opts.useGlobal

        x_med = median(x(valid), 'omitnan');
        x_mad = median(abs(x(valid) - x_med), 'omitnan');

        sigma_global = 1.4826 * x_mad;

        if isfinite(sigma_global) && sigma_global > 0

            z_global(valid) = abs(x(valid) - x_med) ./ sigma_global;
            mask_global = z_global > opts.globalThreshold;

        end

    end

    % Local robust detector
    if opts.useLocal

        t_valid = t(valid);
        dt = median(diff(t_valid), 'omitnan');
        fs = 1/dt;

        if isfinite(fs) && fs > 0

            localWindow_samples = round(opts.localWindow_s * fs);

            if localWindow_samples < 3
                localWindow_samples = 3;
            end

            if mod(localWindow_samples, 2) == 0
                localWindow_samples = localWindow_samples + 1;
            end

            local_median = movmedian(x, localWindow_samples, 'omitnan');

            abs_dev = abs(x - local_median);
            local_mad = movmedian(abs_dev, localWindow_samples, 'omitnan');

            local_sigma = 1.4826 * local_mad;

            validLocal = valid & isfinite(local_sigma) & local_sigma > 0;

            z_local(validLocal) = ...
                abs(x(validLocal) - local_median(validLocal)) ./ local_sigma(validLocal);

            mask_local = z_local > opts.localThreshold;

        end

    end

    mask_combined = mask_global | mask_local;

    % NaN/Inf originali non sono contati come outlier.
    mask_combined(~valid) = false;

    % Outlier -> NaN
    x_clean(mask_combined) = NaN;

    out = buildOutlierStruct(mask_global, mask_local, mask_combined, ...
                             z_global, z_local, local_median, local_sigma, valid);

end

function out = buildOutlierStruct(mask_global, mask_local, mask_combined, ...
                                  z_global, z_local, local_median, local_sigma, valid)

    N_valid = nnz(valid);

    out.mask_global = mask_global;
    out.mask_local = mask_local;
    out.mask_combined = mask_combined;

    out.z_global = z_global;
    out.z_local = z_local;

    out.local_median = local_median;
    out.local_sigma = local_sigma;

    out.N_outliers = sum(mask_combined);
    out.N_global = sum(mask_global);
    out.N_local = sum(mask_local);

    if N_valid > 0
        out.frac_outliers = out.N_outliers / N_valid;
        out.frac_global = out.N_global / N_valid;
        out.frac_local = out.N_local / N_valid;
    else
        out.frac_outliers = NaN;
        out.frac_global = NaN;
        out.frac_local = NaN;
    end

end

function opts = setOutlierDefault(opts, fieldName, defaultValue)

    if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
        opts.(fieldName) = defaultValue;
    end

end