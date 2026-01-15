function compile_mexmaca64()
% Build script for MyM (64-bit Mac OS X, apple silicon)
% For Mac, we can rely on the system zlib. It has been at version >= 1.2.3
% since OS X 10.4

mym_base = fileparts(fileparts(mfilename('fullpath')));
mym_src = fullfile(mym_base, 'src');
build_out = fullfile(mym_base, 'build', mexext());
distrib_out = fullfile(mym_base, 'distribution', mexext());

% Set up input and output directories
mysql_base = fullfile(mym_base, 'mysql-connector');
mysql_include = fullfile(mysql_base, 'include');
mysql_platform_include = fullfile(mysql_base, ['include_' mexext()]);
mysql_lib = fullfile(mysql_base, ['lib_' mexext()]);
mariadb_lib = fullfile(mym_base, ['maria-plugin/','lib_',mexext()]);
lib_lib = fullfile(mym_base, ['lib/',mexext()]);

mkdir(build_out);
mkdir(distrib_out);
oldp = cd(build_out);
pwd_reset = onCleanup(@() cd(oldp));

% Set environment
setenv('MACOSX_DEPLOYMENT_TARGET', '14.0');

% Get MATLAB paths
matlabroot_path = matlabroot;
extern_include = fullfile(matlabroot_path, 'extern', 'include');
bin_path = fullfile(matlabroot_path, 'bin', 'maca64');
extern_lib = fullfile(matlabroot_path, 'extern', 'lib', 'maca64');

% Verify paths exist
assert(exist(fullfile(mym_src, 'mym.cpp'), 'file') > 0, 'mym.cpp not found!');
assert(exist(mysql_include, 'dir') > 0, 'mysql_include directory not found!');
assert(exist(mysql_lib, 'dir') > 0, 'mysql_lib directory not found!');

fprintf('=== Compiling mym.cpp ===\n');

% Compile step
compile_cmd = sprintf([...
    '/usr/bin/clang++ ', ...
    '-c -fno-common -arch arm64 -mmacosx-version-min=14.0 ', ...
    '-fexceptions -fPIC -fno-omit-frame-pointer ', ...
    '-D_GNU_SOURCE -DMATLAB_MEX_FILE -DMEX_DOUBLE_HANDLE ', ...
    '-I"%s" -I"%s" -I"%s" ', ...
    '-O2 "%s" -o mym.o'], ...
    extern_include, mysql_include, mysql_platform_include, ...
    fullfile(mym_src, 'mym.cpp'));

fprintf('Command: %s\n\n', compile_cmd);
[status1, output1] = system(compile_cmd);
fprintf('%s\n', output1);

if status1 ~= 0
    error('Compilation failed!');
end

fprintf('\n=== Compiling MEX version info ===\n');

% Compile the C MEX API version file
version_cmd = sprintf([...
    '/usr/bin/clang++ ', ...
    '-c -fno-common -arch arm64 -mmacosx-version-min=14.0 ', ...
    '-fexceptions -fPIC -DMATLAB_MEX_FILE -DMX_COMPAT_64 ', ...
    '-I"%s" ', ...
    '-O2 "%s/extern/version/c_mexapi_version.c" -o c_mexapi_version.o'], ...
    extern_include, matlabroot_path);

fprintf('Command: %s\n\n', version_cmd);
[status_v, output_v] = system(version_cmd);
fprintf('%s\n', output_v);

if status_v ~= 0
    error('Version compilation failed!');
end

fprintf('\n=== Linking mym.mexmaca64 ===\n');

% Link step - include the version object file
link_cmd = sprintf([...
    '/usr/bin/clang++ ', ...
    '-arch arm64 -mmacosx-version-min=14.0 ', ...
    '-bundle -Wl,-syslibroot,/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk ', ...
    '-Wl,-exported_symbols_list,"%s/mexFunction.map" ', ...
    '-Wl,-exported_symbols_list,"%s/c_exportsmexfileversion.map" ', ...
    '-L"%s" -L"%s" -L"%s" ', ...
    'mym.o c_mexapi_version.o ', ...  % Include both object files
    '-lmx -lmex -lmat -lmysqlclient -lz ', ...
    '-o mym.mexmaca64'], ...
    extern_lib, extern_lib, bin_path, mysql_lib, mariadb_lib);

fprintf('Command: %s\n\n', link_cmd);
[status2, output2] = system(link_cmd);
fprintf('%s\n', output2);

if status2 == 0
    fprintf('\n✓✓✓ SUCCESS! mym.mexmaca64 compiled successfully! ✓✓✓\n');
    % Verify the file exists
    if exist('mym.mexmaca64', 'file')
        fprintf('File created: %s\n', which('mym.mexmaca64'));
    end
else
    error('Linking failed!');
end

% find old libmysql path
[~,old_link] = system(['otool -L ' ...
    fullfile(build_out, ['mym.' mexext()]) ...
    ' | grep libmysqlclient.24.dylib | tail -1 |awk ''{print $1}''']);

% Change libmysql reference to mym mex directory
system(['install_name_tool -change "' strip(old_link) '" ' ...
    '"@loader_path/libmysqlclient.24.dylib" "' ...
    fullfile(build_out, ['mym.' mexext()]) '"']);

% Pack mex with all dependencies into distribution directory
copyfile(['mym.' mexext()], distrib_out, 'f');
copyfile(fullfile(mym_src, 'mym.m'), distrib_out, 'f');
copyfile(fullfile(mysql_lib, 'libmysqlclient*'), distrib_out, 'f');
copyfile(fullfile(mariadb_lib, 'dialog.so'), distrib_out, 'f');
copyfile(fullfile(lib_lib, '*'), distrib_out, 'f');
