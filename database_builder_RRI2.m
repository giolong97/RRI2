clear; close all; clc; svflg = 0;

%% Paths
inpath  = 'cc';
outpath = 'C:\Users\Utente\Documents\RRI2\Loads\database\';

%% Testcase selection
conf = 'IR2'; % 'DR', 'IR', 'IR1', 'IR2'
RPM  = 2000; % [1500:500:4000];
loadcell = 2;
d = importdata([inpath,conf,'_RPM',num2str(RPM),'_dt1.csv']);


if loadcell == 1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 1 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t     = d.data(:,1);     % [s]
T     = d.data(:,3);     % [Kgf]
Q     = d.data(:,4);     % [Nm]
omega = d.data(:,7);     % [RPM]
[~,maxind] = max(d.data(:,2));
meanV = mean(d.data(:,5),'omitNan')
meanA = mean(d.data(:,6),'omitNan')
else
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 2 %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t     = d.data(:,1);     % [s]
T     = d.data(:,16);     % [Kgf]
Q     = d.data(:,17);     % [Nm]
omega = d.data(:,20);     % [RPM]
[~,maxind] = max(d.data(:,15));
meanV = mean(d.data(:,18),'omitNan')
meanA = mean(d.data(:,19),'omitNan')
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
t_init = d.data(maxind,1); sample_duration = 30;
t_end  = t_init + sample_duration;

vals = find(t>t_init&t<t_end);

t_     = t(vals); 
T_     = T(vals);     [posT,~]  = find(~isnan(T_));
Q_     = Q(vals);     [posQ,~]  = find(~isnan(Q_));
omega_ = omega(vals); [posomega,~]  = find(~isnan(omega_));
% P_     = P(vals);     [posP,~]  = find(~isnan(P_));

%% Database

meanT = mean(T_(posT))
sigT  = std(T_(posT))

meanQ = mean(Q_(posQ));
sigQ  = std(Q_(posQ));

meanomega = mean(omega_(posomega));
sigomega  = std(omega_(posomega));

meanP     = (2*pi*meanomega/60).*(meanQ); % [W]
% sigP  = std(P_(posP));

if svflg == 1
save([outpath,conf,'_RPM',num2str(RPM),'_Tmean.m'],'meanT','-mat');
save([outpath,conf,'_RPM',num2str(RPM),'_Tsig.m'],'sigT','-mat');
save([outpath,conf,'_RPM',num2str(RPM),'_Qmean.m'],'meanQ','-mat');
save([outpath,conf,'_RPM',num2str(RPM),'_Qsig.m'],'sigQ','-mat');
save([outpath,conf,'_RPM',num2str(RPM),'_Pmean.m'],'meanP','-mat');
% save([outpath,conf,'_RPM',num2str(RPM),'_Psig.m'],'sigP','-mat');
save([outpath,conf,'_RPM',num2str(RPM),'_Omegamean.m'],'meanomega','-mat');
save([outpath,conf,'_RPM',num2str(RPM),'_Omegasig.m'],'sigomega','-mat');
end

%% Graphics
% 
% TT = fft(T_(posT) - meanT);
% figure(100);
% plot(abs(TT))
% xlabel('f [Hz]')
% xlim([0 1000])

figure(1);
clf
plot(t_(posT),movmean(T_(posT),1000),'.-')
yline(mean(T_(posT)),'--')
xlabel(d.textdata(1))
ylabel(d.textdata(3))
grid on
% axis([0 150 0 4])
% 
% figure(2);
% clf
% plot(t_(posQ),Q_(posQ),'.-')
% xlabel(d.textdata(1))
% ylabel(d.textdata(4))
% grid on

% figure(3);
% clf
% plot(t_(posP),P_(posP),'.-')
% xlabel(d.textdata(1))
% ylabel(d.textdata(9))
% grid on
% 
% figure(4);
% clf
% plot(t_(posomega),omega_(posomega),'.-')
% xlabel(d.textdata(1))
% ylabel(d.textdata(7))
% grid on

