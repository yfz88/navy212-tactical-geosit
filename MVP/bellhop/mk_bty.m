% program mk_bty.m
% creates a file of bottom depths and geological parameters for use in the
% Bellhop TL model.
%

clear;

maxR = 40000;           % meters
Nr = 1000;              % needs to be the same as the number in .env file
zrms = 10;              % rms roughness on the bottom
zL = 7;                % range cells to smooth

cbc = 1497.44;         % compressional speed in the bottom m/s
cbs = 0;               % shear speed in the bottom m/s
rhob = 1.179;          % density in bottom gram/cm^3
attn = 0.1618;         % attenuation in bottom dB/m

% adjust this as you like
B1(1) = 3500;    r1(1) = 0;
B1(2) = 3500;    r1(2) = 20000;
B1(3) = 3200;    r1(3) = 23000;
B1(4) = 3000;    r1(4) = 27000;
B1(5) = 3200;    r1(5) = 30000;
B1(6) = 3500;    r1(6) = 35000;
B1(7) = 3500;    r1(7) = maxR;

% upsample specifications to the TL grid size
r = linspace(0,maxR,Nr);
B = interp1(r1,B1,r);

% add some random variance to the bottom depths
B = B + zrms.*randn(1,Nr);
K = (zeros(1,zL)+1)./zL;        % smoothing filter kernel
B = filtfilt(K,1,B);            % correlate independent data with a smoother

if 1
   % plot if desired
   figure;
   plot(r,-B,'b','linewidth',2.5);
   grid on;
   xlabel('range (m)');
   ylabel('depth (m)');
   title('Bottom depth vs range');
   axis([0 r(end) min(-B) 0]);
end

fo = fopen('scratch_bty.txt','w');
fprintf(fo,'''LL''\n');
fprintf(fo,'%d\n',Nr);
for ic=1:Nr
   % range units in kmeters
   fprintf(fo,'%5.4f  %6.2f  %6.2f  %3.1f  %5.3f  %6.4f \n', ...
       r(ic)./1000,B(ic),cbc,cbs,rhob,attn);
end
fclose(fo);




