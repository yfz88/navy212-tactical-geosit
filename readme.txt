readme.txt

This directory should allow someone to create a plot of transmission loss (TL)
versus range and depth, given a host of inputs that describe the particular
ocean environment. All the code is contained in the "CM" directory.

The program that produces the TL grid is called tst_BH2.m, since it will use
the BellHop program to generate the prediction. More details that describe
the method can be found at http://oalib.hlsresearch.com, including a users guide.
Realize that there are two versions of BH, one coded in Fortran and another
coded in MATLAB. The code provided here is the ML version, which performs 
most of the functions in the FORTRAN version but significantly slower. Still
some find dealing with ML code easier, including modifying the code to produce
custom outputs.

tst_BH2 calls bellhop2.m which is the main routine. BH computes transmission loss
by generating many ray-pairs from a source at the zero range and some defined depth.
BellHop calls a ray-pair a beam. TL is estimated by smoothing the separation of
ray-pairs at each range-depth grid cell with a Gaussian kernel and summing across 
all rays. This is called Gaussian Beams - which inspired the name BellHop. Typically
you want to run a field plot using a few thousand beams. The examples I provided
specify 4000 beams. The more beams, the longer the run time. Fewer beams reduces 
accuracy.

The rays project from a fan of angles between a minimum and maximum (typically
something like -50 --> +20 degrees. bellhop2.m then calls several other 
functions that are in the same directory as bellhop2 or in two other directories
i.e., Misc or ReadWrite. Let me know if the program crashes because I didn't
give you some particular file.

The tst_BH2.m program defines a filename that determines where the parameters
are stored that determine the loss response over range and depth. 
There will be 5 input files located in the Inputs directory. If the filename
is called "Test1" then the parameter files all begin with that but then have
different extensions. For example, the Inputs directory will have the files:
Test1.bty  [range dependent depth profile and geological parameters that determine bottom loss]
Test1.env  [includes many different variables to be defined below]
Test1.sbp  [sensor beam pattern vs. vertical angle]
Test1.ssp  [depth dependent sound speed profile - can be range dependent]
Test1.trc  [reflection coefficient and phase change for rays hitting the surface

To get you started, I've given you two sets of parameters, labeled Test1 and Test 2.
Test1 has an SSP from the North Atlantic retrieved from the HYCOM database.
Test2 is a generic canonical profile used by acousticians and oceanographers to 
test their codes. The curve is called the Munk profile and it approximates what
happens in many deep water environments.

The primary file is the .env file which includes the primary SSP, and many other
parameters used in the TL estimation procedure. You can evaluate the
variability of TL vs. noise on the SSP by running the TL model multiple times
and plotting the different TL results. In the MATLAB version, the ssp in the .env
file is what is used. However I always keep the ssp in .env and the one in the .ssp 
file identical. The .ssp data allows you to evaluate range dependent ssp's which
is likely beyond the scope of your study.

If you change anything in any of these files, be sure to keep the formats exactly as
examples in Test1 or Test2. Any minor change, e.g. if you add a space or comma where
its not supposed to be will cause the program not to run. If the program crashes, 
the first thing to check is whether or not something got corrupted in these files.

Once the tst_BH2.m is run (which takes about 7 minutes for the parameters I gave you)
then plot the results with the plot_TL2.m program. You will have to make sure the filename
is the same as what you used to run tst_BH2.m. plot_TL2 reads the results that were
stored in the Outputs directory (in a .mat file) and produces two types of plots. One
is a colored image that shows the areas of high and low TL. Recall that sound will be 
loudest when the TL is smallest. The units are in dB which is 20log10(pressurelevel).
A second plot is a line-like plot showing TL vs. range for a discrete set of depths (e.g.
100, 200, 300 m). These plots are what sonar engineers use to figure out where in the
range-depth space they should expect to here sounds from a source at some depth, and where
they will likely not hear the signal. Areas with extremely high TL (e.g. > 100 dB) are 
called shadow zones in acoustics parlance.

So to get started, I recommend you run tst_BH2.m, and make sure it produces a .mat file
in the Outputs directory. Then plot it with plot_TL2.m. Then
compare the plots you generated with the contents of the PowerPoint file 
"plots_of_benchmark_tests.pptx to ensure everything is working. 
Then maybe create some new sets of input files, e.g. Test1.bty, .env, ... with 
different SSP's and study the sensitivity. Perhaps some monte carlo runs, with
hundreds of SSPs offset from a mean supports confidence limits on the final TL
response.

regards,
Dave Pistacchio
NUWCDIVNPT
401-832-8267