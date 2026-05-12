function out = detectThrustOutliers(t, T, opts)
%DETECTTHRUSTOUTLIERS Robust global and local outlier detection for thrust signals.
%
%   out = detectThrustOutliers(t, T, opts)
%
% INPUTS
%   t       : time vector [s], Nx1 or 1xN
%   T       : thrust signal, Nx1 or 1xN
%   opts    : optional structure with fields:
%
%       opts.useGlobal        = true/false
%       opts.useLocal         = true/false
%
%       opts.globalThreshold  = robust z-score threshold for global method
%       opts.localThreshold   = robust z-score threshold for local method
%
%       opts.localWindow_s    = local window duration [s]
%
%       opts.replaceMethod    = 'linear', 'pchip', 'spline', 'nearest', or 'none'
%       opts.makePlot         = true/false
%
% OUTPUT
%   out.T_clean           : cleaned thrust signal
%   out.mask_global       : logical mask of global outliers
%   out.mask_local        : logical mask of local outliers
%   out.mask_combined     : logical mask of all detected outliers
%   out.z_global          : global robust z-score
%   out.z_local           : local robust z-score
%   out.local_median      : moving median
%   out.local_sigma       : local robust sigma estimate
%   out.stats             : summary statistics
%
% -------------------------------------------------------------------------
% Robust z-score definition:
%
%   z = abs(T - median(T)) / sigma_robust
%
% with:
%
%   sigma_robust = 1.4826 * MAD
%
% where MAD = median(abs(T - median(T))).
%
% The factor 1.4826 makes MAD comparable to standard deviation for Gaussian
% noise.
% -------------------------------------------------------------------------

    %% ------------------ Input formatting -------------------------------

    t = t(:);
    T = T(:);

    if numel(t) ~= numel(T)
        error('t and T must have the same number of samples.');
    end

    N = numel(T);

    if N < 10
        error('Signal is too short for robust outlier detection.');
    end

    %% ------------------ Default options --------------------------------

    if nargin < 3
        opts = struct();
    end

    opts = setDefault(opts, 'useGlobal', true);
    opts = setDefault(opts, 'useLocal', true);

    opts = setDefault(opts, 'globalThreshold', 5.0);
    opts = setDefault(opts, 'localThreshold', 5.0);

    opts = setDefault(opts, 'localWindow_s', 0.10);

    opts = setDefault(opts, 'replaceMethod', 'linear');
    opts = setDefault(opts, 'makePlot', true);

    %% ------------------ Sampling frequency -----------------------------

    dt = median(diff(t), 'omitnan');
    fs = 1 / dt;

    if ~isfinite(fs) || fs <= 0
        error('Cannot determine a valid sampling frequency from t.');
    end

    %% ------------------ Global robust detector -------------------------

    mask_global = false(N, 1);
    z_global = nan(N, 1);

    if opts.useGlobal

        T_med = median(T, 'omitnan');
        T_mad = median(abs(T - T_med), 'omitnan');

        sigma_global = 1.4826 * T_mad;

        if sigma_global == 0 || ~isfinite(sigma_global)
            warning('Global robust sigma is zero or invalid. Global detection disabled.');
        else
            z_global = abs(T - T_med) / sigma_global;
            mask_global = z_global > opts.globalThreshold;
        end

    end

    %% ------------------ Local robust detector --------------------------

    mask_local = false(N, 1);
    z_local = nan(N, 1);
    local_median = nan(N, 1);
    local_sigma = nan(N, 1);

    if opts.useLocal

        localWindow_samples = round(opts.localWindow_s * fs);

        if localWindow_samples < 3
            localWindow_samples = 3;
        end

        % Force odd window length
        if mod(localWindow_samples, 2) == 0
            localWindow_samples = localWindow_samples + 1;
        end

        local_median = movmedian(T, localWindow_samples, 'omitnan');

        abs_dev = abs(T - local_median);
        local_mad = movmedian(abs_dev, localWindow_samples, 'omitnan');

        local_sigma = 1.4826 * local_mad;

        validLocal = local_sigma > 0 & isfinite(local_sigma);

        z_local(validLocal) = abs(T(validLocal) - local_median(validLocal)) ./ local_sigma(validLocal);

        mask_local = z_local > opts.localThreshold;

    end

    %% ------------------ Combined mask ----------------------------------

    mask_combined = mask_global | mask_local;

    %% ------------------ Replace outliers -------------------------------

    T_clean = T;

    switch lower(opts.replaceMethod)

        case 'none'
            % Leave signal unchanged

        case {'linear', 'pchip', 'spline', 'nearest'}
            T_clean(mask_combined) = NaN;
            T_clean = fillmissing(T_clean, opts.replaceMethod, 'SamplePoints', t);

        otherwise
            error('Unknown replaceMethod: %s', opts.replaceMethod);

    end

    %% ------------------ Statistics -------------------------------------

    stats = struct();

    stats.N = N;
    stats.fs_Hz = fs;
    stats.dt_s = dt;

    stats.N_global = sum(mask_global);
    stats.N_local = sum(mask_local);
    stats.N_combined = sum(mask_combined);

    stats.frac_global = stats.N_global / N;
    stats.frac_local = stats.N_local / N;
    stats.frac_combined = stats.N_combined / N;

    stats.globalThreshold = opts.globalThreshold;
    stats.localThreshold = opts.localThreshold;
    stats.localWindow_s = opts.localWindow_s;

    stats.mean_raw = mean(T, 'omitnan');
    stats.std_raw = std(T, 'omitnan');

    stats.mean_clean = mean(T_clean, 'omitnan');
    stats.std_clean = std(T_clean, 'omitnan');

    %% ------------------ Output -----------------------------------------

    out = struct();

    out.T_clean = T_clean;

    out.mask_global = mask_global;
    out.mask_local = mask_local;
    out.mask_combined = mask_combined;

    out.z_global = z_global;
    out.z_local = z_local;

    out.local_median = local_median;
    out.local_sigma = local_sigma;

    out.stats = stats;

    %% ------------------ Plot -------------------------------------------

    if opts.makePlot

        figure;
        set(gcf, 'Color', 'w');

        subplot(3,1,1)
        hold on; grid on; box on;
        plot(t, T, 'k-', 'DisplayName', 'Raw thrust');
        plot(t, T_clean, 'r-', 'LineWidth', 1.2, 'DisplayName', 'Cleaned thrust');
        plot(t(mask_combined), T(mask_combined), 'bo', ...
            'MarkerSize', 4, ...
            'DisplayName', 'Detected outliers');
        xlabel('$t$ [s]', 'Interpreter', 'latex');
        ylabel('$T$ [N]', 'Interpreter', 'latex');
        title('Thrust signal and detected outliers', 'Interpreter', 'latex');
        legend('Location', 'best', 'Interpreter', 'latex');

        subplot(3,1,2)
        hold on; grid on; box on;
        plot(t, z_global, 'b-', 'DisplayName', 'Global robust z-score');
        yline(opts.globalThreshold, 'r--', 'DisplayName', 'Global threshold');
        xlabel('$t$ [s]', 'Interpreter', 'latex');
        ylabel('$z_{global}$', 'Interpreter', 'latex');
        title('Global outlier score', 'Interpreter', 'latex');
        legend('Location', 'best', 'Interpreter', 'latex');

        subplot(3,1,3)
        hold on; grid on; box on;
        plot(t, z_local, 'b-', 'DisplayName', 'Local robust z-score');
        yline(opts.localThreshold, 'r--', 'DisplayName', 'Local threshold');
        xlabel('$t$ [s]', 'Interpreter', 'latex');
        ylabel('$z_{local}$', 'Interpreter', 'latex');
        title('Local outlier score', 'Interpreter', 'latex');
        legend('Location', 'best', 'Interpreter', 'latex');

    end

end

%% ========================================================================
% Local helper function
% ========================================================================

function opts = setDefault(opts, fieldName, defaultValue)

    if ~isfield(opts, fieldName) || isempty(opts.(fieldName))
        opts.(fieldName) = defaultValue;
    end

end