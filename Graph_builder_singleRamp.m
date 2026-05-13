% ANALISI DATABASE SR/DR SINGLE-RAMP 
%
% Input:
%   - MP_xxx_database.csv generati dal builder single-ramp
%
% Obiettivo:
%   1) Leggere SR e DR
%   2) Estrarre Ct, Cq, T, Q, P e RPM_used
%   3) Confrontare SR e DR a pari RPM effettivo
%   4) Fare confronto:
%        - PW1: SR powertrain 1 vs DR rotor 1
%        - PW2: SR powertrain 2 vs DR rotor 2
%        - MEAN: media SR vs media DR
%
% Convenzione:
%   Delta Ct [%] = 100*(Ct_SR - Ct_DR)/Ct_SR

clear; close all; clc;

%% ===================== INPUT =================================

D   = 20*0.0254;      % [m]
T_C = 23.2;           % [degC]

basepath = 'E:\APC_Prove\20x13\Analisi\database_29_04_26\';

outpath = fullfile(basepath, 'Confronto_SR_DR_singleRamp');

if ~exist(outpath, 'dir')
    mkdir(outpath);
end

figpath = fullfile(outpath, 'Figures');

if ~exist(figpath, 'dir')
    mkdir(figpath);
end

useAllMPFile = false;
allMPFilename = 'database_RRI2_singleRamp_SR_DR_allMP.csv';

% EP_SR -> powertrain 1
% E_SR  -> powertrain 2
% DR    -> double rotor

MP_EP_SR = [
    212 213 214 215 216 217 218 219
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

cases = table();

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

% ATTENZIONE:
% questa riga assume che MP_DR sia ordinato per blocchi:
% 180-187 -> s/R = 2
% 188-195 -> s/R = 5
% 196-203 -> s/R = 10
% 204-211 -> s/R = 20
cases.s_over_R = [
    NaN(numel(MP_EP_SR), 1)
    NaN(numel(MP_E_SR),  1)
    repelem(DR_sR_values(:), nRPM_DR)
];

cases = cases(~isnan(cases.MP_number), :);

sR_values = DR_sR_values(:);

writetable(cases, fullfile(outpath, 'input_cases_singleRamp.csv'));

fprintf('\nMP mapping used in this analysis:\n');
disp(cases);

%% Parametri fisici

interpMethod = 'linear';

rho = 1.225;          % [kg/m^3]
R   = D/2;            % [m]

Tair = T_C + 273.15;  % [K]

mu0 = 1.716e-5;       % [Pa s]
T0  = 273.15;         % [K]
S   = 110.4;          % [K]

mu = mu0 * (Tair/T0)^(3/2) * (T0 + S)/(Tair + S);
nu = mu/rho;

%% ===================== LOAD DATABASE ==========================

DB_all = table();

if useAllMPFile

    fpath = fullfile(basepath, allMPFilename);

    if ~isfile(fpath)
        error('All-MP database file not found: %s', fpath);
    end

    T_all = readDatabaseCSV(fpath);

    if ~ismember('MP_number', T_all.Properties.VariableNames)
        error('The all-MP database does not contain MP_number.');
    end

    for ic = 1:height(cases)

        mp = cases.MP_number(ic);

        idx = T_all.MP_number == mp;

        if ~any(idx)
            error('MP %d not found inside %s.', mp, fpath);
        end

        T = T_all(idx, :);

        n = height(T);
        T.SourceDBFile = repmat(string(allMPFilename), n, 1);
        T.MP_number = repmat(mp, n, 1);
        T.ConditionName = repmat(string(cases.condition(ic)), n, 1);
        T.s_over_R = repmat(cases.s_over_R(ic), n, 1);
        T.activeSRPowertrain = repmat(cases.activeSRPowertrain(ic), n, 1);

        DB_all = appendCompatible(DB_all, T);

    end

else

    for ic = 1:height(cases)

        mp = cases.MP_number(ic);
        fname = sprintf('MP_%d_database.csv', mp);
        fpath = fullfile(basepath, fname);

        if ~isfile(fpath)
            error('Selected MP database file not found: %s', fpath);
        end

        fprintf('Reading MP database: %s\n', fname);

        T = readDatabaseCSV(fpath);

        n = height(T);
        T.SourceDBFile = repmat(string(fname), n, 1);
        T.MP_number = repmat(mp, n, 1);
        T.ConditionName = repmat(string(cases.condition(ic)), n, 1);
        T.s_over_R = repmat(cases.s_over_R(ic), n, 1);
        T.activeSRPowertrain = repmat(cases.activeSRPowertrain(ic), n, 1);

        DB_all = appendCompatible(DB_all, T);

    end

end

fprintf('\nLoaded database rows: %d\n', height(DB_all));

writetable(DB_all, fullfile(outpath, 'DB_all_singleRamp.csv'));

%% ===================== CREATE LONG DATA TABLE =================
% DATA contiene una riga per ogni rotore letto.
% SR:
%   EP_SR -> legge solo rotore/powertrain 1
%   E_SR  -> legge solo rotore/powertrain 2
%
% DR:
%   legge rotore 1 e rotore 2

condition = strings(0,1);
filename = strings(0,1);
sourceDB = strings(0,1);

MP_number = [];
s_over_R = [];
rotorID = [];
RPM_target = [];
RPM_used = [];

Ct = [];
Cq = [];
T_N = [];
Q_Nm = [];
P_W = [];

for i = 1:height(DB_all)

    cond = string(DB_all.ConditionName(i));

    if cond == "DR"

        rotorsToRead = [1 2];

    else

        active = getnum(DB_all, i, 'activeSRPowertrain');

        if isnan(active)
            error('Missing activeSRPowertrain for SR row %d.', i);
        end

        rotorsToRead = active;

    end

    for rr = 1:numel(rotorsToRead)

        rot = rotorsToRead(rr);

        condition(end+1,1) = cond;
        filename(end+1,1) = getstr(DB_all, i, 'filename');
        sourceDB(end+1,1) = getstr(DB_all, i, 'SourceDBFile');

        MP_number(end+1,1) = getnum(DB_all, i, 'MP_number');
        s_over_R(end+1,1) = getnum(DB_all, i, 's_over_R');
        rotorID(end+1,1) = rot;
        RPM_target(end+1,1) = getnum(DB_all, i, 'RPM_target');

        if rot == 1

            Ct(end+1,1) = getnum(DB_all, i, 'Ct1');
            Cq(end+1,1) = getnum(DB_all, i, 'Cq1');
            T_N(end+1,1) = getnum(DB_all, i, 'T1_mean_N');
            Q_Nm(end+1,1) = getFirstNum(DB_all, i, {'Q1_abs_mean_Nm','Q1_mean_Nm'});
            P_W(end+1,1) = getnum(DB_all, i, 'P1_mean_W');
            RPM_used(end+1,1) = getnum(DB_all, i, 'RPM1_used');

        elseif rot == 2

            Ct(end+1,1) = getnum(DB_all, i, 'Ct2');
            Cq(end+1,1) = getnum(DB_all, i, 'Cq2');
            T_N(end+1,1) = getnum(DB_all, i, 'T2_mean_N');
            Q_Nm(end+1,1) = getFirstNum(DB_all, i, {'Q2_abs_mean_Nm','Q2_mean_Nm'});
            P_W(end+1,1) = getnum(DB_all, i, 'P2_mean_W');
            RPM_used(end+1,1) = getnum(DB_all, i, 'RPM2_used');

        end

    end

end

DATA = table(condition, filename, sourceDB, MP_number, s_over_R, rotorID, ...
    RPM_target, RPM_used, Ct, Cq, T_N, Q_Nm, P_W);

writetable(DATA, fullfile(outpath, 'DATA_long_singleRamp.csv'));

fprintf('\nLong table rows:\n');
fprintf('  DATA: %d\n', height(DATA));

%% ===================== AGGREGATE ==============================
% Media per:
%   condition, s/R, rotorID, RPM_target
%
% Nota:
%   per SR s/R è NaN, quindi uso un valore fittizio solo per il grouping.

DATA_valid = DATA(isfinite(DATA.RPM_target) & ...
                  isfinite(DATA.RPM_used) & ...
                  isfinite(DATA.Ct), :);

if isempty(DATA_valid)
    error('DATA_valid is empty. Check RPM_target, RPM_used and Ct columns.');
end

sR_group = DATA_valid.s_over_R;
sR_group(isnan(sR_group)) = -999;

DATA_valid.sR_group = sR_group;

[G, keys] = findgroups(DATA_valid(:, {'condition','sR_group','rotorID','RPM_target'}));

AVG = keys;
AVG.Properties.VariableNames{'sR_group'} = 's_over_R';

AVG.s_over_R(AVG.s_over_R == -999) = NaN;

AVG.RPM_used = splitapply(@meanOmitNaN, DATA_valid.RPM_used, G);
AVG.Ct       = splitapply(@meanOmitNaN, DATA_valid.Ct, G);
AVG.Cq       = splitapply(@meanOmitNaN, DATA_valid.Cq, G);
AVG.T_N      = splitapply(@meanOmitNaN, DATA_valid.T_N, G);
AVG.Q_Nm     = splitapply(@meanOmitNaN, DATA_valid.Q_Nm, G);
AVG.P_W      = splitapply(@meanOmitNaN, DATA_valid.P_W, G);
AVG.N        = splitapply(@numel, DATA_valid.Ct, G);

AVG = sortrows(AVG, {'condition','s_over_R','rotorID','RPM_target'});

writetable(AVG, fullfile(outpath, 'AVG_singleRamp.csv'));

fprintf('\nAveraged table rows:\n');
fprintf('  AVG: %d\n', height(AVG));

%% ===================== BUILD CURVES FOR PLOTS =================

SR_PW1_curve = cleanCurve(AVG(AVG.condition == "EP_SR" & AVG.rotorID == 1, :));
SR_PW2_curve = cleanCurve(AVG(AVG.condition == "E_SR"  & AVG.rotorID == 2, :));

SR_MEAN_curve = makeMeanCurve(SR_PW1_curve, SR_PW2_curve);

DR_MEAN_curves = table();

for isr = 1:numel(sR_values)

    sR = sR_values(isr);

    DR_R1_curve = cleanCurve(AVG(AVG.condition == "DR" & ...
                                 AVG.s_over_R == sR & ...
                                 AVG.rotorID == 1, :));

    DR_R2_curve = cleanCurve(AVG(AVG.condition == "DR" & ...
                                 AVG.s_over_R == sR & ...
                                 AVG.rotorID == 2, :));

    DR_mean_curve = makeMeanCurve(DR_R1_curve, DR_R2_curve);

    if ~isempty(DR_mean_curve)
        DR_mean_curve.s_over_R = sR * ones(height(DR_mean_curve), 1);
        DR_MEAN_curves = appendCompatible(DR_MEAN_curves, DR_mean_curve);
    end

end

writetable(SR_PW1_curve, fullfile(outpath, 'SR_PW1_curve.csv'));
writetable(SR_PW2_curve, fullfile(outpath, 'SR_PW2_curve.csv'));
writetable(SR_MEAN_curve, fullfile(outpath, 'SR_MEAN_curve.csv'));
writetable(DR_MEAN_curves, fullfile(outpath, 'DR_MEAN_curves.csv'));

%% ===================== EXACT RPM COMPARISON ===================

comparison_exact = table();

comparisonTypes = ["PW1"; "PW2"];
srConditions    = ["EP_SR"; "E_SR"];
rotorIDs        = [1; 2];

for itype = 1:numel(comparisonTypes)

    comparisonType = comparisonTypes(itype);
    srCond = srConditions(itype);
    rotID = rotorIDs(itype);

    SR_raw = AVG(AVG.condition == srCond & AVG.rotorID == rotID, :);
    SR_curve = cleanCurve(SR_raw);

    if height(SR_curve) < 2
        warning('Not enough SR points for %s.', comparisonType);
        continue;
    end

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        DR_raw = AVG(AVG.condition == "DR" & ...
                     AVG.s_over_R == sR & ...
                     AVG.rotorID == rotID, :);

        DR_curve = cleanCurve(DR_raw);

        if height(DR_curve) < 2
            warning('Not enough DR points for %s, s/R = %.3g.', comparisonType, sR);
            continue;
        end

        targets = intersect(SR_raw.RPM_target, DR_raw.RPM_target);
        targets = sort(targets(isfinite(targets)));

        for it = 1:numel(targets)

            rpmTarget = targets(it);

            rpmSR_nom = getAtTarget(SR_raw, rpmTarget, 'RPM_used');
            rpmDR_nom = getAtTarget(DR_raw, rpmTarget, 'RPM_used');

            if ~isfinite(rpmSR_nom) || ~isfinite(rpmDR_nom)
                continue;
            end

            row = makeComparisonRow( ...
                comparisonType, rotID, sR, rpmTarget, ...
                rpmSR_nom, rpmDR_nom, ...
                SR_curve, DR_curve, interpMethod, R, nu);

            comparison_exact = appendCompatible(comparison_exact, row);

        end

    end

end

% ===================== MEAN COMPARISON =========================

if height(SR_MEAN_curve) >= 2

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        DR_mean_curve = DR_MEAN_curves(DR_MEAN_curves.s_over_R == sR, :);
        DR_mean_curve = cleanCurve(DR_mean_curve);

        if height(DR_mean_curve) < 2
            warning('Not enough DR mean points for s/R = %.3g.', sR);
            continue;
        end

        targets = intersect(SR_MEAN_curve.RPM_target, DR_mean_curve.RPM_target);
        targets = sort(targets(isfinite(targets)));

        for it = 1:numel(targets)

            rpmTarget = targets(it);

            rpmSR_nom = getAtTarget(SR_MEAN_curve, rpmTarget, 'RPM_used');
            rpmDR_nom = getAtTarget(DR_mean_curve, rpmTarget, 'RPM_used');

            if ~isfinite(rpmSR_nom) || ~isfinite(rpmDR_nom)
                continue;
            end

            row = makeComparisonRow( ...
                "MEAN", NaN, sR, rpmTarget, ...
                rpmSR_nom, rpmDR_nom, ...
                SR_MEAN_curve, DR_mean_curve, interpMethod, R, nu);

            comparison_exact = appendCompatible(comparison_exact, row);

        end

    end

else

    warning('Not enough SR mean points for MEAN comparison.');

end

writetable(comparison_exact, ...
    fullfile(outpath, 'comparison_SR_DR_exactRPM_singleRamp.csv'));

fprintf('\nExact-RPM comparison rows: %d\n', height(comparison_exact));

%% ===================== SAVE MAT ===============================

save(fullfile(outpath, 'analysis_SR_DR_exactRPM_singleRamp.mat'), ...
    'cases', 'DB_all', 'DATA', 'AVG', ...
    'SR_PW1_curve', 'SR_PW2_curve', 'SR_MEAN_curve', ...
    'DR_MEAN_curves', 'comparison_exact', ...
    'rho', 'D', 'R', 'T_C', 'Tair', 'mu', 'nu', ...
    'sR_values', 'interpMethod');

fprintf('\nSaved output tables in:\n%s\n', outpath);


%% ===================== PLOT 01: Ct POWERTRAINS ================

fig = figure('Color','w','Name','Ct vs RPMused - powertrains');
tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

for rotID = 1:2

    nexttile;
    hold on; grid on; box on;

    if rotID == 1
        SR_curve = SR_PW1_curve;
        srLabel = 'SR PW1';
        titleText = '$C_T$ vs $RPM_{used}$ - PW1/R1';
    else
        SR_curve = SR_PW2_curve;
        srLabel = 'SR PW2';
        titleText = '$C_T$ vs $RPM_{used}$ - PW2/R2';
    end

    if ~isempty(SR_curve)
        plot(SR_curve.RPM_used, SR_curve.Ct, '-ok', ...
            'LineWidth', 1.8, ...
            'MarkerFaceColor','k', ...
            'DisplayName', srLabel);
    end

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        DR_curve = cleanCurve(AVG(AVG.condition == "DR" & ...
                                  AVG.s_over_R == sR & ...
                                  AVG.rotorID == rotID, :));

        if isempty(DR_curve)
            continue;
        end

        plot(DR_curve.RPM_used, DR_curve.Ct, '--s', ...
            'LineWidth', 1.4, ...
            'MarkerSize', 6, ...
            'DisplayName', sprintf('DR R%d, s/R = %.3g', rotID, sR));

    end

    xlabel('$RPM_{used}$', 'Interpreter','latex');
    ylabel('$C_T$', 'Interpreter','latex');
    title(titleText, 'Interpreter','latex');
    legend('Location','best', 'Interpreter','latex');

end

exportgraphics(fig, fullfile(figpath, '01_Ct_vs_RPMused_single_powertrains.png'), ...
    'Resolution', 300);

%% ===================== PLOT 02: Ct MEAN =======================

fig = figure('Color','w','Name','Ct vs RPMused - mean case');
hold on; grid on; box on;

if ~isempty(SR_MEAN_curve)
    plot(SR_MEAN_curve.RPM_used, SR_MEAN_curve.Ct, '-ok', ...
        'LineWidth', 1.8, ...
        'MarkerFaceColor','k', ...
        'DisplayName','SR mean');
end

for isr = 1:numel(sR_values)

    sR = sR_values(isr);

    DR_mean_curve = DR_MEAN_curves(DR_MEAN_curves.s_over_R == sR, :);

    if isempty(DR_mean_curve)
        continue;
    end

    plot(DR_mean_curve.RPM_used, DR_mean_curve.Ct, '--s', ...
        'LineWidth', 1.4, ...
        'MarkerSize', 6, ...
        'DisplayName', sprintf('DR mean, s/R = %.3g', sR));

end

xlabel('$RPM_{used}$', 'Interpreter','latex');
ylabel('$C_T$', 'Interpreter','latex');
title('$C_T$ vs $RPM_{used}$ - mean case', 'Interpreter','latex');
legend('Location','best', 'Interpreter','latex');

exportgraphics(fig, fullfile(figpath, '02_Ct_vs_RPMused_mean_case.png'), ...
    'Resolution', 300);

%% ===================== PLOT 03: Ct EXACT COMPARISON ===========

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
    idxType = comparison_exact.comparisonType == type;

    sR_here = unique(comparison_exact.s_over_R(idxType));
    sR_here = sort(sR_here(isfinite(sR_here)));

    for isr = 1:numel(sR_here)

        sR = sR_here(isr);

        idx = idxType & comparison_exact.s_over_R == sR;

        x = comparison_exact.RPM_common(idx);
        ySR = comparison_exact.Ct_SR(idx);
        yDR = comparison_exact.Ct_DR(idx);

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

exportgraphics(fig, fullfile(figpath, '03_Ct_SR_DR_exactRPM.png'), ...
    'Resolution', 300);

%% ===================== PLOT 04: Delta Ct vs RPM ===============

fig = figure('Color','w','Name','Delta Ct exact RPM vs RPM');
tiledlayout(3,1,'Padding','compact','TileSpacing','compact');

titles = [
    "$\Delta C_T$ exact RPM - PW1/R1"
    "$\Delta C_T$ exact RPM - PW2/R2"
    "$\Delta C_T$ exact RPM - MEAN"
];

for itype = 1:numel(types)

    nexttile;
    hold on; grid on; box on;

    type = types(itype);
    idxType = comparison_exact.comparisonType == type;

    sR_here = unique(comparison_exact.s_over_R(idxType));
    sR_here = sort(sR_here(isfinite(sR_here)));

    for isr = 1:numel(sR_here)

        sR = sR_here(isr);

        idx = idxType & comparison_exact.s_over_R == sR;

        x = comparison_exact.RPM_common(idx);
        y = comparison_exact.dCt_percent(idx);

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

exportgraphics(fig, fullfile(figpath, '04_DeltaCt_exactRPM_vs_RPM.png'), ...
    'Resolution', 300);

%% ===================== PLOT 05: Delta Ct vs s/R ===============

fig = figure('Color','w','Name','Delta Ct exact RPM vs s/R');
tiledlayout(3,1,'Padding','compact','TileSpacing','compact');

titles = [
    "$\Delta C_T$ exact RPM vs $s/R$ - PW1/R1"
    "$\Delta C_T$ exact RPM vs $s/R$ - PW2/R2"
    "$\Delta C_T$ exact RPM vs $s/R$ - MEAN"
];

for itype = 1:numel(types)

    nexttile;
    hold on; grid on; box on;

    type = types(itype);
    idxType = comparison_exact.comparisonType == type;

    rpmTargets = unique(comparison_exact.RPM_target(idxType));
    rpmTargets = sort(rpmTargets(isfinite(rpmTargets)));

    for irpm = 1:numel(rpmTargets)

        rpmT = rpmTargets(irpm);

        idx = idxType & comparison_exact.RPM_target == rpmT;

        x = comparison_exact.s_over_R(idx);
        y = comparison_exact.dCt_percent(idx);

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

exportgraphics(fig, fullfile(figpath, '05_DeltaCt_exactRPM_vs_sR.png'), ...
    'Resolution', 300);

%% ===================== PLOTS 06-08: Selected types ============

selectedTypes = ["PW1", "PW2", "MEAN"];
fileNums = [6 7 8];

for itype = 1:numel(selectedTypes)

    selectedType = selectedTypes(itype);

    fig = figure('Color','w','Name',sprintf('Delta Ct exact RPM %s', selectedType));
    hold on; grid on; box on;

    idxType = comparison_exact.comparisonType == selectedType;

    sR_here = unique(comparison_exact.s_over_R(idxType));
    sR_here = sort(sR_here(isfinite(sR_here)));

    for isr = 1:numel(sR_here)

        sR = sR_here(isr);

        idx = idxType & comparison_exact.s_over_R == sR;

        x = comparison_exact.RPM_common(idx);
        y = comparison_exact.dCt_percent(idx);

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
    title(sprintf('$\\Delta C_T$ exact RPM - %s', selectedType), ...
        'Interpreter','latex');
    legend('Location','best', 'Interpreter','latex');

    outName = sprintf('%02d_DeltaCt_exactRPM_%s_vs_RPM.png', ...
        fileNums(itype), char(selectedType));

    exportgraphics(fig, fullfile(figpath, outName), 'Resolution', 300);

end

%% ===================== PLOT 09: Reynolds ======================

fig = figure('Color','w','Name','Reynolds vs RPM');
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

exportgraphics(fig, fullfile(figpath, '09_Reynolds_vs_RPMcommon.png'), ...
    'Resolution', 300);

disp('Exact-RPM single-ramp SR/DR analysis completed.');

%% FUNZIONI
function T = readDatabaseCSV(fpath)

    opts = detectImportOptions(fpath, 'TextType','string');

    stringVars = { ...
        'filename', ...
        'basename', ...
        'basename_1', ...
        'basename_2', ...
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

    for k = 1:numel(stringVars)
        var = stringVars{k};
        if ismember(var, T.Properties.VariableNames)
            T.(var) = string(T.(var));
        end
    end

end

function x = getnum(T, i, varName)

    if ~ismember(varName, T.Properties.VariableNames)
        x = NaN;
        return;
    end

    v = T.(varName);

    if iscell(v)
        x = str2double(string(v{i}));
    elseif isstring(v)
        x = str2double(v(i));
    elseif iscategorical(v)
        x = str2double(string(v(i)));
    elseif islogical(v)
        x = double(v(i));
    else
        x = v(i);
    end

    if isempty(x)
        x = NaN;
    end

end

function s = getstr(T, i, varName)

    if ~ismember(varName, T.Properties.VariableNames)
        s = "";
        return;
    end

    v = T.(varName);

    if iscell(v)
        s = string(v{i});
    else
        s = string(v(i));
    end

end

function x = getFirstNum(T, i, varNames)

    x = NaN;

    for k = 1:numel(varNames)

        candidate = getnum(T, i, varNames{k});

        if isfinite(candidate)
            x = candidate;
            return;
        end

    end

end

function m = meanOmitNaN(x)

    m = mean(x, 'omitnan');

end

function val = getAtTarget(T, rpmTarget, varName)

    val = NaN;

    if isempty(T) || ~ismember(varName, T.Properties.VariableNames)
        return;
    end

    idx = T.RPM_target == rpmTarget;

    if any(idx)
        val = mean(T.(varName)(idx), 'omitnan');
    end

end

function curve = cleanCurve(T)

    if isempty(T)
        curve = table();
        return;
    end

    neededVars = {'RPM_target','RPM_used','Ct','Cq','T_N','Q_Nm','P_W'};

    for k = 1:numel(neededVars)
        var = neededVars{k};
        if ~ismember(var, T.Properties.VariableNames)
            T.(var) = NaN(height(T),1);
        end
    end

    valid = isfinite(T.RPM_used) & isfinite(T.Ct);
    T = T(valid,:);

    if isempty(T)
        curve = table();
        return;
    end

    T = sortrows(T, 'RPM_used');

    [rpmUnique, ~, G] = unique(T.RPM_used);

    curve = table();
    curve.RPM_used = rpmUnique;
    curve.RPM_target = splitapply(@meanOmitNaN, T.RPM_target, G);
    curve.Ct = splitapply(@meanOmitNaN, T.Ct, G);
    curve.Cq = splitapply(@meanOmitNaN, T.Cq, G);
    curve.T_N = splitapply(@meanOmitNaN, T.T_N, G);
    curve.Q_Nm = splitapply(@meanOmitNaN, T.Q_Nm, G);
    curve.P_W = splitapply(@meanOmitNaN, T.P_W, G);

end

function curve = makeMeanCurve(T1, T2)

    if isempty(T1) && isempty(T2)
        curve = table();
        return;
    end

    targets = unique([T1.RPM_target; T2.RPM_target]);
    targets = sort(targets(isfinite(targets)));

    RPM_target = [];
    RPM_used = [];
    Ct = [];
    Cq = [];
    T_N = [];
    Q_Nm = [];
    P_W = [];

    for i = 1:numel(targets)

        rpmT = targets(i);

        RPM_target(end+1,1) = rpmT;

        RPM_used(end+1,1) = meanOmitNaN([
            getAtTarget(T1, rpmT, 'RPM_used')
            getAtTarget(T2, rpmT, 'RPM_used')]);

        Ct(end+1,1) = meanOmitNaN([
            getAtTarget(T1, rpmT, 'Ct')
            getAtTarget(T2, rpmT, 'Ct')]);

        Cq(end+1,1) = meanOmitNaN([
            getAtTarget(T1, rpmT, 'Cq')
            getAtTarget(T2, rpmT, 'Cq')]);

        T_N(end+1,1) = meanOmitNaN([
            getAtTarget(T1, rpmT, 'T_N')
            getAtTarget(T2, rpmT, 'T_N')]);

        Q_Nm(end+1,1) = meanOmitNaN([
            getAtTarget(T1, rpmT, 'Q_Nm')
            getAtTarget(T2, rpmT, 'Q_Nm')]);

        P_W(end+1,1) = meanOmitNaN([
            getAtTarget(T1, rpmT, 'P_W')
            getAtTarget(T2, rpmT, 'P_W')]);

    end

    curve = table(RPM_target, RPM_used, Ct, Cq, T_N, Q_Nm, P_W);
    curve = cleanCurve(curve);

end

function val = interpVal(curve, rpm, varName, interpMethod)

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
        end
        return;
    end

    if rpm < min(x) || rpm > max(x)
        return;
    end

    val = interp1(x, y, rpm, interpMethod, NaN);

end

function row = makeComparisonRow( ...
    comparisonType, powertrainID, sR, rpmTarget, ...
    rpmSR_nom, rpmDR_nom, ...
    SR_curve, DR_curve, interpMethod, R, nu)

    rpmCommon = 0.5*(rpmSR_nom + rpmDR_nom);

    Ct_SR = interpVal(SR_curve, rpmCommon, 'Ct', interpMethod);
    Ct_DR = interpVal(DR_curve, rpmCommon, 'Ct', interpMethod);

    Cq_SR = interpVal(SR_curve, rpmCommon, 'Cq', interpMethod);
    Cq_DR = interpVal(DR_curve, rpmCommon, 'Cq', interpMethod);

    T_SR_N = interpVal(SR_curve, rpmCommon, 'T_N', interpMethod);
    T_DR_N = interpVal(DR_curve, rpmCommon, 'T_N', interpMethod);

    Q_SR_Nm = interpVal(SR_curve, rpmCommon, 'Q_Nm', interpMethod);
    Q_DR_Nm = interpVal(DR_curve, rpmCommon, 'Q_Nm', interpMethod);

    P_SR_W = interpVal(SR_curve, rpmCommon, 'P_W', interpMethod);
    P_DR_W = interpVal(DR_curve, rpmCommon, 'P_W', interpMethod);

    Omega = 2*pi*rpmCommon/60;
    Re_R = Omega * R^2 / nu;

    row = table();

    row.comparisonType = string(comparisonType);
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
    row.dP_W = P_SR_W - P_DR_W;
    row.dP_percent = percentLoss(P_SR_W, P_DR_W);

    row.Re_R = Re_R;

end

function p = percentLoss(SR, DR)

    if ~isfinite(SR) || ~isfinite(DR) || SR == 0
        p = NaN;
    else
        p = 100 * (SR - DR) / SR;
    end

end

function T = appendCompatible(T, row)

    if isempty(row)
        return;
    end

    if isempty(T)
        T = row;
        return;
    end

    varsT = T.Properties.VariableNames;
    varsR = row.Properties.VariableNames;

    allVars = unique([varsT, varsR], 'stable');

    for k = 1:numel(allVars)

        var = allVars{k};

        if ~ismember(var, T.Properties.VariableNames)
            T.(var) = makeMissingLike(row.(var), height(T));
        end

        if ~ismember(var, row.Properties.VariableNames)
            row.(var) = makeMissingLike(T.(var), height(row));
        end

    end

    T = T(:, allVars);
    row = row(:, allVars);

    T = [T; row];

end

function x = makeMissingLike(ref, n)

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