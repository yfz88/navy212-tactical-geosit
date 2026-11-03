function plot_spread_distribution(results_file)
    % PLOT_SPREAD_DISTRIBUTION
    % Diagnostic tool to analyze the empirical Transmission Loss spread
    % (Max - Min in dB) distribution across sensor depths, matching the
    % exact styling and 3-color system of GeoSit Option B.
    %
    % Displays:
    %   1. Active Depth 3-Color Histogram: Cyany Green, Yellow, and Red bars
    %      with Median and Cutoff reference lines.
    %   2. Comparative Cumulative Distribution (CDF): Visualizes all 5 depths
    %      to show why coloring shifts between green, yellow, and red.
    %   3. Simple Real-Time Depth Buttons: [20 m] [50 m] [100 m] [200 m] [500 m].

    if nargin < 1 || isempty(results_file)
        results_file = fullfile(pwd, 'Outputs', 'MonteCarlo_Results.mat');
    end

    if ~exist(results_file, 'file')
        error('Results file not found: %s. Run run_monte_carlo first.', results_file);
    end

    data = load(results_file);
    r_km = data.r_km(:)';
    N_mc = data.N_mc;

    preset_depths = [20, 50, 100, 200, 500];
    preset_labels = {'20 m', '50 m', '100 m', '200 m', '500 m'};
    n_btns        = length(preset_depths);
    active_depth  = 100;
    if isfield(data, 'depth2plot') && any(preset_depths == data.depth2plot)
        active_depth = data.depth2plot;
    end

    % -------------------------------------------------------------
    % 1. Pre-load or extract multi-depth 20-run acoustic ensemble
    % -------------------------------------------------------------
    TL_by_depth = containers.Map('KeyType', 'int32', 'ValueType', 'any');
    if isfield(data, 'TL_depths') && isstruct(data.TL_depths)
        for d = preset_depths
            f_name = sprintf('d%d', d);
            if isfield(data.TL_depths, f_name)
                TL_by_depth(int32(d)) = data.TL_depths.(f_name);
            end
        end
    end

    if isempty(TL_by_depth) || ~isKey(TL_by_depth, int32(active_depth))
        out_folder = fileparts(results_file);
        if isempty(out_folder), out_folder = fullfile(pwd, 'Outputs'); end

        has_shd = true;
        for i = 1:N_mc
            if ~exist(fullfile(out_folder, sprintf('Test_MC_%d.shd.mat', i)), 'file')
                has_shd = false; break;
            end
        end

        if has_shd
            disp('  [Spread Distribution]: Extracting 20-run acoustic ensemble across depths...');
            z_vec = data.z_m;
            TL_depths_extracted = struct();
            for d = preset_depths
                TL_depths_extracted.(sprintf('d%d', d)) = zeros(N_mc, length(r_km));
            end
            for i = 1:N_mc
                shd_file = fullfile(out_folder, sprintf('Test_MC_%d.shd.mat', i));
                res = load(shd_file, 'pressure');
                TL_2d = -20 * log10(squeeze(abs(res.pressure)));
                for d = preset_depths
                    [~, idx_d] = min(abs(z_vec - d));
                    row_d = TL_2d(idx_d, :);
                    if isinf(row_d(1)), row_d(1) = row_d(3); end
                    if isinf(row_d(2)), row_d(2) = row_d(3); end
                    TL_depths_extracted.(sprintf('d%d', d))(i, :) = row_d;
                end
            end
            for d = preset_depths
                TL_by_depth(int32(d)) = TL_depths_extracted.(sprintf('d%d', d));
            end
            try
                TL_depths = TL_depths_extracted;
                save(results_file, 'TL_depths', '-append');
            catch
            end
        else
            TL_by_depth(int32(active_depth)) = data.TL_all;
        end
    end

    % -------------------------------------------------------------
    % 2. Exact Colors Matched to GeoSit Option B
    % -------------------------------------------------------------
    c_bg_dark = [0.04, 0.05, 0.07]; % Deep Tactical Obsidian
    c_ax_bg   = [0.08, 0.08, 0.08]; % Grayscale axes background
    c_grid    = [0.30, 0.30, 0.30]; % Grayscale grid
    c_text    = [0.70, 0.70, 0.70]; % Grayscale text & labels

    % Strict 3-Color Palette (Identical to GeoSit B)
    c_green   = [0.08, 0.82, 0.60]; % Crisp Tactical Cyany Green (<= 4.5 dB)
    c_yellow  = [0.98, 0.85, 0.12]; % Vibrant Amber / Yellow (4.5 - 7.5 dB)
    c_red     = [0.95, 0.20, 0.20]; % Hot Tactical Red (> 7.5 dB)
    c_active  = [0.08, 0.85, 0.85]; % Active Accent Cyan

    th_green  = 4.5; % Flat green threshold
    th_red    = 7.5; % Yellow-to-red threshold

    % Compute distribution stats for each depth
    depth_stats = struct();
    for d = preset_depths
        if isKey(TL_by_depth, int32(d))
            tl_mat = TL_by_depth(int32(d));
            for row = 1:N_mc
                if isinf(tl_mat(row, 1)), tl_mat(row, 1) = tl_mat(row, 3); end
                if isinf(tl_mat(row, 2)), tl_mat(row, 2) = tl_mat(row, 3); end
            end
            sp = max(tl_mat, [], 1) - min(tl_mat, [], 1);
            sp = sp(isfinite(sp));
            sp_sort = sort(sp);
            n_pts = length(sp_sort);

            s.spread     = sp;
            s.min        = min(sp);
            s.max        = max(sp);
            s.median     = median(sp);
            s.p33        = sp_sort(max(1, round(0.333 * n_pts)));
            s.p66        = sp_sort(min(n_pts, round(0.667 * n_pts)));

            s.pct_green  = mean(sp <= th_green) * 100;
            s.pct_yellow = mean(sp > th_green & sp <= th_red) * 100;
            s.pct_red    = mean(sp > th_red) * 100;

            s.cdf_x = [0, sp_sort];
            s.cdf_y = [0, (1:n_pts) / n_pts * 100];

            depth_stats.(sprintf('d%d', d)) = s;
        end
    end

    % -------------------------------------------------------------
    % 3. Create Clean Diagnostic Figure
    % -------------------------------------------------------------
    % Safe screen-centered sizing to ensure window and buttons never clip on any monitor
    screen_sz = get(0, 'ScreenSize');
    fig_w = min(980, screen_sz(3) - 60);
    fig_h = min(700, screen_sz(4) - 80);
    fig_x = max(20, round((screen_sz(3) - fig_w) / 2));
    fig_y = max(40, round((screen_sz(4) - fig_h) / 2));

    fig = figure('Position', [fig_x, fig_y, fig_w, fig_h], 'Color', c_bg_dark, ...
                 'Name', 'ACOUSTIC UNCERTAINTY DISTRIBUTION (GEOSIT B MATCHED)', ...
                 'MenuBar', 'none', 'NumberTitle', 'off');

    % Header text
    annotation('textbox', [0.08, 0.915, 0.38, 0.055], ...
               'String', '\bf[ACOUSTIC SPREAD DISTRIBUTION]', ...
               'Color', c_active, 'FontSize', 10, 'FontName', 'Consolas', ...
               'EdgeColor', 'none', 'BackgroundColor', 'none');

    % Simple Depth Selector Buttons in Top Header
    btn_panel = uipanel('Parent', fig, 'Position', [0.48, 0.905, 0.44, 0.065], ...
                        'BackgroundColor', [0.05, 0.08, 0.12], 'BorderColor', [0.20, 0.45, 0.55]);

    btn_handles = gobjects(n_btns, 1);
    for b = 1:n_btns
        bx = (b - 1) / n_btns + 0.01;
        bw = (1 / n_btns) - 0.02;
        d_val = preset_depths(b);
        btn_handles(b) = uicontrol('Parent', btn_panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
                  'Position', [bx, 0.10, bw, 0.80], ...
                  'String', preset_labels{b}, ...
                  'BackgroundColor', [0.09, 0.14, 0.20], 'ForegroundColor', [0.55, 0.70, 0.80], ...
                  'FontSize', 8.5, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
                  'TooltipString', sprintf('Inspect spread distribution at %d m', d_val), ...
                  'Callback', @(~, ~) set_active_depth(d_val));
    end

    % PANEL 1: Active Depth 3-Color Histogram
    ax_hist = subplot('Position', [0.08, 0.52, 0.84, 0.31]);
    set(ax_hist, 'Color', c_ax_bg, 'XColor', c_text, 'YColor', c_text);
    hold(ax_hist, 'on');

    % PANEL 2: Multi-Depth Cumulative Distribution Comparison (CDF)
    ax_cdf = subplot('Position', [0.08, 0.10, 0.84, 0.31]);
    set(ax_cdf, 'Color', c_ax_bg, 'XColor', c_text, 'YColor', c_text);
    hold(ax_cdf, 'on');

    % Grayscale line styles for all 5 depths
    line_styles = {'-', '--', '-.', ':', '-'};
    gray_shades = {
        [0.50, 0.50, 0.50];  % 20 m
        [0.62, 0.62, 0.62];  % 50 m
        [0.72, 0.72, 0.72];  % 100 m
        [0.55, 0.55, 0.55];  % 200 m
        [0.42, 0.42, 0.42]   % 500 m
    };

    h_cdf_lines = gobjects(n_btns, 1);
    for b = 1:n_btns
        d_val = preset_depths(b);
        s_key = sprintf('d%d', d_val);
        if isfield(depth_stats, s_key)
            s_d = depth_stats.(s_key);
            h_cdf_lines(b) = plot(ax_cdf, s_d.cdf_x, s_d.cdf_y, line_styles{b}, ...
                'Color', gray_shades{b}, 'LineWidth', 1.3, ...
                'DisplayName', sprintf('%d m  (Median: %.1f dB | %.0f%% Green)', d_val, s_d.median, s_d.pct_green));
        end
    end

    % Reference cutoffs on CDF (matching GeoSit B)
    xline(ax_cdf, th_green, ':', sprintf('Green Cutoff: %.1f dB', th_green), ...
          'Color', c_green, 'LineWidth', 1.6, 'LabelVerticalAlignment', 'bottom', ...
          'FontSize', 8.5, 'FontName', 'Consolas', 'FontWeight', 'bold');
    xline(ax_cdf, th_red, ':', sprintf('Yellow/Red: %.1f dB', th_red), ...
          'Color', c_red, 'LineWidth', 1.6, 'LabelVerticalAlignment', 'bottom', ...
          'FontSize', 8.5, 'FontName', 'Consolas', 'FontWeight', 'bold');

    grid(ax_cdf, 'on');
    set(ax_cdf, 'GridColor', c_grid, 'GridAlpha', 0.5);
    xlim(ax_cdf, [0, 20]);
    ylim(ax_cdf, [0, 105]);
    xlabel(ax_cdf, 'Transmission Loss Spread \DeltaTL = Max - Min (dB)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);
    ylabel(ax_cdf, 'Cumulative Range Points (%)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);
    title(ax_cdf, {'CUMULATIVE SPREAD DISTRIBUTION ACROSS ALL SENSOR DEPTHS'}, ...
          'Color', [0.85, 0.85, 0.85], 'FontSize', 9.5, 'FontName', 'Consolas', 'FontWeight', 'bold');
    h_leg = legend(ax_cdf, 'TextColor', [0.85, 0.85, 0.85], 'Color', c_ax_bg, ...
                   'EdgeColor', [0.25, 0.25, 0.25], 'Location', 'southeast', ...
                   'FontSize', 8, 'FontName', 'Consolas');

    % -------------------------------------------------------------
    % 4. Dynamic Depth Switcher
    % -------------------------------------------------------------
    function set_active_depth(d_in)
        active_depth = d_in;
        s_key = sprintf('d%d', active_depth);
        if ~isfield(depth_stats, s_key), return; end
        s = depth_stats.(s_key);

        % Update button highlights
        for bi = 1:n_btns
            if preset_depths(bi) == active_depth
                set(btn_handles(bi), 'BackgroundColor', [0.10, 0.48, 0.42], 'ForegroundColor', 'w', 'FontWeight', 'bold');
            else
                set(btn_handles(bi), 'BackgroundColor', [0.09, 0.14, 0.20], 'ForegroundColor', [0.55, 0.70, 0.80], 'FontWeight', 'normal');
            end
        end

        % Highlight active depth curve in CDF plot (emphasized in Cyan, others in gray)
        for bi = 1:n_btns
            if isgraphics(h_cdf_lines(bi))
                if preset_depths(bi) == active_depth
                    set(h_cdf_lines(bi), 'Color', c_active, 'LineWidth', 2.6, 'LineStyle', '-');
                    uistack(h_cdf_lines(bi), 'top');
                else
                    set(h_cdf_lines(bi), 'Color', gray_shades{bi}, 'LineWidth', 1.2, 'LineStyle', line_styles{bi});
                end
            end
        end

        % Redraw Subplot 1 (Active Depth Histogram)
        cla(ax_hist);
        hold(ax_hist, 'on');

        n_bins = 25;
        bin_edges = linspace(0, 20, n_bins + 1); % Firmly locked [0, 20] dB scale (0.8 dB per bin)
        counts = histcounts(s.spread, bin_edges);
        bin_centers = 0.5 * (bin_edges(1:n_bins) + bin_edges(2:n_bins+1));
        bar_w = bin_edges(2) - bin_edges(1);

        % Strict 3 Colors matching GeoSit B
        for bi = 1:n_bins
            bc = bin_centers(bi);
            if bc <= th_green
                bar_col = c_green;   % Cyany Green (<= 4.5 dB)
            elseif bc <= th_red
                bar_col = c_yellow;  % Vibrant Yellow (4.5 - 7.5 dB)
            else
                bar_col = c_red;     % Tactical Red (> 7.5 dB)
            end
            bar(ax_hist, bc, counts(bi), bar_w, ...
                'FaceColor', bar_col, 'EdgeColor', [0.04, 0.04, 0.04], 'FaceAlpha', 0.90);
        end

        % Reference Lines
        xline(ax_hist, s.median, '-', sprintf('Median: %.1f dB', s.median), ...
              'Color', [1.0, 1.0, 1.0], 'LineWidth', 2.0, 'FontSize', 8.5, 'FontName', 'Consolas', 'FontWeight', 'bold');
        xline(ax_hist, th_green, '--', sprintf('Green Cutoff: %.1f dB', th_green), ...
              'Color', c_green, 'LineWidth', 1.8, 'FontSize', 8.5, 'FontName', 'Consolas', 'FontWeight', 'bold');
        xline(ax_hist, th_red, '--', sprintf('Yellow/Red: %.1f dB', th_red), ...
              'Color', c_red, 'LineWidth', 1.8, 'FontSize', 8.5, 'FontName', 'Consolas', 'FontWeight', 'bold');

        grid(ax_hist, 'on');
        set(ax_hist, 'GridColor', c_grid, 'GridAlpha', 0.5);
        xlim(ax_hist, [0, 20]); % Firmly locked to match CDF and prevent scale jumping
        xlabel(ax_hist, 'Transmission Loss Spread \DeltaTL = Max - Min (dB)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);
        ylabel(ax_hist, 'Number of Range Cells', 'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);
        
        % Descriptive concise title matching GeoSit B colors
        col_g = sprintf('\\color[rgb]{%.2f,%.2f,%.2f}', c_green(1), c_green(2), c_green(3));
        col_y = sprintf('\\color[rgb]{%.2f,%.2f,%.2f}', c_yellow(1), c_yellow(2), c_yellow(3));
        col_r = sprintf('\\color[rgb]{%.2f,%.2f,%.2f}', c_red(1), c_red(2), c_red(3));

        title(ax_hist, {sprintf('ACOUSTIC UNCERTAINTY DISTRIBUTION (%d m DEPTH)', active_depth); ...
                        sprintf('\\rmMedian: \\bf%.1f dB\\rm  |  Spread: \\bf%.1f - %.1f dB\\rm  |  Radar Color Breakdown: %s%.0f%% Green\\rm, %s%.0f%% Yellow\\rm, %s%.0f%% Red\\rm', ...
                                s.median, s.min, s.max, col_g, s.pct_green, col_y, s.pct_yellow, col_r, s.pct_red)}, ...
              'Color', [0.85, 0.85, 0.85], 'FontSize', 9.5, 'FontName', 'Consolas', 'FontWeight', 'bold');
    end

    % Initialize with active depth
    set_active_depth(active_depth);

    % Auto-save high-resolution image capturing all UI buttons and panels
    png_out = fullfile(pwd, 'Outputs', 'TL_Spread_Distribution.png');
    try
        drawnow;
        frame = getframe(fig);
        imwrite(frame.cdata, png_out);
    catch
        try
            print(fig, png_out, '-dpng', '-r200');
        catch
            saveas(fig, png_out);
        end
    end
    disp(['  Spread distribution figure exported: ', png_out]);
end
