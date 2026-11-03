function plot_geosit_optionA(results_file, initial_depth)
    % PLOT_GEOSIT_OPTIONA
    % Top-Down Geographic Situation (GeoSit) Spatial Stoplight Map
    %
    % Option A: The Full-Field Stoplight View
    %
    % Dual Mode Display:
    %   1. 2D Symmetric Mode: Classic range-independent benchmark (concentric stoplight rings)
    %   2. 3D NOAA Bathymetry Mode: Real-world Western North Atlantic / Cape Hatteras slope
    %      (ETOPO 2022 15-arcsecond bathymetry: asymmetric green sound channels & red shadow zones)
    %
    % Interactive Controls:
    %   • Operational Sensor Depth: [20 m (Ship)] [50 m (Duct)] [100 m] [200 m (Best Dipping)] [500 m]
    %   • Propagation Mode: [2D SYMMETRIC BENCHMARK] vs [3D REAL NOAA BATHYMETRY]
    %
    % Usage:
    %   plot_geosit_optionA()           % Default: loads Outputs/MonteCarlo_Results.mat at 100m
    %   plot_geosit_optionA([], 200)     % Starts at 200m dipping sonar depth

    if nargin < 1 || isempty(results_file)
        results_file = fullfile(pwd, 'Outputs', 'MonteCarlo_Results.mat');
    end
    if nargin < 2 || isempty(initial_depth)
        initial_depth = 100; % Default to 100m
    end

    if ~exist(results_file, 'file')
        error('Results file not found: %s. Run run_monte_carlo first.', results_file);
    end

    % Close any existing instance to clear old callbacks
    old_fig = findobj('Type', 'figure', 'Name', 'OPTION A: TOP-DOWN GEOSIT SPATIAL STOPLIGHT DISPLAY');
    if ~isempty(old_fig)
        close(old_fig);
    end

    % --- 1. Load Simulation Data ---
    data         = load(results_file);
    r_km         = data.r_km(:)'; % [1 x Nr]
    z_m          = data.z_m(:);   % [Nz x 1]
    TL_full_mean = data.TL_full_mean;
    N_mc         = data.N_mc;
    Nr           = length(r_km);
    Nz           = length(z_m);

    SL = 150; NL = 60; DI = 20; DT = 6;
    FOM = SL + DI - (NL + DT); % 104 dB
    sigma_eff = 4.0; % dB effective environmental uncertainty

    % Calculate Full-Field Probability of Detection (Pd_2d) across Depth & Range
    if isfield(data, 'Pd_full') && ~isempty(data.Pd_full)
        Pd_2d = data.Pd_full;
    else
        SE_2d = FOM - TL_full_mean;
        Pd_2d = 0.5 * (1 + erf(SE_2d ./ (sigma_eff * sqrt(2)))) * 100;
        Pd_2d = max(0, min(100, Pd_2d));
    end

    % --- 2. Load or Compute 3D Real NOAA Bathymetry ---
    noaa_mat_file = fullfile(pwd, 'Outputs', 'NOAA_Bathymetry_Polar.mat');
    has_noaa = exist(noaa_mat_file, 'file') == 2;
    
    Ntheta = 240;
    theta_rad = linspace(0, 2*pi, Ntheta); % Compass bearing: 0=North, pi/2=East, pi=South, 3pi/2=West

    if has_noaa
        noaa_data = load(noaa_mat_file);
        bathy_matrix = noaa_data.bathy_matrix; % [Ntheta x Nr], depth in meters
        ownship_lat = noaa_data.ownship_lat;
        ownship_lon = noaa_data.ownship_lon;
    else
        % Synthetic fallback if NOAA MAT file not yet extracted
        ownship_lat = 37.0; ownship_lon = -74.2;
        [R_tmp, T_tmp] = meshgrid(r_km, theta_rad);
        % Shoals to North/West, deep to South/East
        bathy_matrix = 2100 - 1500 * (R_tmp/40) .* (cos(T_tmp) - 0.5*sin(T_tmp));
        bathy_matrix = max(10, min(3000, bathy_matrix));
    end

    % Ensure bathy_matrix matches the simulation range dimension Nr exactly
    if size(bathy_matrix, 2) ~= Nr
        r_bathy_in = linspace(r_km(1), r_km(end), size(bathy_matrix, 2));
        bathy_matrix = interp1(r_bathy_in, bathy_matrix', r_km, 'linear', 'extrap')';
    end

    % Pre-compute Coupled Directional Transmission Loss & Pd across all bearings
    % Acoustic Physics: In deep water (>2200m), sound channels without seabed reflection.
    % In water shoaling towards shelf break (<1500m down to 100m), seabed absorbs energy.
    D_crit = 2200.0; % critical depth where bottom rays interact with seafloor
    delta_tl_bathy = zeros(Ntheta, Nr);
    for ti = 1:Ntheta
        d_prof = bathy_matrix(ti, :);
        shoal_factor = max(0, (D_crit - d_prof) ./ D_crit);
        cum_loss = cumsum(shoal_factor .^ 1.8) * 0.15;
        % Shelf cutoff: where depth is shallower than 100m, sound rapidly crashes into seabed
        cutoff_mask = (d_prof < 100.0);
        cum_loss(cutoff_mask) = cum_loss(cutoff_mask) + 60.0;
        delta_tl_bathy(ti, :) = cum_loss;
    end

    % --- 3. Compute Dipping Sonar Optimization Profile across Depth ---
    r_green_max = zeros(Nz, 1);
    for j = 1:Nz
        idx = find(Pd_2d(j, :) >= 70, 1, 'last');
        if ~isempty(idx)
            r_green_max(j) = r_km(idx);
        else
            r_green_max(j) = 0;
        end
    end

    op_mask = (z_m >= 20 & z_m <= 800);
    z_op = z_m(op_mask);
    r_op = r_green_max(op_mask);
    [best_range, best_idx] = max(r_op);
    optimal_dipping_depth = z_op(best_idx);

    [~, idx_50m] = min(abs(z_m - 50));
    range_at_50m = r_green_max(idx_50m);

    % --- 4. Custom Tactical Stoplight Colormap (Deep Red -> Yellow -> Phosphor Green) ---
    cmap_stoplight = zeros(256, 3);
    for k = 1:256
        frac = (k - 1) / 255;
        if frac <= 0.30
            % Deep Shadow Red -> Warm Red/Amber (0% to 30%)
            t = frac / 0.30;
            cmap_stoplight(k, :) = [0.65, 0.10, 0.15] * (1 - t) + [0.92, 0.35, 0.15] * t;
        elseif frac <= 0.65
            % Red/Amber -> Tactical Yellow (30% to 65%)
            t = (frac - 0.30) / 0.35;
            cmap_stoplight(k, :) = [0.92, 0.35, 0.15] * (1 - t) + [0.95, 0.82, 0.15] * t;
        else
            % Tactical Yellow -> Vibrant Phosphor Green (65% to 100%)
            t = (frac - 0.65) / 0.35;
            cmap_stoplight(k, :) = [0.95, 0.82, 0.15] * (1 - t) + [0.10, 0.88, 0.45] * t;
        end
    end

    % --- 5. Build Top-Down GeoSit Display Figure ---
    c_bg_dark = [0.04, 0.05, 0.07]; % Deep Tactical Obsidian
    fig = figure('Position', [35, 25, 1380, 840], 'Color', c_bg_dark, ...
                 'Name', 'OPTION A: TOP-DOWN GEOSIT SPATIAL STOPLIGHT DISPLAY', ...
                 'MenuBar', 'none', 'NumberTitle', 'off', ...
                 'WindowButtonDownFcn', [], 'WindowButtonMotionFcn', []);

    % -------------------------------------------------------------
    % PANEL 1: Top-Down Geographic Situation (GeoSit) Radar Scope
    % -------------------------------------------------------------
    ax_geosit = subplot('Position', [0.03, 0.08, 0.58, 0.84]);
    set(ax_geosit, 'Color', [0.06, 0.08, 0.11]);
    hold on;
    axis equal;
    max_range = 40; % km

    % Navigational Polar Coordinate Grid:
    % theta_rad: 0=North (+Y), pi/2=East (+X), pi=South (-Y), 3pi/2=West (-X)
    [R_mesh, T_mesh] = meshgrid(r_km, theta_rad);
    X_mat = R_mesh .* sin(T_mesh); % East (km)
    Y_mat = R_mesh .* cos(T_mesh); % North (km)

    % Active display state variables
    current_depth = initial_depth;
    current_mode  = 'NOAA'; % Default to 3D NOAA Bathymetry Mode
    [~, cur_idx]  = min(abs(z_m - current_depth));

    % Initial Surface Plot
    dummy_mat = zeros(size(X_mat));
    h_surf = pcolor(ax_geosit, X_mat, Y_mat, dummy_mat);
    shading interp;
    colormap(ax_geosit, cmap_stoplight);
    caxis([0, 100]);

    % Bathymetry Contour Overlays (500m, 1000m, 2000m Depth Contours)
    [~, h_contour] = contour(ax_geosit, X_mat, Y_mat, bathy_matrix, [200, 500, 1000, 2000], ...
                             '--', 'LineColor', [0.35, 0.60, 0.70], 'LineWidth', 0.9);

    % Draw Range Rings (10, 20, 30, 40 km)
    theta_circ = linspace(0, 2*pi, 360);
    for r_idx = 10:10:max_range
        plot(ax_geosit, r_idx * sin(theta_circ), r_idx * cos(theta_circ), '-', ...
             'Color', [0.20, 0.40, 0.48], 'LineWidth', 0.9);
        text(ax_geosit, r_idx * sin(pi/4), r_idx * cos(pi/4), sprintf(' %d km', r_idx), ...
             'FontSize', 8.5, 'Color', [0.55, 0.80, 0.90], 'FontWeight', 'bold', 'FontName', 'Consolas');
    end

    % Outer Radar Boundary
    plot(ax_geosit, max_range * sin(theta_circ), max_range * cos(theta_circ), '-', ...
         'Color', [0.35, 0.65, 0.75], 'LineWidth', 1.8);

    % Compass Rose Tick Marks & Azimuth Degree Labels (Every 30°)
    for deg = 0:30:330
        rad = deg * pi / 180;
        plot(ax_geosit, [max_range * sin(rad), (max_range + 1.2) * sin(rad)], ...
                        [max_range * cos(rad), (max_range + 1.2) * cos(rad)], '-', ...
                        'Color', [0.45, 0.75, 0.85], 'LineWidth', 1.2);
        
        lbl_r = max_range + 3.2;
        text(ax_geosit, lbl_r * sin(rad), lbl_r * cos(rad), sprintf('%03d°', deg), ...
             'HorizontalAlignment', 'center', 'Color', [0.55, 0.80, 0.90], ...
             'FontSize', 8, 'FontWeight', 'bold', 'FontName', 'Consolas');
    end

    % Azimuth Bearing Crosshairs
    plot(ax_geosit, [-max_range, max_range], [0, 0], ':', 'Color', [0.18, 0.30, 0.38], 'LineWidth', 0.8);
    plot(ax_geosit, [0, 0], [-max_range, max_range], ':', 'Color', [0.18, 0.30, 0.38], 'LineWidth', 0.8);

    % Cardinal Labels
    text(ax_geosit, 0, max_range + 5.2, '\bfN (000°)', 'HorizontalAlignment', 'center', 'Color', [0.40, 0.90, 1.0], 'FontSize', 9, 'FontName', 'Consolas');
    text(ax_geosit, max_range + 6.2, 0, '\bfE (090°)', 'HorizontalAlignment', 'center', 'Color', [0.40, 0.90, 1.0], 'FontSize', 9, 'FontName', 'Consolas');
    text(ax_geosit, 0, -max_range - 5.2, '\bfS (180°)', 'HorizontalAlignment', 'center', 'Color', [0.40, 0.90, 1.0], 'FontSize', 9, 'FontName', 'Consolas');
    text(ax_geosit, -max_range - 6.2, 0, '\bfW (270°)', 'HorizontalAlignment', 'center', 'Color', [0.40, 0.90, 1.0], 'FontSize', 9, 'FontName', 'Consolas');

    % Ownship Center Glyph with Heading Vector (Steering North 000°)
    plot(ax_geosit, 0, 0, 'o', 'MarkerFaceColor', [0.1, 0.95, 0.8], 'MarkerEdgeColor', 'w', 'MarkerSize', 7);
    plot(ax_geosit, [0, 0], [0, 3.2], 'Color', [0.1, 0.95, 0.8], 'LineWidth', 2.2);

    xlim(ax_geosit, [-max_range - 7, max_range + 7]);
    ylim(ax_geosit, [-max_range - 7, max_range + 7]);
    axis(ax_geosit, 'off');

    % Colorbar for Stoplight Scale
    cb = colorbar(ax_geosit, 'Position', [0.03, 0.03, 0.28, 0.025], 'Orientation', 'horizontal');
    set(cb, 'Color', [0.80, 0.90, 0.95], 'FontSize', 8, 'FontName', 'Consolas');
    set(cb, 'Ticks', [15, 50, 85], ...
            'TickLabels', {'RED: Hiding Zone (<30%)', 'YELLOW: Uncertain (30-70%)', 'GREEN: Clear Contact (>=70%)'});

    % Top-Left GeoSit Header Box
    hud_topleft = {
        '\bf[TOP-DOWN GEOSIT: OPTION A]';
        'SYSTEM : SPATIAL STOPLIGHT DISPLAY';
        sprintf('ACTIVE SENSOR DEPTH: \\bf%d m', round(current_depth));
        'DATASET: REAL NOAA ETOPO 2022 (CAPE HATTERAS SLOPE)'
    };
    h_topleft_box = annotation('textbox', [0.03, 0.86, 0.28, 0.11], 'String', hud_topleft, ...
               'BackgroundColor', [0.05, 0.08, 0.12, 0.85], 'EdgeColor', [0.20, 0.45, 0.55], ...
               'Color', [0.35, 0.90, 0.85], 'FontSize', 8.5, 'FontName', 'Consolas', 'FitBoxToText', 'on');

    % -------------------------------------------------------------
    % PANEL 2: Synchronized 1D Radial Detection Profiles (North vs South)
    % -------------------------------------------------------------
    ax_profile = subplot('Position', [0.65, 0.67, 0.32, 0.25]);
    set(ax_profile, 'Color', [0.07, 0.09, 0.13], 'XColor', [0.55, 0.70, 0.80], 'YColor', [0.55, 0.70, 0.80]);
    hold on;

    r_fine = linspace(r_km(1), r_km(end), 300);
    h_line_south = plot(ax_profile, r_km, zeros(size(r_km)), '-', 'Color', [0.10, 0.95, 0.60], ...
                        'LineWidth', 2.0, 'DisplayName', 'South 180° (Deep Basin Channel)');
    h_line_north = plot(ax_profile, r_km, zeros(size(r_km)), '--', 'Color', [0.95, 0.30, 0.30], ...
                        'LineWidth', 2.0, 'DisplayName', 'North 000° (Shelf Cutoff)');

    yline(ax_profile, 50, ':', '50% Threshold', 'Color', [0.95, 0.75, 0.15], ...
          'LineWidth', 1.2, 'FontSize', 8, 'FontName', 'Consolas');

    xlim(ax_profile, [0, 40]);
    ylim(ax_profile, [0, 105]);
    grid on;
    set(ax_profile, 'GridColor', [0.20, 0.30, 0.40], 'GridAlpha', 0.5);
    xlabel(ax_profile, 'Range (km)', 'FontSize', 8.5, 'FontName', 'Consolas');
    ylabel(ax_profile, 'P_d (%)', 'FontSize', 8.5, 'FontName', 'Consolas');
    h_profile_title = title(ax_profile, 'DIRECTIONAL DETECTION PROFILE: NORTH VS SOUTH', ...
                            'Color', [0.80, 0.92, 0.98], 'FontSize', 9, 'FontName', 'Consolas', 'FontWeight', 'bold');
    legend(ax_profile, [h_line_south, h_line_north], 'Location', 'northeast', ...
           'TextColor', [0.85, 0.92, 0.98], 'Color', [0.05, 0.08, 0.12], 'FontSize', 7.5);

    % -------------------------------------------------------------
    % PANEL 3A: Interactive Propagation Mode Switcher (2D vs 3D NOAA)
    % -------------------------------------------------------------
    mode_panel = uipanel('Parent', fig, 'Position', [0.65, 0.585, 0.32, 0.065], ...
                         'BackgroundColor', [0.05, 0.08, 0.12], 'BorderColor', [0.20, 0.50, 0.65]);

    uicontrol('Parent', mode_panel, 'Style', 'text', 'Units', 'normalized', ...
              'Position', [0.02, 0.58, 0.96, 0.38], ...
              'String', 'PROPAGATION MODE (CLICK TO TOGGLE):', ...
              'BackgroundColor', [0.05, 0.08, 0.12], 'ForegroundColor', [0.45, 0.75, 0.85], ...
              'FontSize', 7.5, 'FontWeight', 'bold', 'FontName', 'Consolas');

    h_btn_2d = uicontrol('Parent', mode_panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
              'Position', [0.02, 0.08, 0.47, 0.50], ...
              'String', '2D SYMMETRIC BENCHMARK', ...
              'BackgroundColor', [0.10, 0.20, 0.28], 'ForegroundColor', [0.70, 0.85, 0.95], ...
              'FontSize', 7.5, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
              'Callback', @(~, ~) set_mode('2D'));

    h_btn_noaa = uicontrol('Parent', mode_panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
              'Position', [0.51, 0.08, 0.47, 0.50], ...
              'String', '3D NOAA BATHYMETRY', ...
              'BackgroundColor', [0.15, 0.45, 0.35], 'ForegroundColor', 'w', ...
              'FontSize', 7.5, 'FontWeight', 'bold', 'FontName', 'Consolas', ...
              'Callback', @(~, ~) set_mode('NOAA'));

    % -------------------------------------------------------------
    % PANEL 3B: Interactive Sensor Depth Buttons
    % -------------------------------------------------------------
    depth_panel = uipanel('Parent', fig, 'Position', [0.65, 0.505, 0.32, 0.068], ...
                          'BackgroundColor', [0.05, 0.08, 0.12], 'BorderColor', [0.20, 0.45, 0.55]);

    uicontrol('Parent', depth_panel, 'Style', 'text', 'Units', 'normalized', ...
              'Position', [0.02, 0.58, 0.96, 0.38], ...
              'String', 'SELECT OPERATIONAL SENSOR DEPTH (CLICK TO SWITCH):', ...
              'BackgroundColor', [0.05, 0.08, 0.12], 'ForegroundColor', [0.45, 0.75, 0.85], ...
              'FontSize', 7.5, 'FontWeight', 'bold', 'FontName', 'Consolas');

    preset_depths = [20, 50, 100, 200, 500];
    preset_labels = {'20 m (Ship)', '50 m (Duct)', '100 m (Cruise)', '200 m (Dipping)', '500 m (Deep)'};
    n_btns = length(preset_depths);

    for b = 1:n_btns
        bx = (b - 1) / n_btns + 0.01;
        bw = (1 / n_btns) - 0.02;
        d_val = preset_depths(b);
        uicontrol('Parent', depth_panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
                  'Position', [bx, 0.08, bw, 0.50], ...
                  'String', preset_labels{b}, ...
                  'BackgroundColor', [0.10, 0.22, 0.30], 'ForegroundColor', 'w', ...
                  'FontSize', 7.5, 'FontName', 'Consolas', ...
                  'Callback', @(~, ~) set_sensor_depth(d_val));
    end

    % -------------------------------------------------------------
    % PANEL 4: Tactical Mission Guidance HUD Card
    % -------------------------------------------------------------
    h_hud_box = annotation('textbox', [0.65, 0.04, 0.32, 0.44], ...
        'BackgroundColor', [0.04, 0.07, 0.11, 0.95], ...
        'EdgeColor', [0.20, 0.50, 0.65], 'LineWidth', 1.4, ...
        'Color', [0.85, 0.92, 0.98], 'FontSize', 8, 'FontName', 'Consolas', ...
        'FitBoxToText', 'off');

    % --- Core Display Render & Update Function ---
    function update_display(new_d, new_mode)
        current_depth = new_d;
        current_mode  = new_mode;
        [~, d_idx]    = min(abs(z_m - current_depth));
        base_slice    = Pd_2d(d_idx, :); % [1 x Nr]
        TL_base_slice = TL_full_mean(d_idx, :); % [1 x Nr]

        if strcmp(current_mode, 'NOAA')
            % Directional 3D NOAA Bathymetry Mode
            set(h_btn_noaa, 'BackgroundColor', [0.15, 0.55, 0.35], 'ForegroundColor', 'w');
            set(h_btn_2d,   'BackgroundColor', [0.10, 0.20, 0.28], 'ForegroundColor', [0.70, 0.85, 0.95]);
            set(h_contour, 'Visible', 'on');

            % Calculate Pd across each azimuth angle using coupled bathymetric loss
            Pd_mat = zeros(Ntheta, Nr);
            for ti = 1:Ntheta
                TL_dir = TL_base_slice + delta_tl_bathy(ti, :);
                SE_dir = FOM - TL_dir;
                Pd_rad = 0.5 * (1 + erf(SE_dir ./ (sigma_eff * sqrt(2)))) * 100;
                % Zero out if seafloor is shallower than sensor depth
                Pd_rad(bathy_matrix(ti, :) < current_depth) = 0;
                Pd_mat(ti, :) = max(0, min(100, Pd_rad));
            end

            % Update top-down radar sweep
            set(h_surf, 'CData', Pd_mat);

            % Update 1D profile with North (000°) vs South (180°)
            idx_north = 1;                     % Bearing 000°
            idx_south = round(Ntheta / 2);     % Bearing 180°
            set(h_line_south, 'YData', Pd_mat(idx_south, :), 'Visible', 'on');
            set(h_line_north, 'YData', Pd_mat(idx_north, :), 'Visible', 'on');
            set(h_profile_title, 'String', sprintf('P_d PROFILE: NORTH (SHELF) VS SOUTH (DEEP) AT %d m', round(current_depth)));

            % Update Top-Left box
            hud_topleft{3} = sprintf('ACTIVE SENSOR DEPTH: \\bf%d m', round(current_depth));
            hud_topleft{4} = 'DATASET: \\bf3D REAL NOAA ETOPO 2022 (CAPE HATTERAS SLOPE)';
            set(h_topleft_box, 'String', hud_topleft);

            % Directional Reach Numbers
            idx_green_south = find(Pd_mat(idx_south, :) >= 70, 1, 'last');
            if ~isempty(idx_green_south)
                reach_south = r_km(idx_green_south);
            else
                reach_south = 0;
            end
            
            idx_green_north = find(Pd_mat(idx_north, :) >= 70, 1, 'last');
            if ~isempty(idx_green_north)
                reach_north = r_km(idx_green_north);
            else
                reach_north = 0;
            end

            % HUD Guidance text for 3D NOAA Mode
            hud_lines = {
                '\bf================= GEOSIT 3D NOAA TACTICAL GUIDANCE =================';
                '';
                '\bf[1] REAL-WORLD ASYMMETRIC SOUND PROPAGATION';
                sprintf('  • SOUTH / EAST (180°): \\bfDeep Ocean Channel (2,000m+)\\rm');
                sprintf('    Green Clear Reach extends out to: \\bf%.1f km\\rm.', reach_south);
                sprintf('  • NORTH / WEST (000°): \\bfContinental Shelf Shoal (140m)\\rm');
                sprintf('    Sound crashes into seabed; Green reach cut off at: \\bf%.1f km\\rm.', reach_north);
                '';
                '\bf[2] SURFACE SHIP & DIPPING SONAR TACTICS';
                '  • DIRECTIONAL FOCUS  : Steer sonar array to SOUTH / SOUTHEAST.';
                '  • SENSOR PLACEMENT   : Lower dipping sonar to 200m depth to exploit the';
                '                         deep channel corridor extending into open ocean.';
                '  • BLIND SPOT WATCH   : Heavy acoustic shadow zone to the North behind shelf.';
                '';
                '\bf[3] SUBMARINE EVASION & HIDING SANCTUARY';
                '  • HIDING SANCTUARY   : Navigate into the shallow shelf region to the NORTH/WEST.';
                '  • ACOUSTIC SHADOW    : The entire northern sector turns solid RED beyond 15 km.';
                '                         Deep-water dipping sonar cannot penetrate this shelf.';
                '';
                '\bf[CONTROLS]: Click buttons above to toggle 2D vs 3D or change sensor depth!'
            };
            set(h_hud_box, 'String', hud_lines);

        else
            % 2D Symmetric Mode
            set(h_btn_2d,   'BackgroundColor', [0.15, 0.45, 0.35], 'ForegroundColor', 'w');
            set(h_btn_noaa, 'BackgroundColor', [0.10, 0.20, 0.28], 'ForegroundColor', [0.70, 0.85, 0.95]);
            set(h_contour, 'Visible', 'off');

            % Symmetric bullseye sweep
            Pd_mat = repmat(base_slice, Ntheta, 1);
            set(h_surf, 'CData', Pd_mat);

            % Update 1D profile
            set(h_line_south, 'YData', base_slice, 'Visible', 'on');
            set(h_line_north, 'Visible', 'off');
            set(h_profile_title, 'String', sprintf('2D SYMMETRIC P_d PROFILE AT %d m DEPTH', round(current_depth)));

            % Update Top-Left box
            hud_topleft{3} = sprintf('ACTIVE SENSOR DEPTH: \\bf%d m', round(current_depth));
            hud_topleft{4} = 'DATASET: \\bf2D RANGE-INDEPENDENT BENCHMARK';
            set(h_topleft_box, 'String', hud_topleft);

            cur_reach = r_green_max(d_idx);

            hud_lines = {
                '\bf================== GEOSIT 2D BENCHMARK GUIDANCE ==================';
                '';
                '\bf[1] SYMMETRIC PROPAGATION CHARACTERISTICS';
                sprintf('  • ACTIVE SENSOR DEPTH  : \\bf%d m  \\rm--> Clear Reach: \\bf%.1f km (Green)', ...
                        round(current_depth), cur_reach);
                sprintf('  • BEST DIPPING DEPTH   : \\bf%d m  \\rm--> Maximizes Reach to: \\bf%.1f km', ...
                        round(optimal_dipping_depth), best_range);
                sprintf('  • SHALLOW DUCT DEPTH   : \\bf 50 m  \\rm--> Cut off early at: \\bf%.1f km', ...
                        range_at_50m);
                '';
                '\bf[2] WHY THIS PATTERN IS CONCENTRIC';
                '  • Sound speed and water depth are assumed uniform across all bearings.';
                '  • Switch to \\bf[3D NOAA BATHYMETRY]\\rm above to see how real seafloor topography';
                '    warps this circle into asymmetric sound channels and shadow zones!';
                '';
                '\bf[CONTROLS]: Click buttons above to toggle 2D vs 3D or change sensor depth!'
            };
            set(h_hud_box, 'String', hud_lines);
        end
    end

    function set_mode(m_in)
        update_display(current_depth, m_in);
    end

    function set_sensor_depth(d_in)
        update_display(d_in, current_mode);
    end

    % Initial render in 3D NOAA Mode
    update_display(current_depth, current_mode);

    % Auto-save high-resolution image to Outputs folder
    outdir = fullfile(pwd, 'Outputs');
    if ~exist(outdir, 'dir')
        mkdir(outdir);
    end
    png_path = fullfile(outdir, 'Spatial_Stoplight_OptionA.png');
    try
        warn_id = 'MATLAB:exportgraphics:UIComponentsExcluded';
        warn_state = warning('query', warn_id);
        warning('off', warn_id);
        exportgraphics(fig, png_path, 'Resolution', 200);
        warning(warn_state.state, warn_id);
    catch
        saveas(fig, png_path);
    end
    disp(['  Top-Down GeoSit Spatial Stoplight exported: ', png_path]);
end
