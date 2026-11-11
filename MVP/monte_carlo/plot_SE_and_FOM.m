function plot_SE_and_FOM(results_file)
    % PLOT_SE_AND_FOM
    % Generates Acoustic Foundation plots:
    %   1. 2D Transmission Loss Field (Depth vs. Range, matching plot_TL2.m benchmark)
    %   2. 1D Transmission Loss (TL) Monte Carlo Curves with FOM Detection Threshold Line
    %
    % Sonar Parameters (from user specification):
    %   SL = 150 dB  (Source Level)
    %   NL = 60 dB   (Ambient Noise Level)
    %   DI = 20 dB   (Directivity Index)
    %   DT = 6 dB    (Detection Threshold)
    %   FOM = SL + DI - (NL + DT) = 150 + 20 - (60 + 6) = 104 dB
    
    if nargin < 1
        results_file = [];
    end

    script_dir = fileparts(mfilename('fullpath'));
    mvp_dir    = fileparts(script_dir);
    if ~exist('load_mc_results', 'file')
        addpath(mvp_dir);
    end
    [results_file, data, out_folder, version_suffix] = load_mc_results(results_file, script_dir);
    r_km = data.r_km;
    z_m = data.z_m;
    TL_all = data.TL_all;
    TL_full_mean = data.TL_full_mean;
    depth2plot = data.depth2plot;
    N_mc = data.N_mc;
    
    % --- Sonar Equation Parameters ---
    SL = 150;  % Source Level (dB)
    NL = 60;   % Noise Level (dB)
    DI = 20;   % Directivity Index (dB)
    DT = 6;    % Detection Threshold (dB)
    
    FOM = SL + DI - (NL + DT); % Figure of Merit = 104 dB
    
    % Full-Field Signal Excess (SE = FOM - TL)
    SE_full = FOM - TL_full_mean;
    
    % Probability of Detection across range at receiver depth
    % Detection occurs when TL <= FOM (i.e. SE >= 0)
    detection_matrix = (TL_all <= FOM); % [N_mc x N_ranges] boolean
    Pd_percent = mean(detection_matrix, 1) * 100;
    
    % Calculate key tactical distance metrics
    idx_guaranteed = find(Pd_percent >= 90, 1, 'last');
    idx_50pct = find(Pd_percent >= 50, 1, 'last');
    idx_10pct = find(Pd_percent >= 10, 1, 'last');
    
    r_guaranteed = NaN;
    r_50pct = NaN;
    r_cutoff = NaN;
    if ~isempty(idx_guaranteed), r_guaranteed = r_km(idx_guaranteed); end
    if ~isempty(idx_50pct),      r_50pct      = r_km(idx_50pct); end
    if ~isempty(idx_10pct),      r_cutoff     = r_km(idx_10pct); end
    
    tag_suffix = '';
    if isfield(data, 'base_test') && ~isempty(data.base_test)
        tag_suffix = [' (', char(data.base_test), ')'];
    elseif ~isempty(version_suffix)
        tag_suffix = [' (', version_suffix, ')'];
    end

    % -------------------------------------------------------------
    % Figure 1: 2D Transmission Loss (TL) Field (Depth vs. Range)
    % Matches NUWC plot_TL2.m standard benchmark styling
    % -------------------------------------------------------------
    fig1 = figure('Position', [80, 100, 950, 520], 'Name', ['2D Transmission Loss (TL) Field', tag_suffix]);
    
    imagesc(r_km, z_m, TL_full_mean);
    set(gca, 'YDir', 'reverse');
    
    % Inverted jet colormap matching plot_TL2.m:
    % Low TL (warm red/yellow = strong trapped sound), High TL (dark blue = shadow zones)
    colormap(flipud(jet));
    caxis([70, 120]);
    cb = colorbar;
    cb.Label.String = 'Transmission Loss (TL) [dB]';
    cb.FontSize = 11;
    
    hold on;
    % Mark receiver depth slice with a dashed white line
    plot([r_km(1), r_km(end)], [depth2plot, depth2plot], 'w--', 'LineWidth', 2.0);
    text(r_km(end)*0.02, depth2plot - 45, sprintf('\\leftarrow Analyzed Receiver Depth (%d m)', depth2plot), ...
         'Color', 'w', 'FontWeight', 'bold', 'FontSize', 10);
    
    if isfield(data, 'base_test') && strcmpi(data.base_test, 'Test2')
        env_label = 'Munk Profile';
    elseif isfield(data, 'base_test') && strcmpi(data.base_test, 'Test3')
        env_label = 'North Atlantic (Test 3)';
    else
        env_label = 'North Atlantic';
    end

    freq_hz = 3000;
    if isfield(data, 'freq_hz') && ~isempty(data.freq_hz)
        freq_hz = data.freq_hz(1);
    end
    zs_m = 20;
    if isfield(data, 'source_depth_m') && ~isempty(data.source_depth_m)
        zs_m = data.source_depth_m(1);
    elseif isfield(data, 'base_test') && (strcmpi(data.base_test, 'Test2') || strcmpi(data.base_test, 'Test3'))
        zs_m = 100;
    end
    ang_min = -50;
    ang_max = 20;
    if isfield(data, 'launch_angles') && length(data.launch_angles) >= 2
        ang_min = data.launch_angles(1);
        ang_max = data.launch_angles(2);
    elseif isfield(data, 'base_test') && strcmpi(data.base_test, 'Test3')
        ang_min = -50;
        ang_max = 50;
    end

    xlabel('Range (km)', 'FontSize', 12);
    ylabel('Depth (m)', 'FontSize', 12);
    title({sprintf('2D Transmission Loss (TL), %s', env_label); ...
           sprintf('freq = %g Hz, Z_S = %g m, minA = %g°, maxA = %g°', freq_hz, zs_m, ang_min, ang_max)}, ...
          'FontSize', 12, 'Interpreter', 'none');
    grid on;
    set(gca, 'FontSize', 11);
    
    % -------------------------------------------------------------
    % Figure 2: Transmission Loss (TL) Curves & FOM Threshold
    % -------------------------------------------------------------
    fig2 = figure('Position', [120, 100, 950, 520], 'Name', ['Monte Carlo Transmission Loss & FOM', tag_suffix]);
    hold on;
    
    % Plot all Monte Carlo realizations
    h_mc = plot(r_km, TL_all', 'Color', [0.75, 0.75, 0.75], 'LineWidth', 0.9);
    
    % Plot Ensemble Mean TL
    mean_TL = mean(TL_all, 1);
    h_mean = plot(r_km, mean_TL, 'b-', 'LineWidth', 2.4);
    
    % Plot FOM Detection Threshold Line
    h_fom = yline(FOM, 'r--', sprintf('FOM = %d dB (Detection Threshold)', FOM), ...
                  'LineWidth', 2.2, 'FontSize', 11, 'LabelVerticalAlignment', 'bottom');
    
    set(gca, 'YDir', 'reverse'); % Invert Y-axis so louder / less TL is higher
    xlabel('Range (km)', 'FontSize', 12);
    ylabel('Transmission Loss (dB)', 'FontSize', 12);
    ylim([50, 130]);
    grid on;
    title(sprintf('Monte Carlo Transmission Loss at %d m Receiver Depth (N = %d runs, Monotone PCHIP ACS)', depth2plot, N_mc), ...
          'FontSize', 12);
    legend([h_fom, h_mean, h_mc(1)], ...
           {sprintf('FOM Threshold (%d dB)', FOM), 'Ensemble Mean TL', sprintf('Monte Carlo Realizations (%d runs)', N_mc)}, ...
           'Location', 'SouthWest', 'FontSize', 11);
    set(gca, 'FontSize', 11);
    
    % Annotate Detection Zone vs Shadow Zone
    text(r_km(end)*0.02, FOM - 4, '\leftarrow DETECTION ZONE (TL \leq FOM, SE \geq 0 dB)', ...
         'Color', [0, 0.55, 0], 'FontWeight', 'bold', 'FontSize', 11);
    text(r_km(end)*0.02, FOM + 4, '\leftarrow SHADOW ZONE / NO DETECTION (TL > FOM, SE < 0 dB)', ...
         'Color', [0.75, 0, 0], 'FontWeight', 'bold', 'FontSize', 11);
    
    % --- Command Window Summary Report ---
    disp(' ');
    disp('================================================================');
    disp(sprintf(' TACTICAL SONAR DETECTION SUMMARY (Receiver Depth: %d m)', depth2plot));
    disp('================================================================');
    disp(sprintf('  Figure of Merit (FOM):           %d dB', FOM));
    disp(sprintf('  Guaranteed Detection (Pd >= 90%%): 0 to %.1f km  [HIGH CONFIDENCE]', r_guaranteed));
    disp(sprintf('  Median Detection Range (Pd = 50%%): %.1f km', r_50pct));
    disp(sprintf('  Uncertainty Band (Pd 30%% to 70%%): %.1f km to %.1f km  [MARGINAL / UNCERTAIN]', ...
        r_guaranteed, r_cutoff));
    disp(sprintf('  Shadow Zone / Blind Spot:        Beyond %.1f km  [NO DETECTION]', r_cutoff));
    disp('================================================================');
    
    % Auto-save high-resolution slide-ready images to Outputs folder
    if exist(out_folder, 'dir') ~= 7
        mkdir(out_folder);
    end
    png1_path = fullfile(out_folder, ['Transmission_Loss_2D_Field', version_suffix, '.png']);
    png2_path = fullfile(out_folder, ['Transmission_Loss_Curves', version_suffix, '.png']);
    try
        exportgraphics(fig1, png1_path, 'Resolution', 200);
        exportgraphics(fig2, png2_path, 'Resolution', 200);
    catch
        saveas(fig1, png1_path);
        saveas(fig2, png2_path);
    end
    disp(['  2D TL Field exported:            ', png1_path]);
    disp(['  1D TL Curves exported:           ', png2_path]);
    disp(' Plots displayed successfully.');
end
