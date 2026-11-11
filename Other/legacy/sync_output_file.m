function sync_output_file(src_file, extra_dirs)
    % SYNC_OUTPUT_FILE
    % Mirrors an exported artifact (PNG/HTML) into additional canonical
    % output directories (e.g., Outputs/ and MVP/Outputs/) without failing
    % when source and destination resolve to the same file.

    if exist(src_file, 'file') ~= 2
        return;
    end

    src_info = dir(src_file);
    src_abs  = fullfile(src_info(1).folder, src_info(1).name);
    [~, fname, fext] = fileparts(src_abs);

    if ischar(extra_dirs) || isstring(extra_dirs)
        extra_dirs = {char(extra_dirs)};
    end

    for k = 1:length(extra_dirs)
        dst_dir = extra_dirs{k};
        if isempty(dst_dir), continue; end
        if exist(dst_dir, 'dir') ~= 7
            mkdir(dst_dir);
        end
        dst_path = fullfile(dst_dir, [fname, fext]);
        if ~strcmpi(src_abs, dst_path)
            copyfile(src_abs, dst_path);
        end
    end
end

