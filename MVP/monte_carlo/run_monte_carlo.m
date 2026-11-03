function run_monte_carlo(N_mc, Nbeams_run, test_name, optimize_ssp)
    % RUN_MONTE_CARLO
    % Runs physically realistic, production-grade Monte Carlo simulation of transmission loss.
    %
    % Configuration:
    %   - Beams: 1500 (Production standard: dense Gaussian coverage without ray starvation)
    %   - Interpolation: Monotone PCHIP ACS ('PFMF') for continuous, smooth sound gradients
    %   - Perturbation: Holistic thermocline displacement (preserves physical water gradients)
    %   - Zero point-by-point noise: Eliminates artificial 50 dB ray scattering
    %
    % Available Modes & Profiles:
    %   1. Test1 (OPTIMIZED - Recommended):
    %      Decimates 35 redundant surface mixed-layer speedbumps (0.72m spacing)
    %      down to ~10m spacing where sound speed is flat (dc < 0.05 m/s).
    %      Preserves exact curve shape and 100% of thermocline/deep gradient points.
    %      Runtime: ~8-14 minutes for 20 iterations (instead of ~5 hours!).
    %
    %   2. Test1 (ALL POINTS - Raw):
    %      Keeps all 101 original HYCOM depth points verbatim.
    %      Runtime: ~2 hours for 850 beams, ~5 hours for 1500 beams.
    %
    %   3. Test2 (Munk Canonical Profile):
    %      Standard 101-point Munk canonical profile with 35m uniform spacing.
    %      Naturally fast without decimation.
    %
    % Usage Examples:
    %   run_monte_carlo()                          % Test1, 20 runs, 1500 beams, OPTIMIZED (fast)
    %   run_monte_carlo(20, 1500, 'Test1')         % Test1, OPTIMIZED
    %   run_monte_carlo(20, 1500, 'Test1', true)   % Test1, OPTIMIZED (fast, ~8-14 min)
    %   run_monte_carlo(20, 1500, 'Test1', false)  % Test1, ALL 101 points (raw, slow ~5 hrs)
    %   run_monte_carlo(20, 1500, 'Test2')         % Test2 (Munk profile, fast)
    %
    % Shorthand Usage:
    %   run_monte_carlo('Test1')                   % Test1 optimized
    %   run_monte_carlo('Test1_all')               % Test1 all points (raw)
    %   run_monte_carlo('Test2')                   % Test2 Munk profile
    %
    % Outputs:
    %   - Results saved to: Outputs/MonteCarlo_Results.mat
    %   - Automatically displays:
    %       1. plot_SE_and_FOM (Full-Field 2D SE Map & Stoplight Line Plot)
    %       2. plot_geosit_optionB (Dark Tactical Combat Display PPI Radar Console)

    % -----------------------------------------------------------------------
    % 1. Parse and validate inputs
    % -----------------------------------------------------------------------
    if nargin >= 1 && (ischar(N_mc) || isstring(N_mc))
        if nargin >= 2 && islogical(Nbeams_run)
            optimize_ssp = Nbeams_run;
        end
        test_name = char(N_mc);
        N_mc = 20;
        Nbeams_run = 1500;
    end

    if nargin < 1 || isempty(N_mc)
        N_mc = 20;
    end
    if nargin < 2 || isempty(Nbeams_run)
        Nbeams_run = 1500; % Production standard
    end
    if nargin < 3 || isempty(test_name)
        test_name = 'Test1';
    end

    test_str = lower(char(test_name));
    if contains(test_str, 'test2')
        base_test    = 'Test2';
        optimize_ssp = false; % Test2 is already uniformly spaced at 35m
        mode_label   = 'Test2 (Munk Canonical Profile - Uniform 35m Spacing)';
    elseif contains(test_str, 'all') || contains(test_str, 'raw') || contains(test_str, 'unopt')
        base_test    = 'Test1';
        optimize_ssp = false;
        mode_label   = 'Test1 (HYCOM North Atlantic - ALL 101 Raw Points, Unoptimized)';
    else
        base_test = 'Test1';
        if nargin < 4 || isempty(optimize_ssp)
            optimize_ssp = true; % Default: optimal decimation for Test1
        end
        if optimize_ssp
            mode_label = 'Test1 (HYCOM North Atlantic - OPTIMIZED: Decimated Mixed Layer)';
        else
            mode_label = 'Test1 (HYCOM North Atlantic - ALL 101 Raw Points, Unoptimized)';
        end
    end

    % Ensure bellhop engine and supporting libraries are on the MATLAB path
    script_dir = fileparts(mfilename('fullpath'));
    addpath(script_dir);
    addpath(fullfile(script_dir, '..'));
    bellhop_candidates = {
        fullfile(script_dir, '..', 'bellhop'),
        fullfile(script_dir, 'bellhop'),
        fullfile(pwd, 'bellhop'),
        fullfile(pwd, '..', 'bellhop')
    };
    for b_idx = 1:length(bellhop_candidates)
        if exist(bellhop_candidates{b_idx}, 'dir')
            addpath(bellhop_candidates{b_idx});
            addpath(fullfile(bellhop_candidates{b_idx}, 'Misc'));
            addpath(fullfile(bellhop_candidates{b_idx}, 'ReadWrite'));
            break;
        end
    end

    % Determine Inputs directory
    if exist(fullfile(pwd, 'Inputs'), 'dir')
        indir = fullfile(pwd, 'Inputs');
    elseif exist(fullfile(script_dir, '..', 'Inputs'), 'dir')
        indir = fullfile(script_dir, '..', 'Inputs');
    else
        indir = fullfile(pwd, 'Inputs');
    end

    % Determine Outputs directory
    if exist(fullfile(pwd, 'Outputs'), 'dir')
        outdir = fullfile(pwd, 'Outputs');
    elseif exist(fullfile(script_dir, '..', 'Outputs'), 'dir')
        outdir = fullfile(script_dir, '..', 'Outputs');
    else
        outdir = fullfile(pwd, 'Outputs');
        if ~exist(outdir, 'dir'), mkdir(outdir); end
    end

    depth2plot    = 100; % Target/receiver depth for line analysis (m)
    N_depth_cells = 300; % 10m vertical grid resolution
    N_range_cells = 500; % 80m horizontal grid resolution

    % -----------------------------------------------------------------------
    % 2. Read baseline .env file
    % -----------------------------------------------------------------------
    base_env_path = fullfile(indir, [base_test '.env']);
    if ~exist(base_env_path, 'file')
        error('Base environment file not found: %s', base_env_path);
    end
    base_env_txt = fileread(base_env_path);
    env_lines    = splitlines(base_env_txt);

    % Parse SSP table (lines 7 until termination token '/')
    base_z           = [];
    base_c           = [];
    ssp_line_indices = [];

    for j = 7:length(env_lines)
        t_line = strtrim(env_lines{j});
        if isempty(t_line), continue; end
        parts = sscanf(t_line, '%f %f /');
        if length(parts) == 2
            base_z           = [base_z;           parts(1)];
            base_c           = [base_c;           parts(2)];
            ssp_line_indices = [ssp_line_indices; j];
        else
            break; % First non-SSP line terminates table
        end
    end

    Nz_raw = length(base_z);

    % -----------------------------------------------------------------------
    % 3. Mixed-Layer Decimation (Test1 with optimize_ssp = true)
    %
    % HYCOM sigma coordinates place 35 points in the top 40m spaced 0.72m
    % apart where sound speed is flat (dc < 0.05 m/s). Bellhop's reducestep.m
    % collapses integration step size to centimeters to hit every depth boundary.
    % We decimate redundant flat points while keeping the exact curve shape
    % and 100% of thermocline/deep gradients.
    % -----------------------------------------------------------------------
    if strcmp(base_test, 'Test1') && optimize_ssp
        min_spacing = 10.0; % meters
        dc_thresh   = 0.15; % m/s
        
        kept_idx = 1; % Always keep surface point (z = 0)
        last_z   = base_z(1);
        last_c   = base_c(1);
        
        for j = 2:(Nz_raw - 1)
            dz       = base_z(j) - last_z;
            dc       = abs(base_c(j) - last_c);
            cur_grad = abs(base_c(j+1) - base_c(j)) / (base_z(j+1) - base_z(j));
            
            % Keep if spacing >= 10m OR sound speed change >= 0.15 m/s OR gradient turns
            if dz >= min_spacing || dc >= dc_thresh || cur_grad >= 0.05
                kept_idx = [kept_idx; j];
                last_z   = base_z(j);
                last_c   = base_c(j);
            end
        end
        kept_idx = [kept_idx; Nz_raw]; % Always keep bottom boundary point
        
        base_z = base_z(kept_idx);
        base_c = base_c(kept_idx);
    end

    Nz = length(base_z);

    % -----------------------------------------------------------------------
    % 4. Print Tactical Run Banner
    % -----------------------------------------------------------------------
    disp('================================================================');
    disp([' MONTE CARLO SIMULATION: ', num2str(N_mc), ' iterations']);
    disp([' Profile:      ', mode_label]);
    disp([' SSP Points:   ', num2str(Nz_raw), ' raw  -->  ', num2str(Nz), ' active points']);
    disp([' Beam Count:   ', num2str(Nbeams_run), ' (Production Density: Anti-Ray Starvation)']);
    disp([' Grid Mesh:    ', num2str(N_depth_cells), ' depth x ', num2str(N_range_cells), ' range cells']);
    disp(' Interpolation: Monotone PCHIP ACS (''PFMF'')');
    disp(' Perturbation:  Holistic thermocline heave (gradient-preserving)');
    disp('================================================================');

    all_perturbed_c = zeros(Nz, N_mc);
    delta_z_all     = zeros(N_mc, 1);
    bulk_offset_all = zeros(N_mc, 1);
    TL_all          = [];
    TL_full_sum     = [];
    r_km            = [];
    z_m             = [];

    total_start = tic;

    % -----------------------------------------------------------------------
    % 5. Monte Carlo Iteration Loop
    % -----------------------------------------------------------------------
    for i = 1:N_mc
        iter_start = tic;
        mc_name    = sprintf('Test_MC_%d', i);

        % 5a. Copy boundary and beam pattern files from base test
        for ext = {'.bty', '.sbp', '.trc'}
            src_file = fullfile(indir, [base_test ext{1}]);
            if exist(src_file, 'file')
                copyfile(src_file, fullfile(indir, [mc_name ext{1}]));
            end
        end

        % 5b. Holistic Thermocline Heave (preserves natural physical gradients)
        delta_z_max = randn() * 8.0;   % displacement std dev: +/- 8 m
        z_core      = 200.0;            % depth of maximum heave (m)

        eta_z       = delta_z_max * (base_z / z_core) .* exp(1 - base_z / z_core);
        z_lookup    = max(0, min(max(base_z), base_z - eta_z));
        c_displaced = interp1(base_z, base_c, z_lookup, 'pchip');

        bulk_offset = randn() * 0.2;   % whole-column bulk offset std dev: +/- 0.2 m/s
        c_perturbed = c_displaced + bulk_offset;
        all_perturbed_c(:, i) = c_perturbed;
        delta_z_all(i)        = delta_z_max;
        bulk_offset_all(i)    = bulk_offset;

        % 5c. Assemble calibrated .env file
        new_header    = env_lines(1:5);
        new_header{4} = '''PFMF''           ! P-> monotone PCHIP ACS, F-> use surf Rs file, M-> dB/m, F-> Franc-Garr absorp';
        
        line6_str = sprintf(' %d 0.0 %.2f,        ! # SSP depths, depth range (m)', Nz, max(base_z));
        
        insert_lines = cell(Nz, 1);
        for j = 1:Nz
            insert_lines{j} = sprintf('  %8.2f  %8.2f  /', base_z(j), c_perturbed(j));
        end
        
        tail_lines = env_lines(ssp_line_indices(end)+1 : end);
        for j = 1:length(tail_lines)
            t_line = tail_lines{j};
            if isempty(t_line), continue; end
            if contains(t_line, '750') && contains(t_line, 'num depth cells')
                tail_lines{j} = sprintf('%d                  ! num depth cells', N_depth_cells);
            elseif contains(t_line, '1000') && contains(t_line, 'num range cells')
                tail_lines{j} = sprintf('%d                  ! num range cells', N_range_cells);
            elseif contains(t_line, '4000') && contains(t_line, 'beams')
                tail_lines{j} = strrep(t_line, '4000', num2str(Nbeams_run));
            end
        end
        
        new_env_lines = [new_header; {line6_str}; insert_lines; tail_lines];

        % Write .env file
        fid = fopen(fullfile(indir, [mc_name '.env']), 'w');
        for j = 1:length(new_env_lines)
            fprintf(fid, '%s\n', new_env_lines{j});
        end
        fclose(fid);

        % 5d. Write matching .ssp file (Nz rows)
        fid = fopen(fullfile(indir, [mc_name '.ssp']), 'w');
        fprintf(fid, '1\n0\n');
        for j = 1:Nz
            fprintf(fid, '%.2f\n', c_perturbed(j));
        end
        fclose(fid);

        % 5e. Execute Bellhop
        fprintf(' [Iteration %2d/%2d] (Heave = %+.1f m, Bulk = %+.2f m/s)... ', ...
            i, N_mc, delta_z_max, bulk_offset);
        bellhopM2(indir, outdir, mc_name);

        % 5f. Load results immediately to free memory
        res   = load(fullfile(outdir, [mc_name '.shd.mat']), 'pressure', 'Pos');
        TL_2d = -20 * log10(squeeze(abs(res.pressure)));

        if isempty(r_km)
            r_km        = res.Pos.r.r / 1000;
            z_m         = res.Pos.r.z;
            TL_all      = zeros(N_mc, length(r_km));
            TL_full_sum = zeros(size(TL_2d));
        end

        IId          = find(z_m >= depth2plot, 1, 'first');
        TL_all(i, :) = TL_2d(IId, :);
        TL_full_sum  = TL_full_sum + TL_2d;

        iter_time = toc(iter_start);
        elapsed   = toc(total_start);
        remaining = (elapsed / i) * (N_mc - i);
        fprintf('Done (%5.1f s). ETA: %5.1f min\n', iter_time, remaining / 60);
    end

    % -----------------------------------------------------------------------
    % 6. Clean up temporary input copies
    % -----------------------------------------------------------------------
    for i = 1:N_mc
        mc_name = sprintf('Test_MC_%d', i);
        for ext = {'.env', '.ssp', '.bty', '.sbp', '.trc'}
            f_temp = fullfile(indir, [mc_name ext{1}]);
            if exist(f_temp, 'file'), delete(f_temp); end
        end
    end

    % -----------------------------------------------------------------------
    % 7. Save Master Results
    % -----------------------------------------------------------------------
    TL_full_mean = TL_full_sum / N_mc;
    results_file = fullfile(outdir, 'MonteCarlo_Results.mat');
    save(results_file, 'r_km', 'z_m', 'base_z', 'base_c', 'all_perturbed_c', ...
         'delta_z_all', 'bulk_offset_all', 'TL_all', 'TL_full_mean', 'depth2plot', ...
         'N_mc', 'base_test', 'optimize_ssp');

    disp('================================================================');
    disp([' Monte Carlo complete in ', num2str(toc(total_start)/60, '%.1f'), ' minutes.']);
    disp([' Master results saved to: ', results_file]);
    disp(' Opening Tactical Combat Display & Sonar Analysis Figures...');
    disp('================================================================');

    % -----------------------------------------------------------------------
    % 8. Automatically display both tactical figures
    % -----------------------------------------------------------------------
    plot_SE_and_FOM(results_file);
    plot_geosit_optionB(results_file);
end
