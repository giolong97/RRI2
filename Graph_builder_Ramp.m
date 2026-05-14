%  ANALISI DATABASE SR/DR, codice da usare con database_builder_Ramp
%  - Lettura solo file singoli
%  - Verifica drift up/down
%  - Media finale tra rampa crescente e decrescente
%  - Confronto SR vs DR
%  - Delta Ct e Cq vs RPM e vs s/R
%  - Reynolds number vs RPM

clear; close all; clc;

%% Input

basepath = 'E:\APC_Prove\16x10\Analisi\database_04_05_26_pt2\';

% ============================================================
% Qui scegli quali MP leggere, mantenendo questo ordine:
%
% 1  = E_SR_up_mot2
% 2  = E_SR_dw_mot2
% 3  = EP_SR_up_mot1
% 4  = EP_SR_dw_mot1
% 5  = DR_up_sR1
% 6  = DR_dw_sR1
% 7  = DR_up_sR2
% 8  = DR_dw_sR2
% 9  = DR_up_sR3
% 10 = DR_dw_sR3
% ...
%
% Metti 0 se vuoi saltare quella specifica posizione/prova.
% Es: MP_numbers = [1 2 3 4 5 6 7 8 0 10 11 12]; 
% ============================================================

MP_numbers = [220 222 223 224 225 226 227 228 229 0 231 232];

% Valori di s/R nell'ordine delle coppie DR:
% coppia 1 -> DR_up_sR1, DR_dw_sR1
% coppia 2 -> DR_up_sR2, DR_dw_sR2
% ecc.
DR_sR_values = [2 5 10 20];   

inputDB = buildMPInputTableFromOrder(MP_numbers, DR_sR_values);

outpath = fullfile(basepath, 'Confronto_SR_DR');

if ~exist(outpath, 'dir')
    mkdir(outpath);
end

rho = 1.225;          % [kg/m^3]
D   = 16*0.0254;      % [m]
R   = D/2;            % [m]

T_C = 23.2;           % [C]
Tair = T_C + 273.15 ; % [K]

% Sutherland law
mu0 = 1.716e-5;       % [Pa s]
T0  = 273.15;         % [K]
S   = 110.4;          % [K]

mu = mu0 * (Tair/T0)^(3/2) * (T0 + S)/(Tair + S);
nu = mu/rho;

% RPM range
rpmTargetsUp = [1000 1500 2000 2500 3000 3500 4000 4500 4900];

rpmMin = min(rpmTargetsUp);
rpmMax = max(rpmTargetsUp);

showUncertaintyBands = false;   % true = mostra bande, false = solo curve
uncertaintyBandAlpha = 0.18;   % trasparenza bande

%% DATABASE

DB_all = loadSelectedMPDatabaseFilesFromInputTable(basepath, inputDB);

DB_E_SR  = DB_all(DB_all.ConditionName == "E_SR",  :);
DB_EP_SR = DB_all(DB_all.ConditionName == "EP_SR", :);
DB_DR    = DB_all(DB_all.ConditionName == "DR",    :);

fprintf('\nSelected MP database files loaded:\n');
fprintf('  Total rows : %d\n', height(DB_all));
fprintf('  E_SR rows  : %d\n', height(DB_E_SR));
fprintf('  EP_SR rows : %d\n', height(DB_EP_SR));
fprintf('  DR rows    : %d\n', height(DB_DR));

disp(groupsummary(DB_all, "ConditionName"));
disp(groupsummary(DB_all, "DirectionLabel"));

E_SR_raw  = extractSingleRotorData(DB_E_SR,  "E_SR");
EP_SR_raw = extractSingleRotorData(DB_EP_SR, "EP_SR");

DR_raw = extractDoubleRotorData(DB_DR);
%% MEDIE UP E DW

% Qui semplicemente ordino le medie per up e dw e per rpm

E_SR_dir  = aggregateByKeys(E_SR_raw,  {'condition','DirectionLabel','RPM_target'});
EP_SR_dir = aggregateByKeys(EP_SR_raw, {'condition','DirectionLabel','RPM_target'});

DR_dir = aggregateByKeys(DR_raw, {'s_over_R','rotorID','DirectionLabel','RPM_target'});

% Definiamo un drift come ad esempio: 
% drift [%] = 100 * (up - down) / mean(up, down)

drift_E_SR  = buildDriftTable(E_SR_dir,  {'condition','RPM_target'});
drift_EP_SR = buildDriftTable(EP_SR_dir, {'condition','RPM_target'});

drift_DR = buildDriftTable(DR_dir, {'s_over_R','rotorID','RPM_target'});

%% VALORI MEDI UP E DW
% Media tra rampa crescente e decrescente. Cosi do ad up e down hanno lo stesso peso.

E_SR_mean  = averageDirections(E_SR_dir,  {'condition','RPM_target'});
EP_SR_mean = averageDirections(EP_SR_dir, {'condition','RPM_target'});

DR_mean = averageDirections(DR_dir, {'s_over_R','rotorID','RPM_target'});

%% SR
% Costruisco il caso SR come media tra SR_E e SR_EP

rpmAll = unique([
    E_SR_mean.RPM_target
    EP_SR_mean.RPM_target
    DR_mean.RPM_target
]);

rpmAll = sort(rpmAll);

SR = table();
SR.RPM = rpmAll;

SR.Ct_E_SR  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.Ct_mean, rpmAll);
SR.Ct_EP_SR = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.Ct_mean, rpmAll);

SR.Cq_E_SR  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.Cq_mean, rpmAll);
SR.Cq_EP_SR = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.Cq_mean, rpmAll);

SR.T_E_SR_N  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.T_N_mean, rpmAll);
SR.T_EP_SR_N = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.T_N_mean, rpmAll);

SR.Q_E_SR_Nm  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.Q_abs_Nm_mean, rpmAll);
SR.Q_EP_SR_Nm = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.Q_abs_Nm_mean, rpmAll);

SR.Ct_E_SR_std  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.Ct_std, rpmAll);
SR.Ct_EP_SR_std = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.Ct_std, rpmAll);

SR.Cq_E_SR_std  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.Cq_std, rpmAll);
SR.Cq_EP_SR_std = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.Cq_std, rpmAll);

SR.T_E_SR_std_N  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.T_N_std, rpmAll);
SR.T_EP_SR_std_N = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.T_N_std, rpmAll);

SR.Q_E_SR_std_Nm  = mapToRPM(E_SR_mean.RPM_target,  E_SR_mean.Q_abs_Nm_std, rpmAll);
SR.Q_EP_SR_std_Nm = mapToRPM(EP_SR_mean.RPM_target, EP_SR_mean.Q_abs_Nm_std, rpmAll);

% SR come media tra E ed EP

SR.Ct_SR_ref = rowMeanOmitNaN([SR.Ct_E_SR, SR.Ct_EP_SR]);
SR.Cq_SR_ref = rowMeanOmitNaN([SR.Cq_E_SR, SR.Cq_EP_SR]);

SR.T_SR_ref_N  = rowMeanOmitNaN([SR.T_E_SR_N, SR.T_EP_SR_N]);
SR.Q_SR_ref_Nm = rowMeanOmitNaN([SR.Q_E_SR_Nm, SR.Q_EP_SR_Nm]);

% media delle std di E_SR ed EP_SR
SR.Ct_SR_ref_std = rowMeanOmitNaN([SR.Ct_E_SR_std, SR.Ct_EP_SR_std]);
SR.Cq_SR_ref_std = rowMeanOmitNaN([SR.Cq_E_SR_std, SR.Cq_EP_SR_std]);

SR.T_SR_ref_std_N  = rowMeanOmitNaN([SR.T_E_SR_std_N, SR.T_EP_SR_std_N]);
SR.Q_SR_ref_std_Nm = rowMeanOmitNaN([SR.Q_E_SR_std_Nm, SR.Q_EP_SR_std_Nm]);

%% DR

sR_values = unique(DR_mean.s_over_R);
sR_values = sR_values(~isnan(sR_values));
sR_values = sort(sR_values);

% Confronto SR/DR interpolato a RPM comune effettivo.
% RPM_common = 0.5*(RPM_SR_used_nominal + RPM_DR_used_nominal)
comparison_exactRPM = buildExactRPMComparison( ...
    E_SR_mean, EP_SR_mean, DR_mean, sR_values);

comparison = table();

for isr = 1:numel(sR_values)

    sR = sR_values(isr);

    DR_sR = DR_mean(DR_mean.s_over_R == sR, :);

    for irpm = 1:numel(rpmAll)

        rpm = rpmAll(irpm);

        row = table();

        row.s_over_R = sR;
        row.RPM = rpm;

        % SR di riferimento globale
        row.Ct_SR_ref = SR.Ct_SR_ref(SR.RPM == rpm);
        row.Cq_SR_ref = SR.Cq_SR_ref(SR.RPM == rpm);
        row.T_SR_ref_N = SR.T_SR_ref_N(SR.RPM == rpm);
        row.Q_SR_ref_Nm = SR.Q_SR_ref_Nm(SR.RPM == rpm);

        row.Ct_SR_ref_std = SR.Ct_SR_ref_std(SR.RPM == rpm);
        row.Cq_SR_ref_std = SR.Cq_SR_ref_std(SR.RPM == rpm);
        row.T_SR_ref_std_N = SR.T_SR_ref_std_N(SR.RPM == rpm);
        row.Q_SR_ref_std_Nm = SR.Q_SR_ref_std_Nm(SR.RPM == rpm);

        % SR per singolo powertrain, dove considero
        %  EP_SR = powertrain 1
        %  E_SR  = powertrain 2

        row.Ct_SR_PW1 = SR.Ct_EP_SR(SR.RPM == rpm);
        row.Cq_SR_PW1 = SR.Cq_EP_SR(SR.RPM == rpm);
        row.T_SR_PW1_N = SR.T_EP_SR_N(SR.RPM == rpm);
        row.Q_SR_PW1_Nm = SR.Q_EP_SR_Nm(SR.RPM == rpm);

        row.Ct_SR_PW1_std = SR.Ct_EP_SR_std(SR.RPM == rpm);
        row.Cq_SR_PW1_std = SR.Cq_EP_SR_std(SR.RPM == rpm);
        row.T_SR_PW1_std_N = SR.T_EP_SR_std_N(SR.RPM == rpm);
        row.Q_SR_PW1_std_Nm = SR.Q_EP_SR_std_Nm(SR.RPM == rpm);

        row.Ct_SR_PW2 = SR.Ct_E_SR(SR.RPM == rpm);
        row.Cq_SR_PW2 = SR.Cq_E_SR(SR.RPM == rpm);
        row.T_SR_PW2_N = SR.T_E_SR_N(SR.RPM == rpm);
        row.Q_SR_PW2_Nm = SR.Q_E_SR_Nm(SR.RPM == rpm);

        row.Ct_SR_PW2_std = SR.Ct_E_SR_std(SR.RPM == rpm);
        row.Cq_SR_PW2_std = SR.Cq_E_SR_std(SR.RPM == rpm);
        row.T_SR_PW2_std_N = SR.T_E_SR_std_N(SR.RPM == rpm);
        row.Q_SR_PW2_std_Nm = SR.Q_E_SR_std_Nm(SR.RPM == rpm);
        
        % DR - rotore 1
        row.Ct_DR_R1 = getValueByKey(DR_sR, rpm, 1, 'Ct_mean');
        row.Cq_DR_R1 = getValueByKey(DR_sR, rpm, 1, 'Cq_mean');
        row.T_DR_R1_N = getValueByKey(DR_sR, rpm, 1, 'T_N_mean');
        row.Q_DR_R1_Nm = getValueByKey(DR_sR, rpm, 1, 'Q_abs_Nm_mean');

        row.Ct_DR_R1_std = getValueByKey(DR_sR, rpm, 1, 'Ct_std');
        row.Cq_DR_R1_std = getValueByKey(DR_sR, rpm, 1, 'Cq_std');
        row.T_DR_R1_std_N = getValueByKey(DR_sR, rpm, 1, 'T_N_std');
        row.Q_DR_R1_std_Nm = getValueByKey(DR_sR, rpm, 1, 'Q_abs_Nm_std');

        % DR- rotore 2
        row.Ct_DR_R2 = getValueByKey(DR_sR, rpm, 2, 'Ct_mean');
        row.Cq_DR_R2 = getValueByKey(DR_sR, rpm, 2, 'Cq_mean');
        row.T_DR_R2_N = getValueByKey(DR_sR, rpm, 2, 'T_N_mean');
        row.Q_DR_R2_Nm = getValueByKey(DR_sR, rpm, 2, 'Q_abs_Nm_mean');

        row.Ct_DR_R2_std = getValueByKey(DR_sR, rpm, 2, 'Ct_std');
        row.Cq_DR_R2_std = getValueByKey(DR_sR, rpm, 2, 'Cq_std');
        row.T_DR_R2_std_N = getValueByKey(DR_sR, rpm, 2, 'T_N_std');
        row.Q_DR_R2_std_Nm = getValueByKey(DR_sR, rpm, 2, 'Q_abs_Nm_std');

        % DR medio per rotore singolo
        row.Ct_DR_meanRotor = mean([row.Ct_DR_R1, row.Ct_DR_R2], 'omitnan');
        row.Cq_DR_meanRotor = mean([row.Cq_DR_R1, row.Cq_DR_R2], 'omitnan');
        row.T_DR_meanRotor_N = mean([row.T_DR_R1_N, row.T_DR_R2_N], 'omitnan');
        row.Q_DR_meanRotor_Nm = mean([row.Q_DR_R1_Nm, row.Q_DR_R2_Nm], 'omitnan');

        row.Ct_DR_meanRotor_std = stdMeanOmitNaN([row.Ct_DR_R1_std, row.Ct_DR_R2_std]);
        row.Cq_DR_meanRotor_std = stdMeanOmitNaN([row.Cq_DR_R1_std, row.Cq_DR_R2_std]);
        row.T_DR_meanRotor_std_N = stdMeanOmitNaN([row.T_DR_R1_std_N, row.T_DR_R2_std_N]);
        row.Q_DR_meanRotor_std_Nm = stdMeanOmitNaN([row.Q_DR_R1_std_Nm, row.Q_DR_R2_std_Nm]);

        % DR totale
        row.Ct_DR_total = sum([row.Ct_DR_R1, row.Ct_DR_R2], 'omitnan');
        row.Cq_DR_total = sum([row.Cq_DR_R1, row.Cq_DR_R2], 'omitnan');
        row.T_DR_total_N = sum([row.T_DR_R1_N, row.T_DR_R2_N], 'omitnan');
        row.Q_DR_total_Nm = sum([row.Q_DR_R1_Nm, row.Q_DR_R2_Nm], 'omitnan');

        row.Ct_DR_total_std = stdSumOmitNaN([row.Ct_DR_R1_std, row.Ct_DR_R2_std]);
        row.Cq_DR_total_std = stdSumOmitNaN([row.Cq_DR_R1_std, row.Cq_DR_R2_std]);
        row.T_DR_total_std_N = stdSumOmitNaN([row.T_DR_R1_std_N, row.T_DR_R2_std_N]);
        row.Q_DR_total_std_Nm = stdSumOmitNaN([row.Q_DR_R1_std_Nm, row.Q_DR_R2_std_Nm]);

        % Confronto tra DR medio rotore e SR riferimento globale
        row.dCt = row.Ct_SR_ref - row.Ct_DR_meanRotor;
        row.dCq = row.Cq_SR_ref- row.Cq_DR_meanRotor;
        row.dT_N = row.T_SR_ref_N - row.T_DR_meanRotor_N;
        row.dQ_Nm = row.Q_SR_ref_Nm - row.Q_DR_meanRotor_Nm;

        row.dCt_std = stdDiff(row.Ct_SR_ref_std, row.Ct_DR_meanRotor_std);
        row.dCq_std = stdDiff(row.Cq_SR_ref_std, row.Cq_DR_meanRotor_std);
        row.dT_std_N = stdDiff(row.T_SR_ref_std_N, row.T_DR_meanRotor_std_N);
        row.dQ_std_Nm = stdDiff(row.Q_SR_ref_std_Nm, row.Q_DR_meanRotor_std_Nm);

        row.dCt_percent = 100 * row.dCt / row.Ct_SR_ref;
        row.dCq_percent = 100 * row.dCq / row.Cq_SR_ref;
        row.dT_percent = 100 * row.dT_N / row.T_SR_ref_N;
        row.dQ_percent = 100 * row.dQ_Nm / row.Q_SR_ref_Nm;

       % Variazione percentuale delle fluttuazioni DR rispetto a SR globale
        row.dCt_fluct_percent = percentStdChange( ...
            row.Ct_DR_meanRotor_std, row.Ct_SR_ref_std);
        
        row.dCq_fluct_percent = percentStdChange( ...
            row.Cq_DR_meanRotor_std, row.Cq_SR_ref_std);
        
        row.dT_fluct_percent = percentStdChange( ...
            row.T_DR_meanRotor_std_N, row.T_SR_ref_std_N);
        
        row.dQ_fluct_percent = percentStdChange( ...
            row.Q_DR_meanRotor_std_Nm, row.Q_SR_ref_std_Nm);

        % Confronto per singolo Powertrain
        row.dCt_PW1 = row.Ct_SR_PW1 - row.Ct_DR_R1;
        row.dCq_PW1 = row.Cq_SR_PW1 - row.Cq_DR_R1;
        row.dT_PW1_N = row.T_SR_PW1_N - row.T_DR_R1_N;
        row.dQ_PW1_Nm = row.Q_SR_PW1_Nm - row.Q_DR_R1_Nm;

        row.dCt_PW1_std = stdDiff(row.Ct_DR_R1_std, row.Ct_SR_PW1_std);
        row.dCq_PW1_std = stdDiff(row.Cq_DR_R1_std, row.Cq_SR_PW1_std);
        row.dT_PW1_std_N = stdDiff(row.T_DR_R1_std_N, row.T_SR_PW1_std_N);
        row.dQ_PW1_std_Nm = stdDiff(row.Q_DR_R1_std_Nm, row.Q_SR_PW1_std_Nm);

        row.dCt_PW1_percent = 100 * row.dCt_PW1 / row.Ct_SR_PW1;
        row.dCq_PW1_percent = 100 * row.dCq_PW1 / row.Cq_SR_PW1;
        row.dT_PW1_percent = 100 * row.dT_PW1_N / row.T_SR_PW1_N;
        row.dQ_PW1_percent = 100 * row.dQ_PW1_Nm / row.Q_SR_PW1_Nm;

       % Variazione percentuale delle fluttuazioni DR rispetto a SR 
        row.dCt_fluct_percent_PW1 = percentStdChange( ...
            row.Ct_DR_R1_std, row.Ct_SR_PW1_std);
        
        row.dCq_fluct_percent_PW1 = percentStdChange( ...
            row.Cq_DR_R1_std, row.Cq_SR_PW1_std);
        
        row.dT_fluct_percent_PW1 = percentStdChange( ...
            row.T_DR_R1_std_N, row.T_SR_PW1_std_N);
        
        row.dQ_fluct_percent_PW1 = percentStdChange( ...
            row.Q_DR_R1_std_Nm, row.Q_SR_PW1_std_Nm);



        row.dCt_PW2 = row.Ct_SR_PW2 - row.Ct_DR_R2;
        row.dCq_PW2 = row.Cq_SR_PW2 - row.Cq_DR_R2;
        row.dT_PW2_N = row.T_SR_PW2_N - row.T_DR_R2_N;
        row.dQ_PW2_Nm = row.Q_SR_PW2_Nm - row.Q_DR_R2_Nm;

        row.dCt_PW2_std = stdDiff(row.Ct_DR_R2_std, row.Ct_SR_PW2_std);
        row.dCq_PW2_std = stdDiff(row.Cq_DR_R2_std, row.Cq_SR_PW2_std);
        row.dT_PW2_std_N = stdDiff(row.T_DR_R2_std_N, row.T_SR_PW2_std_N);
        row.dQ_PW2_std_Nm = stdDiff(row.Q_DR_R2_std_Nm, row.Q_SR_PW2_std_Nm);

        row.dCt_PW2_percent = 100 * row.dCt_PW2 / row.Ct_SR_PW2;
        row.dCq_PW2_percent = 100 * row.dCq_PW2 / row.Cq_SR_PW2;
        row.dT_PW2_percent = 100 * row.dT_PW2_N / row.T_SR_PW2_N;
        row.dQ_PW2_percent = 100 * row.dQ_PW2_Nm / row.Q_SR_PW2_Nm;

       % Variazione percentuale delle fluttuazioni DR rispetto a SR 
        row.dCt_fluct_percent_PW2 = percentStdChange( ...
            row.Ct_DR_R2_std, row.Ct_SR_PW2_std);
        
        row.dCq_fluct_percent_PW2 = percentStdChange( ...
            row.Cq_DR_R2_std, row.Cq_SR_PW2_std);
        
        row.dT_fluct_percent_PW2 = percentStdChange( ...
            row.T_DR_R2_std_N, row.T_SR_PW2_std_N);
        
        row.dQ_fluct_percent_PW2 = percentStdChange( ...
            row.Q_DR_R2_std_Nm, row.Q_SR_PW2_std_Nm);        

        % Confronto su DR totale e 2*SR_riferimento globale
        % Convenzione: positivo = perdita del DR totale rispetto a 2*SR
        
        row.dCt_total_percent = 100 * ...
            (2*row.Ct_SR_ref - row.Ct_DR_total) / (2*row.Ct_SR_ref);
        
        row.dCq_total_percent = 100 * ...
            (2*row.Cq_SR_ref - row.Cq_DR_total) / (2*row.Cq_SR_ref);
        
        row.dT_total_percent = 100 * ...
            (2*row.T_SR_ref_N - row.T_DR_total_N) / (2*row.T_SR_ref_N);
        
        row.dQ_total_percent = 100 * ...
            (2*row.Q_SR_ref_Nm - row.Q_DR_total_Nm) / (2*row.Q_SR_ref_Nm);

        
        %  Reynolds
        Omega = 2*pi*rpm/60;

        row.Re_R = Omega * R^2 / nu;

        comparison = [comparison; row];

    end

end


%% SALVATAGGIO RISULTATI

% Cartella figure
figpath = fullfile(outpath, 'Figures');

if ~exist(figpath, 'dir')
    mkdir(figpath);
end

% Tabelle di input e controllo
writetable(inputDB, fullfile(outpath, 'inputDB_used.csv'));

% Tabelle raw
writetable(E_SR_raw,  fullfile(outpath, 'E_SR_raw.csv'));
writetable(EP_SR_raw, fullfile(outpath, 'EP_SR_raw.csv'));
writetable(DR_raw,    fullfile(outpath, 'DR_raw.csv'));

% Tabelle per direzione
writetable(E_SR_dir,  fullfile(outpath, 'E_SR_dir.csv'));
writetable(EP_SR_dir, fullfile(outpath, 'EP_SR_dir.csv'));
writetable(DR_dir,    fullfile(outpath, 'DR_dir.csv'));

% Drift up/down
writetable(drift_E_SR,  fullfile(outpath, 'drift_E_SR.csv'));
writetable(drift_EP_SR, fullfile(outpath, 'drift_EP_SR.csv'));
writetable(drift_DR,    fullfile(outpath, 'drift_DR.csv'));

% Medie finali up/down
writetable(E_SR_mean,  fullfile(outpath, 'E_SR_mean_up_down.csv'));
writetable(EP_SR_mean, fullfile(outpath, 'EP_SR_mean_up_down.csv'));
writetable(DR_mean,    fullfile(outpath, 'DR_mean_up_down.csv'));

% SR reference e confronto finale
writetable(SR, fullfile(outpath, 'SR_reference.csv'));
writetable(comparison, fullfile(outpath, 'comparison_SR_DR_vs_sR.csv'));

writetable(comparison_exactRPM, fullfile(outpath, 'comparison_SR_DR_exactRPM.csv'));

% Salvataggio MATLAB completo
save(fullfile(outpath, 'analysis_SR_DR.mat'), ...
    'inputDB', 'DB_all', ...
    'SR', 'comparison', ...
    'E_SR_raw', 'EP_SR_raw', 'DR_raw', ...
    'E_SR_dir', 'EP_SR_dir', 'DR_dir', ...
    'E_SR_mean', 'EP_SR_mean', 'DR_mean', ...
    'drift_E_SR', 'drift_EP_SR', 'drift_DR', ...
    'rho', 'D', 'R', 'T_C', 'Tair', 'mu', 'nu', ...
    'rpmAll', 'sR_values','comparison_exactRPM');

disp('Tables saved.');

%% PLOT

figpath = fullfile(outpath, 'Figures');

if ~exist(figpath, 'dir')
    mkdir(figpath);
end

%% 1) E_SR: Ct up/down + drift
% plotSRUpDownAndDriftCt( ...
%     E_SR_dir, drift_E_SR, ...
%     'E\_SR', ...
%     fullfile(figpath, '01_E_SR_Ct_up_down_drift.png'), ...
%     showUncertaintyBands, uncertaintyBandAlpha);
%% 2) EP_SR: Ct up/down + drift
% plotSRUpDownAndDriftCt( ...
%     EP_SR_dir, drift_EP_SR, ...
%     'EP\_SR', ...
%     fullfile(figpath, '02_EP_SR_Ct_up_down_drift.png'), ...
%     showUncertaintyBands, uncertaintyBandAlpha);
%% 3) DR: Ct up/down + drift per rot 1 e rot 2
% plotDRRotorUpDownAndDriftCt( ...
%     DR_dir, drift_DR, 1, ...
%     fullfile(figpath, '03_DR_R1'), ...
%     showUncertaintyBands, uncertaintyBandAlpha);
% 
% plotDRRotorUpDownAndDriftCt( ...
%     DR_dir, drift_DR, 2, ...
%     fullfile(figpath, '04_DR_R2'), ...
%     showUncertaintyBands, uncertaintyBandAlpha);

%% 4) confronto SR-DR Ct su rotore pw1
plotSRvsDRPowertrain( ...
    SR, comparison, sR_values, ...
    1, "Ct", ...
    fullfile(figpath, '05_Ct_SR_PW1_vs_DR_R1.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);

%% 5) confronto SR-DR Cq su rotore pw1
plotSRvsDRPowertrain( ...
    SR, comparison, sR_values, ...
    1, "Cq", ...
    fullfile(figpath, '06_Cq_SR_PW1_vs_DR_R1.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);
%% 6) confronto SR-DR Ct su rotore pw2
plotSRvsDRPowertrain( ...
    SR, comparison, sR_values, ...
    2, "Ct", ...
    fullfile(figpath, '07_Ct_SR_PW2_vs_DR_R2.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);
%% 7) confronto SR-DR Cq su rotore pw2
plotSRvsDRPowertrain( ...
    SR, comparison, sR_values, ...
    2, "Cq", ...
    fullfile(figpath, '08_Cq_SR_PW2_vs_DR_R2.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);
%% 7b) Potenza calcolata Q*omega - PW1
plotPowerSRvsDRPowertrain( ...
    E_SR_mean, EP_SR_mean, DR_mean, sR_values, ...
    1, "P_Qomega", ...
    fullfile(figpath, '08b_P_Qomega_SR_PW1_vs_DR_R1.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);

%% 7c) Potenza calcolata Q*omega - PW2
plotPowerSRvsDRPowertrain( ...
    E_SR_mean, EP_SR_mean, DR_mean, sR_values, ...
    2, "P_Qomega", ...
    fullfile(figpath, '08c_P_Qomega_SR_PW2_vs_DR_R2.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);

%% 7d) Potenza meccanica da CSV - PW1
plotPowerSRvsDRPowertrain( ...
    E_SR_mean, EP_SR_mean, DR_mean, sR_values, ...
    1, "P_mech_csv", ...
    fullfile(figpath, '08d_P_mech_csv_SR_PW1_vs_DR_R1.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);

%% 7e) Potenza meccanica da CSV - PW2
plotPowerSRvsDRPowertrain( ...
    E_SR_mean, EP_SR_mean, DR_mean, sR_values, ...
    2, "P_mech_csv", ...
    fullfile(figpath, '08e_P_mech_csv_SR_PW2_vs_DR_R2.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);

%% 7f) Potenza elettrica da CSV - PW1
plotPowerSRvsDRPowertrain( ...
    E_SR_mean, EP_SR_mean, DR_mean, sR_values, ...
    1, "P_elec_csv", ...
    fullfile(figpath, '08f_P_elec_csv_SR_PW1_vs_DR_R1.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);

%% 7g) Potenza elettrica da CSV - PW2
plotPowerSRvsDRPowertrain( ...
    E_SR_mean, EP_SR_mean, DR_mean, sR_values, ...
    2, "P_elec_csv", ...
    fullfile(figpath, '08g_P_elec_csv_SR_PW2_vs_DR_R2.png'), ...
    showUncertaintyBands, uncertaintyBandAlpha);
%% 7h) Ct standard deviation per singolo powertrain

plotCtStdPowertrainVsSR( ...
    comparison, rpmAll, ...
    fullfile(figpath, '14_Ct_std_single_powertrain_vs_sR.png'));

% %% 8) confronto SR-DR in termini di Delta_Ct
% plotDeltaCtGlobalVsSR( ...
%     comparison, rpmAll, ...
%     fullfile(figpath, '09_Delta_Ct_global_vs_sR.png'));
% %% 8b) Delta Ct singolo powertrain: PW1
% plotDeltaCoeffPowertrainVsSR( ...
%     comparison, rpmAll, ...
%     1, "Ct", ...
%     fullfile(figpath, '10_Delta_Ct_PW1_vs_sR.png'));
% 
% %% 8c) Delta Ct singolo powertrain: PW2
% plotDeltaCoeffPowertrainVsSR( ...
%     comparison, rpmAll, ...
%     2, "Ct", ...
%     fullfile(figpath, '11_Delta_Ct_PW2_vs_sR.png'));
% 
% %% 8d) Delta Cq singolo powertrain: PW1
% plotDeltaCoeffPowertrainVsSR( ...
%     comparison, rpmAll, ...
%     1, "Cq", ...
%     fullfile(figpath, '12_Delta_Cq_PW1_vs_sR.png'));
% 
% %% 8e) Delta Cq singolo powertrain: PW2
% plotDeltaCoeffPowertrainVsSR( ...
%     comparison, rpmAll, ...
%     2, "Cq", ...
%     fullfile(figpath, '13_Delta_Cq_PW2_vs_sR.png'));
% %% 9) Reynolds
% 
% fig9 = figure('Color','w','Name','Reynolds vs RPM');
% hold on; grid on; box on;
% 
% Omega = 2*pi*rpmAll/60;
% Re_R = Omega * R^2 / nu;
% 
% plot(rpmAll, Re_R, '-o', ...
%     'LineWidth', 1.6, ...
%     'DisplayName','$Re_R = \Omega R^2/\nu$');
% 
% 
% xlabel('RPM');
% ylabel('Reynolds number', 'Interpreter','latex');
% title('Reynolds number', 'Interpreter','latex');
% legend('Location','best', 'Interpreter','latex');
% 
% exportgraphics(fig9, fullfile(figpath, 'Reynolds_vs_RPM.png'), 'Resolution', 300);
% 
% disp('Analysis completed.');
%% ============================================================
%  LOCAL FUNCTIONS
% =============================================================

function inputDB = buildMPInputTableFromOrder(MP_numbers, DR_sR_values)

    MP_numbers = MP_numbers(:);
    DR_sR_values = DR_sR_values(:);

    file = strings(0,1);
    condition = strings(0,1);
    direction = strings(0,1);
    s_over_R = [];
    activeSRPowertrain = [];
    role_index = [];
    MP_number = [];

    for i = 1:numel(MP_numbers)

        mp = MP_numbers(i);

        % Se metti 0, quella posizione viene saltata.
        if mp == 0
            continue;
        end

        if i == 1
            cond_i = "E_SR";
            dir_i  = "up";
            sR_i   = NaN;
            active_i = 2;

        elseif i == 2
            cond_i = "E_SR";
            dir_i  = "down";
            sR_i   = NaN;
            active_i = 2;

        elseif i == 3
            cond_i = "EP_SR";
            dir_i  = "up";
            sR_i   = NaN;
            active_i = 1;

        elseif i == 4
            cond_i = "EP_SR";
            dir_i  = "down";
            sR_i   = NaN;
            active_i = 1;

        else
            drSlot = i - 4;
            pairID = ceil(drSlot/2);

            if pairID > numel(DR_sR_values)
                error(['Not enough DR_sR_values. ', ...
                       'You need one s/R value for each DR up/down pair.']);
            end

            cond_i = "DR";
            sR_i = DR_sR_values(pairID);
            active_i = NaN;

            if mod(drSlot,2) == 1
                dir_i = "up";
            else
                dir_i = "down";
            end
        end

        file(end+1,1) = "MP_" + string(mp) + "_database.csv";
        condition(end+1,1) = cond_i;
        direction(end+1,1) = dir_i;
        s_over_R(end+1,1) = sR_i;
        activeSRPowertrain(end+1,1) = active_i;
        role_index(end+1,1) = i;
        MP_number(end+1,1) = mp;

    end

    inputDB = table(MP_number, role_index, file, condition, direction, ...
                    s_over_R, activeSRPowertrain);

end


function DB = loadSelectedMPDatabaseFilesFromInputTable(basepath, inputDB)

    if ~exist(basepath, 'dir')
        error('Folder not found: %s', basepath);
    end

    DB = table();

    for i = 1:height(inputDB)

        fname = string(inputDB.file(i));
        fpath = fullfile(basepath, fname);

        if ~isfile(fpath)
            error('Selected MP database file not found: %s', fpath);
        end

        fprintf('Reading selected MP database CSV: %s\n', fname);

        opts = detectImportOptions(fpath, 'TextType', 'string');

        % Forzo queste colonne come stringhe per evitare problemi
        % di concatenazione tra CSV diversi.
        stringVars = { ...
            'filename', ...
            'conf', ...
            'mode', ...
            'direction', ...
            'RPM1_used_source', ...
            'RPM2_used_source'};

        for k = 1:numel(stringVars)
            if ismember(stringVars{k}, opts.VariableNames)
                opts = setvartype(opts, stringVars{k}, 'string');
            end
        end

        T = readtable(fpath, opts);

        n = height(T);

        % Metadati assegnati dalla posizione nella lista MP_numbers
        T.SourceDBFile = repmat(fname, n, 1);
        T.MP_number = repmat(inputDB.MP_number(i), n, 1);
        T.role_index = repmat(inputDB.role_index(i), n, 1);

        T.ConditionName = repmat(string(inputDB.condition(i)), n, 1);
        T.DirectionLabel = repmat(string(inputDB.direction(i)), n, 1);
        T.s_over_R = repmat(inputDB.s_over_R(i), n, 1);

        % Per SR imposto anche activeSRPowertrain, se utile.
        % Se la colonna esiste già, la sovrascrivo solo se il valore input
        % non è NaN.
        if ~isnan(inputDB.activeSRPowertrain(i))
            T.activeSRPowertrain = repmat(inputDB.activeSRPowertrain(i), n, 1);
        end

        if isempty(DB)
            DB = T;
        else
            [DB, T] = makeTablesVertcatCompatible(DB, T);
            DB = [DB; T];
        end

    end

    if isempty(DB)
        error('No selected MP database files were loaded.');
    end

end


function [A, B] = makeTablesVertcatCompatible(A, B)

    A = normalizeRampDatabaseTable(A);
    B = normalizeRampDatabaseTable(B);

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

function T = normalizeRampDatabaseTable(T)

    stringVars = { ...
        'filename', ...
        'conf', ...
        'mode', ...
        'direction', ...
        'SourceDBFile', ...
        'ConditionName', ...
        'DirectionLabel', ...
        'RPM1_used_source', ...
        'RPM2_used_source'};

    for k = 1:numel(stringVars)

        var = stringVars{k};

        if ismember(var, T.Properties.VariableNames)
            T.(var) = string(T.(var));
        end

    end

end

function x = makeMissingColumnLike(ref, n)

    if isstring(ref)
        x = strings(n, 1);

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


function out = extractSingleRotorData(DB, conditionName)

    n = height(DB);

    condition = repmat(string(conditionName), n, 1);
    filename  = getStringColumn(DB, 'filename', n);
    sourceDB  = getStringColumn(DB, 'SourceDBFile', n);
    DirectionLabel = getStringColumn(DB, 'DirectionLabel', n);

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

    P_W = NaN(n,1);  % potenza calcolata come Q*omega

    P_mech_csv_W = NaN(n,1);
    std_P_mech_csv_W = NaN(n,1);

    P_elec_csv_W = NaN(n,1);
    std_P_elec_csv_W = NaN(n,1);

    RPM_mean = NaN(n,1);
    RPM_used = NaN(n,1);

    for i = 1:n

        active = getNumericValue(DB, i, 'activeSRPowertrain');

        Ct1 = getNumericValue(DB, i, 'Ct1');
        Ct2 = getNumericValue(DB, i, 'Ct2');

        if isnan(active)

            if ~isnan(Ct1) && isnan(Ct2)
                active = 1;
            elseif isnan(Ct1) && ~isnan(Ct2)
                active = 2;
            elseif ~isnan(Ct1) && ~isnan(Ct2)
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

            Q_abs_Nm(i) = getNumericValue(DB, i, 'Q1_abs_mean_Nm');
            std_Q_abs_Nm(i) = getNumericValue(DB, i, 'Q1_abs_std_Nm');

            P_W(i) = getNumericValue(DB, i, 'P1_mean_W');

            P_mech_csv_W(i) = getNumericValue(DB, i, 'P1_mech_csv_mean_W');
            std_P_mech_csv_W(i) = getNumericValue(DB, i, 'P1_mech_csv_std_W');

            P_elec_csv_W(i) = getNumericValue(DB, i, 'P1_elec_csv_mean_W');
            std_P_elec_csv_W(i) = getNumericValue(DB, i, 'P1_elec_csv_std_W');

            RPM_mean(i) = getNumericValue(DB, i, 'RPM1_mean');
            RPM_used(i) = getNumericValue(DB, i, 'RPM1_used');

        elseif active == 2

            Ct(i)       = getNumericValue(DB, i, 'Ct2');
            std_Ct(i)   = getNumericValue(DB, i, 'Ct2_std');

            Cq(i)       = getNumericValue(DB, i, 'Cq2');
            std_Cq(i)   = getNumericValue(DB, i, 'Cq2_std');

            T_N(i)      = getNumericValue(DB, i, 'T2_mean_N');
            std_TN(i)   = getNumericValue(DB, i, 'T2_std_N');

            Q_abs_Nm(i) = getNumericValue(DB, i, 'Q2_abs_mean_Nm');
            std_Q_abs_Nm(i) = getNumericValue(DB, i, 'Q2_abs_std_Nm');

            P_W(i) = getNumericValue(DB, i, 'P2_mean_W');

            P_mech_csv_W(i) = getNumericValue(DB, i, 'P2_mech_csv_mean_W');
            std_P_mech_csv_W(i) = getNumericValue(DB, i, 'P2_mech_csv_std_W');

            P_elec_csv_W(i) = getNumericValue(DB, i, 'P2_elec_csv_mean_W');
            std_P_elec_csv_W(i) = getNumericValue(DB, i, 'P2_elec_csv_std_W');

            RPM_mean(i) = getNumericValue(DB, i, 'RPM2_mean');
            RPM_used(i) = getNumericValue(DB, i, 'RPM2_used');

        end

    end

    out = table(condition, filename, sourceDB, DirectionLabel, RPM_target, rotorID, ...
        Ct, std_Ct, ...
        Cq, std_Cq, ...
        T_N, std_TN, ...
        Q_abs_Nm, std_Q_abs_Nm, ...
        P_W, ...
        P_mech_csv_W, std_P_mech_csv_W, ...
        P_elec_csv_W, std_P_elec_csv_W, ...
        RPM_mean, RPM_used);

end

function out = extractDoubleRotorData(DB)

    n = height(DB);

    condition = strings(2*n,1);
    filename  = strings(2*n,1);
    sourceDB  = strings(2*n,1);
    DirectionLabel = strings(2*n,1);

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

    P_mech_csv_W = NaN(2*n,1);
    std_P_mech_csv_W = NaN(2*n,1);

    P_elec_csv_W = NaN(2*n,1);
    std_P_elec_csv_W = NaN(2*n,1);

    RPM_mean = NaN(2*n,1);
    RPM_used = NaN(2*n,1);

    filenamesIn = getStringColumn(DB, 'filename', n);
    sourceIn    = getStringColumn(DB, 'SourceDBFile', n);
    directionIn = getStringColumn(DB, 'DirectionLabel', n);

    rpmIn = getNumericColumn(DB, 'RPM_target', n);
    sRin  = getNumericColumn(DB, 's_over_R', n);

    r = 0;

    for i = 1:n

        for rot = 1:2

            r = r + 1;

            condition(r) = "DR";
            filename(r) = filenamesIn(i);
            sourceDB(r) = sourceIn(i);
            DirectionLabel(r) = directionIn(i);

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

                Q_abs_Nm(r) = getNumericValue(DB, i, 'Q1_abs_mean_Nm');
                std_Q_abs_Nm(r) = getNumericValue(DB, i, 'Q1_abs_std_Nm');

                P_W(r) = getNumericValue(DB, i, 'P1_mean_W');

                P_mech_csv_W(r) = getNumericValue(DB, i, 'P1_mech_csv_mean_W');
                std_P_mech_csv_W(r) = getNumericValue(DB, i, 'P1_mech_csv_std_W');

                P_elec_csv_W(r) = getNumericValue(DB, i, 'P1_elec_csv_mean_W');
                std_P_elec_csv_W(r) = getNumericValue(DB, i, 'P1_elec_csv_std_W');

                RPM_mean(r) = getNumericValue(DB, i, 'RPM1_mean');
                RPM_used(r) = getNumericValue(DB, i, 'RPM1_used');

            else

                Ct(r)       = getNumericValue(DB, i, 'Ct2');
                std_Ct(r)   = getNumericValue(DB, i, 'Ct2_std');

                Cq(r)       = getNumericValue(DB, i, 'Cq2');
                std_Cq(r)   = getNumericValue(DB, i, 'Cq2_std');

                T_N(r)      = getNumericValue(DB, i, 'T2_mean_N');
                std_TN(r)   = getNumericValue(DB, i, 'T2_std_N');

                Q_abs_Nm(r) = getNumericValue(DB, i, 'Q2_abs_mean_Nm');
                std_Q_abs_Nm(r) = getNumericValue(DB, i, 'Q2_abs_std_Nm');

                P_W(r) = getNumericValue(DB, i, 'P2_mean_W');

                P_mech_csv_W(r) = getNumericValue(DB, i, 'P2_mech_csv_mean_W');
                std_P_mech_csv_W(r) = getNumericValue(DB, i, 'P2_mech_csv_std_W');

                P_elec_csv_W(r) = getNumericValue(DB, i, 'P2_elec_csv_mean_W');
                std_P_elec_csv_W(r) = getNumericValue(DB, i, 'P2_elec_csv_std_W');

                RPM_mean(r) = getNumericValue(DB, i, 'RPM2_mean');
                RPM_used(r) = getNumericValue(DB, i, 'RPM2_used');

            end

        end

    end

    out = table(condition, filename, sourceDB, DirectionLabel, s_over_R, ...
        RPM_target, rotorID, ...
        Ct, std_Ct, ...
        Cq, std_Cq, ...
        T_N, std_TN, ...
        Q_abs_Nm, std_Q_abs_Nm, ...
        P_W, ...
        P_mech_csv_W, std_P_mech_csv_W, ...
        P_elec_csv_W, std_P_elec_csv_W, ...
        RPM_mean, RPM_used);

end

function out = aggregateByKeys(T, keyVars)

    valid = ~isnan(T.RPM_target);
    T = T(valid,:);

    if isempty(T)
        out = table();
        return;
    end

    % Ordino prima i dati raw
    T = sortrows(T, keyVars);

    % Raggruppo solo per gestire eventuali duplicati.
    % Se non ci sono duplicati, questa funzione restituisce semplicemente
    % gli stessi valori, ma con nomi coerenti.
    [G, keyTable] = findgroups(T(:, keyVars));

    out = keyTable;

    % Valori medi della grandezza nel plateau/prova.
    % Se c'è una sola riga per gruppo, è identico al valore raw.
    out.Ct_mean = splitapply(@meanOmitNaN, T.Ct, G);
    out.Cq_mean = splitapply(@meanOmitNaN, T.Cq, G);

    out.T_N_mean = splitapply(@meanOmitNaN, T.T_N, G);
    out.Q_abs_Nm_mean = splitapply(@meanOmitNaN, T.Q_abs_Nm, G);

    out.P_W_mean = splitapply(@meanOmitNaN, T.P_W, G);
    out.P_mech_csv_W_mean = splitapply(@meanOmitNaN, T.P_mech_csv_W, G);
    out.P_elec_csv_W_mean = splitapply(@meanOmitNaN, T.P_elec_csv_W, G);

    out.RPM_mean = splitapply(@meanOmitNaN, T.RPM_mean, G);
    out.RPM_used = splitapply(@meanOmitNaN, T.RPM_used, G);

    % Deviazioni standard già calcolate dentro il database builder.
    % Non faccio std(std_Ct), ma trasporto/medio la std interna.
    out.Ct_std = splitapply(@meanOmitNaN, T.std_Ct, G);
    out.Cq_std = splitapply(@meanOmitNaN, T.std_Cq, G);

    out.T_N_std = splitapply(@meanOmitNaN, T.std_TN, G);
    out.Q_abs_Nm_std = splitapply(@meanOmitNaN, T.std_Q_abs_Nm, G);
    out.P_mech_csv_W_std = splitapply(@meanOmitNaN, T.std_P_mech_csv_W, G);
    out.P_elec_csv_W_std = splitapply(@meanOmitNaN, T.std_P_elec_csv_W, G);

    % Numero di righe/prove che finiscono nello stesso gruppo.
    % Se è sempre 1, vuol dire che non stai mediando repliche.
    out.N_cases = splitapply(@numel, T.RPM_target, G);

    % Riordino finale
    out = sortrows(out, keyVars);

end


function out = buildDriftTable(Tdir, keyVarsNoDirection)

    if isempty(Tdir)
        out = table();
        return;
    end

    [G, keyTable] = findgroups(Tdir(:, keyVarsNoDirection));

    out = keyTable;

    nG = height(keyTable);

    out.Ct_up = NaN(nG,1);
    out.Ct_down = NaN(nG,1);
    out.Ct_mean_updown = NaN(nG,1);
    out.Ct_drift_percent = NaN(nG,1);

    out.Cq_up = NaN(nG,1);
    out.Cq_down = NaN(nG,1);
    out.Cq_mean_updown = NaN(nG,1);
    out.Cq_drift_percent = NaN(nG,1);

    out.T_up_N = NaN(nG,1);
    out.T_down_N = NaN(nG,1);
    out.T_mean_updown_N = NaN(nG,1);
    out.T_drift_percent = NaN(nG,1);

    out.Q_up_Nm = NaN(nG,1);
    out.Q_down_Nm = NaN(nG,1);
    out.Q_mean_updown_Nm = NaN(nG,1);
    out.Q_drift_percent = NaN(nG,1);

    for ig = 1:nG

        rows = find(G == ig);

        upRow = rows(Tdir.DirectionLabel(rows) == "up");
        downRow = rows(Tdir.DirectionLabel(rows) == "down");

        if ~isempty(upRow)
            upRow = upRow(1);
            out.Ct_up(ig) = Tdir.Ct_mean(upRow);
            out.Cq_up(ig) = Tdir.Cq_mean(upRow);
            out.T_up_N(ig) = Tdir.T_N_mean(upRow);
            out.Q_up_Nm(ig) = Tdir.Q_abs_Nm_mean(upRow);
        end

        if ~isempty(downRow)
            downRow = downRow(1);
            out.Ct_down(ig) = Tdir.Ct_mean(downRow);
            out.Cq_down(ig) = Tdir.Cq_mean(downRow);
            out.T_down_N(ig) = Tdir.T_N_mean(downRow);
            out.Q_down_Nm(ig) = Tdir.Q_abs_Nm_mean(downRow);
        end

        out.Ct_mean_updown(ig) = mean([out.Ct_up(ig), out.Ct_down(ig)], 'omitnan');
        out.Cq_mean_updown(ig) = mean([out.Cq_up(ig), out.Cq_down(ig)], 'omitnan');
        out.T_mean_updown_N(ig) = mean([out.T_up_N(ig), out.T_down_N(ig)], 'omitnan');
        out.Q_mean_updown_Nm(ig) = mean([out.Q_up_Nm(ig), out.Q_down_Nm(ig)], 'omitnan');

        out.Ct_drift_percent(ig) = 100 * ...
            (out.Ct_up(ig) - out.Ct_down(ig)) / out.Ct_mean_updown(ig);

        out.Cq_drift_percent(ig) = 100 * ...
            (out.Cq_up(ig) - out.Cq_down(ig)) / out.Cq_mean_updown(ig);

        out.T_drift_percent(ig) = 100 * ...
            (out.T_up_N(ig) - out.T_down_N(ig)) / out.T_mean_updown_N(ig);

        out.Q_drift_percent(ig) = 100 * ...
            (out.Q_up_Nm(ig) - out.Q_down_Nm(ig)) / out.Q_mean_updown_Nm(ig);

    end

end

function out = averageDirections(Tdir, keyVarsNoDirection)

    if isempty(Tdir)
        out = table();
        return;
    end

    [G, keyTable] = findgroups(Tdir(:, keyVarsNoDirection));

    out = keyTable;

    % ============================================================
    % Valori medi tra up e down
    % ============================================================

    out.Ct_mean = splitapply(@meanOmitNaN, Tdir.Ct_mean, G);
    out.Cq_mean = splitapply(@meanOmitNaN, Tdir.Cq_mean, G);

    out.T_N_mean = splitapply(@meanOmitNaN, Tdir.T_N_mean, G);
    out.Q_abs_Nm_mean = splitapply(@meanOmitNaN, Tdir.Q_abs_Nm_mean, G);

    out.P_W_mean = splitapply(@meanOmitNaN, Tdir.P_W_mean, G);
    out.P_mech_csv_W_mean = splitapply(@meanOmitNaN, Tdir.P_mech_csv_W_mean, G);
    out.P_elec_csv_W_mean = splitapply(@meanOmitNaN, Tdir.P_elec_csv_W_mean, G);

    out.RPM_mean = splitapply(@meanOmitNaN, Tdir.RPM_mean, G);
    out.RPM_used = splitapply(@meanOmitNaN, Tdir.RPM_used, G);

    % ============================================================
    % Std medie dei plateau
    %
    % Queste sono le std già calcolate nel database_builder_Ramp
    % dentro ogni finestra temporale di plateau.
    %
    % Se ho up e down:
    %   Ct_std = mean(Ct_std_up, Ct_std_down)
    %
    % Se ho solo up o solo down:
    %   Ct_std = std di quella singola direzione
    % ============================================================

    out.Ct_std = splitapply(@meanOmitNaN, Tdir.Ct_std, G);
    out.Cq_std = splitapply(@meanOmitNaN, Tdir.Cq_std, G);

    out.T_N_std = splitapply(@meanOmitNaN, Tdir.T_N_std, G);
    out.Q_abs_Nm_std = splitapply(@meanOmitNaN, Tdir.Q_abs_Nm_std, G);
    out.P_mech_csv_W_std = splitapply(@meanOmitNaN, Tdir.P_mech_csv_W_std, G);
    out.P_elec_csv_W_std = splitapply(@meanOmitNaN, Tdir.P_elec_csv_W_std, G);

    % ============================================================
    % Numero di direzioni effettivamente usate
    %
    % Idealmente:
    %   N_directions = 2 -> up + down
    %   N_directions = 1 -> solo up oppure solo down
    % ============================================================

    out.N_directions = splitapply(@numel, Tdir.Ct_mean, G);

end

function y = mapToRPM(srcRPM, srcVal, rpmGrid)

    y = NaN(size(rpmGrid));

    for i = 1:numel(rpmGrid)

        idx = srcRPM == rpmGrid(i);

        if any(idx)
            y(i) = mean(srcVal(idx), 'omitnan');
        end

    end

end

function val = getValueByKey(T, rpm, rotorID, varName)

    idx = T.RPM_target == rpm & T.rotorID == rotorID;

    if any(idx)
        val = mean(T.(varName)(idx), 'omitnan');
    else
        val = NaN;
    end

end

function y = rowMeanOmitNaN(X)

    n = sum(~isnan(X), 2);
    y = sum(X, 2, 'omitnan') ./ n;
    y(n == 0) = NaN;

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

function x = getNumericValue(T, i, varName)

    if ismember(varName, T.Properties.VariableNames)

        value = T.(varName);

        if iscell(value)
            x = str2double(value{i});
        elseif isstring(value)
            x = str2double(value(i));
        elseif iscategorical(value)
            x = str2double(string(value(i)));
        else
            x = value(i);
        end

    else

        x = NaN;

    end

end


function s = stdDiff(s1, s2)

    vals = [s1, s2];
    vals = vals(~isnan(vals));

    if isempty(vals)
        s = NaN;
    else
        s = sqrt(sum(vals.^2));
    end

end


function s = stdSumOmitNaN(stdVals)

    stdVals = stdVals(~isnan(stdVals));

    if isempty(stdVals)
        s = NaN;
    else
        s = sqrt(sum(stdVals.^2));
    end

end

function s = stdMeanOmitNaN(stdVals)

    stdVals = stdVals(~isnan(stdVals));
    n = numel(stdVals);

    if n == 0
        s = NaN;
    elseif n == 1
        s = stdVals;
    else
        s = sqrt(sum(stdVals.^2)) / n;
    end

end

function plotDirectionCurve(T, directionLabel, varName, lineStyle, displayName)

    idx = T.DirectionLabel == directionLabel;

    if ~any(idx)
        return;
    end

    x = T.RPM_target(idx);
    y = T.(varName)(idx);

    % Ordino per RPM crescente per confrontare visivamente le curve.
    % La direzione fisica della prova resta indicata dalla legenda.
    [x, ord] = sort(x);
    y = y(ord);

    plot(x, y, lineStyle, ...
        'LineWidth', 1.5, ...
        'MarkerSize', 6, ...
        'DisplayName', displayName);

end

function plotDirectionCurveDR(T, rotorID, directionLabel, varName, lineStyle, displayName)

    idx = T.rotorID == rotorID & T.DirectionLabel == directionLabel;

    if ~any(idx)
        return;
    end

    x = T.RPM_target(idx);
    y = T.(varName)(idx);

    % Ordino per RPM crescente per avere le due curve sovrapposte
    % sullo stesso asse RPM.
    [x, ord] = sort(x);
    y = y(ord);

    plot(x, y, lineStyle, ...
        'LineWidth', 1.5, ...
        'MarkerSize', 6, ...
        'DisplayName', displayName);

end


function plotSRUpDownAndDriftCt(Tdir, driftTable, labelName, outFile, showUncertaintyBands, bandAlpha)

    if nargin < 5 || isempty(showUncertaintyBands)
        showUncertaintyBands = true;
    end

    if nargin < 6 || isempty(bandAlpha)
        bandAlpha = 0.18;
    end

    fig = figure('Color','w','Name',sprintf('%s Ct up/down drift', labelName));
    tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

    %% Ct up/down

    nexttile;
    hold on; grid on; box on;

    idxUp = Tdir.DirectionLabel == "up";
    plotBandLine( ...
        Tdir.RPM_target(idxUp), ...
        Tdir.Ct_mean(idxUp), ...
        Tdir.Ct_std(idxUp), ...
        '-o', ...
        sprintf('%s up', labelName), ...
        showUncertaintyBands, bandAlpha);

    idxDown = Tdir.DirectionLabel == "down";
    plotBandLine( ...
        Tdir.RPM_target(idxDown), ...
        Tdir.Ct_mean(idxDown), ...
        Tdir.Ct_std(idxDown), ...
        '-s', ...
        sprintf('%s down', labelName), ...
        showUncertaintyBands, bandAlpha);

    xlabel('RPM');
    ylabel('$C_T$', 'Interpreter','latex');

    if showUncertaintyBands
        title(sprintf('%s: $C_T$ up/down with plateau std', labelName), ...
            'Interpreter','latex');
    else
        title(sprintf('%s: $C_T$ up/down', labelName), ...
            'Interpreter','latex');
    end

    legend('Location','best', 'Interpreter','latex');

    %% Drift

    nexttile;
    hold on; grid on; box on;

    plot(driftTable.RPM_target, driftTable.Ct_drift_percent, '-o', ...
        'LineWidth', 1.5, ...
        'MarkerSize', 6, ...
        'DisplayName', sprintf('%s drift', labelName));

    yline(0, '--k', 'HandleVisibility','off');

    xlabel('RPM');
    ylabel('$C_T$ drift up/down [\%]', 'Interpreter','latex');
    title(sprintf('%s: $C_T$ drift', labelName), 'Interpreter','latex');
    legend('Location','best', 'Interpreter','latex');

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotDRRotorUpDownAndDriftCt(DR_dir, drift_DR, rotorID, outPrefix, showUncertaintyBands, bandAlpha)

    if nargin < 5 || isempty(showUncertaintyBands)
        showUncertaintyBands = true;
    end

    if nargin < 6 || isempty(bandAlpha)
        bandAlpha = 0.18;
    end

    sR_values = unique(DR_dir.s_over_R);
    sR_values = sR_values(~isnan(sR_values));
    sR_values = sort(sR_values);
    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        T = DR_dir(DR_dir.s_over_R == sR & DR_dir.rotorID == rotorID, :);
        D = drift_DR(drift_DR.s_over_R == sR & drift_DR.rotorID == rotorID, :);

        if isempty(T)
            continue;
        end

        fig = figure('Color','w', ...
            'Name', sprintf('DR R%d Ct up/down drift sR %.3g', rotorID, sR));

        tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

        %% Ct up/down

        nexttile;
        hold on; grid on; box on;

        idxUp = T.DirectionLabel == "up";
        plotBandLine( ...
            T.RPM_target(idxUp), ...
            T.Ct_mean(idxUp), ...
            T.Ct_std(idxUp), ...
            '-o', ...
            sprintf('DR rotor %d up', rotorID), ...
            showUncertaintyBands, bandAlpha);

        idxDown = T.DirectionLabel == "down";
        plotBandLine( ...
            T.RPM_target(idxDown), ...
            T.Ct_mean(idxDown), ...
            T.Ct_std(idxDown), ...
            '-s', ...
            sprintf('DR rotor %d down', rotorID), ...
            showUncertaintyBands, bandAlpha);

        xlabel('RPM');
        ylabel('$C_T$', 'Interpreter','latex');

        if showUncertaintyBands
            title(sprintf('DR rotor %d: $C_T$ up/down with plateau std, $s/R = %.3g$', ...
                rotorID, sR), 'Interpreter','latex');
        else
            title(sprintf('DR rotor %d: $C_T$ up/down, $s/R = %.3g$', ...
                rotorID, sR), 'Interpreter','latex');
        end

        legend('Location','best', 'Interpreter','latex');

        %% Drift

        nexttile;
        hold on; grid on; box on;

        plot(D.RPM_target, D.Ct_drift_percent, '-o', ...
            'LineWidth', 1.5, ...
            'MarkerSize', 6, ...
            'DisplayName', sprintf('DR rotor %d, s/R = %.3g', rotorID, sR));

        yline(0, '--k', 'HandleVisibility','off');

        xlabel('RPM');
        ylabel('$C_T$ drift up/down [\%]', 'Interpreter','latex');
        title(sprintf('DR rotor %d: $C_T$ drift, $s/R = %.3g$', ...
            rotorID, sR), 'Interpreter','latex');
        legend('Location','best', 'Interpreter','latex');

        outFile = sprintf('%s_sR_%g.png', outPrefix, sR);
        exportgraphics(fig, outFile, 'Resolution', 300);

    end

end

function plotSRvsDRPowertrain(SR, comparison, sR_values, powertrainID, coeffName, outFile, showUncertaintyBands, bandAlpha)

    if nargin < 7 || isempty(showUncertaintyBands)
        showUncertaintyBands = true;
    end

    if nargin < 8 || isempty(bandAlpha)
        bandAlpha = 0.18;
    end

    coeffName = string(coeffName);

    fig = figure('Color','w', ...
        'Name', sprintf('%s SR PW%d vs DR R%d', coeffName, powertrainID, powertrainID));

    hold on; grid on; box on;

    %% SR reference for the selected powertrain

    if powertrainID == 1

        % Assunzione: PW1 = EP_SR
        if coeffName == "Ct"
            srY = SR.Ct_EP_SR;
            srS = SR.Ct_EP_SR_std;
            yLabelText = '$C_T$';
            srLabel = 'SR PW1 = EP\_SR';
        else
            srY = SR.Cq_EP_SR;
            srS = SR.Cq_EP_SR_std;
            yLabelText = '$C_Q$';
            srLabel = 'SR PW1 = EP\_SR';
        end

        drMeanVar = sprintf('%s_DR_R1', coeffName);
        drStdVar  = sprintf('%s_DR_R1_std', coeffName);

    elseif powertrainID == 2

        % Assunzione: PW2 = E_SR
        if coeffName == "Ct"
            srY = SR.Ct_E_SR;
            srS = SR.Ct_E_SR_std;
            yLabelText = '$C_T$';
            srLabel = 'SR PW2 = E\_SR';
        else
            srY = SR.Cq_E_SR;
            srS = SR.Cq_E_SR_std;
            yLabelText = '$C_Q$';
            srLabel = 'SR PW2 = E\_SR';
        end

        drMeanVar = sprintf('%s_DR_R2', coeffName);
        drStdVar  = sprintf('%s_DR_R2_std', coeffName);

    else
        error('powertrainID must be 1 or 2.');
    end

    plotBandLine(SR.RPM, srY, srS, '-^', srLabel, ...
        showUncertaintyBands, bandAlpha);

    %% DR curves for each s/R

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        idx = comparison.s_over_R == sR;

        plotBandLine( ...
            comparison.RPM(idx), ...
            comparison.(drMeanVar)(idx), ...
            comparison.(drStdVar)(idx), ...
            '--o', ...
            sprintf('DR R%d, s/R = %.3g', powertrainID, sR), ...
            showUncertaintyBands, bandAlpha);

    end

    xlabel('RPM');
    ylabel(yLabelText, 'Interpreter','latex');

    if coeffName == "Ct"
        title(sprintf('$C_T$: SR powertrain %d vs DR rotor %d', ...
            powertrainID, powertrainID), 'Interpreter','latex');
    else
        title(sprintf('$C_Q$: SR powertrain %d vs DR rotor %d', ...
            powertrainID, powertrainID), 'Interpreter','latex');
    end

    legend('Location','best', 'Interpreter','latex');

    exportgraphics(fig, outFile, 'Resolution', 300);

end
function plotDeltaCtGlobalVsSR(comparison, rpmAll, outFile)

    fig = figure('Color','w','Name','Delta Ct global vs sR');
    hold on; grid on; box on;

    for irpm = 1:numel(rpmAll)

        rpm = rpmAll(irpm);

        idx = comparison.RPM == rpm;

        if ~any(idx)
            continue;
        end

        x = comparison.s_over_R(idx);
        y = comparison.dCt_percent(idx);

        valid = ~isnan(x) & ~isnan(y);
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
            'DisplayName', sprintf('%d RPM', rpm));

    end

    yline(0, '--k', 'HandleVisibility','off');

    xlabel('$s/R$', 'Interpreter','latex');
    ylabel('$\Delta C_T$ [\%]', 'Interpreter','latex');
    title('$\Delta C_T$: DR mean single rotor vs SR global reference', ...
        'Interpreter','latex');
    legend('Location','best', 'Interpreter','latex');

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function plotBandLine(x, y, s, lineSpec, displayName, showBand, bandAlpha)

    if nargin < 6 || isempty(showBand)
        showBand = true;
    end

    if nargin < 7 || isempty(bandAlpha)
        bandAlpha = 0.18;
    end

    x = x(:);
    y = y(:);

    if isempty(s)
        s = NaN(size(y));
    else
        s = s(:);
    end

    valid = ~isnan(x) & ~isnan(y);

    x = x(valid);
    y = y(valid);
    s = s(valid);

    if isempty(x)
        return;
    end

    if all(isnan(s))
        s = zeros(size(y));
    end

    s(isnan(s)) = 0;

    [x, ord] = sort(x);
    y = y(ord);
    s = s(ord);

    ax = gca;
    colorOrder = ax.ColorOrder;
    colorIndex = ax.ColorOrderIndex;
    colorIndex = mod(colorIndex - 1, size(colorOrder,1)) + 1;
    thisColor = colorOrder(colorIndex,:);

    % Banda di incertezza opzionale
    if showBand && numel(x) >= 2 && any(s > 0)

        xb = [x; flipud(x)];
        yb = [y - s; flipud(y + s)];

        fill(xb, yb, thisColor, ...
            'FaceAlpha', bandAlpha, ...
            'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end

    plot(x, y, lineSpec, ...
        'Color', thisColor, ...
        'LineWidth', 1.5, ...
        'MarkerSize', 6, ...
        'DisplayName', displayName);

    % Avanzo manualmente il colore, perché la Color viene assegnata esplicitamente.
    ax.ColorOrderIndex = colorIndex + 1;

end

function dStd_percent = percentStdChange(std_DR, std_SR)

    % Variazione percentuale delle fluttuazioni:
    %
    % dStd_percent = 100 * (std_DR - std_SR) / std_SR
    %
    % > 0  -> fluttuazioni maggiori in DR rispetto a SR
    % < 0  -> fluttuazioni minori in DR rispetto a SR

    if isnan(std_DR) || isnan(std_SR) || std_SR == 0
        dStd_percent = NaN;
        return;
    end

    dStd_percent = 100 * (std_DR - std_SR) / std_SR;

end

function plotDeltaCoeffPowertrainVsSR(comparison, rpmAll, powertrainID, coeffName, outFile)

    coeffName = string(coeffName);

    if powertrainID ~= 1 && powertrainID ~= 2
        error('powertrainID must be 1 or 2.');
    end

    if coeffName == "Ct"
        yVar = sprintf('dCt_PW%d_percent', powertrainID);
        yLabelText = sprintf('$(C_{T,SR,PW%d}-C_{T,DR,R%d})/C_{T,SR,PW%d}$ [\\%%]', ...
            powertrainID, powertrainID, powertrainID);
        titleText = sprintf('$C_T$ loss: SR PW%d vs DR rotor %d', ...
            powertrainID, powertrainID);

    elseif coeffName == "Cq"
        yVar = sprintf('dCq_PW%d_percent', powertrainID);
        yLabelText = sprintf('$(C_{Q,SR,PW%d}-C_{Q,DR,R%d})/C_{Q,SR,PW%d}$ [\\%%]', ...
            powertrainID, powertrainID, powertrainID);
        titleText = sprintf('$C_Q$ loss: SR PW%d vs DR rotor %d', ...
            powertrainID, powertrainID);

    elseif coeffName == "T"
        yVar = sprintf('dT_PW%d_percent', powertrainID);
        yLabelText = sprintf('$(T_{SR,PW%d}-T_{DR,R%d})/T_{SR,PW%d}$ [\\%%]', ...
            powertrainID, powertrainID, powertrainID);
        titleText = sprintf('$T$ loss: SR PW%d vs DR rotor %d', ...
            powertrainID, powertrainID);

    elseif coeffName == "Q"
        yVar = sprintf('dQ_PW%d_percent', powertrainID);
        yLabelText = sprintf('$(Q_{SR,PW%d}-Q_{DR,R%d})/Q_{SR,PW%d}$ [\\%%]', ...
            powertrainID, powertrainID, powertrainID);
        titleText = sprintf('$Q$ loss: SR PW%d vs DR rotor %d', ...
            powertrainID, powertrainID);

    else
        error('coeffName must be "Ct", "Cq", "T", or "Q".');
    end

    if ~ismember(yVar, comparison.Properties.VariableNames)
        error('Variable %s not found in comparison table.', yVar);
    end

    fig = figure('Color','w', ...
        'Name', sprintf('Delta %s PW%d vs sR', coeffName, powertrainID));

    hold on; grid on; box on;

    for irpm = 1:numel(rpmAll)

        rpm = rpmAll(irpm);

        idx = comparison.RPM == rpm;

        if ~any(idx)
            continue;
        end

        x = comparison.s_over_R(idx);
        y = comparison.(yVar)(idx);

        valid = ~isnan(x) & ~isnan(y);

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
            'DisplayName', sprintf('%d RPM', rpm));

    end

    yline(0, '--k', 'HandleVisibility','off');

    xlabel('$s/R$', 'Interpreter','latex');
    ylabel(yLabelText, 'Interpreter','latex');
    title(titleText, 'Interpreter','latex');

    legend('Location','best', 'Interpreter','latex');

    exportgraphics(fig, outFile, 'Resolution', 300);

end
function plotPowerSRvsDRPowertrain(E_SR_mean, EP_SR_mean, DR_mean, sR_values, ...
                                   powertrainID, powerName, outFile, ...
                                   showUncertaintyBands, bandAlpha)

    if nargin < 8 || isempty(showUncertaintyBands)
        showUncertaintyBands = true;
    end

    if nargin < 9 || isempty(bandAlpha)
        bandAlpha = 0.18;
    end

    powerName = string(powerName);

    switch powerName

        case "P_Qomega"
            yVar = 'P_W_mean';
            sVar = '';
            yLabelText = '$P_{Q\omega}$ [W]';
            titlePrefix = '$P_{Q\omega}$ from cleaned $Q \cdot \omega$';

        case "P_mech_csv"
            yVar = 'P_mech_csv_W_mean';
            sVar = 'P_mech_csv_W_std';
            yLabelText = '$P_{mech,csv}$ [W]';
            titlePrefix = '$P_{mech}$ from CSV';

        case "P_elec_csv"
            yVar = 'P_elec_csv_W_mean';
            sVar = 'P_elec_csv_W_std';
            yLabelText = '$P_{elec,csv}$ [W]';
            titlePrefix = '$P_{elec}$ from CSV';

        otherwise
            error('Unknown powerName: %s', powerName);

    end

    if powertrainID == 1
        SR_T = EP_SR_mean;
        rotorID = 1;
        srLabel = 'SR PW1 = EP\_SR';
    elseif powertrainID == 2
        SR_T = E_SR_mean;
        rotorID = 2;
        srLabel = 'SR PW2 = E\_SR';
    else
        error('powertrainID must be 1 or 2.');
    end

    fig = figure('Color','w', ...
        'Name', sprintf('%s SR PW%d vs DR R%d', powerName, powertrainID, rotorID));

    hold on; grid on; box on;

    xSR = SR_T.RPM_used;
    ySR = SR_T.(yVar);

    if ~isempty(sVar) && ismember(sVar, SR_T.Properties.VariableNames)
        sSR = SR_T.(sVar);
    else
        sSR = NaN(size(ySR));
    end

    plotBandLine(xSR, ySR, sSR, '-^', srLabel, ...
        showUncertaintyBands, bandAlpha);

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        T = DR_mean(DR_mean.s_over_R == sR & DR_mean.rotorID == rotorID, :);

        if isempty(T)
            continue;
        end

        xDR = T.RPM_used;
        yDR = T.(yVar);

        if ~isempty(sVar) && ismember(sVar, T.Properties.VariableNames)
            sDR = T.(sVar);
        else
            sDR = NaN(size(yDR));
        end

        plotBandLine(xDR, yDR, sDR, '--o', ...
            sprintf('DR R%d, s/R = %.3g', rotorID, sR), ...
            showUncertaintyBands, bandAlpha);

    end

    xlabel('$RPM_{used}$', 'Interpreter','latex');
    ylabel(yLabelText, 'Interpreter','latex');

    title(sprintf('%s: SR PW%d vs DR R%d', ...
        titlePrefix, powertrainID, rotorID), 'Interpreter','latex');

    legend('Location','best', 'Interpreter','latex');

    exportgraphics(fig, outFile, 'Resolution', 300);

end

function comparison_exactRPM = buildExactRPMComparison(E_SR_mean, EP_SR_mean, DR_mean, sR_values)

    SR_PW1_curve = makeExactCurveFromMeanTable(EP_SR_mean);
    SR_PW2_curve = makeExactCurveFromMeanTable(E_SR_mean);

    SR_MEAN_curve = makeMeanExactCurve(SR_PW1_curve, SR_PW2_curve);

    comparison_exactRPM = table();

    for isr = 1:numel(sR_values)

        sR = sR_values(isr);

        DR_R1_curve = makeExactCurveFromMeanTable( ...
            DR_mean(DR_mean.s_over_R == sR & DR_mean.rotorID == 1, :));

        DR_R2_curve = makeExactCurveFromMeanTable( ...
            DR_mean(DR_mean.s_over_R == sR & DR_mean.rotorID == 2, :));

        DR_MEAN_curve = makeMeanExactCurve(DR_R1_curve, DR_R2_curve);

        comparison_exactRPM = addExactRowsForPair( ...
            comparison_exactRPM, "PW1", 1, sR, SR_PW1_curve, DR_R1_curve);

        comparison_exactRPM = addExactRowsForPair( ...
            comparison_exactRPM, "PW2", 2, sR, SR_PW2_curve, DR_R2_curve);

        comparison_exactRPM = addExactRowsForPair( ...
            comparison_exactRPM, "MEAN", NaN, sR, SR_MEAN_curve, DR_MEAN_curve);

    end

end

function C = makeExactCurveFromMeanTable(T)

    C = table();

    if isempty(T)
        return;
    end

    needed = { ...
        'RPM_target', ...
        'RPM_used', ...
        'Ct_mean', ...
        'Cq_mean', ...
        'T_N_mean', ...
        'Q_abs_Nm_mean', ...
        'P_W_mean', ...
        'P_mech_csv_W_mean', ...
        'P_elec_csv_W_mean'};

    for k = 1:numel(needed)
        if ~ismember(needed{k}, T.Properties.VariableNames)
            T.(needed{k}) = NaN(height(T),1);
        end
    end

    C.RPM_target = T.RPM_target;
    C.RPM_used   = T.RPM_used;

    C.Ct = T.Ct_mean;
    C.Cq = T.Cq_mean;

    C.T_N = T.T_N_mean;
    C.Q_abs_Nm = T.Q_abs_Nm_mean;

    C.P_Qomega_W   = T.P_W_mean;
    C.P_mech_csv_W = T.P_mech_csv_W_mean;
    C.P_elec_csv_W = T.P_elec_csv_W_mean;

    valid = isfinite(C.RPM_target) & isfinite(C.RPM_used);
    C = C(valid,:);

    if ~isempty(C)
        C = sortrows(C, 'RPM_used');
    end

end

function Cmean = makeMeanExactCurve(C1, C2)

    Cmean = table();

    if isempty(C1) && isempty(C2)
        return;
    end

    targets = unique([C1.RPM_target; C2.RPM_target]);
    targets = sort(targets(isfinite(targets)));

    vars = ["RPM_used", "Ct", "Cq", "T_N", "Q_abs_Nm", ...
            "P_Qomega_W", "P_mech_csv_W", "P_elec_csv_W"];

    Cmean.RPM_target = targets;

    for iv = 1:numel(vars)

        var = vars(iv);
        y = NaN(numel(targets),1);

        for i = 1:numel(targets)

            rpmT = targets(i);

            y(i) = mean([ ...
                getCurveAtTarget(C1, rpmT, var), ...
                getCurveAtTarget(C2, rpmT, var)], 'omitnan');

        end

        Cmean.(char(var)) = y;

    end

    valid = isfinite(Cmean.RPM_target) & isfinite(Cmean.RPM_used);
    Cmean = Cmean(valid,:);

    if ~isempty(Cmean)
        Cmean = sortrows(Cmean, 'RPM_used');
    end

end

function Tbig = addExactRowsForPair(Tbig, comparisonType, powertrainID, sR, SR_curve, DR_curve)

    if isempty(SR_curve) || isempty(DR_curve)
        return;
    end

    targets = intersect(SR_curve.RPM_target, DR_curve.RPM_target);
    targets = sort(targets(isfinite(targets)));

    vars = ["Ct", "Cq", "T_N", "Q_abs_Nm", ...
            "P_Qomega_W", "P_mech_csv_W", "P_elec_csv_W"];

    for it = 1:numel(targets)

        rpmTarget = targets(it);

        rpmSR = getCurveAtTarget(SR_curve, rpmTarget, "RPM_used");
        rpmDR = getCurveAtTarget(DR_curve, rpmTarget, "RPM_used");

        if ~isfinite(rpmSR) || ~isfinite(rpmDR)
            continue;
        end

        rpmCommon = 0.5*(rpmSR + rpmDR);

        row = table();

        row.comparisonType = string(comparisonType);
        row.powertrainID = powertrainID;
        row.s_over_R = sR;
        row.RPM_target = rpmTarget;

        row.RPM_SR_used_nominal = rpmSR;
        row.RPM_DR_used_nominal = rpmDR;
        row.RPM_common = rpmCommon;
        row.RPM_common_definition = "0.5*(RPM_SR_used_nominal + RPM_DR_used_nominal)";

        for iv = 1:numel(vars)

            var = vars(iv);
            varChar = char(var);

            SR_val = interpExactCurve(SR_curve, rpmCommon, var);
            DR_val = interpExactCurve(DR_curve, rpmCommon, var);

            row.(sprintf('%s_SR', varChar)) = SR_val;
            row.(sprintf('%s_DR', varChar)) = DR_val;
            row.(sprintf('d%s', varChar)) = SR_val - DR_val;
            row.(sprintf('d%s_percent', varChar)) = percentLossLocal(SR_val, DR_val);

        end

        if isempty(Tbig)
            Tbig = row;
        else
            Tbig = [Tbig; row];
        end

    end

end

function val = getCurveAtTarget(C, rpmTarget, varName)

    val = NaN;

    if isempty(C) || ~ismember(char(varName), C.Properties.VariableNames)
        return;
    end

    idx = C.RPM_target == rpmTarget;

    if any(idx)
        val = mean(C.(char(varName))(idx), 'omitnan');
    end

end

function val = interpExactCurve(C, rpm, varName)

    val = NaN;

    varName = char(varName);

    if isempty(C) || ~ismember(varName, C.Properties.VariableNames)
        return;
    end

    x = C.RPM_used;
    y = C.(varName);

    valid = isfinite(x) & isfinite(y);

    x = x(valid);
    y = y(valid);

    if numel(x) < 1
        return;
    end

    [x, ord] = sort(x);
    y = y(ord);

    [x, ia] = unique(x, 'stable');
    y = y(ia);

    if numel(x) == 1
        val = y(1);
        return;
    end

    % Per evitare NaN ai bordi se RPM_common cade pochi rpm fuori dal range.
    edgeTolRPM = 50;

    if rpm < min(x) - edgeTolRPM || rpm > max(x) + edgeTolRPM
        return;
    end

    if rpm < min(x)
        val = y(1);
    elseif rpm > max(x)
        val = y(end);
    else
        val = interp1(x, y, rpm, 'linear', NaN);
    end

end

function p = percentLossLocal(SR, DR)

    if ~isfinite(SR) || ~isfinite(DR) || SR == 0
        p = NaN;
    else
        p = 100*(SR - DR)/SR;
    end

end

function plotCtStdPowertrainVsSR(comparison, rpmAll, outFile)

    requiredVars = { ...
        's_over_R', ...
        'RPM', ...
        'Ct_SR_PW1_std', ...
        'Ct_DR_R1_std', ...
        'Ct_SR_PW2_std', ...
        'Ct_DR_R2_std'};

    for iv = 1:numel(requiredVars)
        if ~ismember(requiredVars{iv}, comparison.Properties.VariableNames)
            error('Variable %s not found in comparison table.', requiredVars{iv});
        end
    end

    rpmList = rpmAll(:);
    rpmList = rpmList(isfinite(rpmList));

    fig = figure('Color','w', ...
        'Name','Ct standard deviation single powertrain');

    tiledlayout(2,1,'Padding','compact','TileSpacing','compact');

    for powertrainID = 1:2

        nexttile;
        hold on; grid on; box on;

        if powertrainID == 1

            srStdVar = 'Ct_SR_PW1_std';
            drStdVar = 'Ct_DR_R1_std';

            titleText = '$\sigma(C_T)$: SR PW1 vs DR R1';
            srLabelBase = 'SR PW1';
            drLabelBase = 'DR R1';

        else

            srStdVar = 'Ct_SR_PW2_std';
            drStdVar = 'Ct_DR_R2_std';

            titleText = '$\sigma(C_T)$: SR PW2 vs DR R2';
            srLabelBase = 'SR PW2';
            drLabelBase = 'DR R2';

        end

        colors = lines(numel(rpmList));

        for irpm = 1:numel(rpmList)

            rpm = rpmList(irpm);

            idx = comparison.RPM == rpm;

            if ~any(idx)
                continue;
            end

            x = comparison.s_over_R(idx);

            yDR = comparison.(drStdVar)(idx);
            ySR = comparison.(srStdVar)(idx);

            valid = isfinite(x) & isfinite(yDR) & isfinite(ySR);

            x = x(valid);
            yDR = yDR(valid);
            ySR = ySR(valid);

            if isempty(x)
                continue;
            end

            [x, ord] = sort(x);
            yDR = yDR(ord);
            ySR = ySR(ord);

            thisColor = colors(irpm,:);

            % DR: sigma del singolo rotore in configurazione double rotor
            plot(x, yDR, '-o', ...
                'Color', thisColor, ...
                'LineWidth', 1.5, ...
                'MarkerSize', 6, ...
                'DisplayName', sprintf('%s, %d RPM', drLabelBase, rpm));

            % SR: sigma del powertrain corrispondente.
            % La curva è orizzontale perché SR non dipende da s/R.
            plot(x, ySR, '--s', ...
                'Color', thisColor, ...
                'LineWidth', 1.5, ...
                'MarkerSize', 6, ...
                'DisplayName', sprintf('%s, %d RPM', srLabelBase, rpm));

        end

        xlabel('$s/R$', 'Interpreter','latex');
        ylabel('$\sigma(C_T)$', 'Interpreter','latex');
        title(titleText, 'Interpreter','latex');

        legend('Location','bestoutside', 'Interpreter','latex');

    end

    exportgraphics(fig, outFile, 'Resolution', 300);

end