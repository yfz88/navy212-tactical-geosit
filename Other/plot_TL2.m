% plot a 2-D TL plot, depth vs range from BellHop
% Reads a transmission loss field grid from the specified file and plots a
% range-depth image and a line (ascan) plot at discrete depths.
%

function plot_TL2(test_name)
    indirname = [pwd '\' 'Inputs'];
    outdirname = [pwd '\' 'Outputs'];
    
    infilename = test_name;
    outfilename = [test_name '.shd.mat'];

do_ssp = 1;             % = 1 to include an SSP in the plot
depth2plot = [50 100 200 300];       % depths for ascan plots

% parse the input file to get plot parameters
% use these parameters to fill in the plot title
fo=fopen([indirname '\' infilename '.env']);
while 1
   tline = fgets(fo);
   if tline == -1 break; end
   Nl = length(tline);
   for ic=1:Nl-4
      if tline(ic:ic+3) == 'FREQ' | tline(ic:ic+3) == 'freq'
        [bd,count] = sscanf(tline(1:8),'%f\n');
        f = bd(1);
        break;
      end
   end
   % find source depth
   for ic=1:Nl-5
      if tline(ic:ic+5) == 'Source'
         [bd,count] = sscanf(tline,'%f\n');
         Z_S = bd(1);
         break;
      end
   end
   % find max depth
   for ic=1:Nl-10
      if tline(ic:ic+9) == 'SSP depths'
         [bd,count] = sscanf(tline,'%d %f %f\n');
         Lssp = bd(1);
         z1 = bd(2);   zmax = bd(3);
         for n=1:Lssp
            tline2 = fgets(fo);
            [bd,count] = sscanf(tline2,'%f %f \n');
            z(n) = bd(1);
            ssp1(n) = bd(2);
         end
         break;
      end
   end
   % find launch angles
   for ic=1:Nl-5
      if tline(ic:ic+5) == 'launch'
         [bd,count] = sscanf(tline,'%f  %f\n');
         minA = bd(1);  maxA = bd(2);
         break;
      end
   end
end

fclose(fo);

% get the bathymetry vector
fo=fopen([indirname '\' infilename '.bty']);

tline = fgets(fo);
tline = fgets(fo);
[bd,count] = sscanf(tline,'%f\n'); 
Nz = bd(1);
for ic=1:Nz
   tline = fgets(fo);
   if tline == -1 break; end
   [bd,count] = sscanf(tline,'%f %f %f %f %f %f\n');   
   r2(ic) = bd(1).*1000;
   zb(ic) = bd(2);
end

% get all the SSP's used
fo=fopen([indirname '\' infilename '.ssp']);

tline = fgets(fo);
[bd,count] = sscanf(tline,'%d \n'); 
Nssp = bd(1);                           % number of SSP's
tline = fgets(fo);
[bd, count] = sscanf(tline,'%f');
rs = bd(1:Nssp);                      % range at each SSP

SSP = zeros(Lssp,Nssp);
for ic=1:Lssp                           % loop on number of depth cells
   tline = fgets(fo);
   if tline == -1 break; end
   [bd, count] = sscanf(tline,'%f');
   SSP(ic,1:Nssp) = bd(1:Nssp);
end

% load the precomputed TL data from outfilename
load([outdirname '\' outfilename]);

figure;

% the TL values are stored as complex linear pressures
% convert them to Decibels (dB)
TL=-20*log10(squeeze(abs(pressure)));

if do_ssp == 1
   subplot(1,6,[1]);
   hold on;
   for ic=1:Nssp
      if ic == 1
         plot(SSP(:,ic),z,'k','linewidth',1.5);
      else
         plot(SSP(:,ic),z,'k','linewidth',0.75);
      end
   end
   axis([min(ssp1).*0.999, max(ssp1).*1.001 min(z) max(z)]);
   set(gca,'XaxisLocation','Top');
   grid on; set(gca,'gridalpha',0.31);
   set(gca,'ydir','reverse');
   TT = title('SSP (m/s))');
   ylabel('Depth (m)');
   set(gca,'fontsize',12);

   subplot(1,6,[2 3 4 5 6]);
end

% plot the 2-D image (TL = color vs range (horiz) and depth (vertical)
hold on;
imagesc(Pos.r.r,Pos.r.z,TL);
set(gca,'ydir','reverse');
axis([Pos.r.r(1) Pos.r.r(end) Pos.r.z(1) Pos.r.z(end)]);
xlabel('Range (m)');
plot(r2,zb,'w','linewidth',2.5);
set(gca,'ydir','reverse');

[Nj idim] = size(jet);
jet2 = zeros(Nj,3);
jet1 = jet;
for ic=1:Nj
   jet2(ic,:) = jet1(Nj-ic+1,:);
end
colormap(jet2);

CB = colorbar;
CB.Label.String = 'dB';

if do_ssp == 1
   TT2 = title({['Transmission Loss (TL), ',PlotTitle]; ...
    ['freq = ',num2str(f),' Hz, Z_S = ',num2str(Z_S),' m, minA = ',num2str(minA),', maxA = ',num2str(maxA),' degs']});
else
   TT2 = title({['Transmission Loss for']; [PlotTitle]});
end
set(TT2,'interpreter','none');
caxis([70 120]);
set(gca,'fontsize',12);
grid on; set(gca,'gridalpha',0.31);

figure;
col(1) = 'b'; col(2) = 'r'; col(3) = 'g'; col(4) = 'm'; col(5) = 'k';  col(6) = 'c'; 
Ndp = length(depth2plot);
hold on;
for ic=1:Ndp
   IId = find(Pos.r.z >= depth2plot(ic),1,'first');
   plot(Pos.r.r,-TL(IId,:),col(ic),'linewidth',2);
end
grid on; set(gca,'gridalpha',0.31);
xlabel('Range (m)'); ylabel('TL (dB)');
if do_ssp == 1
   TT2 = title({['Transmission Loss (TL), ',PlotTitle]; ...
    ['freq = ',num2str(f),' Hz, Z_S = ',num2str(Z_S),' m, minA = ',num2str(minA),', maxA = ',num2str(maxA),' degs']});
else
   TT2 = title({['Transmission Loss for']; [PlotTitle]});
end
set(TT2,'interpreter','none');
C='';
for ic = Ndp:-1:1
  C=strvcat([num2str(depth2plot(ic),'%3.1f'),' m'],C);
end
legend(C,'location','northeast');
axis([Pos.r.r(1) Pos.r.r(end) -140 -50]);
set(gca,'fontsize',12);

