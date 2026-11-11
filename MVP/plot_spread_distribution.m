function plot_spread_distribution(results_or_ens, close_fig)
    % PLOT_SPREAD_DISTRIBUTION
    % Analyzes empirical Transmission Loss spread (Max - Min in dB) across all
    % modeled target depths (and 5 quick-compare preset depths) using the shared
    % adaptive IQR/boxplot calibration from compute_ensemble_stats.
    %
    % Displays:
    %   1. Horizontal IQR Boxplot (Q1, Median, Q3, 1.5*IQR Whiskers, Outliers)
    %   2. Empirical Histogram colored 1:1 with the GeoSit IQR gradient
    %   3. Multi-Depth CDF Cloud across all target depths + 5 preset curves

    if nargin < 1
        results_or_ens = [];
    end
    if nargin < 2 || isempty(close_fig)
        close_fig = false;
    end

    script_dir = fileparts(mfilename('fullpath'));
    if ~exist('compute_ensemble_stats', 'file')
        addpath(script_dir);
    end

    ens = compute_ensemble_stats(results_or_ens, script_dir);

    depth_stats    = ens.depth_stats;
    all_cdfs_x     = ens.all_cdfs_x;
    all_cdfs_y     = ens.all_cdfs_y;
    btn_keys       = ens.btn_keys;
    btn_labels     = ens.btn_labels;
    btn_tooltips   = ens.btn_tooltips;
    preset_keys    = ens.preset_keys;
    n_depths       = ens.n_depths;
    out_folder     = ens.out_folder;
    version_suffix = ens.version_suffix;
    cs             = ens.color_scale;

    % -------------------------------------------------------------
    % 1. Adaptive IQR Color Palette & Dynamic Axis Bounds
    % -------------------------------------------------------------
    c_bg_dark = [0.04, 0.05, 0.07];
    c_ax_bg   = [0.08, 0.08, 0.08];
    c_grid    = [0.28, 0.28, 0.28];
    c_text    = [0.75, 0.78, 0.82];

    c_green   = [0.08, 0.82, 0.60];
    c_yellow  = [0.98, 0.85, 0.12];
    c_red     = [0.95, 0.20, 0.20];
    c_active  = [0.08, 0.85, 0.85];

    th_green   = cs.th_flat;
    th_red     = cs.th_yel;
    tukey_ref  = cs.tukey_hi;
    max_spread = cs.max_spread;
    x_lim_max  = max(20, ceil(max_spread / 2) * 2 + 2);

    % -------------------------------------------------------------
    % 2. Build 3-Panel Diagnostic Figure (Boxplot + Histogram + CDF)
    % -------------------------------------------------------------
    screen_sz = get(0, 'ScreenSize');
    fig_w = min(1060, screen_sz(3) - 60);
    fig_h = min(800, screen_sz(4) - 60);
    fig_x = max(20, round((screen_sz(3) - fig_w) / 2));
    fig_y = max(30, round((screen_sz(4) - fig_h) / 2));

    fig = figure('Position', [fig_x, fig_y, fig_w, fig_h], 'Color', c_bg_dark, ...
                 'Name', 'ALL-DEPTH ACOUSTIC UNCERTAINTY IQR & DISTRIBUTION', ...
                 'MenuBar', 'none', 'NumberTitle', 'off');

    annotation('textbox', [0.06, 0.928, 0.42, 0.050], ...
               'String', '\bf[ALL-DEPTH SPREAD & IQR BOXPLOT]', ...
               'Color', c_active, 'FontSize', 10.5, 'FontName', 'Consolas', ...
               'EdgeColor', 'none', 'BackgroundColor', 'none');

    btn_panel = uipanel('Parent', fig, 'Position', [0.46, 0.922, 0.48, 0.056], ...
                        'BackgroundColor', [0.05, 0.08, 0.12], 'BorderColor', [0.20, 0.45, 0.55]);

    n_btns = length(btn_keys);
    btn_handles = gobjects(n_btns, 1);
    for b = 1:n_btns
        bx = (b - 1) / n_btns + 0.008;
        bw = (1 / n_btns) - 0.016;
        k_str = btn_keys{b};
        btn_handles(b) = uicontrol('Parent', btn_panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
                  'Position', [bx, 0.12, bw, 0.76], ...
                  'String', btn_labels{b}, ...
                  'BackgroundColor', [0.09, 0.14, 0.20], 'ForegroundColor', [0.60, 0.75, 0.85], ...
                  'FontSize', 8.5, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
                  'TooltipString', btn_tooltips{b}, ...
                  'Callback', @(~, ~) set_active_key(k_str));
    end

    ax_box = subplot('Position', [0.08, 0.765, 0.86, 0.110]);
    set(ax_box, 'Color', c_ax_bg, 'XColor', c_text, 'YColor', c_text);
    hold(ax_box, 'on');

    ax_hist = subplot('Position', [0.08, 0.435, 0.86, 0.245]);
    set(ax_hist, 'Color', c_ax_bg, 'XColor', c_text, 'YColor', c_text);
    hold(ax_hist, 'on');

    ax_cdf = subplot('Position', [0.08, 0.075, 0.86, 0.255]);
    set(ax_cdf, 'Color', c_ax_bg, 'XColor', c_text, 'YColor', c_text);
    hold(ax_cdf, 'on');

    if ~isempty(all_cdfs_x)
        for di = 1:length(all_cdfs_x)
            plot(ax_cdf, all_cdfs_x{di}, all_cdfs_y{di}, '-', ...
                 'Color', [0.50, 0.60, 0.72, 0.14], 'LineWidth', 0.7, ...
                 'HandleVisibility', 'off');
        end
    end

    line_styles = {'--', '-.', ':', '-', '-'};
    preset_cols = {
        [0.85, 0.65, 0.45];
        [0.95, 0.42, 0.42];
        [0.65, 0.78, 0.90];
        [0.45, 0.85, 0.65];
        [0.55, 0.62, 0.75]
    };

    n_pre = length(preset_keys);
    h_cdf_lines = gobjects(1 + n_pre, 1);
    cdf_keys    = [{'all'}, preset_keys];

    s_all = depth_stats.all;
    h_cdf_lines(1) = plot(ax_cdf, s_all.cdf_x, s_all.cdf_y, '-', ...
        'Color', c_active, 'LineWidth', 2.8, ...
        'DisplayName', sprintf('ALL %d DEPTHS  (Q1 %.1f | Med %.1f | Q3 %.1f | p99 %.1f)', ...
                               n_depths, s_all.q1, s_all.median, s_all.q3, s_all.p99));

    for b = 1:n_pre
        pk = preset_keys{b};
        s_d = depth_stats.(pk);
        col_use = preset_cols{min(b, length(preset_cols))};
        ls_use  = line_styles{min(b, length(line_styles))};
        h_cdf_lines(1 + b) = plot(ax_cdf, s_d.cdf_x, s_d.cdf_y, ls_use, ...
            'Color', col_use, 'LineWidth', 1.4, ...
            'DisplayName', sprintf('%s  (Med %.1f | IQR %.1f-%.1f)', s_d.label, s_d.median, s_d.q1, s_d.q3));
    end

    xline(ax_cdf, th_green,   ':', 'Color', c_green,  'LineWidth', 1.6, 'HandleVisibility', 'off');
    xline(ax_cdf, th_red,     ':', 'Color', c_yellow, 'LineWidth', 1.6, 'HandleVisibility', 'off');
    xline(ax_cdf, max_spread, ':', 'Color', c_red,    'LineWidth', 1.6, 'HandleVisibility', 'off');
    if th_green < 0.14 * x_lim_max
        text(ax_cdf, th_green + 0.18, 106, sprintf('Q1: %.1f dB (25%%)', th_green), ...
             'Color', c_green, 'FontSize', 8.3, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
    else
        text(ax_cdf, th_green - 0.15, 106, sprintf('Q1: %.1f dB (25%%)', th_green), ...
             'Color', c_green, 'FontSize', 8.3, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
    end
    text(ax_cdf, th_red + 0.15, 106, sprintf('Q3: %.1f dB (75%%)', th_red), ...
         'Color', c_yellow, 'FontSize', 8.3, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
    text(ax_cdf, max_spread - 0.15, 106, sprintf('Full Red: %.1f dB (p99)', max_spread), ...
         'Color', c_red, 'FontSize', 8.3, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');

    grid(ax_cdf, 'on');
    set(ax_cdf, 'GridColor', c_grid, 'GridAlpha', 0.45);
    xlim(ax_cdf, [0, x_lim_max]);
    ylim(ax_cdf, [0, 113]);
    yticks(ax_cdf, 0:20:100);
    xlabel(ax_cdf, 'Transmission Loss Spread \DeltaTL = Max - Min (dB)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);
    ylabel(ax_cdf, 'Cumulative Cells (%)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);
    title(ax_cdf, sprintf('CUMULATIVE UNCERTAINTY ACROSS ALL %d DEPTHS (GRAY CLOUD = INDIVIDUAL DEPTHS)', n_depths), ...
          'Color', [0.88, 0.90, 0.92], 'FontSize', 9.0, 'FontName', 'Consolas', 'FontWeight', 'bold');
    legend(ax_cdf, h_cdf_lines, 'TextColor', [0.88, 0.90, 0.92], 'Color', [0.06, 0.08, 0.11], ...
           'EdgeColor', [0.28, 0.32, 0.38], 'Location', 'southeast', ...
           'FontSize', 7.6, 'FontName', 'Consolas');

    % -------------------------------------------------------------
    % 3. Dynamic Key Switcher (Updates Boxplot + Histogram + CDF)
    % -------------------------------------------------------------
    active_key = 'all';

    function set_active_key(k_in)
        if ~isfield(depth_stats, k_in), return; end
        active_key = k_in;
        s = depth_stats.(active_key);

        for bi = 1:n_btns
            if strcmp(btn_keys{bi}, active_key)
                set(btn_handles(bi), 'BackgroundColor', [0.10, 0.48, 0.42], 'ForegroundColor', 'w', 'FontWeight', 'bold');
            else
                set(btn_handles(bi), 'BackgroundColor', [0.09, 0.14, 0.20], 'ForegroundColor', [0.60, 0.75, 0.85], 'FontWeight', 'normal');
            end
        end

        for ci = 1:length(cdf_keys)
            if isgraphics(h_cdf_lines(ci))
                if strcmp(cdf_keys{ci}, active_key)
                    set(h_cdf_lines(ci), 'Color', c_active, 'LineWidth', 3.0, 'LineStyle', '-');
                    uistack(h_cdf_lines(ci), 'top');
                else
                    if ci == 1
                        set(h_cdf_lines(ci), 'Color', [0.88, 0.92, 0.96], 'LineWidth', 2.0, 'LineStyle', '-');
                    else
                        col_p = preset_cols{min(ci - 1, length(preset_cols))};
                        ls_p  = line_styles{min(ci - 1, length(line_styles))};
                        set(h_cdf_lines(ci), 'Color', col_p, 'LineWidth', 1.3, 'LineStyle', ls_p);
                    end
                end
            end
        end

        % --- PANEL 1: Horizontal IQR Boxplot Strip ---
        cla(ax_box);
        hold(ax_box, 'on');

        xline(ax_box, th_green,   '--', 'Color', [c_green,  0.45], 'LineWidth', 1.2);
        xline(ax_box, th_red,     '--', 'Color', [c_yellow, 0.45], 'LineWidth', 1.2);
        xline(ax_box, tukey_ref,  ':',  'Color', [0.95, 0.65, 0.25, 0.45], 'LineWidth', 1.2);
        xline(ax_box, max_spread, ':',  'Color', [c_red,    0.45], 'LineWidth', 1.2);

        w_hi_plot = min(s.w_high, x_lim_max - 0.3);
        q3_plot   = min(s.q3, x_lim_max - 0.2);
        q1_plot   = min(s.q1, q3_plot);
        med_plot  = min(max(s.median, q1_plot), q3_plot);

        plot(ax_box, [s.w_low, q1_plot],     [1.0, 1.0], '-', 'Color', [0.75, 0.82, 0.90], 'LineWidth', 1.8);
        plot(ax_box, [q3_plot, w_hi_plot],   [1.0, 1.0], '-', 'Color', [0.75, 0.82, 0.90], 'LineWidth', 1.8);
        plot(ax_box, [s.w_low, s.w_low],     [0.84, 1.16], '-', 'Color', [0.75, 0.82, 0.90], 'LineWidth', 1.8);
        plot(ax_box, [w_hi_plot, w_hi_plot], [0.84, 1.16], '-', 'Color', [0.75, 0.82, 0.90], 'LineWidth', 1.8);

        patch(ax_box, [q1_plot, med_plot, med_plot, q1_plot], [0.72, 0.72, 1.28, 1.28], ...
              [0.08, 0.46, 0.42], 'FaceAlpha', 0.85, 'EdgeColor', 'none');
        patch(ax_box, [med_plot, q3_plot, q3_plot, med_plot], [0.72, 0.72, 1.28, 1.28], ...
              [0.52, 0.56, 0.14], 'FaceAlpha', 0.85, 'EdgeColor', 'none');
        plot(ax_box, [q1_plot, q3_plot, q3_plot, q1_plot, q1_plot], [0.72, 0.72, 1.28, 1.28, 0.72], ...
             '-', 'Color', [0.88, 0.94, 0.98], 'LineWidth', 1.5);
        plot(ax_box, [med_plot, med_plot], [0.68, 1.32], '-', 'Color', [1.0, 1.0, 1.0], 'LineWidth', 3.0);

        if ~isempty(s.outliers)
            out_vis = unique(round(min(s.outliers, x_lim_max - 0.35) * 6) / 6);
            plot(ax_box, out_vis, ones(size(out_vis)), 'o', ...
                 'MarkerSize', 3.8, 'MarkerFaceColor', c_red, 'MarkerEdgeColor', [1.0, 0.55, 0.55]);
        end

        text(ax_box, med_plot, 1.56, sprintf('Med: %.1f dB', s.median), ...
             'Color', [1.0, 1.0, 1.0], 'FontSize', 8.2, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        text(ax_box, q1_plot - 0.15, 0.36, sprintf('Q1: %.1f', s.q1), ...
             'Color', c_green, 'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
        text(ax_box, q3_plot + 0.15, 0.36, sprintf('Q3: %.1f', s.q3), ...
             'Color', c_yellow, 'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
        if w_hi_plot > q3_plot + 1.4
            text(ax_box, w_hi_plot, 0.36, sprintf('Whisker: %.1f', s.w_high), ...
                 'Color', [0.95, 0.65, 0.25], 'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
                 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        end
        text(ax_box, x_lim_max - 0.25, 1.58, sprintf('IQR = %.1f dB  |  Outliers (>Q3+1.5 IQR): %.1f%%', s.iqr, s.pct_outliers), ...
             'Color', [0.85, 0.88, 0.92], 'BackgroundColor', c_ax_bg, 'Margin', 1, ...
             'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');

        grid(ax_box, 'on');
        set(ax_box, 'GridColor', c_grid, 'GridAlpha', 0.35, 'YTick', [], 'XTick', 0:2:x_lim_max, 'XTickLabel', []);
        xlim(ax_box, [0, x_lim_max]);
        ylim(ax_box, [0.05, 1.85]);
        ylabel(ax_box, 'IQR Box', 'FontSize', 8.5, 'FontName', 'Consolas', 'Color', c_text);
        title(ax_box, sprintf('%s   (%s cells)   —   IQR BOXPLOT (GEOSIT SCALE)', upper(s.label), commafy(s.n_pts)), ...
              'Color', [0.92, 0.94, 0.96], 'FontSize', 9.2, 'FontName', 'Consolas', 'FontWeight', 'bold');

        % --- PANEL 2: Histogram (Matched 1:1 with GeoSit IQR Gradient) ---
        cla(ax_hist);
        hold(ax_hist, 'on');

        bin_w = 0.5;
        n_bins = round(x_lim_max / bin_w);
        bin_edges = linspace(0, x_lim_max, n_bins + 1);
        [counts, ~] = histcounts(min(s.spread, x_lim_max - 0.001), bin_edges);
        pct_counts = (counts / length(s.spread)) * 100;
        bin_centers = 0.5 * (bin_edges(1:n_bins) + bin_edges(2:n_bins+1));

        for bi = 1:n_bins
            bc = bin_centers(bi);
            bar_col = eval_geosit_color(bc, th_green, th_red, max_spread, c_green, c_yellow, c_red);
            bar(ax_hist, bc, pct_counts(bi), bin_w, ...
                'FaceColor', bar_col, 'EdgeColor', [0.04, 0.04, 0.04], 'FaceAlpha', 0.92);
        end

        y_max = max(12, max(pct_counts) * 1.40);

        xline(ax_hist, th_green,   '--', 'Color', c_green,            'LineWidth', 1.8);
        xline(ax_hist, th_red,     '--', 'Color', c_yellow,           'LineWidth', 1.8);
        xline(ax_hist, tukey_ref,  ':',  'Color', [0.95, 0.65, 0.25], 'LineWidth', 1.6);
        xline(ax_hist, max_spread, ':',  'Color', c_red,              'LineWidth', 1.8);

        if th_green < 0.16 * x_lim_max
            text(ax_hist, th_green + 0.18, y_max * 0.94, sprintf('Green <= %.1f (Q1)', th_green), ...
                 'Color', c_green, 'BackgroundColor', c_ax_bg, 'Margin', 1, ...
                 'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
                 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
        else
            text(ax_hist, th_green - 0.15, y_max * 0.94, sprintf('Green <= %.1f (Q1)', th_green), ...
                 'Color', c_green, 'BackgroundColor', c_ax_bg, 'Margin', 1, ...
                 'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
                 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
        end
        text(ax_hist, th_red + 0.15, y_max * 0.94, sprintf('Yellow = %.1f (Q3)', th_red), ...
             'Color', c_yellow, 'BackgroundColor', c_ax_bg, 'Margin', 1, ...
             'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
        text(ax_hist, tukey_ref + 0.15, y_max * 0.80, sprintf('Whisker: %.1f', tukey_ref), ...
             'Color', [0.95, 0.65, 0.25], 'BackgroundColor', c_ax_bg, 'Margin', 1, ...
             'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
        text(ax_hist, max_spread - 0.15, y_max * 0.94, sprintf('Full Red: %.1f (p99)', max_spread), ...
             'Color', c_red, 'BackgroundColor', c_ax_bg, 'Margin', 1, ...
             'FontSize', 8.0, 'FontName', 'Consolas', 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');

        grid(ax_hist, 'on');
        set(ax_hist, 'GridColor', c_grid, 'GridAlpha', 0.45, 'XTick', 0:2:x_lim_max);
        xlim(ax_hist, [0, x_lim_max]);
        ylim(ax_hist, [0, y_max]);
        xlabel(ax_hist, sprintf('Transmission Loss Spread \\DeltaTL = Max - Min (dB)   [Last bin includes >%d dB tail]', x_lim_max), ...
               'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);
        ylabel(ax_hist, 'Share of Cells (%)', 'FontSize', 9, 'FontName', 'Consolas', 'Color', c_text);

        col_g = sprintf('\\color[rgb]{%.2f,%.2f,%.2f}', c_green(1), c_green(2), c_green(3));
        col_y = sprintf('\\color[rgb]{%.2f,%.2f,%.2f}', c_yellow(1), c_yellow(2), c_yellow(3));
        col_r = sprintf('\\color[rgb]{%.2f,%.2f,%.2f}', c_red(1), c_red(2), c_red(3));

        title(ax_hist, sprintf('\\rmQ1 / Med / Q3 / Whisker / p99: \\bf%.1f / %.1f / %.1f / %.1f / %.1f dB\\rm (Max %.1f)  |  IQR Split: %s%.1f%% Steady\\rm, %s%.1f%% IQR\\rm, %s%.1f%% Upper\\rm', ...
                               s.q1, s.median, s.q3, s.w_high, s.p99, s.max, col_g, s.pct_green, col_y, s.pct_yellow, col_r, s.pct_red), ...
              'Color', [0.90, 0.92, 0.95], 'FontSize', 8.8, 'FontName', 'Consolas', 'FontWeight', 'bold');
    end

    set_active_key('all');

    % Export updated PNG cleanly & mirror across canonical output folders
    if exist(out_folder, 'dir') ~= 7
        mkdir(out_folder);
    end
    png_out = fullfile(out_folder, ['TL_Spread_Distribution', version_suffix, '.png']);
    try
        drawnow;
        pause(0.15);
        frame = getframe(fig);
        imwrite(frame.cdata, png_out);
    catch
        try
            exportgraphics(fig, png_out, 'Resolution', 180, 'BackgroundColor', c_bg_dark);
        catch
            try
                print(fig, png_out, '-dpng', '-r200');
            catch
                saveas(fig, png_out);
            end
        end
    end

    fprintf('  Spread distribution figure exported: %s\n', png_out);
    fprintf('  ALL DEPTHS IQR STATS: Q1=%.2f | Med=%.2f | Q3=%.2f | IQR=%.2f | Whisker=%.2f | p95=%.2f | p99=%.2f | Max=%.2f dB (Outliers=%.2f%%)\n', ...
            s_all.q1, s_all.median, s_all.q3, s_all.iqr, s_all.w_high, s_all.p95, s_all.p99, s_all.max, s_all.pct_outliers);
    fprintf('  IQR GeoSit Split (<=%.1f / %.1f-%.1f / >%.1f dB, Red cap %.1f): %.1f%% Steady | %.1f%% IQR | %.1f%% Upper (%.2f%% >%.1f dB)\n', ...
            th_green, th_green, th_red, th_red, max_spread, ...
            s_all.pct_green, s_all.pct_yellow, s_all.pct_red, mean(s_all.spread > max_spread) * 100, max_spread);

    if close_fig && isgraphics(fig)
        close(fig);
    end
end

function col = eval_geosit_color(val, th_flat, th_yel, max_sp, c_green, c_yellow, c_red)
    if val <= th_flat
        col = c_green;
    elseif val <= th_yel
        t = (val - th_flat) / max(0.01, (th_yel - th_flat));
        col = (1 - t) * c_green + t * c_yellow;
    else
        t = min(1.0, max(0.0, (val - th_yel) / max(0.01, (max_sp - th_yel))));
        col = (1 - t) * c_yellow + t * c_red;
    end
end

function out = commafy(n)
    out = regexprep(sprintf('%d', round(n)), '(\d)(?=(\d{3})+$)', '$1,');
end
