function [results_file, data, out_folder, version_suffix, shd_pattern] = load_mc_results(results_arg, caller_dir)
% LOAD_MC_RESULTS
% Resolves a Monte Carlo results path or test identifier (e.g. 'Test3', 3, 1,
% or 'Outputs/Case_3/MonteCarlo_Results_3.mat') and loads version metadata.

    mvp_dir   = fileparts(mfilename('fullpath'));
    repo_root = fileparts(mvp_dir);
    if nargin < 2 || isempty(caller_dir)
        caller_dir = mvp_dir; %#ok<NASGU>
    end

    out_root = fullfile(repo_root, 'Outputs');
    if exist(out_root, 'dir') ~= 7 && exist(fullfile(pwd, 'Outputs'), 'dir') == 7
        out_root = fullfile(pwd, 'Outputs');
    end

    % Search Outputs/Case_* directories first, then Outputs/ root
    out_candidates = {};
    if exist(out_root, 'dir') == 7
        sub = dir(fullfile(out_root, 'Case_*'));
        sub = sub([sub.isdir]);
        for k = 1:length(sub)
            out_candidates{end+1} = fullfile(out_root, sub(k).name); %#ok<AGROW>
        end
        out_candidates{end+1} = out_root;
    end
    if isempty(out_candidates)
        out_candidates = {out_root};
    end

    results_file = '';
    if nargin < 1 || isempty(results_arg)
        best_datenum = -inf;
        for k = 1:length(out_candidates)
            files = dir(fullfile(out_candidates{k}, 'MonteCarlo_Results*.mat'));
            if ~isempty(files)
                [cand_date, newest_idx] = max([files.datenum]);
                if cand_date > best_datenum
                    best_datenum = cand_date;
                    results_file = fullfile(out_candidates{k}, files(newest_idx).name);
                end
            end
        end
        if isempty(results_file)
            results_file = fullfile(out_candidates{1}, 'MonteCarlo_Results.mat');
        end
    elseif isnumeric(results_arg)
        num_str      = sprintf('%d', round(results_arg(1)));
        results_file = find_case_mat(out_root, out_candidates, num_str);
    else
        arg_str = strtrim(char(results_arg));
        if exist(arg_str, 'file') == 2
            results_file = arg_str;
        elseif exist(fullfile(repo_root, arg_str), 'file') == 2
            results_file = fullfile(repo_root, arg_str);
        elseif exist(fullfile(mvp_dir, arg_str), 'file') == 2
            results_file = fullfile(mvp_dir, arg_str);
        else
            tok = regexp(lower(arg_str), '^(?:test\s*|case[_ ]*|_|)?(\d+)(?:_all|_raw|_unopt)?$', 'tokens', 'once');
            if ~isempty(tok)
                results_file = find_case_mat(out_root, out_candidates, tok{1});
            else
                results_file = arg_str;
            end
        end
    end

    if exist(results_file, 'file') ~= 2
        error('Results file not found: %s. Run run_monte_carlo first.', results_file);
    end

    f_info = dir(results_file);
    if ~isempty(f_info) && ~f_info(1).isdir
        results_file = fullfile(f_info(1).folder, f_info(1).name);
    else
        w_path = which(results_file);
        if ~isempty(w_path)
            results_file = w_path;
        end
    end

    [out_folder, r_base] = fileparts(results_file);
    if isempty(out_folder)
        out_folder = pwd;
    end

    data = load(results_file);

    version_suffix = '';
    if isfield(data, 'version_suffix') && ~isempty(data.version_suffix)
        version_suffix = char(data.version_suffix);
    else
        v_tok = regexp(r_base, '(_\d+)$', 'tokens', 'once');
        if ~isempty(v_tok)
            version_suffix = v_tok{1};
        end
    end

    if isfield(data, 'shd_pattern') && ~isempty(data.shd_pattern)
        shd_pattern = char(data.shd_pattern);
    else
        shd_pattern = ['Test_MC_%d', version_suffix, '.shd.mat'];
    end
end

function match_path = find_case_mat(out_root, out_candidates, num_str)
    names = {['MonteCarlo_Results_', num_str, '.mat']};
    if strcmp(num_str, '1')
        names{end+1} = 'MonteCarlo_Results.mat';
    end
    search_dirs = [{fullfile(out_root, ['Case_', num_str])}, out_candidates];
    match_path  = fullfile(search_dirs{1}, names{1});
    for d_idx = 1:length(search_dirs)
        for n_idx = 1:length(names)
            cand = fullfile(search_dirs{d_idx}, names{n_idx});
            if exist(cand, 'file') == 2
                match_path = cand;
                return;
            end
        end
    end
end
