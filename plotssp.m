% program plotssp.m
% Plots the sound speed profile

% MBP 03/2009

clear;

% read in the environmental file
% location and name of env file
iplot=3;
if iplot == 1
   indirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\MATLAB\Bellhop\Inputs';
   infilename = 'MunkB_Coh.env';
elseif iplot == 2
   indirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\MATLAB\Bellhop\Inputs';
   infilename = 'MunkB_Semi.env';
elseif iplot == 3
   indirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\MATLAB\Bellhop\Inputs';
   infilename = 'MunkB_Semi_gb.env';
elseif iplot == 4
   indirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\MATLAB\Bellhop\Inputs';
   infilename = 'wedgeB.env';
elseif iplot == 5
   indirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\MATLAB\Bellhop\Inputs';
   infilename = 'shaded.env';
elseif iplot == 6
   indirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\MATLAB\Bellhop\Inputs';
   infilename = 'arcticB_gb.env';
end


[ ~, ~, SSP, Bdry, ~, ~, ~, ~, fid ] = read_env( infilename, 'BELLHOP' );

SSPType = Bdry.Top.Opt( 1 : 1 );

fclose( fid );

figure
hold on

for medium = 1 : SSP.NMedia
   
   npts = round( SSP.raw( medium ).z(end) - SSP.raw( medium ).z( 1 ) ) + 1;
   if ( contains( SSPType, 'S' ) || contains( SSPType, 'P' ) )
      npts = 2 * npts;   % need to see internal points for cubic interpolation
   end
   
   z_eval = linspace( SSP.raw( medium ).z(1), SSP.raw( medium ).z( end ), npts );
   
   % plot the compression wave speed
   
   switch ( SSPType )
      case ( 'N' )   % n^2 Linear
         n2_eval = interp1( SSP.raw( medium ).z, 1.0 ./ ( SSP.raw( medium ).alphaR ).^2, z_eval, 'linear' );
         c_eval = real( 1.0 ./ sqrt( n2_eval ) );
      case ( 'P' )   % monotone PCHIP ACS (almost a cubic spline)
         c_eval = pchip_acs(  SSP.raw( medium ).z, real( SSP.raw( medium ).alphaR ), z_eval );
      case ( 'S' )   % Cubic Spline using not-a-knot boundary condition
         c_eval = spline( SSP.raw( medium ).z, real( SSP.raw( medium ).alphaR ), z_eval );
      otherwise      % piecewise Linear
         c_eval = real( interp1( SSP.raw( medium ).z, SSP.raw( medium ).alphaR, z_eval, 'linear' ) );
   end
   
   plot( real( SSP.raw( medium ).alphaR ), SSP.raw( medium ).z, 'ko' );
   hh = plot( c_eval, z_eval, 'b-' );
   set( hh, 'LineWidth', 2 );
   
   % plot the shear wave speed (if any non-zero values were supplied)
   
   if ( any( SSP.raw( medium ).betaR ) )
      
      switch ( SSPType )
         case ( 'N' )   % n^2 Linear
            n2_eval = interp1( SSP.raw( medium ).z, 1.0 ./ ( SSP.raw( medium ).betaR ).^2, z_eval, 'linear' );
            c_eval  = real( 1.0 ./ sqrt( n2_eval ) );
         case ( 'P' )   % monotone PCHIP ACS (almost a cubic spline)
            c_eval = pchip_acs(  SSP.raw( medium ).z, real( SSP.raw( medium ).betaR ), z_eval );
         case ( 'S' )   % Cubic Spline using not-a-knot boundary condition
            c_eval = spline( SSP.raw( medium ).z, real( SSP.raw( medium ).betaR ), z_eval );
         otherwise      % piecewise Linear
      end
      
      plot( real( SSP.raw( medium ).betaR ), SSP.raw( medium ).z, 'ko' );
      hh = plot( c_eval, z_eval, 'r-' );
      set( hh, 'LineWidth', 2 );
   end
   
end

set( gca, 'YDir', 'Reverse' )   % because view messes up the zoom feature
%axis IJ

TT=title(infilename);
set(TT,'interpreter','none');
xlabel('Sound Speed (m/s)');
set(gca,'XAxisLocation','top');
ylabel('Depth (m)');
grid on; set(gca,'gridalpha',0.1);
set(gca,'fontsize',12);

