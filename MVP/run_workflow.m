function ens = run_workflow(mode, varargin)
    % RUN_WORKFLOW
    % Top-level pipeline orchestrating Monte Carlo sonar physics (Stage 1)
    % separately from adaptive IQR statistical analysis (Stage 2) and
    % interactive / diagnostic displays (Stage 3).
    %
    % Modes:
    %   run_workflow()                      % Default: 'display' on newest .mat
    %   run_workflow('display')             % Stage 2 + Stage 3 (no Bellhop rerun)
    %   run_workflow('display', results)    % Display/export a specific .mat or test ID
    %   run_workflow('all_displays', ...)   % Also regenerate SE/FOM 2D/1D PNG plots
    %   run_workflow('full', 'Test1')       % Stage 1 (MC) + Stage 2 + Stage 3
    %   run_workflow('full', 'Test3', 20, 1500)
    %
    % Extra trailing logical flags for 'display' / 'all_displays':
    %   run_workflow('display', 'Outputs/Case_1/MonteCarlo_Results.mat', open_browser, close_figs)

    mvp_dir = fileparts(mfilename('fullpath'));
    addpath(mvp_dir);
    addpath(fullfile(mvp_dir, 'html'));
    addpath(fullfile(mvp_dir, 'monte_carlo'));

    if nargin < 1 || isempty(mode)
        mode = 'display';
    end
    mode_l = lower(strtrim(char(mode)));

    results_arg  = [];
    include_se   = strcmp(mode_l, 'all_displays');
    open_browser = true;
    close_figs   = false;

    if strcmp(mode_l, 'full')
        test_name  = 'Test1';
        N_mc       = 20;
        Nbeams_run = 1500;
        if ~isempty(varargin) && ~isempty(varargin{1}), test_name  = varargin{1}; end
        if length(varargin) >= 2 && ~isempty(varargin{2}), N_mc       = varargin{2}; end
        if length(varargin) >= 3 && ~isempty(varargin{3}), Nbeams_run = varargin{3}; end
        if length(varargin) >= 4 && islogical(varargin{4}), include_se = varargin{4}; end

        fprintf('\n=== [WORKFLOW STAGE 1/3] MONTE CARLO SIMULATION (%s) ===\n', char(test_name));
        run_monte_carlo(N_mc, Nbeams_run, test_name);

        tok = regexp(lower(char(test_name)), '(?:test\s*)?(\d+)', 'tokens', 'once');
        if ~isempty(tok)
            results_arg = str2double(tok{1});
        end
    elseif strcmp(mode_l, 'display') || strcmp(mode_l, 'all_displays')
        if ~isempty(varargin), results_arg = varargin{1}; end
        if length(varargin) >= 2 && islogical(varargin{2}), open_browser = varargin{2}; end
        if length(varargin) >= 3 && islogical(varargin{3}), close_figs   = varargin{3}; end
    else
        % Shorthand: run_workflow('Outputs/MonteCarlo_Results.mat') or run_workflow('Test3')
        results_arg = mode;
    end

    fprintf('\n=== [WORKFLOW STAGE 2/3] ENSEMBLE & IQR CALIBRATION ===\n');
    ens = compute_ensemble_stats(results_arg, mvp_dir);
    cs  = ens.color_scale;
    fprintf('  Sensor Depth: %.0f ft (%.1f m) | Target Depths: %d\n', ...
            ens.ownship_depth_m * 3.28084, ens.ownship_depth_m, ens.n_depths);
    fprintf('  Adaptive IQR Color Scale: Steady <= %.1f dB | Yellow = %.1f dB | Whisker = %.1f dB | Full Red = %.1f dB\n', ...
            cs.th_flat, cs.th_yel, cs.tukey_hi, cs.max_spread);

    fprintf('\n=== [WORKFLOW STAGE 3/3] DIAGNOSTICS & GEOSIT HTML CONSOLE ===\n');
    plot_spread_distribution(ens, close_figs);
    if include_se
        plot_SE_and_FOM(ens.results_file);
        if close_figs
            close all;
        end
    end

    % Discover all simulated case folders (Outputs/Case_1, Case_3, ...)
    case_mats = discover_case_mats(ens.repo_root);
    if numel(case_mats) >= 2
        ens_list     = cell(1, numel(case_mats));
        default_case = 0;
        for ci = 1:numel(case_mats)
            if strcmpi(case_mats{ci}, ens.results_file)
                ens_list{ci} = ens;
                default_case = ci - 1;
            else
                ens_list{ci} = compute_ensemble_stats(case_mats{ci}, mvp_dir);
                plot_spread_distribution(ens_list{ci}, close_figs);
            end
            % Export single-case HTML directly inside each Case folder
            export_geosit_to_html(ens_list{ci}, '', false);
        end
        fprintf('  Multi-Case Comparison (%d cases) -> Exporting unified HTML console...\n', numel(ens_list));
        export_geosit_to_html(ens_list, '', open_browser, default_case);
    else
        export_geosit_to_html(ens, '', open_browser);
    end

    fprintf('\n[WORKFLOW COMPLETE] All outputs written to Case folders (no duplicates).\n');
end

function mat_list = discover_case_mats(repo_root)
    mat_list = {};
    out_root = fullfile(repo_root, 'Outputs');
    if exist(out_root, 'dir') ~= 7
        return;
    end
    sub = dir(fullfile(out_root, 'Case_*'));
    sub = sub([sub.isdir]);
    case_nums = inf(1, length(sub));
    for k = 1:length(sub)
        tok = regexp(sub(k).name, '^Case_(\d+)$', 'tokens', 'once');
        if ~isempty(tok)
            case_nums(k) = str2double(tok{1});
        end
    end
    [~, order] = sort(case_nums);
    for k = order
        mfiles = dir(fullfile(out_root, sub(k).name, 'MonteCarlo_Results*.mat'));
        if ~isempty(mfiles)
            [~, newest] = max([mfiles.datenum]);
            mat_list{end+1} = fullfile(out_root, sub(k).name, mfiles(newest).name); %#ok<AGROW>
        end
    end
end

