% ============================================================
% ANALISI DATABASE SR/DR SINGLE-RAMP
% Coerente con database_builder_singleRamp con outlier detection
% ============================================================
%
% Input:
%   - MP_xxx_database.csv generati dal builder single-ramp
%   oppure
%   - database_RRI2_singleRamp_SR_DR_allMP.csv
%
% Obiettivo:
%   1) Leggere SR e DR
%   2) Estrarre Ct, Cq, T, Q e RPM_used
%   3) Confrontare SR e DR a pari RPM effettivo
%   4) Fare confronto:
%        - PW1: SR powertrain 1 vs DR rotor 1
%        - PW2: SR powertrain 2 vs DR rotor 2
%        - MEAN: media SR vs media DR
%
% Convenzione:
%   Delta Ct [%] = 100*(Ct_SR - Ct_DR)/Ct_SR
%
% Quindi:
%   > 0  -> DR perde Ct rispetto a SR
%   < 0  -> DR guadagna Ct rispetto a SR
%
% Nota importante:
%   Il confronto a pari RPM usa:
%
%       RPM_common = 0.5*(RPM_SR_used_nominale + RPM_DR_used_nominale)
%
%   Poi interpola sia SR sia DR a RPM_common.
% ============================================================

clear; close all; clc;

%% ===================== INPUT =================================

D   = 20*0.0254;      % [m]
T_C = 23.2;           % [degC]

basepath = 'E:\APC_Prove\20x13\Analisi\database_29_04_26\';

outpath = fullfile(basepath, 'Confronto_SR_DR_singleRamp_exactRPM');

if ~exist(outpath, 'dir')
    mkdir(outpath);
end

figpath = fullfile(outpath, 'Figures');

if ~exist(figpath, 'dir')
    mkdir(figpath);
end

% ============================================================
% Lettura database
%
% false -> legge tanti file MP_xxx_database.csv
% true  -> legge un unico database_RRI2_singleRamp_SR_DR_allMP.csv
% ============================================================

useAllMPFile = false;
allMPFilename = 'database_RRI2_singleRamp_SR_DR_allMP.csv';

% ============================================================
% Definizione casi
%
% EP_SR -> powertrain 1
% E_SR  -> powertrain 2
% DR    -> double rotor
% ============================================================

cases = table();

MP_EP_SR = [
    172 173 174 175 176 177 178 179
];

MP_E_SR = [
    164 165 166 167 168 169 170 171
];

MP_DR = [
    180 181 182 183 184 185 186 187 ...
    188 189 190 191 192 193 194 195 ...
    196 197 198 199 200 201 202 203 ...
    204 205 206 207 208 209 210 211 ...
];

DR_sR_values = [2 5 10 20];

nRPM_DR = numel(MP_DR) / numel(DR_sR_values);

if mod(numel(MP_DR), numel(DR_sR_values)) ~= 0
    error('MP_DR must contain the same number of RPM points for each s/R.');
end

cases.MP_number = [
    MP_EP_SR(:)
    MP_E_SR(:)
    MP_DR(:)
];

cases.condition = [
    repmat("EP_SR", numel(MP_EP_SR), 1)
    repmat("E_SR",  numel(MP_E_SR),  1)
    repmat("DR",    numel(MP_DR),    1)
];

cases.activeSRPowertrain = [
    ones(numel(MP_EP_SR), 1)
    2*ones(numel(MP_E_SR), 1)
    NaN(numel(MP_DR), 1)
];

cases.s_over_R = [
    NaN(numel(MP_EP_SR), 1)
    NaN(numel(MP_E_SR),  1)
    repelem(DR_sR_values(:), nRPM_DR)
];

cases = cases(~isnan(cases.MP_number), :);

%% ===================== SETTINGS ==============================

srPW1Condition = "EP_SR";
srPW2Condition = "E_SR";

interpMethod = 'linear';

rho = 1.225;          % [kg/m^3]
R   = D/2;            % [m]

Tair = T_C + 273.15;  % [K]

mu0 = 1.716e-5;       % [Pa s]
T0  = 273.15;         % [K]
S   = 110.4;          % [K]

mu = mu0 * (Tair/T0)^(3/2) * (T0 + S)/(Tair + S);
nu = mu/rho;

%% ===================== LOAD DATABASE =========================

DB_all = loadSelectedSingleRampDatabase( ...
    basepath, cases, useAllMPFile, allMPFilename);

DB_SR = DB_all(DB_all.ConditionName ~= "DR", :);
DB_DR = DB_all(DB_all.ConditionName == "DR", :);

fprintf('\nLoaded database rows:\n');
fprintf('  total : %d\n', height(DB_all));
fprintf('  SR    : %d\n', height(DB_SR));
fprintf('  DR    : %d\n', height(DB_DR));

disp(groupsummary(DB_all, "ConditionName"));

%% ===================== EXTRACT DATA ===========================

SR_raw = extractSingleRotorData(DB_SR);
DR_raw = extractDoubleRotorData(DB_DR);

SR_byCond = aggregateByKeys(SR_raw, {'condition','RPM_target'});
DR_byRotor = aggregateByKeys(DR_raw, {'s_over_R','rotorID','RPM_target'});

%% ===================== BUILD CURVES ===========================

SR_PW1_curve = buildSRCurve(SR_byCond, srPW1Condition);
SR_PW2_curve = buildSRCurve(SR_byCond, srPW2Condition);
SR_mean_curve = buildMeanSRCurve(SR_byCond, srPW1Condition, srPW2Condition);

DR_curves = table();

sR_values = unique(DR_byRotor.s_over_R);
sR_values = sR_values(~isnan(sR_values));
sR_values = sort(sR_values);

for isr = 1:numel(sR_values)

    sR = sR_values(isr);

    DR_R1_curve   = buildDRRotorCurve(DR_byRotor, sR, 1);
    DR_R2_curve   = buildDRRotorCurve(DR_byRotor, sR, 2);
    DR_mean_curve = buildMeanDRCurve(DR_byRotor, sR);

    DR_R1_curve   = addDRCurveMetadata(DR_R1_curve,   sR, 1,   "DR_R1");
    DR_R2_curve   = addDRCurveMetadata(DR_R2_curve,   sR, 2,   "DR_R2");
    DR_mean_curve = addDRCurveMetadata(DR_mean_curve, sR, NaN, "DR_MEAN");

    DR_curves = appendTable(DR_curves, DR_R1_curve);
    DR_curves = appendTable(DR_curves, DR_R2_curve);
    DR_curves = appendTable(DR_curves, DR_mean_curve);

end

%% ===================== EXACT RPM COMPARISON ==================

comparison_exact = buildExactRPMComparison( ...
    SR_byCond, DR_byRotor, sR_values, ...
    srPW1Condition, srPW2Condition, ...
    interpMethod, R, nu);

fprintf('\nExact-RPM comparison rows: %d\n', height(comparison_exact));

%% ===================== SAVE TABLES ============================

writetable(cases, fullfile(outpath, 'input_cases_singleRamp.csv'));

writetable(DB_all, fullfile(outpath, 'DB_all_singleRamp.csv'));
writetable(SR_raw, fullfile(outpath, 'SR_raw_singleRamp.csv'));
writetable(DR_raw, fullfile(outpath, 'DR_raw_singleRamp.csv'));

writetable(SR_byCond, fullfile(outpath, 'SR_byCondition_singleRamp.csv'));
writetable(DR_byRotor, fullfile(outpath, 'DR_byRotor_singleRamp.csv'));

writetable(SR_PW1_curve, fullfile(outpath, 'SR_PW1_curve.csv'));
writetable(SR_PW2_curve, fullfile(outpath, 'SR_PW2_curve.csv'));
writetable(SR_mean_curve, fullfile(outpath, 'SR_mean_curve.csv'));
writetable(DR_curves, fullfile(outpath, 'DR_curves.csv'));

writetable(comparison_exact, ...
    fullfile(outpath, 'comparison_SR_DR_exactRPM_singleRamp.csv'));

save(fullfile(outpath, 'analysis_SR_DR_exactRPM_singleRamp.mat'), ...
    'cases', 'DB_all', ...
    'SR_raw', 'DR_raw', ...
    'SR_byCond', 'DR_byRotor', ...
    'SR_PW1_curve', 'SR_PW2_curve', 'SR_mean_curve', ...
    'DR_curves', 'comparison_exact', ...
    'rho', 'D', 'R', 'T_C', 'Tair', 'mu', 'nu', ...
    'sR_values', 'interpMethod');

fprintf('\nSaved output tables in:\n%s\n', outpath);

%% ===================== PLOTS ==================================

plotCtVsRPMusedPowertrains( ...
    SR_PW1_curve, SR_PW2_curve, DR_curves, sR_values, ...
    fullfile(figpath, '01_Ct_vs_RPMused_single_powertrains.png'));

plotCtVsRPMusedMean( ...
    SR_mean_curve, DR_curves, sR_values, ...
    fullfile(figpath, '02_Ct_vs_RPMused_mean_case.png'));

plotCtExactComparison( ...
    comparison_exact, ...
    fullfile(figpath, '03_Ct_SR_DR_exactRPM.png'));

plotDeltaExactVsRPM( ...
    comparison_exact, ...
    fullfile(figpath, '04_DeltaCt_exactRPM_vs_RPM.png'));

plotDeltaExactVsSR( ...
    comparison_exact, ...
    fullfile(figpath, '05_DeltaCt_exactRPM_vs_sR.png'));

plotDeltaExactVsRPMSelectedType( ...
    comparison_exact, "PW1", ...
    fullfile(figpath, '06_DeltaCt_exactRPM_PW1_vs_RPM.png'));

plotDeltaExactVsRPMSelectedType( ...
    comparison_exact, "PW2", ...
    fullfile(figpath, '07_DeltaCt_exactRPM_PW2_vs_RPM.png'));

plotDeltaExactVsRPMSelectedType( ...
    comparison_exact, "MEAN", ...
    fullfile(figpath, '08_DeltaCt_exactRPM_MEAN_vs_RPM.png'));

% Reynolds number
figRe = figure('Color','w','Name','Reynolds vs RPM');
hold on; grid on; box on;

rpmGrid = unique(comparison_exact.RPM_common);
rpmGrid = sort(rpmGrid(isfinite(rpmGrid)));

Omega = 2*pi*rpmGrid/60;
Re_R = Omega * R^2 / nu;

plot(rpmGrid, Re_R, '-o', ...
    'LineWidth', 1.6, ...
    'DisplayName','$Re_R = \Omega R^2/\nu$');

xlabel('$RPM_{common}$', 'Interpreter','latex');
ylabel('$Re_R$', 'Interpreter','latex');
title('Reynolds number at comparison RPM', 'Interpreter','latex');
legend('Location','best', 'Interpreter','latex');

exportgraphics(figRe, fullfile(figpath, '09_Reynolds_vs_RPMcommon.png'), 'Resolution', 300);

disp('Exact-RPM single-ramp SR/DR analysis completed.');

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function DB = loadSelectedSingleRampDatabase(basepath, cases, useAllMPFile, allMPFilename)

    if ~exist(basepath, 'dir')
        error('Folder not found: %s', basepath);
    end

    cases.condition = string(cases.condition);

    if useAllMPFile

        fpath = fullfile(basepath, allMPFilename);

        if ~isfile(fpath)
            error('All-MP database file not found: %s', fpath);
        end

        T_all = readDatabaseCSV(fpath);
        DB = table();

        for i = 1:height(cases)

            mp = cases.MP_number(i);

            if ~ismember('MP_number', T_all.Properties.VariableNames)
                error('The all-MP database does not contain MP_number.');
            end

            idx = T_all.MP_number == mp;

            if ~any(idx)
                error('MP %d not found inside %s.', mp, fpath);
            end

            T = T_all(idx, :);
            T = applyCaseMetadata(T, cases(i,:), string(allMPFilename));

            DB = appendTable(DB, T);

        end

    else

        DB = table();

        for i = 1:height(cases)

            mp = cases.MP_number(i);
            fname = sprintf('MP_%d_database.csv', mp);
            fpath = fullfile(basepath, fname);

            if ~isfile(fpath)
                error('Selected MP database file not found: %s', fpath);
            end

            fprintf('Reading MP database: %s\n', fname);

            T = readDatabaseCSV(fpath);
            T = applyCaseMetadata(T, cases(i,:), string(fname));

            DB = appendTable(DB, T);

        end

    end

end

function T = readDatabaseCSV(fpath)

    opts = detectImportOptions(fpath, 'TextType','string');

    stringVars = { ...
        'filename', ...
        'basename', ...
        'conf', ...
        'mode', ...
        'direction', ...
        'DirectionLabel', ...
        'SourceDBFile', ...
        'ConditionName', ...
        'RPM1_used_source', ...
        'RPM2_used_source', ...
        'windowStartMode'};

    for k = 1:numel(stringVars)
        if ismember(stringVars{k}, opts.VariableNames)
            opts = setvartype(opts, stringVars{k}, 'string');
        end
    end

    T = readtable(fpath, opts);
    T = normalizeStringColumns(T);

end

function T = applyCaseMetadata(T, caseRow, sourceFile)

    n = height(T);

    T.SourceDBFile = repmat(sourceFile, n, 1);
    T.MP_number = repmat(caseRow.MP_number, n, 1);

    T.ConditionName = repmat(string(caseRow.condition), n, 1);
    T.s_over_R = repmat(caseRow.s_over_R, n, 1);

    if ~isnan(caseRow.activeSRPowertrain)
        T.activeSRPowertrain = repmat(caseRow.activeSRPowertrain, n, 1);
    elseif ~ismember('activeSRPowertrain', T.Properties.VariableNames)
        T.activeSRPowertrain = NaN(n,1);
    end

end

function out = extractSingleRotorData(DB)

    n = height(DB);

    condition = strings(n,1);
    filename  = getStringColumn(DB, 'filename', n);
    sourceDB  = getStringColumn(DB, 'SourceDBFile', n);
    RPM_target = getNumericColumn(DB, 'RPM_target', n);

    rotorID = NaN(n,1);

    Ct = NaN(n,1);
    std_Ct = NaN(n,1);
    Cq = NaN(n,1);
    std_Cq = NaN(n,1);

    T_N = NaN(n,1);
    std_TN = NaN(n,1);

    Q_abs_Nm = NaN(n,1);
    std_Q_abs_Nm = NaN(n,1);

    P_W = NaN(n,1);

    RPM_mean = NaN(n,1);
    RPM_used = NaN(n,1);

    for i = 1:n

        condition(i) = getStringValue(DB, i, 'ConditionName');

        active = getNumericValue(DB, i, 'activeSRPowertrain');

        if isnan(active)

            Ct1 = getNumericValue(DB, i, 'Ct1');
            Ct2 = getNumericValue(DB, i, 'Ct2');

            if isfinite(Ct1) && ~isfinite(Ct2)
                active = 1;
            elseif ~isfinite(Ct1) && isfinite(Ct2)
                active = 2;
            elseif isfinite(Ct1) && isfinite(Ct2)
                active = 1;
            else
                active = NaN;
            end

        end

        rotorID(i) = active;

        if active == 1

            Ct(i)       = getNumericValue(DB, i, 'Ct1');
            std_Ct(i)   = getNumericValue(DB, i, 'Ct1_std');
            Cq(i)       = getNumericValue(DB, i, 'Cq1');
            std_Cq(i)   = getNumericValue(DB, i, 'Cq1_std');

            T_N(i)      = getNumericValue(DB, i, 'T1_mean_N');
            std_TN(i)   = getNumericValue(DB, i, 'T1_std_N');

            Q_abs_Nm(i)     = getFirstAvailableNumericValue(DB, i, {'Q1_abs_mean_Nm','Q1_mean_Nm'});
            std_Q_abs_Nm(i) = getFirstAvailableNumericValue(DB, i, {'Q1_abs_std_Nm','Q1_std_Nm'});

            P_W(i)      = getNumericValue(DB, i, 'P1_mean_W');
            RPM_mean(i) = getNumericValue(DB, i, 'RPM1_mean');
            RPM_used(i) = getNumericValue(DB, i, 'RPM1_used');

        elseif active == 2

            Ct(i)       = getNumericValue(DB, i, 'Ct2');
            std_Ct(i)   = getNumericValue(DB, i, 'Ct2_std');
            Cq(i)       = getNumericValue(DB, i, 'Cq2');
            std_Cq(i)   = getNumericValue(DB, i, 'Cq2_std');

            T_N(i)      = getNumericValue(DB, i, 'T2_mean_N');
            std_TN(i)   = getNumericValue(DB, i, 'T2_std_N');

            Q_abs_Nm(i)     = getFirstAvailableNumericValue(DB, i, {'Q2_abs_mean_Nm','Q2_mean_Nm'});
            std_Q_abs_Nm(i) = getFirstAvailableNumericValue(DB, i, {'Q2_abs_std_Nm','Q2_std_Nm'});

            P_W(i)      = getNumericValue(DB, i, 'P2_mean_W');
            RPM_mean(i) = getNumericValue(DB, i, 'RPM2_mean');
            RPM_used(i) = getNumericValue(DB, i, 'RPM2_used');

        end

    end

    out = table(condition, filename, sourceDB, RPM_target, rotorID, ...
        Ct, std_Ct, Cq, std_Cq, T_N, std_TN, ...
        Q_abs_Nm, std_Q_abs_Nm, P_W, RPM_mean, RPM_used);

end

function out = extractDoubleRotorData(DB)

    n = height(DB);

    condition = strings(2*n,1);
    filename  = strings(2*n,1);
    sourceDB  = strings(2*n,1);

    s_over_R = NaN(2*n,1);
    RPM_target = NaN(2*n,1);
    rotorID = NaN(2*n,1);

    Ct = NaN(2*n,1);
    std_Ct = NaN(2*n,1);
    Cq = NaN(2*n,1);
    std_Cq = NaN(2*n,1);

    T_N = NaN(2*n,1);
    std_TN = NaN(2*n,1);

    Q_abs_Nm = NaN(2*n,1);
    std_Q_abs_Nm = NaN(2*n,1);

    P_W = NaN(2*n,1);

    RPM_mean = NaN(2*n,1);
    RPM_used = NaN(2*n,1);

    filenamesIn = getStringColumn(DB, 'filename', n);
    sourceIn = getStringColumn(DB, 'SourceDBFile', n);
    rpmIn = getNumericColumn(DB, 'RPM_target', n);
    sRin = getNumericColumn(DB, 's_over_R', n);

    r = 0;

    for i = 1:n

        for rot = 1:2

            r = r + 1;

            condition(r) = "DR";
            filename(r) = filenamesIn(i);
            sourceDB(r) = sourceIn(i);
            s_over_R(r) = sRin(i);
            RPM_target(r) = rpmIn(i);
            rotorID(r) = rot;

            if rot == 1

                Ct(r)       = getNumericValue(DB, i, 'Ct1');
                std_Ct(r)   = getNumericValue(DB, i, 'Ct1_std');
                Cq(r)       = getNumericValue(DB, i, 'Cq1');
                std_Cq(r)   = getNumericValue(DB, i, 'Cq1_std');

                T_N(r)      = getNumericValue(DB, i, 'T1_mean_N');
                std_TN(r)   = getNumericValue(DB, i, 'T1_std_N');

                Q_abs_Nm(r)     = getFirstAvailableNumericValue(DB, i, {'Q1_abs_mean_Nm','Q1_mean_Nm'});
                std_Q_abs_Nm(r) = getFirstAvailableNumericValue(DB, i, {'Q1_abs_std_Nm','Q1_std_Nm'});

                P_W(r)      = getNumericValue(DB, i, 'P1_mean_W');
                RPM_mean(r) = getNumericValue(DB, i, 'RPM1_mean');
                RPM_used(r) = getNumericValue(DB, i, 'RPM1_used');

            else

                Ct(r)       = getNumericValue(DB, i, 'Ct2');
                std_Ct(r)   = getNumericValue(DB, i, 'Ct2_std');
                Cq(r)       = getNumericValue(DB, i, 'Cq2');
                std_Cq(r)   = getNumericValue(DB, i, 'Cq2_std');

                T_N(r)      = getNumericValue(DB, i, 'T2_mean_N');
                std_TN(r)   = getNumericValue(DB, i, 'T2_std_N');

                Q_abs_Nm(r)     = getFirstAvailableNumericValue(DB, i, {'Q2_abs_mean_Nm','Q2_mean_Nm'});
                std_Q_abs_Nm(r) = getFirstAvailableNumericValue(DB, i, {'Q2_abs_std_Nm','Q2_std_Nm'});

                P_W(r)      = getNumericValue(DB, i, 'P2_mean_W');
                RPM_mean(r) = getNumericValue(DB, i, 'RPM2_mean');
                RPM_used(r) = getNumericValue(DB, i, 'RPM2_used');

            end

        end

    end

    out = table(condition, filename, sourceDB, s_over_R, RPM_target, rotorID, ...
        Ct, std_Ct, Cq, std_Cq, T_N, std_TN, ...
        Q_abs_Nm, std_Q_abs_Nm, P_W, RPM_mean, RPM_used);

end

function out = aggregateByKeys(T, keyVars)

    valid = isfinite(T.RPM_target);
    T = T(valid,:);

    if isempty(T)
        out = table();
        return;
    end

    T = sortrows(T, keyVars);

    [G, keyTable] = findgroups(T(:, keyVars));

    out = keyTable;

    out.Ct_mean = splitapply(@meanOmitNaN, T.Ct, G);
    out.Cq_mean = splitapply(@meanOmitNaN, T.Cq, G);
    out.T_N_mean = splitapply(@meanOmitNaN, T.T_N, G);
    out.Q_abs_Nm_mean = splitapply(@meanOmitNaN, T.Q_abs_Nm, G);
    out.P_W_mean = splitapply(@meanOmitNaN, T.P_W, G);

    out.RPM_mean = splitapply(@meanOmitNaN, T.RPM_mean, G);
    out.RPM_used = splitapply(@meanOmitNaN, T.RPM_used, G);

    out.Ct_std = splitapply(@meanOmitNaN, T.std_Ct, G);
    out.Cq_std = splitapply(@meanOmitNaN, T.std_Cq, G);
    out.T_N_std = splitapply(@meanOmitNaN, T.std_TN, G);
    out.Q_abs_Nm_std = splitapply(@meanOmitNaN, T.std_Q_abs_Nm, G);

    out.N_cases = splitapply(@numel, T.RPM_target, G);

    out = sortrows(out, keyVars);

end

function curve = buildSRCurve(SR_byCond, conditionName)

    curve = SR_byCond(SR_byCond.condition == conditionName, :);
    curve = cleanCurveForInterpolation(curve);

end

function curve = buildDRRotorCurve(DR_byRotor, sR, rotorID)

    curve = DR_byRotor(DR_byRotor.s_over_R == sR & DR_byRotor.rotorID == rotorID, :);
    curve = cleanCurveForInterpolation(curve);

end

function curve = buildMeanSRCurve(SR_byCond, cond1, cond2)

    T1 = SR_byCond(SR_byCond.condition == cond1, :);
    T2 = SR_byCond(SR_byCond.condition == cond2, :);

    targets = unique([T1.RPM_target; T2.RPM_target]);
    targets = sort(targets(isfinite(targets)));

    curve = table();

    for i = 1:numel(targets)

        rpmT = targets(i);

        row = table();

        row.RPM_target = rpmT;
        row.RPM_used = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'RPM_used'), ...
            getTargetValue(T2, rpmT, 'RPM_used')]);

        row.Ct_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Ct_mean'), ...
            getTargetValue(T2, rpmT, 'Ct_mean')]);

        row.Cq_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Cq_mean'), ...
            getTargetValue(T2, rpmT, 'Cq_mean')]);

        row.T_N_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'T_N_mean'), ...
            getTargetValue(T2, rpmT, 'T_N_mean')]);

        row.Q_abs_Nm_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Q_abs_Nm_mean'), ...
            getTargetValue(T2, rpmT, 'Q_abs_Nm_mean')]);

        row.P_W_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'P_W_mean'), ...
            getTargetValue(T2, rpmT, 'P_W_mean')]);

        row.Ct_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Ct_std'), ...
            getTargetValue(T2, rpmT, 'Ct_std')]);

        row.Cq_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Cq_std'), ...
            getTargetValue(T2, rpmT, 'Cq_std')]);

        row.T_N_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'T_N_std'), ...
            getTargetValue(T2, rpmT, 'T_N_std')]);

        row.Q_abs_Nm_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Q_abs_Nm_std'), ...
            getTargetValue(T2, rpmT, 'Q_abs_Nm_std')]);

        curve = appendTable(curve, row);

    end

    curve = cleanCurveForInterpolation(curve);

end

function curve = buildMeanDRCurve(DR_byRotor, sR)

    T1 = DR_byRotor(DR_byRotor.s_over_R == sR & DR_byRotor.rotorID == 1, :);
    T2 = DR_byRotor(DR_byRotor.s_over_R == sR & DR_byRotor.rotorID == 2, :);

    targets = unique([T1.RPM_target; T2.RPM_target]);
    targets = sort(targets(isfinite(targets)));

    curve = table();

    for i = 1:numel(targets)

        rpmT = targets(i);

        row = table();

        row.s_over_R = sR;
        row.RPM_target = rpmT;

        row.RPM_used = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'RPM_used'), ...
            getTargetValue(T2, rpmT, 'RPM_used')]);

        row.Ct_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Ct_mean'), ...
            getTargetValue(T2, rpmT, 'Ct_mean')]);

        row.Cq_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Cq_mean'), ...
            getTargetValue(T2, rpmT, 'Cq_mean')]);

        row.T_N_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'T_N_mean'), ...
            getTargetValue(T2, rpmT, 'T_N_mean')]);

        row.Q_abs_Nm_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Q_abs_Nm_mean'), ...
            getTargetValue(T2, rpmT, 'Q_abs_Nm_mean')]);

        row.P_W_mean = meanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'P_W_mean'), ...
            getTargetValue(T2, rpmT, 'P_W_mean')]);

        row.Ct_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Ct_std'), ...
            getTargetValue(T2, rpmT, 'Ct_std')]);

        row.Cq_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Cq_std'), ...
            getTargetValue(T2, rpmT, 'Cq_std')]);

        row.T_N_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'T_N_std'), ...
            getTargetValue(T2, rpmT, 'T_N_std')]);

        row.Q_abs_Nm_std = stdMeanOmitNaN([ ...
            getTargetValue(T1, rpmT, 'Q_abs_Nm_std'), ...
            getTargetValue(T2, rpmT, 'Q_abs_Nm_std')]);

        curve = appendTable(curve, row);

    end

    curve = cleanCurveForInterpolation(curve);

end

function comparison = buildExactRPMComparison( ...
    SR_byCond, DR_byRotor, sR_values, condPW1, condPW2, interpMethod, R, nu)

    comparison = table();

    % ============================================================
    % Confronti PW1 e PW2
    % ============================================================

    for powertrainID = 1:2

        if powertrainID == 1
            srCond = condPW1;
            comparisonType = "PW1";
        else
            srCond = condPW2;
            comparisonType = "PW2";
        end

        SR_raw = SR_byCond(SR_byCond.condition == srCond, :);
        SR_curve = cleanCurveForInterpolation(SR_raw);

        if height(SR_curve) < 2
            warning('Not enough SR points for %s.', comparisonType);
            continue;
        end

        for isr = 1:numel(sR_values)

            sR = sR_values(isr);

            DR_raw = DR_byRotor(DR_byRotor.s_over_R == sR & DR_byRotor.rotorID == powertrainID, :);
            DR_curve = cleanCurveForInterpolation(DR_raw);

            if height(DR_curve) < 2
                warning('Not enough DR points for %s, s/R = %.3g.', comparisonType, sR);
                continue;
            end

            targets = intersect(SR_raw.RPM_target, DR_raw.RPM_target);
            targets = sort(targets(isfinite(targets)));

            for it = 1:numel(targets)

                rpmTarget = targets(it);

                rpmSR_nom = getTargetValue(SR_raw, rpmTarget, 'RPM_used');
                rpmDR_nom = getTargetValue(DR_raw, rpmTarget, 'RPM_used');

                if ~isfinite(rpmSR_nom) || ~isfinite(rpmDR_nom)
                    continue;
                end

                rpmCommon = 0.5*(rpmSR_nom + rpmDR_nom);

                row = buildExactComparisonRow( ...
                    comparisonType, powertrainID, sR, rpmTarget, ...
                    rpmSR_nom, rpmDR_nom, rpmCommon, ...
                    SR_curve, DR_curve, interpMethod, R, nu);

                comparison = appendTable(comparison, row);

            end

        end

    end

    % ============================================================
    % Confronto medio: SR medio vs DR medio
    % ============================================================

    SR_mean_raw = buildMeanSRCurve(SR_byCond, condPW1, condPW2);
    SR_mean_curve = cleanCurveForInterpolation(SR_mean_raw);

    if height(SR_mean_curve) >= 2

        for isr = 1:numel(sR_values)

            sR = sR_values(isr);

            DR_mean_raw = buildMeanDRCurve(DR_byRotor, sR);
            DR_mean_curve = cleanCurveForInterpolation(DR_mean_raw);

            if height(DR_mean_curve) < 2
                warning('Not enough DR mean points for s/R = %.3g.', sR);
                continue;
            end

            targets = intersect(SR_mean_raw.RPM_target, DR_mean_raw.RPM_target);
            targets = sort(targets(isfinite(targets)));

            for it = 1:numel(targets)

                rpmTarget = targets(it);

                rpmSR_nom = getTargetValue(SR_mean_raw, rpmTarget, 'RPM_used');
                rpmDR_nom = getTargetValue(DR_mean_raw, rpmTarget, 'RPM_used');

                if ~isfinite(rpmSR_nom) || ~isfinite(rpmDR_nom)
                    continue;
                end

                rpmCommon = 0.5*(rpmSR_nom + rpmDR_nom);

                row = buildExactComparisonRow( ...
                    "MEAN", NaN, sR, rpmTarget, ...
                    rpmSR_nom, rpmDR_nom, rpmCommon, ...
                    SR_mean_curve, DR_mean_curve, interpMethod, R, nu);

                comparison = appendTable(comparison, row);

            end

        end

    else

        warning('Not enough SR mean points for MEAN comparison.');

    end

end

function row = buildExactComparisonRow( ...
    comparisonType, powertrainID, sR, rpmTarget, ...
    rpmSR_nom, rpmDR_nom, rpmCommon, ...
    SR_curve, DR_curve, interpMethod, R, nu)

    Ct_SR = interpCurveValue(SR_curve, rpmCommon, 'Ct_mean', interpMethod);
    Ct_DR = interpCurveValue(DR_curve, rpmCommon, 'Ct_mean', interpMethod);

    Cq_SR = interpCurveValue(SR_curve, rpmCommon, 'Cq_mean', interpMethod);
    Cq_DR = interpCurveValue(DR_curve, rpmCommon, 'Cq_mean', interpMethod);

    T_SR_N = interpCurveValue(SR_curve, rpmCommon, 'T_N_mean', interpMethod);
    T_DR_N = interpCurveValue(DR_curve, rpmCommon, 'T_N_mean', interpMethod);

    Q_SR_Nm = interpCurveValue(SR_curve, rpmCommon, 'Q_abs_Nm_mean', interpMethod);
    Q_DR_Nm = interpCurveValue(DR_curve, rpmCommon, 'Q_abs_Nm_mean', interpMethod);

    P_SR_W = interpCurveValue(SR_curve, rpmCommon, 'P_W_mean', interpMethod);
    P_DR_W = interpCurveValue(DR_curve, rpmCommon, 'P_W_mean', interpMethod);

    Ct_SR_std = interpCurveValue(SR_curve, rpmCommon, 'Ct_std', interpMethod);
    Ct_DR_std = interpCurveValue(DR_curve, rpmCommon, 'Ct_std', interpMethod);

    Cq_SR_std = interpCurveValue(SR_curve, rpmCommon, 'Cq_std', interpMethod);
    Cq_DR_std = interpCurveValue(DR_curve, rpmCommon, 'Cq_std', interpMethod);

    row = table();

    row.comparisonType = comparisonType;
    row.powertrainID = powertrainID;
    row.s_over_R = sR;
    row.RPM_target = rpmTarget;

    row.RPM_SR_used_nominal = rpmSR_nom;
    row.RPM_DR_used_nominal = rpmDR_nom;
    row.RPM_common = rpmCommon;
    row.RPM_common_definition = "0.5*(RPM_SR_used_nominal + RPM_DR_used_nominal)";

    row.Ct_SR = Ct_SR;
    row.Ct_DR = Ct_DR;
    row.dCt = Ct_SR - Ct_DR;
    row.dCt_percent = percentLoss(Ct_SR, Ct_DR);

    row.Cq_SR = Cq_SR;
    row.Cq_DR = Cq_DR;
    row.dCq = Cq_SR - Cq_DR;
    row.dCq_percent = percentLoss(Cq_SR, Cq_DR);

    row.T_SR_N = T_SR_N;
    row.T_DR_N = T_DR_N;
    row.dT_N = T_SR_N - T_DR_N;
    row.dT_percent = percentLoss(T_SR_N, T_DR_N);

    row.Q_SR_Nm = Q_SR_Nm;
    row.Q_DR_Nm = Q_DR_Nm;
    row.dQ_Nm = Q_SR_Nm - Q_DR_Nm;
    row.dQ_percent = percentLoss(Q_SR_Nm, Q_DR_Nm);

    row.P_SR_W = P_SR_W;
    row.P_DR_W = P_DR_W;

    row.Ct_SR_std = Ct_SR_std;
    row.Ct_DR_std = Ct_DR_std;
    row.dCt_std = stdDiff(Ct_SR_std, Ct_DR_std);

    row.Cq_SR_std = Cq_SR_std;
    row.Cq_DR_std = Cq_DR_std;
    row.dCq_std = stdDiff(Cq_SR_std, Cq_DR_std);

    Omega = 2*pi*rpmCommon/60;
    row.Re_R = Omega * R^2 / nu;

end

function Tclean = cleanCurveForInterpolation(T)

    if isempty(T)
        Tclean = table();
        return;
    end

    requiredVars = { ...
        'RPM_target', ...
        'RPM_used', ...
        'Ct_mean', ...
        'Cq_mean', ...
        'T_N_mean', ...
        'Q_abs_Nm_mean', ...
        'P_W_mean', ...
        'Ct_std', ...
        'Cq_std', ...
        'T_N_std', ...
        'Q_abs_Nm_std'};

    for k = 1:numel(requiredVars)
        if ~ismember(requiredVars{k}, T.Properties.VariableNames)
            T.(requiredVars{k}) = NaN(height(T),1);
        end
    end

    valid = isfinite(T.RPM_used) & ...
            isfinite(T.Ct_mean) & ...
            isfinite(T.Cq_mean);

    T = T(valid,:);

    if isempty(T)
        Tclean = table();
        return;
    end

    T = sortrows(T, 'RPM_used');

    [rpmUnique, ~, G] = unique(T.RPM_used);

    Tclean = table();

    Tclean.RPM_used = rpmUnique;
    Tclean.RPM_target = splitapply(@meanOmitNaN, T.RPM_target, G);

    Tclean.Ct_mean = splitapply(@meanOmitNaN, T.Ct_mean, G);
    Tclean.Cq_mean = splitapply(@meanOmitNaN, T.Cq_mean, G);
    Tclean.T_N_mean = splitapply(@meanOmitNaN, T.T_N_mean, G);
    Tclean.Q_abs_Nm_mean = splitapply(@meanOmitNaN, T.Q_abs_Nm_mean, G);
    Tclean.P_W_mean = splitapply(@meanOmitNaN, T.P_W_mean, G);

    Tclean.Ct_std = splitapply(@meanOmitNaN, T.Ct_std, G);
    Tclean.Cq_std = splitapply(@meanOmitNaN, T.Cq_std, G);
    Tclean.T_N_std = splitapply(@meanOmitNaN, T.T_N_std, G);
    Tclean.Q_abs_Nm_std = splitapply(@meanOmitNaN, T.Q_abs_Nm_std, G);

end

function val = interpCurveValue(curve, rpm, varName, interpMethod)

    val = NaN;

    if isempty(curve) || ~ismember(varName, curve.Properties.VariableNames)
        return;
    end

    x = curve.RPM_used;
    y = curve.(varName);

    valid = isfinite(x) & isfinite(y);

    x = x(valid);
    y = y(valid);

    if isempty(x)
        return;
    end

    [x, ord] = sort(x);
    y = y(ord);

    [x, uniqueIdx] = unique(x, 'stable');
    y = y(uniqueIdx);

    if numel(x) == 1
        if abs(rpm - x) < 1e-9
            val = y;
        else
            val = NaN;
        end
        return;
    end

    if rpm < min(x) || rpm > max(x)
        val = NaN;
        return;
    end

    val = interp1(x, y, rpm, interpMethod, NaN);

end

function val = getTargetValue(T, rpmTarget, varName)

    val = NaN;

    if isempty(T) || ~ismember(varName, T.Properties.VariableNames)
        return;
    end

    idx = T.RPM_target == rpmTarget;

    if any(idx)
        val = mean(T.(varName)(idx), 'omitnan');
    end

end

function p = percentLoss(SR, DR)

    if ~isfinite(SR) || ~isfinite(DR) || SR == 0
        p = NaN;
    else
        p = 100 * (SR - DR) / SR;
    end

end

function s = stdDiff(s1, s2)

    vals = [s1, s2];
    vals = vals(isfinite(vals));

    if isempty(vals)
        s = NaN;
    else
        s = sqrt(sum(vals.^2));
    end

end

function s = stdMeanOmitNaN(stdVals)

    stdVals = stdVals(isfinite(stdVals));
    n = numel(stdVals);

    if n == 0
        s = NaN;
    elseif n == 1
        s = stdVals;
    else
        s = sqrt(sum(stdVals.^2))/n;
    end

end

function m = meanOmitNaN(x)

    m = mean(x, 'omitnan');

end

function x = getNumericColumn(T, varName, n)

    if ismember(varName, T.Properties.VariableNames)
        x = T.(varName);
    else
        x = NaN(n,1);
    end

end

function s = getStringColumn(T, varName, n)

    if ismember(varName, T.Properties.VariableNames)
        s = string(T.(varName));
    else
        s = strings(n,1);
    end

end

function s = getStringValue(T, i, varName)

    if ~ismember(varName, T.Properties.VariableNames)
        s = "";
        return;
    end

    x = T.(varName);

    if iscell(x)
        s = string(x{i});
    else
        s = string(x(i));
    end

end

function x = getNumericValue(T, i, varName)

    if ~ismember(varName, T.Properties.VariableNames)
        x = NaN;
        return;
    end

    value = T.(varName);

    if iscell(value)
        x = str2double(string(value{i}));
    elseif isstring(value)
        x = str2double(value(i));
    elseif iscategorical(value)
        x = str2double(string(value(i)));
    elseif islogical(value)
        x = double(value(i));
    else
        x = value(i);
    end

    if isempty(x)
        x = NaN;
    end

end

function x = getFirstAvailableNumericValue(T, i, varNames)

    x = NaN;

    for k = 1:numel(varNames)
        candidate = getNumericValue(T, i, varNames{k});

        if isfinite(candidate)
            x = candidate;
            return;
        end
    end

end

function T = normalizeStringColumns(T)

    stringVars = { ...
        'filename', ...
        'basename', ...
        'conf', ...
        'mode', ...
        'direction', ...
        'DirectionLabel', ...
        'SourceDBFile', ...
        'ConditionName', ...
        'RPM1_used_source', ...
        'RPM2_used_source', ...
        'windowStartMode'};

    for k = 1:numel(stringVars)

        var = stringVars{k};

        if ismember(var, T.Properties.VariableNames)
            T.(var) = string(T.(var));
        end

    end

end

function [A, B] = makeTablesVertcatCompatible(A, B)

    A = normalizeStringColumns(A);
    B = normalizeStringColumns(B);

    varsA = A.Properties.VariableNames;
    varsB = B.Properties.VariableNames;

    allVars = unique([varsA, varsB], 'stable');

    for k = 1:numel(allVars)

        var = allVars{k};

        if ~ismember(var, A.Properties.VariableNames)
            A.(var) = makeMissingColumnLike(B.(var), height(A));
        end

        if ~ismember(var, B.Properties.VariableNames)
            B.(var) = makeMissingColumnLike(A.(var), height(B));
        end

    end

    A = A(:, allVars);
    B = B(:, allVars);

end

function x = makeMissingColumnLike(ref, n)

    if isstring(ref)
        x = strings(n, size(ref,2));
    elseif isnumeric(ref)
        x = NaN(n, size(ref,2));
    elseif islogical(ref)
        x = false(n, size(ref,2));
    elseif iscell(ref)
        x = cell(n, size(ref,2));
    elseif iscategorical(ref)
        x = categorical(strings(n,1));
    else
        x = strings(n,1);
    end

end

function T = appendTable(T, row)

    if isempty(row)
        return;
    end

    if isempty(T)
        T = row;
    else
        [T, row] = makeTablesVertcatCompatible(T, row);
        T = [T; row];
    end

end

%% ===================== PLOT FUNCTIONS =========================

function plotCtVsRPMusedPowertrains(SR_PW1_curve, SR_PW2_curve, DR_curves, sR_values, outFile)

    if isempty(DR_curves) || ...
       ~ismember('s_over_R', DR_curves.Properties.VariableNames) || ...
       ~ismember('curveType', DR_curves.Properties.VariableNames)

        warning('DR_curves is empty or missing s_over_R/curveType. Skipping powertrain Ct plot.');
        return;

    end

    fig = figure('Color','w','Name','Ct vs RPMused - powertrains');
    tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

    for powertrainID = 1:2

        nexttile;
        hold on; grid on; box on;

        if powertrainID == 1
            SRcurve = SR_PW1_curve;
            srLabel = 'SR PW1';
            drType = "DR_R1";
            titleText = '$C_T$ vs $RPM_{used}$ - PW1/R1';
        else
            SRcurve = SR_PW2_curve;
            srLabel = 'SR PW2';
            drType = "DR_R2";
            titleText = '$C_T$ vs $RPM_{used}$ - PW2/R2';
        end

        if ~isempty(SRcurve)
            plot(SRcurve.RPM_used, SRcurve.Ct_mean, '-ok', ...
                'LineWidth', 1.8, ...
                'MarkerFaceColor','k', ...
                'DisplayName', srLabel);
        end

        for isr = 1:numel(sR_values)

            sR = sR_values(isr);

            idx = DR_curves.s_over_R == sR & DR_curves.curveType == drType;
            DRp = DR_curves(idx,:);

            if isempty(DRp)
                continue;
            end

            plot(DRp.RPM_used, DRp.Ct_mean, '--s', ...
                'LineWidth', 1.4, ...
                'MarkerSize', 6, ...
                'DisplayName', sprintf('DR R%d, s/R = %.3g', powertrainID, sR));

        end

        xlabel('$RPM_{used}$', 'Interpreter','latex');
        ylabel('$C_T$', 'Interpreter','latex');
        title(titleText, 'Interpreter','latex');
        legend('Location','best', 'Interpreter','latex');

    end

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotCtVsRPMusedMean(SR_mean_curve, DR_curves, sR_values, outFile)

    if isempty(DR_curves) || ...
       ~ismember('s_over_R', DR_curves.Properties.VariableNames) || ...
       ~ismember('curveType', DR_curves.Properties.VariableNames)

        warning('DR_curves is empty or missing s_over_R/curveType. Skipping mean Ct plot.');
        return;

    end

    fig = figure('Color','w','Name','Ct vs RPMused - mean case');

    if ~isempty(SR_mean_curve)
        plot(SR_mean_curve.RPM_used, SR_mean_curve.Ct_mean, '-ok', ...
            'LineWidth', 1.8, ...
            'MarkerFaceColor','k', ...
            'DisplayName','SR mean');
    end

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        idx = DR_curves.s_over_R == sR & DR_curves.curveType == "DR_MEAN";
        DRp = DR_curves(idx,:);

        if isempty(DRp)
            continue;
        end

        plot(DRp.RPM_used, DRp.Ct_mean, '--s', ...
            'LineWidth', 1.4, ...
            'MarkerSize', 6, ...
            'DisplayName', sprintf('DR mean, s/R = %.3g', sR));

    end

    xlabel('$RPM_{used}$', 'Interpreter','latex');
    ylabel('$C_T$', 'Interpreter','latex');
    title('$C_T$ vs $RPM_{used}$ - mean case', 'Interpreter','latex');
    legend('Location','best', 'Interpreter','latex');

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotCtExactComparison(comparison, outFile)

    fig = figure('Color','w','Name','Ct exact RPM comparison');
    tiledlayout(3,1,'Padding','compact','TileSpacing','compact');

    types = ["PW1", "PW2", "MEAN"];
    titles = [
        "$C_T$ exact RPM - PW1/R1"
        "$C_T$ exact RPM - PW2/R2"
        "$C_T$ exact RPM - MEAN"
    ];

    for itype = 1:numel(types)

        nexttile;
        hold on; grid on; box on;

        type = types(itype);
        idxType = comparison.comparisonType == type;

        sR_values = unique(comparison.s_over_R(idxType));
        sR_values = sort(sR_values(isfinite(sR_values)));

        for isr = 1:numel(sR_values)

            sR = sR_values(isr);

            idx = idxType & comparison.s_over_R == sR;

            x = comparison.RPM_common(idx);
            ySR = comparison.Ct_SR(idx);
            yDR = comparison.Ct_DR(idx);

            valid = isfinite(x) & isfinite(ySR) & isfinite(yDR);

            x = x(valid);
            ySR = ySR(valid);
            yDR = yDR(valid);

            if isempty(x)
                continue;
            end

            [x, ord] = sort(x);
            ySR = ySR(ord);
            yDR = yDR(ord);

            plot(x, ySR, '-o', ...
                'LineWidth', 1.5, ...
                'MarkerSize', 5, ...
                'DisplayName', sprintf('SR, s/R %.3g', sR));

            plot(x, yDR, '--s', ...
                'LineWidth', 1.5, ...
                'MarkerSize', 5, ...
                'DisplayName', sprintf('DR, s/R %.3g', sR));

        end

        xlabel('$RPM_{common}$', 'Interpreter','latex');
        ylabel('$C_T$', 'Interpreter','latex');
        title(titles(itype), 'Interpreter','latex');
        legend('Location','best', 'Interpreter','latex');

    end

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotDeltaExactVsRPM(comparison, outFile)

    fig = figure('Color','w','Name','Delta Ct exact RPM vs RPM');
    tiledlayout(3,1,'Padding','compact','TileSpacing','compact');

    types = ["PW1", "PW2", "MEAN"];
    titles = [
        "$\Delta C_T$ exact RPM - PW1/R1"
        "$\Delta C_T$ exact RPM - PW2/R2"
        "$\Delta C_T$ exact RPM - MEAN"
    ];

    for itype = 1:numel(types)

        nexttile;
        hold on; grid on; box on;

        type = types(itype);
        idxType = comparison.comparisonType == type;

        sR_values = unique(comparison.s_over_R(idxType));
        sR_values = sort(sR_values(isfinite(sR_values)));

        for isr = 1:numel(sR_values)

            sR = sR_values(isr);

            idx = idxType & comparison.s_over_R == sR;

            x = comparison.RPM_common(idx);
            y = comparison.dCt_percent(idx);

            valid = isfinite(x) & isfinite(y);

            x = x(valid);
            y = y(valid);

            if isempty(x)
                continue;
            end

            [x, ord] = sort(x);
            y = y(ord);

            plot(x, y, '-o', ...
                'LineWidth', 1.5, ...
                'MarkerSize', 6, ...
                'DisplayName', sprintf('s/R = %.3g', sR));

        end

        yline(0, '--k', 'HandleVisibility','off');

        xlabel('$RPM_{common}$', 'Interpreter','latex');
        ylabel('$\Delta C_T$ [\%]', 'Interpreter','latex');
        title(titles(itype), 'Interpreter','latex');
        legend('Location','best', 'Interpreter','latex');

    end

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotDeltaExactVsSR(comparison, outFile)

    fig = figure('Color','w','Name','Delta Ct exact RPM vs s/R');
    tiledlayout(3,1,'Padding','compact','TileSpacing','compact');

    types = ["PW1", "PW2", "MEAN"];
    titles = [
        "$\Delta C_T$ exact RPM vs $s/R$ - PW1/R1"
        "$\Delta C_T$ exact RPM vs $s/R$ - PW2/R2"
        "$\Delta C_T$ exact RPM vs $s/R$ - MEAN"
    ];

    for itype = 1:numel(types)

        nexttile;
        hold on; grid on; box on;

        type = types(itype);
        idxType = comparison.comparisonType == type;

        rpmTargets = unique(comparison.RPM_target(idxType));
        rpmTargets = sort(rpmTargets(isfinite(rpmTargets)));

        for irpm = 1:numel(rpmTargets)

            rpmT = rpmTargets(irpm);

            idx = idxType & comparison.RPM_target == rpmT;

            x = comparison.s_over_R(idx);
            y = comparison.dCt_percent(idx);

            valid = isfinite(x) & isfinite(y);

            x = x(valid);
            y = y(valid);

            if isempty(x)
                continue;
            end

            [x, ord] = sort(x);
            y = y(ord);

            plot(x, y, '-o', ...
                'LineWidth', 1.5, ...
                'MarkerSize', 6, ...
                'DisplayName', sprintf('%d RPM target', rpmT));

        end

        yline(0, '--k', 'HandleVisibility','off');

        xlabel('$s/R$', 'Interpreter','latex');
        ylabel('$\Delta C_T$ [\%]', 'Interpreter','latex');
        title(titles(itype), 'Interpreter','latex');
        legend('Location','best', 'Interpreter','latex');

    end

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotDeltaExactVsRPMSelectedType(comparison, selectedType, outFile)

    selectedType = string(selectedType);

    fig = figure('Color','w','Name',sprintf('Delta Ct exact RPM %s', selectedType));
    hold on; grid on; box on;

    idxType = comparison.comparisonType == selectedType;

    sR_values = unique(comparison.s_over_R(idxType));
    sR_values = sort(sR_values(isfinite(sR_values)));

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        idx = idxType & comparison.s_over_R == sR;

        x = comparison.RPM_common(idx);
        y = comparison.dCt_percent(idx);

        valid = isfinite(x) & isfinite(y);

        x = x(valid);
        y = y(valid);

        if isempty(x)
            continue;
        end

        [x, ord] = sort(x);
        y = y(ord);

        plot(x, y, '-o', ...
            'LineWidth', 1.5, ...
            'MarkerSize', 6, ...
            'DisplayName', sprintf('s/R = %.3g', sR));

    end

    yline(0, '--k', 'HandleVisibility','off');

    xlabel('$RPM_{common}$', 'Interpreter','latex');
    ylabel('$\Delta C_T$ [\%]', 'Interpreter','latex');
    title(sprintf('$\\Delta C_T$ exact RPM - %s', selectedType), 'Interpreter','latex');
    legend('Location','best', 'Interpreter','latex');

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function curve = addDRCurveMetadata(curve, sR, rotorID, curveType)

    if isempty(curve)
        return;
    end

    curve.s_over_R = sR * ones(height(curve), 1);
    curve.rotorID = rotorID * ones(height(curve), 1);
    curve.curveType = repmat(string(curveType), height(curve), 1);

end