function ens = compute_ensemble_stats(results_arg, caller_dir)
    % COMPUTE_ENSEMBLE_STATS
    % Single source of truth for Monte Carlo ensemble extraction and empirical
    % IQR/boxplot color-scale calibration across all modeled target depths.
    %
    % Reads Bellhop .shd.mat files (with fallback to cached presets), cleans
    % r ~ 0 singularities once, computes per-depth spread CDFs, derives
    % adaptive all-depth boxplot thresholds (Q1, Q3, Tukey whisker, p99 cap),
    % and returns a structured bundle consumed by plotting and HTML exporters.

    if nargin < 1
        results_arg = [];
    end

    mvp_dir   = fileparts(mfilename('fullpath'));
    repo_root = fileparts(mvp_dir);
    if nargin < 2 || isempty(caller_dir)
        caller_dir = mvp_dir;
    end
    if ~exist('load_mc_results', 'file')
        addpath(mvp_dir);
    end

    % Pass-through if caller already computed the ensemble bundle
    if isstruct(results_arg) && isfield(results_arg, 'color_scale') && isfield(results_arg, 'TL_cube')
        ens = results_arg;
        return;
    end

    [results_file, data, out_folder, version_suffix, shd_pattern] = load_mc_results(results_arg, caller_dir);

    r_km       = data.r_km(:)';
    depth2plot = data.depth2plot;
    N_mc       = data.N_mc;
    Nr         = length(r_km);
    M_TO_FT    = 3.28084;
    preset_nominal_m = [20, 50, 100, 200, 500];

    ownship_depth_m = 20.0;
    if isfield(data, 'source_depth_m') && ~isempty(data.source_depth_m)
        ownship_depth_m = data.source_depth_m(1);
    elseif isfield(data, 'base_test') && (strcmpi(data.base_test, 'Test2') || strcmpi(data.base_test, 'Test3'))
        ownship_depth_m = 100.0;
    end

    % Check availability of full Bellhop .shd.mat files across all depths
    has_shd = isfield(data, 'z_m') && ~isempty(data.z_m);
    if has_shd
        for i = 1:N_mc
            if exist(fullfile(out_folder, sprintf(shd_pattern, i)), 'file') ~= 2
                has_shd = false;
                break;
            end
        end
    end

    all_cdfs_x    = {};
    all_cdfs_y    = {};
    preset_keys   = {};
    preset_vals_m = [];

    if has_shd
        z_full    = data.z_m(:)';
        idx_avail = find(z_full > 0 & z_full <= 1010);
        if isempty(idx_avail)
            idx_avail = 1:length(z_full);
        end
        z_avail  = z_full(idx_avail);
        n_depths = length(z_avail);
        TL_cube  = zeros(N_mc, n_depths, Nr);

        fprintf('  [Ensemble Stats]: Loading %d MC runs across %d target depths (%.0f ft - %.0f ft)...\n', ...
                N_mc, n_depths, z_avail(1) * M_TO_FT, z_avail(end) * M_TO_FT);

        for i = 1:N_mc
            shd_file = fullfile(out_folder, sprintf(shd_pattern, i));
            if i == 1
                res = load(shd_file, 'pressure', 'Pos');
                if ~isfield(data, 'source_depth_m') && isfield(res, 'Pos') && ...
                   isfield(res.Pos, 's') && isfield(res.Pos.s, 'z') && ~isempty(res.Pos.s.z)
                    ownship_depth_m = res.Pos.s.z(1);
                end
            else
                res = load(shd_file, 'pressure');
            end
            TL_2d = -20 * log10(squeeze(abs(res.pressure)));
            TL_cube(i, :, :) = TL_2d(idx_avail, :);
        end

        preset_idx = zeros(1, length(preset_nominal_m));
        for b = 1:length(preset_nominal_m)
            [~, preset_idx(b)] = min(abs(z_avail - preset_nominal_m(b)));
        end
    else
        avail_depths = [];
        avail_blocks = {};
        if isfield(data, 'TL_depths') && isstruct(data.TL_depths)
            for d = preset_nominal_m
                f_name = sprintf('d%d', d);
                if isfield(data.TL_depths, f_name)
                    avail_depths(end+1) = d; %#ok<AGROW>
                    avail_blocks{end+1} = data.TL_depths.(f_name); %#ok<AGROW>
                end
            end
        end
        if isempty(avail_depths)
            avail_depths = depth2plot;
            avail_blocks = {data.TL_all};
        end
        z_avail  = avail_depths;
        n_depths = length(z_avail);
        TL_cube  = zeros(N_mc, n_depths, Nr);
        for bi = 1:n_depths
            TL_cube(1:size(avail_blocks{bi}, 1), bi, :) = avail_blocks{bi};
        end
        preset_idx = 1:n_depths;
    end

    % Clean r ~ 0 infinities once per depth realization & compute spreads
    spread_mat = zeros(n_depths, Nr);
    for di = 1:n_depths
        tl_mat = reshape(TL_cube(:, di, :), N_mc, Nr);
        for row = 1:N_mc
            idx_fin = find(~isinf(tl_mat(row, :)), 1, 'first');
            if ~isempty(idx_fin) && idx_fin > 1
                tl_mat(row, 1:idx_fin-1) = tl_mat(row, idx_fin);
            elseif isempty(idx_fin)
                tl_mat(row, :) = 140;
            end
        end
        TL_cube(:, di, :) = tl_mat;

        sp_d = max(tl_mat, [], 1) - min(tl_mat, [], 1);
        spread_mat(di, :) = sp_d;

        if has_shd
            sp_fin = sort(sp_d(isfinite(sp_d)));
            all_cdfs_x{di} = [0, sp_fin]; %#ok<AGROW>
            all_cdfs_y{di} = [0, (1:length(sp_fin)) / length(sp_fin) * 100]; %#ok<AGROW>
        end
    end

    % Derive scenario's adaptive IQR / boxplot color thresholds across all depths
    sp_all_raw = spread_mat(:)';
    raw_stats  = compute_spread_stats(sp_all_raw, 'All Target Depths', 0, 0);

    th_flat    = max(0.5, round(raw_stats.q1, 1));
    th_yel     = max(th_flat + 0.5, round(raw_stats.q3, 1));
    tukey_hi   = max(th_yel + 0.5, round(raw_stats.w_high, 1));
    max_spread = max([ceil(raw_stats.p99), floor(tukey_hi) + 1]);

    color_scale = struct( ...
        'th_flat',    th_flat, ...
        'th_yel',     th_yel, ...
        'tukey_hi',   tukey_hi, ...
        'max_spread', max_spread, ...
        'q1',         round(raw_stats.q1, 2), ...
        'median',     round(raw_stats.median, 2), ...
        'q3',         round(raw_stats.q3, 2), ...
        'iqr',        round(raw_stats.iqr, 2), ...
        'p99',        round(raw_stats.p99, 2), ...
        'mode',       'adaptive_all_depth_iqr' ...
    );

    % Populate depth_stats & preset selector metadata using the active color_scale
    depth_stats  = struct();
    btn_keys     = {};
    btn_labels   = {};
    btn_tooltips = {};

    if has_shd
        all_lbl = sprintf('All %d Target Depths (%d - %d ft)', ...
            n_depths, round(z_avail(1) * M_TO_FT), round(z_avail(end) * M_TO_FT));
    else
        all_lbl = sprintf('Pooled %d Preset Depths', n_depths);
    end
    depth_stats.all = compute_spread_stats(sp_all_raw, all_lbl, th_flat, th_yel);

    btn_keys{end+1}     = 'all';
    btn_labels{end+1}   = sprintf('All (%d)', n_depths);
    btn_tooltips{end+1} = sprintf('Pooled IQR distribution across %d target depths', n_depths);

    for b = 1:length(preset_idx)
        p_i      = preset_idx(b);
        d_actual = z_avail(p_i);
        if has_shd
            d_nom = preset_nominal_m(b);
        else
            d_nom = round(d_actual);
        end
        s_key   = sprintf('d%d', d_nom);
        lbl_str = sprintf('%d ft (%dm)', round(d_actual * M_TO_FT), round(d_actual));

        depth_stats.(s_key) = compute_spread_stats(spread_mat(p_i, :), lbl_str, th_flat, th_yel);
        btn_keys{end+1}     = s_key; %#ok<AGROW>
        btn_labels{end+1}   = sprintf('%d ft', round(d_actual * M_TO_FT)); %#ok<AGROW>
        btn_tooltips{end+1} = lbl_str; %#ok<AGROW>
        preset_keys{end+1}  = s_key; %#ok<AGROW>
        preset_vals_m(end+1) = d_nom; %#ok<AGROW>
    end

    ens = struct();
    ens.results_file    = results_file;
    ens.data            = data;
    ens.out_folder      = out_folder;
    ens.repo_root       = repo_root;
    ens.mvp_dir         = mvp_dir;
    ens.version_suffix  = version_suffix;
    ens.shd_pattern     = shd_pattern;
    ens.has_shd         = has_shd;
    ens.r_km            = r_km;
    ens.N_mc            = N_mc;
    ens.Nr              = Nr;
    ens.z_avail         = z_avail;
    ens.n_depths        = n_depths;
    ens.depth2plot      = depth2plot;
    ens.ownship_depth_m = ownship_depth_m;
    ens.preset_nominal_m = preset_nominal_m;
    ens.preset_idx      = preset_idx;
    ens.preset_keys     = preset_keys;
    ens.preset_vals_m   = preset_vals_m;
    ens.TL_cube         = TL_cube;
    ens.spread_mat      = spread_mat;
    ens.all_cdfs_x      = all_cdfs_x;
    ens.all_cdfs_y      = all_cdfs_y;
    ens.depth_stats     = depth_stats;
    ens.btn_keys        = btn_keys;
    ens.btn_labels      = btn_labels;
    ens.btn_tooltips    = btn_tooltips;
    ens.color_scale     = color_scale;
end

function s = compute_spread_stats(sp_in, label_str, th_flat, th_yel)
    sp = sp_in(isfinite(sp_in));
    sp_sort = sort(sp);
    n_pts = length(sp_sort);

    s.label        = label_str;
    s.spread       = sp;
    s.n_pts        = n_pts;
    s.min          = sp_sort(1);
    s.max          = sp_sort(end);
    s.q1           = sp_sort(max(1, round(0.2500 * n_pts)));
    s.median       = median(sp_sort);
    s.q3           = sp_sort(min(n_pts, round(0.7500 * n_pts)));
    s.iqr          = s.q3 - s.q1;
    s.p33          = sp_sort(max(1, round(0.3333 * n_pts)));
    s.p67          = sp_sort(min(n_pts, round(0.6667 * n_pts)));
    s.p90          = sp_sort(min(n_pts, round(0.9000 * n_pts)));
    s.p95          = sp_sort(min(n_pts, round(0.9500 * n_pts)));
    s.p99          = sp_sort(min(n_pts, round(0.9900 * n_pts)));

    tukey_lo       = s.q1 - 1.5 * s.iqr;
    tukey_hi       = s.q3 + 1.5 * s.iqr;
    in_fence       = sp_sort(sp_sort >= tukey_lo & sp_sort <= tukey_hi);
    if isempty(in_fence)
        s.w_low  = s.q1;
        s.w_high = s.q3;
    else
        s.w_low  = in_fence(1);
        s.w_high = in_fence(end);
    end
    s.outliers     = sp_sort(sp_sort > tukey_hi);
    s.pct_outliers = length(s.outliers) / n_pts * 100;

    s.pct_green    = mean(sp <= th_flat) * 100;
    s.pct_yellow   = mean(sp > th_flat & sp <= th_yel) * 100;
    s.pct_red      = mean(sp > th_yel) * 100;
    s.cdf_x        = [0, sp_sort];
    s.cdf_y        = [0, (1:n_pts) / n_pts * 100];
end
