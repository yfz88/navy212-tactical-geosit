% plot all eigen rays, depth vs range from BellHop
%

clear;
% location and name of env file
iplot=1;
if iplot == 1
   indirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\Matlab\Bellhop\Inputs';
   infilename = 'MunkB_eigenray.env';
   outdirname = 'C:\Users\david.pistacchio\Documents\Projects\DUST\SI\2023\ML\BellHop\Matlab\Bellhop\Outputs';
   outfilename = 'MunkB_eigenray.shd.mat';
end

% parse the input file to get plot parameters
fo=fopen([indirname '\' infilename]);
while 1
   tline = fgets(fo);
   if tline == -1 break; end
   Nl = length(tline);
   % find frequency
   for ic=1:Nl-3
      if tline(ic:ic+3) == 'FREQ'
         [bd,count] = sscanf(tline,'%f\n');
         freq = bd(1);
         break;
      end
   end
   % find source depth
   for ic=1:Nl-3
      if tline(ic:ic+3) == 'SD(1'
         [bd,count] = sscanf(tline,'%f\n');
         Z_S = bd(1);
         break;
      end
   end
   % find max depth
   for ic=1:Nl-5
      if tline(ic:ic+5) == 'ALPHA1'
         [bd,count] = sscanf(tline,'%f\n');
         minA = bd(1);  maxA = bd(2);
         break;
      end
   end
end

% load the precomputed data from outfilename
load([outdirname '\' outfilename]);
return;

figure;
colormap(jet);

TL=10*log10(squeeze(abs(pressure)));
imagesc(Pos.r.r,Pos.r.z,TL);

colorbar;
title({['Transmission Loss (TL), ',PlotTitle]; ...
    ['freq = ',num2str(freq),' Hz, Z_S = ',num2str(Z_S),' m, minA = ',num2str(minA),', maxA = ',num2str(maxA),' degs']});
xlabel('Range (m)');
ylabel('Depth (m)');
caxis([-80 -20]);

