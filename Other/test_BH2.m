% program to run MATLAB version of BellHop test
% Parameters are read from files in "indirname." Most parameters are in the
% .env file.
% Results are stored into "outdirname"
% These are plotted with plot_TL2.m
% Execution time on a modern laptop is about 6-7 minutes
%

function test_BH2(test_name)
    global ray MaxSteps Nsteps omega Bdry Beam
    
    indirname = [pwd '\' 'Inputs'];
    outdirname = [pwd '\' 'Outputs'];
    
    filename = test_name;

SSP = bellhopM2(indirname, outdirname, filename);

