function export_geosit_to_html(results_file, output_html)
% EXPORT_GEOSIT_TO_HTML
% Exports the Tactical Combat Display (Option B) to a standalone, zero-dependency
% interactive HTML5/Canvas/JavaScript web application.
%
% Features in exported HTML:
%   - Circular Sonar PPI Radar Canvas (Polar uncertainty heatmap, compass bezel, range rings)
%   - Synchronized 1D Transmission Loss chart (20 Monte Carlo runs, mean TL, FOM line, cutoff)
%   - Probability of Detection (Pd) chart with shaded area and 50% threshold
%   - Instant sensor depth switching ([20 m], [50 m], [100 m], [200 m], [500 m])
%   - Synchronized Tactical Range Inspector (Attribution, FOM margin, Reliability status)
%   - Interactive click-to-pin, keyboard hotkeys, and high-res PNG snapshot export
%   - Completely offline: works in any browser without MATLAB or server dependencies.
%
% Usage:
%   export_geosit_to_html()
%   export_geosit_to_html('Outputs/MonteCarlo_Results.mat', 'Outputs/GeoSit_Tactical_Console.html')

    if nargin < 1 || isempty(results_file)
        results_file = fullfile(pwd, 'Outputs', 'MonteCarlo_Results.mat');
    end
    if nargin < 2 || isempty(output_html)
        output_html = fullfile(pwd, 'Outputs', 'GeoSit_Tactical_Console.html');
    end

    if ~exist(results_file, 'file')
        error('Results file not found: %s. Run run_monte_carlo first.', results_file);
    end

    disp('=== EXPORTING GEOSIT TACTICAL CONSOLE TO STANDALONE HTML5 ===');
    disp(['  Source Data : ', results_file]);
    disp(['  Output File : ', output_html]);

    % --- 1. Load Simulation Data ---
    data       = load(results_file);
    r_km       = data.r_km(:)'; % [1 x Nr]
    depth2plot = data.depth2plot;
    N_mc       = data.N_mc;
    preset_depths = [20, 50, 100, 200, 500];

    % Multi-depth extraction / cache
    TL_by_depth = containers.Map('KeyType', 'int32', 'ValueType', 'any');
    if isfield(data, 'TL_depths') && isstruct(data.TL_depths)
        for d = preset_depths
            f_name = sprintf('d%d', d);
            if isfield(data.TL_depths, f_name)
                TL_by_depth(int32(d)) = data.TL_depths.(f_name);
            end
        end
    end

    if isempty(TL_by_depth) || ~isKey(TL_by_depth, int32(depth2plot))
        out_folder = fileparts(results_file);
        if isempty(out_folder), out_folder = fullfile(pwd, 'Outputs'); end
        has_shd = true;
        for i = 1:N_mc
            if ~exist(fullfile(out_folder, sprintf('Test_MC_%d.shd.mat', i)), 'file')
                has_shd = false; break;
            end
        end

        if has_shd
            disp('  Extracting multi-depth acoustic runs from Bellhop shade files...');
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
                    TL_row = TL_2d(idx_d, :);
                    TL_depths_extracted.(sprintf('d%d', d))(i, :) = TL_row;
                end
            end
            for d = preset_depths
                TL_by_depth(int32(d)) = TL_depths_extracted.(sprintf('d%d', d));
            end
        else
            TL_by_depth(int32(depth2plot)) = data.TL_all;
        end
    end

    % --- 2. Sonar Parameters & Perturbation Vectors ---
    SL = 150; NL = 60; DI = 20; DT = 6;
    FOM = SL + DI - (NL + DT); % 104 dB

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

    r_fine = linspace(r_km(1), r_km(end), 300);
    N_fine = length(r_fine);

    % --- 3. Build JSON Payload Structure for All Depths ---
    sim_data = struct();
    sim_data.FOM = FOM;
    sim_data.r_km = round(r_km, 3);
    sim_data.r_fine = round(r_fine, 3);
    sim_data.depths = struct();

    for d = preset_depths
        if ~isKey(TL_by_depth, int32(d))
            continue;
        end
        TL_d = TL_by_depth(int32(d));

        % Clean singularity at r ~ 0 km safely
        for mc_i = 1:N_mc
            idx_fin = find(~isinf(TL_d(mc_i, :)), 1, 'first');
            if ~isempty(idx_fin) && idx_fin > 1
                TL_d(mc_i, 1:idx_fin-1) = TL_d(mc_i, idx_fin);
            end
        end

        mean_TL   = mean(TL_d, 1);
        sigma_TL  = std(TL_d, 0, 1);
        min_TL    = min(TL_d, [], 1);
        max_TL    = max(TL_d, [], 1);
        spread_TL = max_TL - min_TL;

        det_mat = (TL_d <= FOM);
        Pd = mean(det_mat, 1) * 100;

        mean_fine   = interp1(r_km, mean_TL,   r_fine, 'pchip');
        spread_fine = interp1(r_km, spread_TL, r_fine, 'pchip');
        sigma_fine  = interp1(r_km, sigma_TL,  r_fine, 'pchip');
        Pd_fine     = interp1(r_km, Pd,        r_fine, 'pchip');
        Pd_fine     = max(0, min(100, Pd_fine));

        % Ocean Sensitivity Correlations
        r_heave = zeros(1, length(r_km));
        r_bulk  = zeros(1, length(r_km));
        for k = 1:length(r_km)
            tl_col = TL_d(:, k);
            if sigma_TL(k) > 0.05 && std(delta_z_vec) > 0
                c_h = corrcoef(tl_col, delta_z_vec);
                if ~isnan(c_h(1, 2)), r_heave(k) = abs(c_h(1, 2)); end
            end
            if sigma_TL(k) > 0.05 && std(bulk_offset_vec) > 0
                c_b = corrcoef(tl_col, bulk_offset_vec);
                if ~isnan(c_b(1, 2)), r_bulk(k) = abs(c_b(1, 2)); end
            end
        end
        heave_fine = interp1(r_km, r_heave, r_fine, 'pchip');
        bulk_fine  = interp1(r_km, r_bulk,  r_fine, 'pchip');

        % Nominal Cutoff Range (First FOM crossing)
        fom_diff = mean_fine - FOM;
        cross_indices = find(fom_diff(1:N_fine-1) .* fom_diff(2:N_fine) <= 0);
        all_crossings = [];
        for ci = 1:length(cross_indices)
            k_c = cross_indices(ci);
            if fom_diff(k_c+1) ~= fom_diff(k_c)
                r_c = r_fine(k_c) - fom_diff(k_c) * (r_fine(k_c+1) - r_fine(k_c)) / (fom_diff(k_c+1) - fom_diff(k_c));
            else
                r_c = r_fine(k_c);
            end
            if isempty(all_crossings) || (r_c - all_crossings(end) > 0.25)
                all_crossings = [all_crossings, r_c];
            end
        end

        if isempty(all_crossings)
            idx_fom = find(mean_TL <= FOM, 1, 'last');
            if isempty(idx_fom), R_nom = r_km(1); else, R_nom = r_km(idx_fom); end
        else
            R_nom = all_crossings(1);
        end

        idx_90 = find(Pd_fine >= 90, 1, 'last'); if isempty(idx_90), idx_90 = 1; end
        idx_10 = find(Pd_fine >= 10, 1, 'last'); if isempty(idx_10), idx_10 = round(length(r_fine)/2); end
        R_guaranteed = r_fine(idx_90);
        R_shadow     = r_fine(idx_10);
        spread_km    = (R_shadow - R_guaranteed) / 2;
        uncertainty_pct = (spread_km / R_nom) * 100;

        if uncertainty_pct < 10
            conf_rating = 'HIGH CONFIDENCE';
        elseif uncertainty_pct <= 25
            conf_rating = 'MODERATE (YELLOW)';
        else
            conf_rating = 'HIGH UNCERTAINTY (RED)';
        end

        % Pack into depth entry
        d_key = sprintf('d%d', d);
        entry = struct();
        entry.depth = d;
        entry.R_nom = round(R_nom, 2);
        entry.spread_km = round(spread_km, 2);
        entry.conf_rating = conf_rating;
        entry.mean_TL = round(mean_TL, 2);
        entry.sigma_TL = round(sigma_TL, 2);
        entry.spread_TL = round(spread_TL, 2);
        entry.Pd = round(Pd, 2);
        entry.mean_fine = round(mean_fine, 2);
        entry.spread_fine = round(spread_fine, 2);
        entry.Pd_fine = round(Pd_fine, 2);
        entry.heave_fine = round(heave_fine, 3);
        entry.bulk_fine = round(bulk_fine, 3);

        mc_cell = cell(1, N_mc);
        for mi = 1:N_mc
            mc_cell{mi} = round(TL_d(mi, :), 1);
        end
        entry.mc_curves = mc_cell;

        sim_data.depths.(d_key) = entry;
    end

    % --- 4. Serialize JSON ---
    disp('  Encoding multi-depth ensemble into JSON...');
    try
        json_str = jsonencode(sim_data);
    catch
        error('jsonencode failed. Ensure MATLAB R2016b or newer is running.');
    end

    % Fix key names if needed (e.g., d20 -> 20)
    json_str = strrep(json_str, '"d20":', '"20":');
    json_str = strrep(json_str, '"d50":', '"50":');
    json_str = strrep(json_str, '"d100":', '"100":');
    json_str = strrep(json_str, '"d200":', '"200":');
    json_str = strrep(json_str, '"d500":', '"500":');

    % --- 5. Read HTML Template & Inject Data ---
    template_file = fullfile(pwd, 'template_geosit_console.html');
    if ~exist(template_file, 'file')
        error('HTML template not found: %s', template_file);
    end

    fid = fopen(template_file, 'r');
    if fid == -1
        error('Could not open HTML template: %s', template_file);
    end
    raw_template = fread(fid, '*char')';
    fclose(fid);

    % Replace placeholder %SIM_DATA_JSON% with actual JSON
    final_html = strrep(raw_template, '%SIM_DATA_JSON%', json_str);

    % Ensure output directory exists
    [out_dir, ~, ~] = fileparts(output_html);
    if ~isempty(out_dir) && ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    % Write final HTML
    fid = fopen(output_html, 'w', 'native', 'UTF-8');
    if fid == -1
        error('Could not create output HTML file: %s', output_html);
    end
    fwrite(fid, final_html, 'char');
    fclose(fid);

    disp('  [SUCCESS]: Standalone HTML5 Tactical Console generated successfully!');
    disp(['  File Location: ', output_html]);
    disp('  Opening in default web browser...');

    try
        web(output_html, '-browser');
    catch
        % Browser launch warning only
    end
end

