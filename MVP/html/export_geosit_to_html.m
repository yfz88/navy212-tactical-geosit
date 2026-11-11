function export_geosit_to_html(results_or_ens, output_html, open_browser, default_case_index)
% EXPORT_GEOSIT_TO_HTML
% Exports the Tactical Combat Display to a standalone, zero-dependency
% interactive HTML5/Canvas/JavaScript web application using the shared
% adaptive IQR calibration from compute_ensemble_stats.
%
% Usage:
%   export_geosit_to_html()
%   export_geosit_to_html('Outputs/MonteCarlo_Results.mat')
%   export_geosit_to_html({ens1, ens3}, '', false)   % Unified multi-sensor comparison
%   export_geosit_to_html(ens, '', false)

    script_dir = fileparts(mfilename('fullpath'));
    mvp_dir    = fileparts(script_dir);

    if nargin < 1
        results_or_ens = [];
    end
    if nargin < 3 || isempty(open_browser)
        open_browser = true;
    end
    if nargin < 4 || isempty(default_case_index)
        default_case_index = 0;
    end
    if ~exist('compute_ensemble_stats', 'file')
        addpath(mvp_dir);
    end

    is_multi = iscell(results_or_ens);
    if is_multi
        if isempty(results_or_ens)
            error('export_geosit_to_html received an empty scenario cell array.');
        end
        n_cases  = numel(results_or_ens);
        ens_list = cell(1, n_cases);
        payloads = cell(1, n_cases);
        for ci = 1:n_cases
            ens_list{ci} = compute_ensemble_stats(results_or_ens{ci}, script_dir);
            payloads{ci} = build_scenario_payload(ens_list{ci});
        end
        ref_ens        = ens_list{1};
        version_suffix = '';
    else
        ens            = compute_ensemble_stats(results_or_ens, script_dir);
        sim_data       = build_scenario_payload(ens);
        ref_ens        = ens;
        version_suffix = ens.version_suffix;
    end

    out_folder = ref_ens.out_folder;

    if nargin < 2 || isempty(output_html)
        if is_multi
            output_html = fullfile(script_dir, 'GeoSit_Tactical_Console.html');
        else
            single_suffix = version_suffix;
            if isempty(single_suffix)
                single_suffix = '_1';
            end
            if exist(out_folder, 'dir') ~= 7
                mkdir(out_folder);
            end
            output_html = fullfile(out_folder, ['GeoSit_Tactical_Console', single_suffix, '.html']);
        end
    end

    disp('=== EXPORTING GEOSIT TACTICAL CONSOLE TO STANDALONE HTML5 ===');
    if is_multi
        for ci = 1:numel(ens_list)
            disp(['  Source Case ', num2str(ci), ': ', ens_list{ci}.results_file, ...
                  ' (', payloads{ci}.case_label, ')']);
        end
        sim_data = struct();
        sim_data.cases = payloads;
        sim_data.default_case_index = max(0, min(numel(payloads) - 1, round(default_case_index)));
    else
        disp(['  Source Data : ', ref_ens.results_file]);
    end
    disp(['  Output File : ', output_html]);

    % --- 4. Serialize JSON ---
    disp('  Encoding multi-depth ensemble into JSON...');
    try
        json_str = jsonencode(sim_data);
    catch
        error('jsonencode failed. Ensure MATLAB R2016b or newer is running.');
    end

    % --- 5. Read HTML Template & Inject Data ---
    template_file = fullfile(script_dir, 'template_geosit_console.html');
    if ~exist(template_file, 'file')
        template_file = fullfile(pwd, 'template_geosit_console.html');
    end
    if ~exist(template_file, 'file')
        error('HTML template not found: %s', template_file);
    end

    fid = fopen(template_file, 'r', 'native', 'UTF-8');
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

    if open_browser
        disp('  Opening in default web browser...');
        try
            web(output_html, '-browser');
        catch
            % Browser launch warning only
        end
    end
end

function sim_data = build_scenario_payload(ens)
% BUILD_SCENARIO_PAYLOAD Build one sensor-depth scenario payload struct for JSON injection.
    data            = ens.data;
    repo_root       = ens.repo_root;
    r_km            = ens.r_km;
    depth2plot      = ens.depth2plot;
    N_mc            = ens.N_mc;
    ownship_depth_m = ens.ownship_depth_m;
    z_avail         = ens.z_avail;
    n_depths        = ens.n_depths;
    TL_cube         = ens.TL_cube;
    preset_idx      = ens.preset_idx;

    if (isfield(data, 'base_test') && strcmpi(data.base_test, 'Test2')) || ...
       (isfield(data, 'test_name') && strcmpi(data.test_name, 'Test2'))
        test_key = 'Test2';
        env_profile_name = 'MUNK CANONICAL DEEP SOUND CHANNEL';
        ocean_location = 'Deep Ocean (Munk Benchmark)';
        ocean_location_detail = 'Canonical Munk profile; 0-43.7 kyd transect';
    else
        test_key = 'Test1';
        if isfield(data, 'base_test') && ~isempty(data.base_test)
            test_key = char(data.base_test);
        elseif isfield(data, 'test_name') && ~isempty(data.test_name)
            test_key = char(data.test_name);
        end
        env_profile_name = 'NORTH ATLANTIC OCEAN';
        ocean_location = 'North Atlantic Ocean';
        ocean_location_detail = 'HYCOM profile, 15 C, 35 ppt; 0-43.7 kyd transect';
    end

    % Extract source frequency (Hz) from .env if available
    freq_hz = 3000.0;
    env_candidates = {
        fullfile(repo_root, 'Inputs', [test_key, '.env']), ...
        fullfile(repo_root, 'Inputs', 'Test1.env')
    };
    for ei = 1:length(env_candidates)
        if exist(env_candidates{ei}, 'file')
            efid = fopen(env_candidates{ei}, 'r');
            if efid ~= -1
                fgetl(efid); % title line
                ln2 = fgetl(efid);
                fclose(efid);
                if ischar(ln2)
                    tok = sscanf(ln2, '%f', 1);
                    if ~isempty(tok) && tok > 0, freq_hz = tok; end
                end
            end
            break;
        end
    end

    % Extract ocean seafloor bathymetry metrics & range profile from .bty
    bty_r_km = [];
    bty_z_m  = [];
    bty_candidates = {
        fullfile(repo_root, 'Inputs', [test_key, '.bty']), ...
        fullfile(repo_root, 'Inputs', 'Test1.bty')
    };
    for bi = 1:length(bty_candidates)
        if exist(bty_candidates{bi}, 'file')
            bfid = fopen(bty_candidates{bi}, 'r');
            if bfid ~= -1
                fgetl(bfid); % 'LL'
                n_bty = str2double(strtrim(fgetl(bfid)));
                if ~isnan(n_bty) && n_bty > 1
                    b_raw = fscanf(bfid, '%f', [6, Inf])';
                    if ~isempty(b_raw) && size(b_raw, 2) >= 2
                        bty_r_km = b_raw(:, 1)';
                        bty_z_m  = b_raw(:, 2)';
                    end
                end
                fclose(bfid);
            end
            if ~isempty(bty_z_m), break; end
        end
    end
    if isempty(bty_z_m)
        if isfield(data, 'z_m') && ~isempty(data.z_m)
            max_z = data.z_m(end);
        else
            max_z = 3013.0;
        end
        bty_r_km = [r_km(1), r_km(end)];
        bty_z_m  = [max_z, max_z];
    end
    ocean_depth_min_m  = min(bty_z_m);
    ocean_depth_max_m  = max(bty_z_m);
    ocean_depth_mean_m = mean(bty_z_m);

    % Extract Thermocline Depth (steepest sound-speed cooling/drop depth) from baseline SSP
    thermocline_depth_m = 43.9;
    ssp_surface_speed_ms = 1513.0;
    if isfield(data, 'base_z') && isfield(data, 'base_c') && ~isempty(data.base_c) && length(data.base_c) >= 2
        bz_vec = data.base_z(:);
        bc_vec = data.base_c(:);
        dz_vec = diff(bz_vec);
        dc_vec = diff(bc_vec);
        pos_mask = (dz_vec > 0);
        if any(pos_mask)
            grad_vec = dc_vec(pos_mask) ./ dz_vec(pos_mask);
            [~, tc_idx_rel] = min(grad_vec);
            pos_indices = find(pos_mask);
            tc_idx = pos_indices(tc_idx_rel);
            thermocline_depth_m = 0.5 * (bz_vec(tc_idx) + bz_vec(tc_idx + 1));
        end
        ssp_surface_speed_ms = bc_vec(1);
    end

    [~, def_idx] = min(abs(z_avail - depth2plot));

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
    bathy_fine = interp1(bty_r_km, bty_z_m, r_fine, 'linear', 'extrap');

    % --- 3. Build JSON Payload Structure for All Operational Target Depths ---
    rx_ft = round(ownship_depth_m * 3.28084);

    sim_data = struct();
    sim_data.case_label = sprintf('%d ft (%d m)', rx_ft, round(ownship_depth_m));
    sim_data.test_name = test_key;
    sim_data.FOM = FOM;
    sim_data.SL = SL;
    sim_data.NL = NL;
    sim_data.DI = DI;
    sim_data.DT = DT;
    sim_data.N_mc = N_mc;
    sim_data.freq_hz = round(freq_hz, 1);
    sim_data.receiver_depth_m = round(ownship_depth_m, 2);
    sim_data.env_profile = env_profile_name;
    sim_data.ocean_location = ocean_location;
    sim_data.ocean_location_detail = ocean_location_detail;
    sim_data.ocean_depth_min_m = round(ocean_depth_min_m, 1);
    sim_data.ocean_depth_max_m = round(ocean_depth_max_m, 1);
    sim_data.ocean_depth_mean_m = round(ocean_depth_mean_m, 1);
    sim_data.thermocline_depth_m = round(thermocline_depth_m, 1);
    sim_data.ssp_surface_speed_ms = round(ssp_surface_speed_ms, 1);
    sim_data.bathy_fine = round(bathy_fine, 1);
    sim_data.preset_indices = num2cell(preset_idx - 1); % 0-based indices for JS
    sim_data.default_index = def_idx - 1;               % 0-based default index
    sim_data.color_scale = ens.color_scale;
    sim_data.r_km = round(r_km, 3);
    sim_data.r_fine = round(r_fine, 3);
    depths_cell = cell(1, n_depths);

    dz_std = std(delta_z_vec);
    bo_std = std(bulk_offset_vec);
    dz_norm = [];
    bo_norm = [];
    if dz_std > 0
        dz_norm = (delta_z_vec - mean(delta_z_vec)) / ((N_mc - 1) * dz_std);
    end
    if bo_std > 0
        bo_norm = (bulk_offset_vec - mean(bulk_offset_vec)) / ((N_mc - 1) * bo_std);
    end

    KM_TO_KYD = 1.0936133;

    for di = 1:n_depths
        TL_d = reshape(TL_cube(:, di, :), N_mc, length(r_km));

        mean_TL   = mean(TL_d, 1);
        sigma_TL  = std(TL_d, 0, 1);
        spread_TL = max(TL_d, [], 1) - min(TL_d, [], 1);

        Pd = mean(TL_d <= FOM, 1) * 100;

        mean_fine   = interp1(r_km, mean_TL,   r_fine, 'pchip');
        spread_fine = interp1(r_km, spread_TL, r_fine, 'pchip');
        Pd_fine     = interp1(r_km, Pd,        r_fine, 'pchip');
        Pd_fine     = max(0, min(100, Pd_fine));

        % Vectorized Ocean Sensitivity Correlations across range cells
        r_heave = zeros(1, length(r_km));
        r_bulk  = zeros(1, length(r_km));
        tl_centered = TL_d - mean_TL;
        valid_rng = (sigma_TL > 0.05);
        if ~isempty(dz_norm)
            rh = abs(dz_norm' * tl_centered) ./ max(sigma_TL, eps);
            r_heave(valid_rng) = min(1.0, rh(valid_rng));
        end
        if ~isempty(bo_norm)
            rb = abs(bo_norm' * tl_centered) ./ max(sigma_TL, eps);
            r_bulk(valid_rng) = min(1.0, rb(valid_rng));
        end
        heave_fine = interp1(r_km, r_heave, r_fine, 'pchip');
        bulk_fine  = interp1(r_km, r_bulk,  r_fine, 'pchip');

        % Nominal Cutoff Range (persistent upward FOM crossing into shadow)
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
            if isempty(all_crossings) || (r_c - all_crossings(end) > 0.25)
                all_crossings = [all_crossings, r_c];
            end
            if fom_diff(k_c) <= 0 && fom_diff(k_c+1) > 0
                if isempty(up_crossings) || (r_c - up_crossings(end) > 0.25)
                    up_crossings = [up_crossings, r_c];
                end
            end
        end

        R_nom = [];
        look_km = 1.0 / KM_TO_KYD;
        for ui = 1:length(up_crossings)
            r_u = up_crossings(ui);
            look_mask = (r_fine > r_u) & (r_fine <= min(r_fine(end), r_u + look_km));
            if any(look_mask) && all(fom_diff(look_mask) > 0)
                R_nom = r_u;
                break;
            end
        end
        if isempty(R_nom)
            if ~isempty(up_crossings)
                R_nom = up_crossings(1);
            elseif ~isempty(all_crossings)
                R_nom = all_crossings(1);
            else
                idx_fom = find(mean_TL <= FOM, 1, 'last');
                if isempty(idx_fom), R_nom = r_km(1); else, R_nom = r_km(idx_fom); end
            end
        end

        idx_90 = find(Pd_fine >= 90, 1, 'last'); if isempty(idx_90), idx_90 = 1; end
        idx_10 = find(Pd_fine >= 10, 1, 'last'); if isempty(idx_10), idx_10 = round(length(r_fine)/2); end
        R_guaranteed = r_fine(idx_90);
        R_shadow     = r_fine(idx_10);
        spread_km    = (R_shadow - R_guaranteed) / 2;
        if R_nom > 0
            uncertainty_pct = (spread_km / R_nom) * 100;
        else
            uncertainty_pct = 100;
        end

        if uncertainty_pct < 10
            conf_rating = 'HIGH CONFIDENCE';
        elseif uncertainty_pct <= 25
            conf_rating = 'MODERATE (YELLOW)';
        else
            conf_rating = 'HIGH UNCERTAINTY (RED)';
        end

        % Encode 20 Monte Carlo TL curves tightly as 0.1-dB Uint16 Base64
        u16_flat = uint16(round(min(200.0, max(0.0, reshape(TL_d', 1, []))) * 10.0));
        raw_bytes = typecast(u16_flat, 'uint8');
        try
            mc_b64 = matlab.net.base64encode(raw_bytes);
        catch
            mc_b64 = reshape(char(org.apache.commons.codec.binary.Base64.encodeBase64(raw_bytes)), 1, []);
        end

        entry = struct();
        entry.depth = round(z_avail(di), 2);
        entry.R_nom = round(R_nom, 2);
        entry.spread_km = round(spread_km, 2);
        entry.conf_rating = conf_rating;
        entry.mean_TL = round(mean_TL, 1);
        entry.spread_fine = round(spread_fine, 1);
        entry.Pd_fine = round(Pd_fine, 1);
        entry.heave_fine = round(heave_fine, 2);
        entry.bulk_fine = round(bulk_fine, 2);
        entry.mc_b64 = mc_b64;

        depths_cell{di} = entry;
    end
    sim_data.depths = depths_cell;
end

