function reflect( I, BeamType, BC, cHS, rhoHS, BotTop, TBdry, NBdry, kappa, SSP, rcp, bb )
% rcp = pointer to surface reflection coefficients
% bb = point to bottom geological properties

% Reflect a ray/beam off a boundary

global ray omega Layer

RADDEG = 180 / pi;   % used to convert radians to degrees

Tg = dot( ray( I ).Tray', TBdry' );  % component of ray tangent, along boundary
Th = dot( ray( I ).Tray', NBdry' );  % component of ray tangent, normal to boundary

% *** calculate the change in curvature ***
% Based on formulas given by Muller, Geoph. J. R.A.S., 79 (1984).

[ c, c_imag, gradc, ~, ~, ~, Layer ] = ssp( ray( I ).x( : ), SSP, Layer );

% incident unit ray tangent and normal
rayt = ray( I ).Tray;
rayn = [ -rayt( 2 ) rayt( 1 ) ];

%cnjump = 2 * gradc( 2 ) .* ray( I ).Tray( 1 );
%csjump = 2 * gradc( 2 ) .* ray( I ).Tray( 2 );   % assumes gradc( 1 ) = cr = 0
cnjump = 2 * gradc * rayn.';
csjump = 2 * gradc * rayt.';

RN = 2 * kappa / c^2 / Th;    % boundary curvature correction

if ( strcmp( BotTop, 'TOP' ) )
    cnjump = -cnjump;    % flip sign for top reflection
    RN     = -RN;
end

RM = Tg ./ Th;
RN = RN + RM' .* ( 2 * cnjump - RM' .* csjump ) ./ c;

switch ( BeamType(2:2) )
    case ( 'D' )
        RN = 2.0 * RN;
    case ( 'Z' )
        RN = 0.0;
end

ray( I ).Tray( 1 ) =  ray( I ).Tray( 1 ) - 2.0 * ( Th .* NBdry( 1 )' )';
ray( I ).Tray( 2 ) =  ray( I ).Tray( 2 ) - 2.0 * ( Th .* NBdry( 2 )' )';

ray( I ).p( 1 ) = ray( I ).p( 1 ) + ray( I ).q( 1 ) * RN;
ray( I ).p( 2 ) = ray( I ).p( 2 ) + ray( I ).q( 2 ) * RN;

% *** account for phase change ***

switch ( BC )
    case ( 'R' )                 % rigid
    case ( 'V' )                 % vacuum
        ray( I ).Rfa = -ray( I ).Rfa;
    case ( 'F' )                 % file
        theInt = RADDEG * abs( atan2( Th, Tg ) );   % angle of incidence (relative to normal to surface)
        % find the reflection coefficient and phase that matches the incident angle (degrees)
        [~, IIt] = min(abs(rcp.thetaTop - theInt));
        rInt = rcp.RTop(IIt);
        phiInt = rcp.phiTop(IIt);
        %[ theta, RefC, phi ] = RefCO( theInt, rInt, phiInt, Npts  )
        ray( I ).Rfa = ray( I ).Rfa * rInt * exp( 1i * phiInt );
    case ( 'A' )                 % half-space
        if 0
           GK       = omega * Tg;   % wavenumber in direction parallel to bathymetry
           gamma1SQ = ( omega / c'  ).^ 2 - GK^ 2;
           gamma2SQ = ( omega / cHS ) ^ 2 - GK^ 2;
           gamma1   = sqrt( -gamma1SQ );
           gamma2   = sqrt( -gamma2SQ );
           Refl = ( rhoHS * gamma1 - gamma2 ) / ( rhoHS * gamma1 + gamma2 );
           % above should really be:
           % Refl = ( rhoHs * gamma1 - rho * gamma2 ) / ( rhoHS * gamma1 + rho * gamma2 )
           % However, BELLHOP assumes rho=1 in water
           % Need to modify this as was done in the Fortran version to have
           % ssp return rho
           %fprintf('I = %d, Tg = %8.6f, Th = %8.6f. Tray(1) = %8.6f, Tray(2) = %8.6f, TBdry = %8.4f %8.4f, NBdry = %8.4f %8.4f \n', ...
           %         I,Tg, Th, ray(I).Tray(1,1),ray(I).Tray(1,2),TBdry(1,1), TBdry(1,2), NBdry(1,1), NBdry(1,2));
           %fprintf('w = %5.1f, Th = %8.6f, Tg = %8.6f, c = %5.1f, cHS = %5.1f, rhoHS = %5.1f, Refl = %5.3f \n', ...
           %         omega, Th, Tg, c, cHS, rhoHS, Refl);
        else
           % from pg IV-18 in APL-UW Handbook
           c2 = bb.alphaR;
           a2 = bb.alphaI;
           r2 = bb.rho;
           v = c2/c;        % sound speed ratio
           delta = a2*v*1.528*log(10)./(omega/1000*20);             % loss term
           kappa = (1+i*delta)./v;
           theInt = RADDEG * abs( atan2( Th, Tg ) );
           %fprintf('c2 = %5.1f, r2 = %6.4f, a2 = %7.5f, angle = %5.2f \n',c2,r2,a2,theInt);
           Ptheta = sqrt(kappa.^2 - cosd(theInt).^2);             % 
           y = rhoHS.*sind(theInt)./Ptheta;
           Refl = (y-1)./(y+1);
        end
        
        ray( I ).Rfa = Refl.' .* ray( I ).Rfa;
    end
end
