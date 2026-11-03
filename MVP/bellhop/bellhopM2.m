function [SSP,pressure,Pos,r,z,Nbeams,Nsteps_bm] = bellhopM2( indirname, outdirname, filename )

% Beam-tracing code for ocean acoustics problems
% Copyright (C) 2009 Michael B. Porter
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.

% Based on the earlier Fortran version
% MBP Dec. 30, 2001
%
% For Matlab, the code had to be vectorized so all beams are traced in parallel.
% Furthermore, to keep the various vectors associated with each ray
% together in memory, it was necessary to collect them in a structure.
%
% The tracing of beams in parallel lead to huge storage requirements for the ray trajectories
% Suggests a possible rewrite to calculate TL (INFLUG module) in parallel
% with the ray trace (TRACE module).
% In the meantime, note that the run time goes through the ceiling when the
% required storage gets too large ...

clear global

tic

if ( isempty( indirname ) )
    warndlg( 'No envfil directory has been selected', 'Warning' );
end
if ( isempty( outdirname ) )
    warndlg( 'No outfile directory has been selected', 'Warning' );
end
if ( isempty( filename ) )
    warndlg( 'No file name has been selected', 'Warning' );
end

global ray MaxSteps Nsteps omega Bdry Beam
global Pos
global alpha Nbeams
global U Arr MxNarr
global NumTopBnc NumBotBnc

% include the functions in these two subdirectories in your path
bellhop_folder = fileparts(mfilename('fullpath'));
P1 = fullfile(bellhop_folder, 'ReadWrite');
P2 = fullfile(bellhop_folder, 'Misc');
addpath(P1);
addpath(P2);

% filenames
infilename = [indirname '\' filename];
outfilename = [outdirname '\' filename];
envfil = [ infilename '.env' ];   % input environmental file
shdfil = [ outfilename '.shd.mat' ];   % output file name (pressure)
arrfil = [ outfilename '.arr.mat' ];   % output file name (arrivals)
btyfil = [ infilename '.bty' ];   % input bathymetry
atifil = [ infilename '.ati' ];   % input altimetry
rayfil = [ infilename '.ray' ];   % ray trace file
sbpfil = [ infilename '.sbp' ];   % input source beam pattern
trcfil = [ infilename  '.trc' ];   % input top    reflection coefficient
brcfil = [ infilename  '.brc' ];   % input bottom reflection coefficient


[ PlotTitle, freq, SSP, Bdry, Pos, Beam, ~, ~, fid ] = read_env( envfil, 'BELLHOP' );    % read in the environmental file
fclose( fid );                    % close out the envfil

Beam.Box.r  = 1000.0 * Beam.Box.r;
Pos.r.r     = 1000.0 * Pos.r.r; % convert km to m

PlotTitle = ['BELLHOP(M) -' PlotTitle ];

SSP.Type = Bdry.Top.Opt(1:1);

% initialization for interpolation options other than c-Linear
switch ( SSP.Type )
   case ( 'N' )   % n^2 linear
      SSP.n2  = 1.0 ./ ( SSP.c.^2 );
      SSP.n2z = diff( SSP.n2 ) ./ diff( SSP.z );
   case ( 'P' )   % monotone PCHIP ACS (almost a cubic spline), commonly used but doesnt have second derivative
      % force values to be real (DP, 2025)
      SSP.ppc  = pchip_acs( SSP.z, real(SSP.c) );
   case ( 'S' )   % Cubic Spline using not-a-knot boundary condition
      SSP.ppc = spline( SSP.z, SSP.c );
end

if ( SSP.Type == 'P'  || SSP.Type == 'S')
      [ breaks, coefs, pieces, order, dim ] = unmkpp( SSP.ppc );

      coefs_cz  = repmat( order - 1 : -1 : 1, pieces, 1 ) .* coefs( : , 1 : order - 1 );
      SSP.ppcz  = mkpp( breaks, coefs_cz,  dim ); % reassemble the differentiated piecewise polynomial

      coefs_czz = repmat( order - 2 : -1 : 1, pieces, 1 ) .* coefs_cz( : , 1 : order - 2 );
      SSP.ppczz = mkpp( breaks, coefs_czz, dim ); % reassemble the differentiated piecewise polynomial
end

TopATI = Bdry.Top.Opt(5:5);
readati( atifil, TopATI, Bdry.Top.depth, Beam.Box.r );    % read in the altimetry  file

BotBTY = Bdry.Bot.Opt(2:2);
readbty2( btyfil, BotBTY, Bdry.Bot.depth, Beam.Box.r );    % read in the bathymetry file (with corrected routine)

fprintf('Top bdry opt: %s, Bot bdry opt: %s \n',Bdry.Top.Opt( 2 : 2 ),Bdry.Bot.Opt( 1 : 1 ) );

rcp = readrc( trcfil, brcfil, Bdry.Top.Opt( 2 : 2 ), Bdry.Bot.Opt( 1 : 1 ) );   % READ Reflection Coefficients (top and bottom)

SrcBmPat = readpat( infilename, Beam.RunType( 3 : 3 ) );   % optionally read source beam pattern

if ( ismember( 'A', upper( Beam.RunType( 1 : 1 ) ) ) )
    MxNarr = round( max( 2000000 / ( Pos.Nrz * Pos.Nrr ), 10 ) );   % allow space for at least 10 arrivals
    fprintf( '\n( Maximum # of arrivals = %i ) \n', MxNarr );
    
    Arr.A     = zeros( Pos.Nrz, Pos.Nrr, MxNarr );
    Arr.delay = zeros( Pos.Nrz, Pos.Nrr, MxNarr );
    Arr.angle = zeros( Pos.Nrz, Pos.Nrr, MxNarr );
    Arr.Narr  = zeros( Pos.Nrz, Pos.Nrr );
else
    pressure = zeros( 1, Pos.Nsz, Pos.Nrz, Pos.Nrr );
end

%MaxSteps = round( 2000000 );
MaxSteps = round( 20000 );

% pre-allocate
% ray( MaxSteps ) = struct( 'c', [], 'x', [], 'Tray', [ 0 0 ], 'p', [ 0 0 ], 'q', [ 0 0 ], 'tau', [], 'Rfa', [] );
ray( MaxSteps  ).c    = [];
ray( MaxSteps  ).x    = [];
ray( MaxSteps  ).Tray = [ 0 0 ];
ray( MaxSteps  ).p    = [ 0.0 0.0 ];
ray( MaxSteps  ).q    = [ 0.0 0.0 ];
ray( MaxSteps  ).tau  = [];
ray( MaxSteps  ).Rfa  = [];

omega = 2 * pi * freq;
Amp0  = interp1( SrcBmPat( :, 1 ), SrcBmPat( :, 2 ), alpha ); % calculate initial beam amplitude based on source beam pattern

alpha = ( pi / 180 ) * alpha;   % convert to radians
Dalpha = 0.0;
if ( Nbeams ~= 1 )
    Dalpha = ( alpha( Nbeams ) - alpha( 1 ) ) / ( Nbeams - 1 );  % angular spacing between beams
end

% *** Loop over source depths ***
Layer = 1;

for is = 1 : Pos.Nsz
    xs = [ 0.0 Pos.s.z( is ) ];   % source coordinate
    [ c, ~, ~, ~, ~, ~, Layer ] = ssp( xs, SSP, Layer );
    % RadMax = 10 * c / freq;  % 10 wavelength max radius
    
    % Are there enough beams?
    DalphaOpt = sqrt( c / ( 6.0 * freq * Pos.r.r( end ) ) );
    NbeamsOpt = round( 2 + ( alpha( Nbeams ) - alpha( 1 ) ) / DalphaOpt );
    fprintf('NbeamsOpt = %d while Nbeams = %d \n',NbeamsOpt,Nbeams);
    
    if ( Beam.RunType(1:1) == 'C' & Nbeams < NbeamsOpt )
        fprintf( 'Warning: Nbeams should be at least = %i \n', NbeamsOpt )
    end
    
    % *** Trace rays ***
    U = zeros( length( Pos.r.z ), length( Pos.r.r ) );
    
    if Beam.RunType(1:1) == 'R'
       figure;
       hold on;
       rmax = -9999;
    end
    
    NumTopBnc = zeros(1,Nbeams);            % counter for number of surface bounces
    NumBotBnc = zeros(1,Nbeams);            % counter for number of bottom bounces
    
    r = zeros(MaxSteps,Nbeams);
    z = zeros(MaxSteps,Nbeams);
    Nsteps_bm = zeros(1,Nbeams);
    
    fprintf('made r and z [%d x %d] \n',Nsteps,Nbeams);

    for ibeam = 1 : Nbeams
       
        if ( mod( ibeam - 1, max( fix( Nbeams / 50 ), 1 ) ) == 0 )
           disp( [' Tracing beam ', num2str( ibeam ) ] )
        end
        
        trace( SSP, Beam.deltas, xs, alpha( ibeam ), Amp0( ibeam ), Beam.Type, Beam.Box, Beam.RunType, rcp, ibeam );
        
        if ibeam == -500
            fprintf('got here \n');
            return;
        end
        Nsteps_bm(ibeam) = Nsteps;
        
        % ray trace run?
        if Beam.RunType(1:1) == 'R'
            %figure
            %title( PlotTitle );
            %set( gca, 'YDir', 'Reverse' )   % plot with depth-axis positive down
            
            % r = zeros( Nsteps, 1 );
            % z = zeros( Nsteps, 1 );
            
            for ii = 1 : Nsteps
                r( ii, ibeam ) = ray( ii ).x( 1 );
                z( ii, ibeam ) = ray( ii ).x( 2 );
            end
            %fprintf('NtB = %d, NbB = %d \n',NumTopBnc, NumBotBnc);
            if NumTopBnc(ibeam) > 0 & NumBotBnc(ibeam) > 0
                plot( r(1:Nsteps,ibeam), z(1:Nsteps,ibeam), 'k' )    % hits both boundaries
            elseif NumTopBnc(ibeam) == 0 & NumBotBnc(ibeam) > 0
                plot( r(1:Nsteps,ibeam), z(1:Nsteps,ibeam), 'b' )	   % hits bottom only
            elseif NumTopBnc(ibeam) > 0 & NumBotBnc(ibeam) == 0
                plot( r(1:Nsteps,ibeam), z(1:Nsteps,ibeam), 'g' )	   % hits surface only
            elseif NumTopBnc(ibeam) == 0 & NumBotBnc(ibeam) == 0
                plot( r(:,ibeam), z(:,ibeam), 'r' )     % direct path
            end
            drawnow; hold on
            %plot( r(:,ibeam), z(:,ibeam) ); drawnow; hold on

            if rmax < r(end, ibeam)
               rmax = r(end, ibeam);
            end
            if ibeam == Nbeams
               set( gca, 'YDir', 'Reverse' )   % plot with depth-axis positive down
               axis([0 rmax 0 z(end,ibeam)]);
               xlabel('Range (m)');
               ylabel('Depth (m)');
               grid on; set(gca,'gridalpha',0.35);
               rad2deg = 180/pi;
               TT = title({['Ray trace, ',filename]; ...
                     ['Z_s = ',num2str(Pos.s.z(1)),' m, minA =',num2str(alpha(1)*rad2deg,'%3.1f'),', maxA = ',num2str(alpha(end)*rad2deg,'%3.1f'),' degs']});
               set(TT,'interpreter','none');
               set(gca,'fontsize',12);
               hold off;
            end
            if ibeam == Nbeams
               save (rayfil, 'ibeam', 'Nsteps', 'ray');
            end
        else
            
            if ( Beam.RunType(2:2) == 'G' )
                InfluenceGeoHat(      Pos.s.z( is ), alpha( ibeam ), Beam.RunType, Dalpha  )
            else
                InfluenceGeoGaussian( Pos.s.z( is ), alpha( ibeam ), Beam.RunType, Dalpha, Beam.deltas  )
            end
        end
    end
    if ( Beam.RunType(1:1) == 'A' )   % arrivals calculation
        
        % add in cylindrical spreading
        for ir = 1 : Pos.Nrr
            factor = 1 / sqrt( Pos.r.r( ir ) );
            Arr.A( :, ir, : ) = factor * Arr.A( :, ir, : );
        end
        save( arrfil, 'PlotTitle', 'Pos', 'Arr', 'MxNarr' )
    else
        pressure( 1, is, :, : ) = scalep( Dalpha, c, Pos.r.r, U, Beam.RunType, Bdry.Top.Opt, freq );
        fprintf('got here too \n');
        PlotType     = 'rectilin  ';
        atten        = 0;
        freqVec( 1 ) = freq;
        freq0        = freq;
        % problem: sd is outside the loop
        save( shdfil, 'PlotTitle', 'PlotType', 'freqVec', 'freq0', 'atten', 'Pos', 'pressure' )
        %plotshd( shdfil )
    end

end % next source depth

toc
