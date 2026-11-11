function plot_geosit_final(results_file)
    if nargin < 1
        results_file = [];
    end

    script_dir = fileparts(mfilename('fullpath'));
    if ~exist('load_mc_results', 'file')
        addpath(script_dir);
    end
    [results_file, data, out_folder, version_suffix, shd_pattern] = load_mc_results(results_file, script_dir);

    if isfield(data, 'base_test') && ~isempty(data.base_test)
        fig_name = sprintf('TACTICAL COMBAT DISPLAY: SONAR PPI CONSOLE (%s)', upper(char(data.base_test)));
    elseif ~isempty(version_suffix)
        fig_name = sprintf('TACTICAL COMBAT DISPLAY: SONAR PPI CONSOLE (%s)', upper(strrep(version_suffix, '_', 'TEST ')));
    else
        fig_name = 'TACTICAL COMBAT DISPLAY: SONAR PPI CONSOLE';
    end

    % Close any existing instance for this version to clear old callbacks
    old_fig = findobj('Type', 'figure', 'Name', fig_name);
    if ~isempty(old_fig)
        close(old_fig);
    end

    % --- 1. Load Simulation Data ---
    KM_TO_KYD  = 1.0936133;
    M_TO_FT    = 3.28084;
    r_km       = data.r_km(:)'; % Force row vector [1 x Nr]
    r_kyd      = r_km * KM_TO_KYD; % Convert horizontal range to kiloyards (1 km = 1.0936133 kyd)
    TL_all     = data.TL_all;   % [N_mc x Nr]
    depth2plot = data.depth2plot;
    N_mc       = data.N_mc;

    preset_nominal_m = [20, 50, 100, 200, 500];
    n_btns           = length(preset_nominal_m);

    has_shd = isfield(data, 'z_m') && ~isempty(data.z_m);
    if has_shd
        for i = 1:N_mc
            if exist(fullfile(out_folder, sprintf(shd_pattern, i)), 'file') ~= 2
                has_shd = false; break;
            end
        end
    end

    ownship_depth_m = 20.0;
    if isfield(data, 'source_depth_m') && ~isempty(data.source_depth_m)
        ownship_depth_m = data.source_depth_m(1);
    elseif (isfield(data, 'base_test') && (strcmpi(data.base_test, 'Test2') || strcmpi(data.base_test, 'Test3')))
        ownship_depth_m = 100.0;
    end

    if has_shd
        % Load acoustic ensemble across operational submarine target depths (33 ft to 3,306 ft)
        z_full    = data.z_m(:)';
        idx_avail = find(z_full > 0 & z_full <= 1010);
        if isempty(idx_avail)
            idx_avail = 1:length(z_full);
        end
        z_avail  = z_full(idx_avail);
        n_depths = length(z_avail);
        TL_cube  = zeros(N_mc, n_depths, length(r_km));

        disp(sprintf('  [Tactical Console]: Loading %d-run acoustic ensemble across %d target depths (%s - %s)...', ...
                     N_mc, n_depths, format_depth_ft(z_avail(1)), format_depth_ft(z_avail(end))));
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

        % Map quick-jump preset buttons onto nearest exact Bellhop grid cells
        preset_idx = zeros(1, n_btns);
        for b = 1:n_btns
            [~, preset_idx(b)] = min(abs(z_avail - preset_nominal_m(b)));
        end
    else
        % Fallback to cached presets stored in MonteCarlo_Results.mat when .shd.mat files are unavailable
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
            avail_blocks = {TL_all};
        end
        z_avail  = avail_depths;
        n_depths = length(z_avail);
        TL_cube  = zeros(N_mc, n_depths, length(r_km));
        for bi = 1:n_depths
            TL_cube(1:size(avail_blocks{bi}, 1), bi, :) = avail_blocks{bi};
        end
        n_btns     = n_depths;
        preset_idx = 1:n_depths;
    end

    ownship_lbl   = format_depth_ft(ownship_depth_m);
    preset_depths = z_avail(preset_idx);
    preset_labels = arrayfun(@format_depth_ft, preset_depths, 'UniformOutput', false);

    [~, cur_depth_idx] = min(abs(z_avail - depth2plot));
    depth2plot = z_avail(cur_depth_idx);
    TL_all     = reshape(TL_cube(:, cur_depth_idx, :), N_mc, length(r_km));

    % --- 2. Sonar Figure of Merit (FOM) & Transmission Loss Statistics ---
    SL = 150; NL = 60; DI = 20; DT = 6;
    FOM = SL + DI - (NL + DT); % 104 dB

    % Standardized IQR-Based Cutoff Thresholds across all 100 target depths
    th_flat = 3.7; % Steady Cyany Green below All-Depth Q1 (3.72 dB)
    th_yel  = 6.5; % Yellow peak at All-Depth Q3 (6.50 dB); IQR = 3.7-6.5 dB

    % Fine range grid in kiloyards for smooth rendering
    r_fine = linspace(r_kyd(1), r_kyd(end), 300);
    N_fine = length(r_fine);

    if (isfield(data, 'base_test') && strcmp(data.base_test, 'Test2')) || ...
       (isfield(data, 'test_name') && strcmp(data.test_name, 'Test2'))
        attribution_text = 'Munk Canonical Profile Heave (Internal Wave Mode 1)';
        env_profile_name = 'MUNK CANONICAL DEEP SOUND CHANNEL';
    else
        attribution_text = 'HYCOM Thermocline Heave (Internal Wave Mode 1)';
        env_profile_name = 'NORTH ATLANTIC HYCOM';
    end

    % Sensitivity correlations between thermocline heave & bulk temperature
    if isfield(data, 'delta_z_all') && ~isempty(data.delta_z_all)
        delta_z_vec     = data.delta_z_all(:);
        bulk_offset_vec = data.bulk_offset_all(:);
    elseif isfield(data, 'all_perturbed_c') && ~isempty(data.all_perturbed_c)
        bulk_offset_vec = (data.all_perturbed_c(1, :) - data.base_c(1))';
        [~, idx_200]    = min(abs(data.base_z - 200));
        delta_c_core    = (data.all_perturbed_c(idx_200, :) - data.base_c(idx_200))' - bulk_offset_vec;
        delta_z_vec     = delta_c_core(:);
        bulk_offset_vec = bulk_offset_vec(:);
    else
        delta_z_vec     = randn(N_mc, 1);
        bulk_offset_vec = randn(N_mc, 1);
    end

    [TL_all, mean_TL, sigma_TL, Pd, Pd_fine, spread_fine, heave_fine, bulk_fine, ...
     R_nom, spread_kyd, conf_rating] = compute_depth_metrics(TL_all);

    % =============================================================
    % CREATE TACTICAL DISPLAY FIGURE
    % =============================================================
    c_bg_dark = [0.04, 0.05, 0.07]; % Deep Tactical Obsidian
    fig = figure('Position', [50, 30, 1280, 800], 'Color', c_bg_dark, ...
                 'Name', fig_name, ...
                 'MenuBar', 'none', 'NumberTitle', 'off');

    % -------------------------------------------------------------
    % PANEL 1: Circular Top-Down Radar Display (PPI Sweep)
    % -------------------------------------------------------------
    ax_ppi = subplot('Position', [0.02, 0.08, 0.47, 0.84]);
    set(ax_ppi, 'Color', [0.06, 0.08, 0.11]);
    hold on;
    axis equal;
    max_range = r_kyd(end); % kyd (40 km = 43.7 kyd)

    % Build 2D Polar Meshgrid (240 angle steps x 300 range steps)
    theta_mesh = linspace(0, 2*pi, 240);
    [R_mat, T_mat] = meshgrid(r_fine, theta_mesh);
    X_mat = R_mat .* cos(T_mat);
    Y_mat = R_mat .* sin(T_mat);

    % Full-Field Radar Uncertainty Heatmap (IQR Scale capped at p99 = 16.0 dB)
    max_spread = 16.0; % All-depth p99 (15.83 dB) saturation scale [0, 16] dB
    Var_slice = spread_fine;
    Var_mat   = repmat(Var_slice, length(theta_mesh), 1);

    % =============================================================
    % STRICTLY 3-COLOR SYSTEM: Cyany Green, Yellow, Red ONLY
    % =============================================================
    c_green  = [0.08, 0.82, 0.60]; % Crisp Tactical Cyany Green (Uniform below Q1 = 3.7 dB)
    c_yellow = [0.98, 0.85, 0.12]; % Vibrant Amber / Yellow (Q3 = 6.5 dB)
    c_red    = [0.95, 0.20, 0.20]; % Hot Tactical Red (Saturates at p99 = 16.0 dB)

    % th_flat (3.7 dB, Q1) and th_yel (6.5 dB, Q3) anchored across all depths
    % Matched 1:1 with Tactical Reliability Thresholds
    n_colors = 256;
    cmap_tactical = zeros(n_colors, 3);
    for k = 1:n_colors
        val = ((k - 1) / (n_colors - 1)) * max_spread;
        if val <= th_flat
            % Constant, simple, uniform Cyany Green below threshold
            cmap_tactical(k, :) = c_green;
        elseif val <= th_yel
            % Pure linear transition: Cyany Green -> Yellow
            t = (val - th_flat) / (th_yel - th_flat);
            cmap_tactical(k, :) = (1 - t) * c_green + t * c_yellow;
        else
            % Pure linear transition: Yellow -> Red
            t = (val - th_yel) / max(0.01, (max_spread - th_yel));
            cmap_tactical(k, :) = (1 - t) * c_yellow + t * c_red;
        end
    end

    % Render Full-Field Continuous Acoustic Uncertainty / Variance Field
    h_pcolor = pcolor(ax_ppi, X_mat, Y_mat, Var_mat);
    shading interp;
    colormap(ax_ppi, cmap_tactical);
    caxis(ax_ppi, [0, max_spread]);

    % Compact Vertical Colorbar for Continuous dB Readings (IQR scale 0-16 dB)
    cb_ppi = colorbar(ax_ppi, 'Position', [0.472, 0.12, 0.013, 0.32], ...
                      'Color', [0.65, 0.65, 0.65]);
    ylabel(cb_ppi, 'TL Spread \DeltaTL (dB)', 'FontSize', 8, 'FontName', 'Consolas', 'Color', [0.70, 0.70, 0.70]);
    set(cb_ppi, 'FontSize', 7.5, 'FontName', 'Consolas', 'Limits', [0, max_spread], ...
                'Ticks', [0, 3.7, 6.5, 10.7, 16]);

    % Transparent overlay axes strictly aligned with the colorbar for horizontal indicator line
    cb_pos = get(cb_ppi, 'Position');
    ax_cb_overlay = axes('Parent', fig, 'Position', cb_pos, 'Color', 'none', ...
                         'XLim', [0, 1.4], 'YLim', [0, max_spread], 'Visible', 'off', ...
                         'HitTest', 'off');
    hold(ax_cb_overlay, 'on');
    h_cb_line = plot(ax_cb_overlay, [0, 1.0], [NaN, NaN], '-', 'Color', [0.0, 0.0, 0.0], 'LineWidth', 2.8, 'Visible', 'off');
    h_cb_tag  = plot(ax_cb_overlay, 1.18, NaN, '<', 'MarkerFaceColor', [0.0, 0.0, 0.0], ...
                     'MarkerEdgeColor', [0.0, 0.0, 0.0], 'MarkerSize', 7, 'Visible', 'off');

    % Ownship Center Dot (Clean dot, no vertical line, no white edges)
    plot(ax_ppi, 0, 0, 'o', 'MarkerFaceColor', [0, 0, 0], 'MarkerEdgeColor', c_green, 'MarkerSize', 5.5);

    % Highlighting Ring (Pure Bold Tactical Black Ring)
    h_cursor_ring = plot(ax_ppi, NaN, NaN, '-', 'Color', [0.0, 0.0, 0.0], 'LineWidth', 2.8, 'Visible', 'off');

    % Highlighting Distance Caption (Follows the ring, no border color)
    h_cursor_txt = text(ax_ppi, NaN, NaN, '', ...
        'Color', [1.0, 1.0, 1.0], 'FontSize', 8.5, 'FontWeight', 'bold', ...
        'FontName', 'Consolas', 'BackgroundColor', [0.02, 0.04, 0.07, 0.90], ...
        'EdgeColor', 'none', ...
        'Margin', 2.5, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Visible', 'off', 'HitTest', 'off');

    % =============================================================
    % RADAR RANGE DISTANCE MARKERS (Cross-Ticks at 10, 20, 30, 40 kyd)
    % =============================================================
    range_markers = [10, 20, 30, 40];
    c_dist_tick   = [0.15, 0.15, 0.15]; % Tactical Dark Gray / Black
    for rm = range_markers
        % 4 Cardinal Cross-Ticks (North, East, South, West)
        plot(ax_ppi, [rm, rm], [-0.8, 0.8], '-', 'Color', c_dist_tick, 'LineWidth', 1.8);
        plot(ax_ppi, [-rm, -rm], [-0.8, 0.8], '-', 'Color', c_dist_tick, 'LineWidth', 1.8);
        plot(ax_ppi, [-0.8, 0.8], [rm, rm], '-', 'Color', c_dist_tick, 'LineWidth', 1.8);
        plot(ax_ppi, [-0.8, 0.8], [-rm, -rm], '-', 'Color', c_dist_tick, 'LineWidth', 1.8);

        % Tactical distance label along East spoke
        text(ax_ppi, rm, 1.6, sprintf('%d kyd', rm), ...
             'Color', [0.85, 0.85, 0.85], 'FontSize', 7.5, 'FontWeight', 'bold', ...
             'FontName', 'Consolas', 'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'bottom', ...
             'BackgroundColor', [0.03, 0.06, 0.10, 0.75], 'Margin', 2);
    end

    % =============================================================
    % CIRCULAR DIRECTIONAL DEGREES AXIS (Azimuth Compass Bezel)
    % =============================================================
    theta_circ = linspace(0, 2*pi, 360);

    % Outer Circular Radar Bezel Ring at max_range (43.7 kyd / 40 km)
    plot(ax_ppi, max_range * cos(theta_circ), max_range * sin(theta_circ), '-', ...
         'Color', [0.25, 0.45, 0.55], 'LineWidth', 1.6);

    % Circular Directional Degree Ticks and Azimuth Labels (000° to 350°)
    % Standard nautical bearing: 000° North (up), 090° East (right), 180° South (down), 270° West (left)
    for deg = 0:10:350
        rad = deg * pi / 180;
        sx = sin(rad); cy = cos(rad);
        if mod(deg, 30) == 0
            % Major tick mark (every 30°)
            plot(ax_ppi, [max_range * sx, (max_range + 1.4) * sx], ...
                         [max_range * cy, (max_range + 1.4) * cy], '-', ...
                 'Color', [0.35, 0.65, 0.75], 'LineWidth', 1.4);

            % Directional degree label around the perimeter
            lbl_r = max_range + 3.4;
            if deg == 0
                lbl_str = '000° N';
            elseif deg == 90
                lbl_str = '090° E';
            elseif deg == 180
                lbl_str = '180° S';
            elseif deg == 270
                lbl_str = '270° W';
            else
                lbl_str = sprintf('%03d°', deg);
            end
            text(ax_ppi, lbl_r * sx, lbl_r * cy, lbl_str, ...
                 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                 'Color', [0.45, 0.75, 0.85], 'FontSize', 7.5, 'FontWeight', 'bold', ...
                 'FontName', 'Consolas');
        else
            % Minor tick mark (every 10°)
            plot(ax_ppi, [max_range * sx, (max_range + 0.7) * sx], ...
                         [max_range * cy, (max_range + 0.7) * cy], '-', ...
                 'Color', [0.20, 0.38, 0.48], 'LineWidth', 0.8);
        end
    end

    xlim(ax_ppi, [-max_range - 5.5, max_range + 5.5]);
    ylim(ax_ppi, [-max_range - 5.5, max_range + 5.5]);
    axis(ax_ppi, 'off');

    % -------------------------------------------------------------
    % PANEL 2: Synchronized 1D Tactical Range Horizon & Spread
    % -------------------------------------------------------------
    ax_1d = subplot('Position', [0.52, 0.69, 0.45, 0.24]);
    set(ax_1d, 'Color', [0.08, 0.08, 0.08], 'XColor', [0.70, 0.70, 0.70], 'YColor', [0.70, 0.70, 0.70]);
    hold on;

    % 20 Monte Carlo lines in clean, clearly visible medium grayscale
    h_mc_lines = plot(ax_1d, r_kyd, TL_all', 'Color', [0.62, 0.62, 0.62, 0.55], 'LineWidth', 1.2);

    % Mean TL curve in cyan
    h_mean_line = plot(ax_1d, r_kyd, mean_TL, 'Color', [0.08, 0.85, 0.85], 'LineWidth', 2.4);

    yline(ax_1d, FOM, '--', sprintf('FOM = %d dB', FOM), 'Color', [0.75, 0.75, 0.75], ...
          'LineWidth', 1.8, 'LabelVerticalAlignment', 'bottom', 'FontSize', 9, ...
          'FontName', 'Consolas', 'FontWeight', 'bold');
      
    h_cutoff_1d = xline(ax_1d, R_nom, ':', sprintf('Cutoff: %.1f kyd', R_nom), 'Color', [0.65, 0.65, 0.65], ...
          'LineWidth', 1.4, 'LabelVerticalAlignment', 'top', 'FontSize', 9, ...
          'FontName', 'Consolas', 'FontWeight', 'bold');

    % Mark the exact intersection point with a star
    h_star = plot(ax_1d, R_nom, FOM, 'p', 'MarkerFaceColor', [0.85, 0.85, 0.85], ...
         'MarkerEdgeColor', [0.2, 0.2, 0.2], 'MarkerSize', 10);

    h_cursor_1d = xline(ax_1d, -999, '-', 'Color', [1.0, 1.0, 1.0], 'LineWidth', 2.5, 'Visible', 'off');

    set(ax_1d, 'YDir', 'reverse');
    xlim(ax_1d, [0, max_range]);
    xticks(ax_1d, 0:10:40);
    ylim(ax_1d, [55, 125]);
    grid(ax_1d, 'on');
    set(ax_1d, 'GridColor', [0.30, 0.30, 0.30], 'GridAlpha', 0.5);
    xlabel(ax_1d, 'Range (kyd)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', [0.75, 0.75, 0.75]);
    ylabel(ax_1d, 'Transmission Loss (dB)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', [0.75, 0.75, 0.75]);
    h_title_1d = title(ax_1d, {sprintf('ACOUSTIC TRANSMISSION LOSS (%s TARGET)', format_depth_ft(depth2plot)); ...
           sprintf('\\rmMonte Carlo Spread (N=%d runs)', N_mc)}, ...
          'Color', [0.85, 0.85, 0.85], 'FontSize', 9.5, 'FontName', 'Consolas', 'FontWeight', 'bold');

    % -------------------------------------------------------------
    % PANEL 3: Probability of Detection (Pd) Tactical Bar
    % -------------------------------------------------------------
    ax_pd = subplot('Position', [0.52, 0.37, 0.45, 0.21]);
    set(ax_pd, 'Color', [0.08, 0.08, 0.08], 'XColor', [0.70, 0.70, 0.70], 'YColor', [0.70, 0.70, 0.70]);
    hold on;

    h_pd_area = area(ax_pd, r_fine, Pd_fine, 'FaceColor', [0.45, 0.45, 0.45], 'EdgeColor', [0.75, 0.75, 0.75], ...
         'LineWidth', 1.6, 'FaceAlpha', 0.35);
    yline(ax_pd, 50, '--', '50% Threshold', 'Color', [0.70, 0.70, 0.70], 'LineWidth', 1.2, ...
          'FontSize', 8.5, 'FontName', 'Consolas');

    h_cutoff_pd = xline(ax_pd, R_nom, ':', sprintf('Cutoff: %.1f kyd', R_nom), 'Color', [0.65, 0.65, 0.65], ...
          'LineWidth', 1.4, 'LabelVerticalAlignment', 'top', 'FontSize', 8.5, ...
          'FontName', 'Consolas', 'FontWeight', 'bold');

    h_cursor_pd = xline(ax_pd, -999, '-', 'Color', [1.0, 1.0, 1.0], 'LineWidth', 2.5, 'Visible', 'off');

    xlim(ax_pd, [0, max_range]);
    xticks(ax_pd, 0:10:40);
    ylim(ax_pd, [0, 105]);
    grid(ax_pd, 'on');
    set(ax_pd, 'GridColor', [0.30, 0.30, 0.30], 'GridAlpha', 0.5);
    xlabel(ax_pd, 'Range (kyd)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', [0.75, 0.75, 0.75]);
    ylabel(ax_pd, 'Detection Prob P_d (%)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', [0.75, 0.75, 0.75]);
    h_title_pd = title(ax_pd, {sprintf('TACTICAL PROBABILITY OF DETECTION P_d(r) (%s TARGET)', format_depth_ft(depth2plot))}, ...
          'Color', [0.85, 0.85, 0.85], 'FontSize', 9.5, 'FontName', 'Consolas', 'FontWeight', 'bold');

    % -------------------------------------------------------------
    % PANEL 4: Target Submarine Depth Slider & Quick-Jump Presets
    % -------------------------------------------------------------
    btn_panel = uipanel('Parent', fig, 'Position', [0.52, 0.185, 0.45, 0.115], ...
                        'BackgroundColor', [0.05, 0.08, 0.12], 'BorderColor', [0.20, 0.45, 0.55]);

    uicontrol('Parent', btn_panel, 'Style', 'text', 'Units', 'normalized', ...
              'Position', [0.02, 0.72, 0.72, 0.24], ...
              'String', sprintf('TARGET SUBMARINE DEPTH (OWN-SHIP SONAR: %s FIXED):', ownship_lbl), ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.05, 0.08, 0.12], 'ForegroundColor', [0.45, 0.75, 0.85], ...
              'FontSize', 7.5, 'FontWeight', 'bold', 'FontName', 'Consolas');

    h_depth_readout = uicontrol('Parent', btn_panel, 'Style', 'text', 'Units', 'normalized', ...
              'Position', [0.74, 0.72, 0.24, 0.24], ...
              'String', format_depth_ft(depth2plot), ...
              'HorizontalAlignment', 'right', ...
              'BackgroundColor', [0.05, 0.08, 0.12], 'ForegroundColor', [0.35, 0.95, 0.90], ...
              'FontSize', 8.5, 'FontWeight', 'bold', 'FontName', 'Consolas');

    uicontrol('Parent', btn_panel, 'Style', 'text', 'Units', 'normalized', ...
              'Position', [0.02, 0.43, 0.09, 0.22], ...
              'String', format_depth_ft(z_avail(1)), ...
              'HorizontalAlignment', 'left', ...
              'BackgroundColor', [0.05, 0.08, 0.12], 'ForegroundColor', [0.55, 0.70, 0.80], ...
              'FontSize', 7.5, 'FontName', 'Consolas');

    uicontrol('Parent', btn_panel, 'Style', 'text', 'Units', 'normalized', ...
              'Position', [0.87, 0.43, 0.11, 0.22], ...
              'String', format_depth_ft(z_avail(end)), ...
              'HorizontalAlignment', 'right', ...
              'BackgroundColor', [0.05, 0.08, 0.12], 'ForegroundColor', [0.55, 0.70, 0.80], ...
              'FontSize', 7.5, 'FontName', 'Consolas');

    if n_depths > 1
        slider_step = [1 / (n_depths - 1), min(1, 5 / (n_depths - 1))];
        slider_max  = n_depths;
        slider_en   = 'on';
    else
        slider_step = [1, 1];
        slider_max  = 2;
        slider_en   = 'off';
    end

    h_depth_slider = uicontrol('Parent', btn_panel, 'Style', 'slider', 'Units', 'normalized', ...
              'Position', [0.11, 0.44, 0.75, 0.22], ...
              'Min', 1, 'Max', slider_max, 'Value', cur_depth_idx, ...
              'SliderStep', slider_step, 'Enable', slider_en, ...
              'BackgroundColor', [0.12, 0.18, 0.25], 'ForegroundColor', [0.35, 0.90, 0.85], ...
              'TooltipString', sprintf('Slide target submarine depth from %s to %s (~33 ft step)', ...
                                       format_depth_ft(z_avail(1)), format_depth_ft(z_avail(end))), ...
              'Callback', @(src, ~) on_slider_change(src, true));

    try
        addlistener(h_depth_slider, 'ContinuousValueChange', @(src, ~) on_slider_change(src, false));
    catch
        % Release Callback above still handles slider updates cleanly
    end

    btn_handles = gobjects(n_btns, 1);
    for b = 1:n_btns
        bx = (b - 1) / n_btns + 0.01;
        bw = (1 / n_btns) - 0.02;
        b_idx = preset_idx(b);
        if b_idx == cur_depth_idx
            btn_handles(b) = uicontrol('Parent', btn_panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
                      'Position', [bx, 0.06, bw, 0.30], ...
                      'String', preset_labels{b}, ...
                      'BackgroundColor', [0.10, 0.48, 0.42], 'ForegroundColor', 'w', ...
                      'FontSize', 8, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
                      'TooltipString', sprintf('Jump target depth to %s', preset_labels{b}), ...
                      'Callback', @(~, ~) set_target_depth_index(b_idx, true));
        else
            btn_handles(b) = uicontrol('Parent', btn_panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
                      'Position', [bx, 0.06, bw, 0.30], ...
                      'String', preset_labels{b}, ...
                      'BackgroundColor', [0.09, 0.14, 0.20], 'ForegroundColor', [0.55, 0.70, 0.80], ...
                      'FontSize', 8, 'FontName', 'Consolas', ...
                      'TooltipString', sprintf('Jump target depth to %s', preset_labels{b}), ...
                      'Callback', @(~, ~) set_target_depth_index(b_idx, true));
        end
    end

    % -------------------------------------------------------------
    % PANEL 5: Dedicated Acoustic Attribution & Uncertainty Inspector
    % -------------------------------------------------------------
    h_inspector_box = annotation('textbox', [0.52, 0.02, 0.45, 0.15], ...
        'BackgroundColor', [0.04, 0.07, 0.11, 0.95], ...
        'EdgeColor', c_green, 'LineWidth', 2.0, ...
        'Color', [1.0, 1.0, 1.0], 'FontSize', 9.5, 'FontName', 'Consolas', ...
        'FitBoxToText', 'off');

    % Top-Left System Telemetry Box
    hud_topleft = {
        '\bf[TACTICAL SONAR CONSOLE]';
        sprintf('ENV PROFILE  : %s', env_profile_name);
        sprintf('TARGET DEPTH : %s (OWNSHIP: %s)', format_depth_ft(depth2plot), ownship_lbl);
        sprintf('SYSTEM LIMIT : FOM = %d dB (SL:150 NL:60)', FOM)
    };
    h_topleft_box = annotation('textbox', [0.02, 0.86, 0.22, 0.11], 'String', hud_topleft, ...
               'BackgroundColor', [0.05, 0.08, 0.12, 0.85], 'EdgeColor', [0.20, 0.45, 0.55], ...
               'Color', [0.35, 0.90, 0.85], 'FontSize', 8.5, 'FontName', 'Consolas', 'FitBoxToText', 'on');

    % Bottom Tactical Estimation Box (Clean white style, no distracting green)
    hud_estimation = {
        sprintf('\\bf[TACTICAL ESTIMATION]  \\rmNominal Cutoff: \\bf%.1f kyd\\rm (\\pm%.1f kyd)  |  Confidence: \\bf%s\\rm  |  Target Cutoff: \\bf%d dB FOM\\rm', ...
                R_nom, spread_kyd, conf_rating, FOM);
        sprintf('Acoustic Environment: %s  |  Target Depth: %s (Ownship: %s)', env_profile_name, format_depth_ft(depth2plot), ownship_lbl)
    };
    h_estimation_box = annotation('textbox', [0.02, 0.02, 0.47, 0.045], 'String', hud_estimation, ...
               'BackgroundColor', [0.05, 0.08, 0.12, 0.88], 'EdgeColor', [1.0, 1.0, 1.0], ...
               'Color', [1.0, 1.0, 1.0], 'FontSize', 7.5, 'FontName', 'Consolas', 'FitBoxToText', 'off');

    % -------------------------------------------------------------
    % Dynamic Attribution Logic & Interactive Callbacks
    % -------------------------------------------------------------
    pinned_range = [];
    pinned_theta = pi / 4;

    function on_slider_change(src, is_commit)
        new_idx = max(1, min(n_depths, round(get(src, 'Value'))));
        if is_commit
            set(src, 'Value', new_idx);
        end
        if new_idx ~= cur_depth_idx || is_commit
            set_target_depth_index(new_idx, is_commit);
        end
    end

    function set_target_depth_index(new_idx, sync_slider)
        new_idx = max(1, min(n_depths, round(new_idx)));
        d_val   = z_avail(new_idx);
        changed = (new_idx ~= cur_depth_idx);
        cur_depth_idx = new_idx;
        depth2plot    = d_val;

        if changed
            [TL_all, mean_TL, sigma_TL, Pd, Pd_fine, spread_fine, heave_fine, bulk_fine, ...
             R_nom, spread_kyd, conf_rating] = compute_depth_metrics(reshape(TL_cube(:, cur_depth_idx, :), N_mc, length(r_km)));

            % Update radar uncertainty heatmap (colormap and [0, 20] scale are static)
            Var_mat = repmat(spread_fine, length(theta_mesh), 1);
            set(h_pcolor, 'CData', Var_mat);

            % Update 1D Transmission Loss lines & titles
            for mci = 1:N_mc
                set(h_mc_lines(mci), 'YData', TL_all(mci, :));
            end
            set(h_mean_line, 'YData', mean_TL);
            set(h_cutoff_1d, 'Value', R_nom, 'Label', sprintf('Cutoff: %.1f kyd', R_nom));
            set(h_star, 'XData', R_nom, 'YData', FOM);
            set(h_title_1d, 'String', {sprintf('ACOUSTIC TRANSMISSION LOSS (%s TARGET)', format_depth_ft(d_val)); ...
                                       sprintf('\\rmMonte Carlo Spread (N=%d runs)', N_mc)});

            % Update Pd plot
            set(h_pd_area, 'YData', Pd_fine);
            set(h_cutoff_pd, 'Value', R_nom, 'Label', sprintf('Cutoff: %.1f kyd', R_nom));
            set(h_title_pd, 'String', sprintf('TACTICAL PROBABILITY OF DETECTION P_d(r) (%s TARGET)', format_depth_ft(d_val)));

            % Update Telemetry, Slider Readout & Estimation HUD
            set(h_depth_readout, 'String', format_depth_ft(d_val));
            hud_topleft{3} = sprintf('TARGET DEPTH : %s (OWNSHIP: %s)', format_depth_ft(d_val), ownship_lbl);
            set(h_topleft_box, 'String', hud_topleft);
            hud_estimation = {
                sprintf('\\bf[TACTICAL ESTIMATION]  \\rmNominal Cutoff: \\bf%.1f kyd\\rm (\\pm%.1f kyd)  |  Confidence: \\bf%s\\rm  |  Target Cutoff: \\bf%d dB FOM\\rm', ...
                        R_nom, spread_kyd, conf_rating, FOM);
                sprintf('Acoustic Environment: %s  |  Target Depth: %s (Ownship: %s)', env_profile_name, format_depth_ft(d_val), ownship_lbl)
            };
            set(h_estimation_box, 'String', hud_estimation, 'EdgeColor', [1.0, 1.0, 1.0]);

            % Highlight quick-jump preset only when slider matches that exact grid depth
            for bi = 1:n_btns
                if preset_idx(bi) == cur_depth_idx
                    set(btn_handles(bi), 'BackgroundColor', [0.10, 0.48, 0.42], 'ForegroundColor', 'w', 'FontWeight', 'bold');
                else
                    set(btn_handles(bi), 'BackgroundColor', [0.09, 0.14, 0.20], 'ForegroundColor', [0.55, 0.70, 0.80], 'FontWeight', 'normal');
                end
            end
        end

        if sync_slider
            set(h_depth_slider, 'Value', cur_depth_idx);
            disp(['  [Tactical Console]: Target depth ', format_depth_ft(d_val), ' active (switched in real time).']);
        end

        if changed
            % Refresh inspector with active target depth
            [r_curr, th_curr] = get_hovered_range();
            if isnan(r_curr)
                if ~isempty(pinned_range)
                    r_curr = pinned_range;
                    th_curr = pinned_theta;
                else
                    r_curr = R_nom;
                    th_curr = pi / 4;
                end
            end
            update_inspector(r_curr, ~isempty(pinned_range), th_curr);
        end
    end

    function update_inspector(r_target, is_pinned, th_target)
        if nargin < 3 || isempty(th_target)
            th_target = pi / 4;
        end
        r_target = max(0, min(max_range, r_target));
        [~, k]   = min(abs(r_kyd - r_target));
        p_det    = interp1(r_kyd, Pd, r_target, 'linear', 'extrap');
        p_det    = max(0, min(100, p_det));
        tl_val   = mean_TL(k);
        tl_std   = sigma_TL(k);
        
        r_spread  = interp1(r_fine, spread_fine, r_target, 'nearest');
        cur_heave = interp1(r_fine, heave_fine, r_target, 'nearest');
        cur_bulk  = interp1(r_fine, bulk_fine,  r_target, 'nearest');
        heave_pct = round(cur_heave^2 * 100);

        sig_margin = FOM - tl_val; % Signal Excess / Margin relative to FOM (SE = FOM - TL)
        if sig_margin >= 0
            margin_str = sprintf('+%.1f dB Above FOM', sig_margin);
        else
            margin_str = sprintf('-%.1f dB Below FOM', abs(sig_margin));
        end

        % 1. Acoustic Reliability Status & exact gradient color matching
        k_color = round(1 + (min(max_spread, max(0, r_spread)) / max_spread) * (n_colors - 1));
        stat_color = cmap_tactical(k_color, :);

        if r_spread > 10.7
            rel_status = 'HIGH VOLATILITY (RED)';
        elseif r_spread > th_yel
            rel_status = 'ELEVATED VOLATILITY (AMBER)';
        elseif r_spread > th_flat
            rel_status = 'MODERATE FADING (YELLOW)';
        else
            rel_status = 'HIGH CONFIDENCE (GREEN)';
        end

        % 3. Data-Driven Ocean Cause ("The WHY")
        if abs(r_target - R_nom) <= (1.8 * KM_TO_KYD)
            if r_spread >= th_flat
                ocean_cause = sprintf('Shadow Boundary: Cutoff horizon (%.1f kyd) oscillates with wave heave (%.0f%% correlation)', R_nom, heave_pct);
            else
                ocean_cause = sprintf('Sharp Cutoff Horizon: Clean acoustic shadow transition at %.1f kyd with low multipath spread', R_nom);
            end
        elseif r_target < R_nom
            if r_spread >= th_yel
                if cur_heave >= 0.45
                    ocean_cause = sprintf('Thermocline Heave: Internal waves drive %.0f%% of variance, shifting surface duct across target', heave_pct);
                elseif cur_bulk >= 0.45
                    ocean_cause = sprintf('Thermal Stratification: Bulk water column warming/cooling shifts sound channel axis (%.0f%% correlation)', round(cur_bulk^2 * 100));
                else
                    ocean_cause = 'Multipath Interference: Chaotic phase cancellation between surface bounce and direct path';
                end
            elseif r_spread >= th_flat
                if cur_heave >= 0.35
                    ocean_cause = sprintf('Internal Wave Wobble: Heave shifts arrival angles, causing +/-%.1f dB fading (%.0f%% correlation)', r_spread/2, heave_pct);
                else
                    ocean_cause = 'Mixed-Layer Leakage: Rays intermittently escape the upper duct into the thermocline';
                end
            else
                if depth2plot >= 200
                    ocean_cause = sprintf('Deep Channel Stability: Target (%s) lies below surface internal waves (heave correlation %.0f%%)', format_depth_ft(depth2plot), heave_pct);
                else
                    ocean_cause = 'Direct Acoustic Path: Robust direct line-of-sight propagation with minimal wave scattering';
                end
            end
        else
            % Beyond nominal cutoff
            if r_spread >= th_yel
                ocean_cause = sprintf('Diffraction Fluctuation: Deep shadow zone with volatile diffracted energy (%.0f%% wave-driven)', heave_pct);
            elseif r_spread >= th_flat
                ocean_cause = 'Acoustic Shadow Leakage: Weak bottom-reflected energy fluctuating beyond nominal cutoff';
            else
                ocean_cause = 'Uniform Acoustic Shadow: Signal extinguished past cutoff; quiet noise floor across all runs';
            end
        end

        col_tag = sprintf('\\color[rgb]{%.2f,%.2f,%.2f}', stat_color(1), stat_color(2), stat_color(3));
        hud_txt = {
            sprintf('[RANGE: %.1f kyd]  (P_d = %.0f%%  |  %s)  [Target: %s]', ...
                    r_target, p_det, margin_str, format_depth_ft(depth2plot));
            sprintf('RELIABILITY : %s%s\\color[rgb]{1,1,1}  |  Acoustic Spread: \\Delta TL = %.1f dB (\\pm %.1f dB)', ...
                    col_tag, rel_status, r_spread, r_spread / 2);
            sprintf('OCEAN CAUSE : %s', ocean_cause)
        };
        set(h_inspector_box, 'String', hud_txt, 'EdgeColor', stat_color, 'LineWidth', 2.0);
        
        % Update horizontal indicator on the colorbar gradient
        set(h_cb_line, 'YData', [r_spread, r_spread], 'Visible', 'on');
        set(h_cb_tag,  'YData', r_spread, 'Visible', 'on');

        % Update highlighting ring graphics (pure bold black ring)
        theta_full = linspace(0, 2*pi, 180);
        x_c = r_target * cos(theta_full);
        y_c = r_target * sin(theta_full);
        set(h_cursor_ring, 'XData', x_c, 'YData', y_c, 'Visible', 'on');

        % Update distance caption following the ring
        if r_target < (max_range - 6.5)
            r_txt = r_target + 2.0;
        else
            r_txt = r_target - 2.0;
        end
        if r_target < 4.5
            r_txt = r_target + 2.4;
        end
        x_txt = r_txt * cos(th_target);
        y_txt = r_txt * sin(th_target);
        set(h_cursor_txt, 'Position', [x_txt, y_txt, 0], ...
                          'String', sprintf(' %.1f kyd ', r_target), ...
                          'EdgeColor', 'none', ...
                          'Visible', 'on');

        % Update vertical highlight lines (pure white, bold, brought to top)
        set(h_cursor_1d, 'Value', r_target, 'Visible', 'on');
        set(h_cursor_pd, 'Value', r_target, 'Visible', 'on');
        uistack(h_cursor_1d, 'top');
        uistack(h_cursor_pd, 'top');
    end

    function [r_found, th_found] = get_hovered_range()
        r_found = NaN;
        th_found = pi / 4;
        % Get mouse position in figure normalized units
        old_units = get(fig, 'Units');
        set(fig, 'Units', 'normalized');
        m_pos = get(fig, 'CurrentPoint');
        set(fig, 'Units', old_units);
        
        mx = m_pos(1);
        my = m_pos(2);
        
        % Check Radar PPI sweep
        pos_ppi = get(ax_ppi, 'Position');
        if mx >= pos_ppi(1) && mx <= (pos_ppi(1) + pos_ppi(3)) && ...
           my >= pos_ppi(2) && my <= (pos_ppi(2) + pos_ppi(4))
            cp = get(ax_ppi, 'CurrentPoint');
            r = sqrt(cp(1, 1)^2 + cp(1, 2)^2);
            if r <= (max_range + 1.0)
                r_found = min(max_range, max(0, r));
                th_found = atan2(cp(1, 2), cp(1, 1));
                return;
            end
        end
        
        % Check 1D TL axes
        pos_1d = get(ax_1d, 'Position');
        if mx >= pos_1d(1) && mx <= (pos_1d(1) + pos_1d(3)) && ...
           my >= pos_1d(2) && my <= (pos_1d(2) + pos_1d(4))
            cp = get(ax_1d, 'CurrentPoint');
            r_found = min(max_range, max(0, cp(1, 1)));
            th_found = pi / 4;
            return;
        end
        
        % Check Pd axes
        pos_pd = get(ax_pd, 'Position');
        if mx >= pos_pd(1) && mx <= (pos_pd(1) + pos_pd(3)) && ...
           my >= pos_pd(2) && my <= (pos_pd(2) + pos_pd(4))
            cp = get(ax_pd, 'CurrentPoint');
            r_found = min(max_range, max(0, cp(1, 1)));
            th_found = pi / 4;
            return;
        end
    end

    function on_mouse_move(~, ~)
        if ~isempty(pinned_range), return; end
        [r_found, th_found] = get_hovered_range();
        if ~isnan(r_found)
            update_inspector(r_found, false, th_found);
        end
    end

    function on_mouse_click(~, ~)
        [r_found, th_found] = get_hovered_range();
        if ~isnan(r_found)
            if isempty(pinned_range)
                pinned_range = r_found;
                pinned_theta = th_found;
                update_inspector(pinned_range, true, pinned_theta);
            else
                pinned_range = [];
                update_inspector(r_found, false, th_found);
            end
        end
    end

    % Set interactive mouse callbacks
    set(fig, 'WindowButtonMotionFcn', @on_mouse_move);
    set(fig, 'WindowButtonDownFcn',   @on_mouse_click);

    % Initialize with nominal detection range
    update_inspector(R_nom, false, pi / 4);

    % Auto-save high-resolution image to Outputs folder
    if exist(out_folder, 'dir') ~= 7
        mkdir(out_folder);
    end
    png_path = fullfile(out_folder, ['Tactical_Combat_Display', version_suffix, '.png']);
    try
        drawnow;
        frame = getframe(fig);
        imwrite(frame.cdata, png_path);
    catch
        try
            warn_id = 'MATLAB:exportgraphics:UIComponentsExcluded';
            warn_state = warning('query', warn_id);
            warning('off', warn_id);
            exportgraphics(fig, png_path, 'Resolution', 200);
            warning(warn_state.state, warn_id);
        catch
            saveas(fig, png_path);
        end
    end
    disp(['  Tactical Display exported: ', png_path]);

    function [TL_out, mean_out, sigma_out, Pd_out, Pd_fine_out, spread_fine_out, ...
              heave_fine_out, bulk_fine_out, R_nom_out, spread_kyd_out, conf_out] = compute_depth_metrics(TL_in)
        TL_out = TL_in;
        % Clean acoustic source singularity (Inf at r ~ 0 before rays launch)
        for mc_i = 1:N_mc
            idx_fin = find(~isinf(TL_out(mc_i, :)), 1, 'first');
            if ~isempty(idx_fin) && idx_fin > 1
                TL_out(mc_i, 1:idx_fin-1) = TL_out(mc_i, idx_fin);
            elseif isempty(idx_fin)
                TL_out(mc_i, :) = 140;
            end
        end

        mean_out  = mean(TL_out, 1);
        sigma_out = std(TL_out, 0, 1);
        spread_TL = max(TL_out, [], 1) - min(TL_out, [], 1); % Full Spread (Max - Min) across runs (dB)

        Pd_out = mean(TL_out <= FOM, 1) * 100;
        Pd_out = Pd_out(:)';

        Pd_fine_out = interp1(r_kyd, Pd_out, r_fine, 'pchip');
        Pd_fine_out = max(0, min(100, Pd_fine_out));
        Pd_fine_out = Pd_fine_out(:)';

        spread_fine_out = interp1(r_kyd, spread_TL, r_fine, 'pchip');
        mean_fine       = interp1(r_kyd, mean_out,  r_fine, 'pchip');

        % Data-driven ocean heave & bulk sensitivity across range
        r_heave = zeros(1, length(r_kyd));
        r_bulk  = zeros(1, length(r_kyd));
        for k_rng = 1:length(r_kyd)
            tl_col = TL_out(:, k_rng);
            tl_col = tl_col(:);
            if sigma_out(k_rng) > 0.05 && std(delta_z_vec) > 0
                c_h = corrcoef(tl_col, delta_z_vec);
                if ~isnan(c_h(1, 2)), r_heave(k_rng) = abs(c_h(1, 2)); end
            end
            if sigma_out(k_rng) > 0.05 && std(bulk_offset_vec) > 0
                c_b = corrcoef(tl_col, bulk_offset_vec);
                if ~isnan(c_b(1, 2)), r_bulk(k_rng) = abs(c_b(1, 2)); end
            end
        end
        heave_fine_out = interp1(r_kyd, r_heave, r_fine, 'pchip');
        bulk_fine_out  = interp1(r_kyd, r_bulk,  r_fine, 'pchip');

        % Key tactical boundaries (Nominal FOM Cutoff in kyd: persistent upward crossing into shadow)
        fom_diff = mean_fine - FOM;
        cross_indices = find(fom_diff(1:N_fine-1) .* fom_diff(2:N_fine) <= 0);
        all_crossings = [];
        up_crossings  = [];
        for ci = 1:length(cross_indices)
            k_c = cross_indices(ci);
            if fom_diff(k_c+1) ~= fom_diff(k_c)
                r_c = r_fine(k_c) - fom_diff(k_c) * (r_fine(k_c+1) - r_fine(k_c)) / (fom_diff(k_c+1) - fom_diff(k_c));
            else
                r_c = r_fine(k_c);
            end
            if isempty(all_crossings) || (r_c - all_crossings(length(all_crossings)) > 0.25 * KM_TO_KYD)
                all_crossings = [all_crossings, r_c];
            end
            if fom_diff(k_c) <= 0 && fom_diff(k_c+1) > 0
                if isempty(up_crossings) || (r_c - up_crossings(length(up_crossings)) > 0.25 * KM_TO_KYD)
                    up_crossings = [up_crossings, r_c];
                end
            end
        end

        R_nom_out = [];
        for ui = 1:length(up_crossings)
            r_u = up_crossings(ui);
            look_mask = (r_fine > r_u) & (r_fine <= min(r_fine(end), r_u + 1.0));
            if ~isempty(find(look_mask, 1)) && all(fom_diff(look_mask) > 0)
                R_nom_out = r_u;
                break;
            end
        end
        if isempty(R_nom_out)
            if ~isempty(up_crossings)
                R_nom_out = up_crossings(1);
            elseif ~isempty(all_crossings)
                R_nom_out = all_crossings(1);
            else
                idx_fom = find(mean_out <= FOM, 1, 'last');
                if isempty(idx_fom), R_nom_out = r_kyd(1); else, R_nom_out = r_kyd(idx_fom); end
            end
        end

        idx_90 = find(Pd_fine_out >= 90, 1, 'last'); if isempty(idx_90), idx_90 = 1; end
        idx_10 = find(Pd_fine_out >= 10, 1, 'last'); if isempty(idx_10), idx_10 = round(length(r_fine)/2); end
        R_guaranteed   = r_fine(idx_90);
        R_shadow       = r_fine(idx_10);
        spread_kyd_out = (R_shadow - R_guaranteed) / 2;
        if R_nom_out > 0
            uncertainty_pct = (spread_kyd_out / R_nom_out) * 100;
        else
            uncertainty_pct = 100;
        end

        if uncertainty_pct < 10
            conf_out = 'HIGH CONFIDENCE';
        elseif uncertainty_pct <= 25
            conf_out = 'MODERATE (YELLOW)';
        else
            conf_out = 'HIGH UNCERTAINTY (RED)';
        end
    end

    function lbl = format_depth_ft(depth_m)
        ft_val = round(depth_m * M_TO_FT);
        if ft_val >= 1000
            lbl = sprintf('%d,%03d ft', floor(ft_val / 1000), mod(ft_val, 1000));
        else
            lbl = sprintf('%d ft', ft_val);
        end
    end
end
