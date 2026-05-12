% CODICE  POST PROCESSING COSTRUZIONE DATABASE PER PROVE A RAMPA
% SR/DR
% Fornisce in output le grandezze medie in ciascun plateau di RPM

clear; close all; clc;

%% Input

svflg = true;

inpath  = 'E:\APC_Prove\20x13\06_05_26\';
outpath = 'E:\APC_Prove\20x13\Analisi\database_06_05_26\';

if ~exist(outpath, 'dir')
    mkdir(outpath);
end

MP_numbers = [245 246];

MP = "MP_" + string(MP_numbers(:));   % colonna, non riga

fileList = [
    dir(fullfile(inpath,'APC_20x13EP_SR_4500to1000.csv'))
    dir(fullfile(inpath,'APC_20x13EP_SR_1000to4500.csv'))
    % dir(fullfile(inpath,'APC_16x10DR_4900to1000_sR20.csv'))
    % dir(fullfile(inpath,'APC_16x10DR_1000to4900_sR20.csv'))
];

if numel(MP) ~= numel(fileList)
error('Number of MP labels (%d) must match number of input files (%d).', ...
    numel(MP), numel(fileList));
end

% Valido solo per prove SR.
% 1 = usa Powertrain 1
% 2 = usa Powertrain 2
SR_powertrain_default = 1;

rho = 1.225;        % [kg/m^3]

D = 16*0.0254;      % [m] 

kgf2N = 9.80665;

%% RPM scelta per coefficienti

% "measured"    : usa sempre RPM medio misurato, se disponibile
% "target"      : usa sempre RPM target
% "targetIfBad" : usa RPM target solo se RPM medio è assente o troppo lontano dal target
% "manual"      : usa RPM target solo nei plateau indicati manualmente
rpmCoeffPolicy = "targetIfBad";

% Soglia per decidere se un RPM misurato è sballato nel caso "targetIfBad"
rpmBadTolAbs = 100;     % [rpm]
rpmBadTolRel = 0.05;    % 5%

% Plateau nei quali forzare RPM_target per il calcolo di Ct e Cq.
% Valido se rpmCoeffPolicy = "manual".
forceTargetRPM_plateaus = containers.Map();

forceTargetRPM_plateaus('APC_16x10EP_SR_1000to4900.csv') = [1];
forceTargetRPM_plateaus('APC_16x10E_SR_4900to1000.csv') = [9];

% Esempio:
% [3 7] significa:
% nel plateau 3 e nel plateau 7 calcola Ct/Cq usando RPM_target,
% anche se RPM_mean è presente.
%% Plateau ricerca

plateauDuration = 60;      % [s]
plateauTol      = 5;       % [s], tolleranza sul riconoscimento plateau

settleTime      = 0;      % [s], tempo scartato all'inizio plateau
avgDuration     = plateauDuration - settleTime;      % [s], durata finestra di media

rpmTargetsUp = [1000 1500 2000 2500 3000 3500 4000 4500];

rpmMin = min(rpmTargetsUp);
rpmMax = max(rpmTargetsUp);

useAbsTorqueForCoeff = true;
useAbsTorqueForPower = true;

makePlots = true;

%% indici colonne utili

col.t = 1;

% Powertrain 1
col.pwm1 = 2;
col.T1   = 3;
col.Q1   = 4;
col.rpm1 = 7;

% Powertrain 2
col.pwm2 = 15;
col.T2   = 16;
col.Q2   = 17;
col.rpm2 = 20;

%% ================= MAIN LOOP ================================

for ifile = 1:numel(fileList)

    filename = fileList(ifile).name;
    filepath = fullfile(fileList(ifile).folder, filename);

    fprintf('\nProcessing: %s\n', filename);

    d = importdata(filepath);
    data = d.data;

    t = data(:,col.t);

    meta = parseTestMetadata(filename, rpmMin, rpmMax);

    if meta.rpmStart > meta.rpmEnd
        rpmTargets = fliplr(rpmTargetsUp);
    else
        rpmTargets = rpmTargetsUp;
    end

    if strcmp(meta.conf, "DR")
        nRotors = 2;
        activeSRPowertrain = NaN;
    else
        nRotors = 1;
    
        if exist('SR_powertrain_map','var') && isKey(SR_powertrain_map, filename)
            activeSRPowertrain = SR_powertrain_map(filename);
        else
            activeSRPowertrain = SR_powertrain_default;
        end
    
        if activeSRPowertrain ~= 1 && activeSRPowertrain ~= 2
            error('For SR tests, activeSRPowertrain must be either 1 or 2.');
        end
    end

    %% Individuo i plateau basandomi su pwm

    if nRotors == 2
        pwmRef = data(:,col.pwm1);
    else
        if activeSRPowertrain == 1
            pwmRef = data(:,col.pwm1);
        else
            pwmRef = data(:,col.pwm2);
        end
    end

    plateaus = findPlateausFromThrottle( ...
        t, pwmRef, plateauDuration, plateauTol);

    nPlateaus = numel(plateaus);

    fprintf('Detected %d plateaus from throttle command.\n', nPlateaus);

    if nPlateaus ~= numel(rpmTargets)
        warning('Detected plateaus = %d, expected RPM targets = %d.', ...
            nPlateaus, numel(rpmTargets));
    end

    resultTable = table();

    for k = 1:nPlateaus

        tPlateauStart = plateaus(k).t_start;
        tPlateauEnd   = plateaus(k).t_end;

        tAvgStart = tPlateauStart + settleTime;
        tAvgEnd   = tAvgStart + avgDuration;

        if tAvgEnd > tPlateauEnd
            tAvgEnd = tPlateauEnd;
        end

        idx = t >= tAvgStart & t <= tAvgEnd;

        if k <= numel(rpmTargets)
            rpmTarget = rpmTargets(k);
        else
            rpmTarget = NaN;
        end

        forceTargetRPMThisPlateau = false;

        if exist('forceTargetRPM_plateaus','var') && isKey(forceTargetRPM_plateaus, filename)
            badPlateaus = forceTargetRPM_plateaus(filename);
            forceTargetRPMThisPlateau = any(badPlateaus == k);
        end

        row = struct();

        row.filename = string(filename);
        row.conf     = string(meta.conf);
        row.mode     = string(meta.mode);
        row.direction = string(meta.direction);

        row.activeSRPowertrain = activeSRPowertrain;

        row.plateau_id = k;
        row.RPM_target = rpmTarget;

        row.t_plateau_start_s = tPlateauStart;
        row.t_plateau_end_s   = tPlateauEnd;
        row.t_avg_start_s     = tAvgStart;
        row.t_avg_end_s       = tAvgEnd;

       if nRotors == 2

            row.PWM1_set_us = plateaus(k).pwm_set;
            row.PWM2_set_us = lastValidBefore(t, data(:,col.pwm2), tPlateauStart + 1);
        
        elseif activeSRPowertrain == 1
        
            row.PWM1_set_us = plateaus(k).pwm_set;
            row.PWM2_set_us = NaN;
        
        elseif activeSRPowertrain == 2
        
            row.PWM1_set_us = NaN;
            row.PWM2_set_us = plateaus(k).pwm_set;
        
        end

        %% Rotor 1 and Rotor 2

        computeRotor1 = false;
        computeRotor2 = false;
        
        if nRotors == 2
            computeRotor1 = true;
            computeRotor2 = true;
        else
            if activeSRPowertrain == 1
                computeRotor1 = true;
            elseif activeSRPowertrain == 2
                computeRotor2 = true;
            end
        end
        
        %% Rotor 1
        
        if computeRotor1
        
            R1 = rotorStats( ...
                data, idx, col.T1, col.Q1, col.rpm1, ...
                rpmTarget, NaN, rho, D, kgf2N, ...
                useAbsTorqueForCoeff, useAbsTorqueForPower, ...
                rpmCoeffPolicy, forceTargetRPMThisPlateau, ...
                rpmBadTolAbs, rpmBadTolRel);
        
            row = writeRotorToRow(row, R1, 1);
        
        else
        
            row = writeRotorNaN(row, 1);
            R1.RPM_used = NaN;
        
        end
        
        %% Rotor 2
        
        if computeRotor2
        
            if nRotors == 2
                rpmFallback = R1.RPM_used;
            else
                rpmFallback = NaN;
            end
        
           R2 = rotorStats( ...
                data, idx, col.T2, col.Q2, col.rpm2, ...
                rpmTarget, rpmFallback, rho, D, kgf2N, ...
                useAbsTorqueForCoeff, useAbsTorqueForPower, ...
                rpmCoeffPolicy, forceTargetRPMThisPlateau, ...
                rpmBadTolAbs, rpmBadTolRel);
        
            row = writeRotorToRow(row, R2, 2);
        
        else
        
            row = writeRotorNaN(row, 2);
        
        end
        %% Combined values

        row.T_total_N = nansum([row.T1_mean_N, row.T2_mean_N]);
        row.P_total_W = nansum([row.P1_mean_W, row.P2_mean_W]);

        row.Ct_mean_rotors = mean([row.Ct1, row.Ct2], 'omitnan');
        row.Cq_mean_rotors = mean([row.Cq1, row.Cq2], 'omitnan');

        resultTable = [resultTable; struct2table(row)];

        if nRotors == 1
            if activeSRPowertrain == 1
                rpmMeanPrint = row.RPM1_mean;
                pwmPrint     = row.PWM1_set_us;
            else
                rpmMeanPrint = row.RPM2_mean;
                pwmPrint     = row.PWM2_set_us;
            end
        
            fprintf('  Plateau %d | SR PT%d | RPM target %.0f | PWM %.0f | %.2f-%.2f s | RPM %.1f\n', ...
                k, activeSRPowertrain, rpmTarget, pwmPrint, tAvgStart, tAvgEnd, rpmMeanPrint);
        
        else
        
            fprintf('  Plateau %d | DR | RPM target %.0f | PWM1 %.0f | PWM2 %.0f | %.2f-%.2f s | RPM1 %.1f | RPM2 %.1f\n', ...
                k, rpmTarget, row.PWM1_set_us, row.PWM2_set_us, ...
                tAvgStart, tAvgEnd, row.RPM1_mean, row.RPM2_mean);
        
        end

    end

    %% Save output

   [~,baseName,~] = fileparts(filename);

    outMP = MP(ifile);
    
    if svflg
        outCSV = fullfile(outpath, outMP + "_database.csv");
        outMAT = fullfile(outpath, outMP + "_database.mat");
    
        writetable(resultTable, outCSV);
        save(outMAT, "resultTable");
    end


    %% Plots

    if makePlots

        figure('Color','w','Name',baseName);
        tiledlayout(3,1,'Padding','compact','TileSpacing','compact');

        nexttile;
        hold on; grid on; box on;
        if nRotors == 2
            plot(t, data(:,col.rpm1), '.k', 'MarkerSize', 3);
            plot(t, data(:,col.rpm2), '.r', 'MarkerSize', 3);
        else
            if activeSRPowertrain == 1
                plot(t, data(:,col.rpm1), '.k', 'MarkerSize', 3);
            else
                plot(t, data(:,col.rpm2), '.r', 'MarkerSize', 3);
            end
        end
        for k = 1:nPlateaus
            xline(resultTable.t_avg_start_s(k), '--b');
            xline(resultTable.t_avg_end_s(k), '--b');
        end
        xlabel('t [s]');
        ylabel('RPM');
        title(strrep(baseName,'_','\_'));

        if nRotors == 2
            legend('Rotor 1','Rotor 2','Averaging window','Location','best');
        else
            if activeSRPowertrain == 1
                legend('Rotor 1','Averaging window','Location','best');
            else
                legend('Rotor 2','Averaging window','Location','best');
            end
        end

        nexttile;
        hold on; grid on; box on;
        if nRotors == 2
            plot(t, data(:,col.T1), '.k', 'MarkerSize', 3);
            plot(t, data(:,col.T2), '.r', 'MarkerSize', 3);
        else
            if activeSRPowertrain == 1
                plot(t, data(:,col.T1), '.k', 'MarkerSize', 3);
            else
                plot(t, data(:,col.T2), '.r', 'MarkerSize', 3);
            end
        end
        ylabel('T [kgf]');
        xlabel('t [s]');

        nexttile;
        hold on; grid on; box on;
        if nRotors == 2
            plot(t, data(:,col.Q1), '.k', 'MarkerSize', 3);
            plot(t, data(:,col.Q2), '.r', 'MarkerSize', 3);
        else
            if activeSRPowertrain == 1
                plot(t, data(:,col.Q1), '.k', 'MarkerSize', 3);
            else
                plot(t, data(:,col.Q2), '.r', 'MarkerSize', 3);
            end
        end
        ylabel('Q [Nm]');
        xlabel('t [s]');

    end

end


disp('Done.');

%% ============================================================
%  LOCAL FUNCTIONS
% =============================================================

function meta = parseTestMetadata(filename, rpmMin, rpmMax)

    fname = upper(filename);

    % Configuration: SR / DR
    if contains(fname, 'DR')
        meta.conf = "DR";
    elseif contains(fname, 'SR')
        meta.conf = "SR";
    else
        meta.conf = "UNKNOWN";
    end

    % Single rotor mode: E / EP
    if contains(fname, 'EP')
        meta.mode = "EP";
    elseif contains(fname, 'E')
        meta.mode = "E";
    else
        meta.mode = "";
    end

    % Direction: rpmMin to rpmMax oppure rpmMax to rpmMin
    strUp   = sprintf('%dTO%d', rpmMin, rpmMax);
    strDown = sprintf('%dTO%d', rpmMax, rpmMin);

    if contains(fname, strUp)
        meta.direction = sprintf('%dto%d', rpmMin, rpmMax);
        meta.rpmStart  = rpmMin;
        meta.rpmEnd    = rpmMax;

    elseif contains(fname, strDown)
        meta.direction = sprintf('%dto%d', rpmMax, rpmMin);
        meta.rpmStart  = rpmMax;
        meta.rpmEnd    = rpmMin;

    else
        meta.direction = "unknown";
        meta.rpmStart  = NaN;
        meta.rpmEnd    = NaN;
    end

end

function plateaus = findPlateausFromThrottle(t, pwm, plateauDuration, plateauTol)

    idxCmd = find(~isnan(pwm));

    tCmd   = t(idxCmd);
    pwmCmd = pwm(idxCmd);

    dtCmd = diff(tCmd);

    isPlateauGap = dtCmd >= (plateauDuration - plateauTol) & ...
                   dtCmd <= (plateauDuration + plateauTol);

    gapIdx = find(isPlateauGap);

    plateaus = struct('t_start',{},'t_end',{},'pwm_set',{});

    for i = 1:numel(gapIdx)

        j = gapIdx(i);

        plateaus(i).t_start = tCmd(j);
        plateaus(i).t_end   = tCmd(j+1);
        plateaus(i).pwm_set = pwmCmd(j);

    end

end

function value = lastValidBefore(t, x, t0)

    idx = find(~isnan(x) & t <= t0, 1, 'last');

    if isempty(idx)
        value = NaN;
    else
        value = x(idx);
    end

end

function R = rotorStats(data, idx, colT, colQ, colRPM, rpmTarget, rpmFallback, ...
                        rho, D, kgf2N, useAbsTorqueForCoeff, useAbsTorqueForPower, ...
                        rpmForCoeffMode, forceTargetRPMThisPlateau, ...
                        rpmBadTolAbs, rpmBadTolRel)

    if nargin < 13 || isempty(rpmForCoeffMode)
        rpmForCoeffMode = "measured";
    end

    if nargin < 14 || isempty(forceTargetRPMThisPlateau)
        forceTargetRPMThisPlateau = false;
    end

    if nargin < 15 || isempty(rpmBadTolAbs)
        rpmBadTolAbs = 150;
    end

    if nargin < 16 || isempty(rpmBadTolRel)
        rpmBadTolRel = 0.05;
    end

    T_kgf_raw = data(idx,colT);
    Q_raw     = data(idx,colQ);
    RPM_raw   = data(idx,colRPM);

    T_kgf = T_kgf_raw(~isnan(T_kgf_raw));
    Q     = Q_raw(~isnan(Q_raw));

    R.N_T = numel(T_kgf);
    R.N_Q = numel(Q);

    R.T_mean_kgf = mean(T_kgf, 'omitnan');
    R.T_std_kgf  = std(T_kgf,  'omitnan');

    R.T_mean_N = R.T_mean_kgf * kgf2N;
    R.T_std_N  = R.T_std_kgf  * kgf2N;

    R.Q_mean_Nm = mean(Q, 'omitnan');
    R.Q_std_Nm  = std(Q,  'omitnan');

    R.Q_abs_mean_Nm = mean(abs(Q), 'omitnan');

    % RPM misurato nel plateau

    RPM_valid = RPM_raw(~isnan(RPM_raw));

    if ~isnan(rpmTarget)

        % Soglia larga: serve solo a buttare fuori valori chiaramente non fisici.
        rpmTolStats = max(250, 0.20*rpmTarget);

        RPM_valid = RPM_valid( ...
            RPM_valid > 0 & ...
            abs(RPM_valid - rpmTarget) <= rpmTolStats);

    else

        RPM_valid = RPM_valid(RPM_valid > 0);

    end

    R.N_RPM = numel(RPM_valid);

    if R.N_RPM > 0
        R.RPM_mean = mean(RPM_valid, 'omitnan');
        R.RPM_std  = std(RPM_valid,  'omitnan');
    else
        R.RPM_mean = NaN;
        R.RPM_std  = NaN;
    end

    % Decido RPM da usare per Ct, Cq e P

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

    rpmForCoeffMode = string(rpmForCoeffMode);

    R.RPM_used = NaN;
    R.RPM_used_source = "";

    if forceTargetRPMThisPlateau && hasTarget

        R.RPM_used = rpmTarget;
        R.RPM_used_source = "target_manual";

    else

        switch rpmForCoeffMode

            case "measured"

                if hasMeasured
                    R.RPM_used = R.RPM_mean;
                    R.RPM_used_source = "measured";
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
                    R.RPM_used_source = "target_global";
                elseif hasMeasured
                    R.RPM_used = R.RPM_mean;
                    R.RPM_used_source = "measured";
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
                    R.RPM_used_source = "measured";
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

            case "manual"

                if hasMeasured
                    R.RPM_used = R.RPM_mean;
                    R.RPM_used_source = "measured";
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

                error('Unknown rpmForCoeffMode: %s', rpmForCoeffMode);

        end

    end

    if isnan(R.RPM_used) || R.RPM_used <= 0

        R.P_mean_W = NaN;
        R.Ct       = NaN;
        R.Ct_std   = NaN;
        R.Cq       = NaN;
        R.Cq_std   = NaN;
        return;

    end

    n = R.RPM_used/60;     % [rev/s]

    % Potenza

    if useAbsTorqueForPower
        Q_power = mean(abs(Q), 'omitnan');
    else
        Q_power = mean(Q, 'omitnan');
    end

    R.P_mean_W = 2*pi*n*Q_power;

    % Coefficienti

    if useAbsTorqueForCoeff
        Q_coeff = abs(Q);
    else
        Q_coeff = Q;
    end

    R.Ct     = R.T_mean_N / (rho*n^2*D^4);
    R.Ct_std = R.T_std_N  / (rho*n^2*D^4);

    R.Cq     = mean(Q_coeff, 'omitnan') / (rho*n^2*D^5);
    R.Cq_std = std(Q_coeff,  'omitnan') / (rho*n^2*D^5);

end
function row = writeRotorToRow(row, R, rotorID)

    s = num2str(rotorID);

    row.(sprintf('T%s_mean_kgf',s)) = R.T_mean_kgf;
    row.(sprintf('T%s_std_kgf',s))  = R.T_std_kgf;
    row.(sprintf('T%s_mean_N',s))   = R.T_mean_N;
    row.(sprintf('T%s_std_N',s))    = R.T_std_N;

    row.(sprintf('Q%s_mean_Nm',s))     = R.Q_mean_Nm;
    row.(sprintf('Q%s_std_Nm',s))      = R.Q_std_Nm;
    row.(sprintf('Q%s_abs_mean_Nm',s)) = R.Q_abs_mean_Nm;

    row.(sprintf('RPM%s_mean',s)) = R.RPM_mean;
    row.(sprintf('RPM%s_std',s))  = R.RPM_std;
    row.(sprintf('RPM%s_used',s)) = R.RPM_used;
    row.(sprintf('RPM%s_used_source',s)) = string(R.RPM_used_source);
    row.(sprintf('RPM%s_bad_for_coeff',s)) = R.RPM_bad_for_coeff;

    row.(sprintf('P%s_mean_W',s)) = R.P_mean_W;

    row.(sprintf('Ct%s',s))     = R.Ct;
    row.(sprintf('Ct%s_std',s)) = R.Ct_std;
    row.(sprintf('Cq%s',s))     = R.Cq;
    row.(sprintf('Cq%s_std',s)) = R.Cq_std;

    row.(sprintf('N_T%s',s))   = R.N_T;
    row.(sprintf('N_Q%s',s))   = R.N_Q;
    row.(sprintf('N_RPM%s',s)) = R.N_RPM;

end

function row = writeRotorNaN(row, rotorID)

    s = num2str(rotorID);

    row.(sprintf('T%s_mean_kgf',s)) = NaN;
    row.(sprintf('T%s_std_kgf',s))  = NaN;
    row.(sprintf('T%s_mean_N',s))   = NaN;
    row.(sprintf('T%s_std_N',s))    = NaN;

    row.(sprintf('Q%s_mean_Nm',s))     = NaN;
    row.(sprintf('Q%s_std_Nm',s))      = NaN;
    row.(sprintf('Q%s_abs_mean_Nm',s)) = NaN;

    row.(sprintf('RPM%s_mean',s)) = NaN;
    row.(sprintf('RPM%s_std',s))  = NaN;
    row.(sprintf('RPM%s_used',s)) = NaN;
    row.(sprintf('RPM%s_used_source',s)) = "";
    row.(sprintf('RPM%s_bad_for_coeff',s)) = false;

    row.(sprintf('P%s_mean_W',s)) = NaN;

    row.(sprintf('Ct%s',s))     = NaN;
    row.(sprintf('Ct%s_std',s)) = NaN;
    row.(sprintf('Cq%s',s))     = NaN;
    row.(sprintf('Cq%s_std',s)) = NaN;

    row.(sprintf('N_T%s',s))   = NaN;
    row.(sprintf('N_Q%s',s))   = NaN;
    row.(sprintf('N_RPM%s',s)) = NaN;

end