% program mk_munk_ssp.m
% simulate a sound speed profile following the classic "Munk" shape and
% store to a text file.

clear;

maxZ = 3500;                % meters
Nz = 101;
z = linspace(0,maxZ,Nz);

% Monk's canonical profile
zax = 1000; B = 1000;	elp = 0.0057;	c_0 = 1490;
fo=fopen('munk_ssp.txt','w');
for ic = 1:Nz
   nu = 2*(z(ic)-zax)./B;
   c(ic) = c_0*(1+elp*(exp(-nu)+nu-1));
   fprintf(fo,'%5.2f  %6.2f  / \n',z(ic),c(ic));
end
fclose(fo);

if 0
   figure;
   % plot svp if desired
   minc = min(c(1:Nz));
   maxc = max(c(1:Nz));
   minz = min(z(1:Nz));
   maxz = max(z(1:Nz));
   plot(c(1:Nz),-z(1:Nz),'b-','linewidth',2);
   axis([round(.999*minc),round(1.001*maxc),-maxz,-minz]);
   ylabel('Depth (m)');
   xlabel('Speed of sound (m/s)');
   set(gca,'XAxisLocation','top');
   title('Canonical Munk Profile');
   grid on; set(gca,'gridalpha',0.31);
   set(gca,'fontsize',12);
end
  