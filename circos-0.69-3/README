
################################################################

Circos - flexible and automatable circular data visualization

Martin Krzywinski
Canada's Michael Smith Genome Sciences Center
British Columbia Cancer Agency

martink@bcgsc.ca
www.circos.ca

################################################################

0. INTRODUCTION
   0.a   what is circos?
   0.b   requirements

1. GETTING STARTED
   1.a   installation 
   1.b   executing scripts
   1.c   testing GD
   1.d   tools
   1.e   batch files
   1.f   configuration files

2. BUGS
   2.a 	 report bugs and comments
   2.b   known issues

3. INSTALLATION PROBLEMS
   3.a   missing modules

4. OTHER ISSUES
   4.a   configuration paths
   4.b   typical errors and how to fix them
   4.b.1 numerical parameter units

################################################################

0. INTRODUCTION

0.a  What is circos?

Circos is a program for the generation of publication-quality,
circularly composited renditions of genomic data and related
annotations.

Circos is particularly suited for visualizing alignments, conservation
and intra and inter-chromosomal relationships.

But wait. Also, Circos is useful to visualize any type of information
that benefits from a circular layout. Thus, although it has been
designed for the field of genomics, it is sufficiently flexible to be
used in other data domains.

0.b  Requirements

Perl 5.8.x, or newer, is highly recommended. In addition to the core
modules that come with your Perl distribution, some CPAN modules are required.

On UNIX systems, for a list of modules required by Circos, run

> cd bin
> ./list.modules

On UNIX systems, to test whether you have these modules, run

> cd bin
> ./test.modules

Circos supports TTF fonts. A few fonts are included in fonts/.

UNIX users likely do not need to install perl on their systems, since it is commonly included by default. Windows users on the other hand usually do not have Perl and need to install it - Strawberry Perl or ActiveState Perl.

  http://strawberryperl.com
  http://www.activestate.com/activeperl

Both Windows Perl distributions have their own module manager that make it easy to install, update and remove modules.


1. GETTING STARTED

Refer to online tutorials for installation, configuration and troubleshooting

  http://www.circos.ca/documentation/tutorials/configuration/

1.a  Installation

On UNIX systems, use 'tar' to extract the files.

> tar xvfz circos-x.xx.tgz
> cd circos-x.xx

On Windows, use an archiver like WinZip or WinRAR or Window's built-in
support for Zip files.

You don't need to move or edit any files in the main distribution.

1.b  Executing Scripts

Circos is written in Perl, which is an interpreted language. This
means that the program files are plain-text and are passed through the
Perl interpreter in order to run.

On UNIX systems, to run the scripts you simply need to make sure that
the files are executable (they should be already)

> chmod +x bin/circos

after which you can execute them directly

> bin/circos 

The association between the bin/circos script and perl is created by
the first line in the script]

#!/bin/env perl

which instructs the shell to run the perl binary and provide the
script as input. See notes on /bin/env below.

On Windows, you'll also want to work from the command line (DOS
window), but you'll need to call perl explicitly. Once you've
installed a Perl distribution, like Strawberry Perl or ActiveState
Perl, you should be able to run the interpreter which has been placed
in your PATH by the installation process.

C:>perl -V
...information about version of perl

To run Circos, 

C:>perl C:\path\to\circos\bin\circos [any command-line parameters]

Anytime you see instruction to run a script, such as

> tools/bin/binlinks ...

substitute instead

C:>perl tools\bin\binlinks ...

Also note that on UNIX file paths use "/" as a separation
(e.g. /bin/env) and on Windows "\" is used (e.g. C:\perl\bin\perl).

1.c  Testing GD

To test your GD installation to make sure your Perl distribution can
create graphics and handle True Type fonts.

> bin/gddiag

Look at the created gddiag.png. It should look like this

  http://www.circos.ca/documentation/tutorials/configuration/png_output/images

If you don't see any text, see 4.b.2 below.

If you get an error like

-bash: /bin/env: No such file or directory

then your 'env' binary is likely in /usr/bin (e.g. on Mac OS X) Check this by 

> which env
/usr/bin/env

To fix this, either change the first line in scripts in bin/* and tools/*/bin to 

#!/usr/bin/env perl

or make a symlink from /usr/bin/env to /bin/env

> sudo su
> cd /bin
> ln -s /usr/bin/env env

Now try creating the example image

> cd circos-x.xx
> cd example
> ../bin/circos -conf etc/circos.conf

To get some verbose reporting about file I/O , use 

> ../bin/circos -conf etc/circos.conf -debug_group io,summary

Please see L<http://www.circos.ca> for documentation. There are a
large number of tutorials that described how the configuration files
are formatted. Tutorials need to be downloaded separately.

1.d  Tools

There are several helper scripts, available separately, that are designed
to aid you in processing your data.

Many of these involve manipulating link files. These tools independent
scripts and are covered in Tutorial 9.

  http://www.circos.ca/documentation/tutorials/utilities

The tools can be downloaded independently. Note that the stand-alone
tools distribution may contain scripts that are newer than those
bundled with Circos. To check this, look at the release date for the
archives at L<http://www.circos.ca/software/download>.

1.e Batch Files

There may be batch files scattered throughout the data/ and tutorial/
directories. These files begin with

#!/bin/bash

and are designed for use in UNIX environments.

1.f Configuration files

Central configuration files with global parameters are found in
etc/. See etc/README for details about the contents of this file and
how the <<include>> directive is used to link them.

For a full explanation of the configuration system, see

  http://www.circos.ca/documentation/tutorials/configuration/configuration_files


2. BUGS

2.a  Report bugs and comments

I appreciate any and all comments you may have about Circos. Please
use the Google Group for questions and bug reports.

  http://groups.google.com/group/circos-data-visualization

2.b  Known issues

GD does not draw rotated text correctly when the font size is small
for certain fonts. For example, using a font size of 6pt, text drawn
an an angle is drawn with letters upright. If you see this, increase
the font size of the text.

Fonts with which this problem occurs are

  CMUBright-Roman
  CMUTypewriter-Regular

For this reason, TTF versions of these fonts are used, rather than OTF.

3. INSTALLATION PROBLEMS

3.a  Missing modules

  http://www.circos.ca/documentation/tutorials/configuration/perl_and_modules/

In order to run Circos you may need to install some modules from CPAN
(www.cpan.org). You will need the modules listed at L<http://www.circos.ca/software/requirements>.

If you run Circos and get a message like

Can't locate Config/General.pm in @INC (@INC contains: /usr/lib/perl5/5.8.0/i386-linux
-thread-multi /usr/lib/perl5/5.8.0 /usr/lib/perl5/site_perl/5.8.0/i386-linux-thread-mu
lti /usr/lib/perl5/site_perl/5.8.0 /usr/lib/perl5/site_perl /usr/lib/perl5/vendor_perl
/5.8.0/i386-linux-thread-multi /usr/lib/perl5/vendor_perl/5.8.0 /usr/lib/perl5/vendor_
perl .) at ./bin/circos line 121.

then you do not have a module installed. It may be that you have the module elsewhere,
but Perl cannot find it. In this case, the error message is barking at the fact that
Config::General is not installed.

You can install the module using CPAN (if CPAN module is installed)

> perl -MCPAN -e shell
% install Config::General

Make sure that you are using the same perl binary to install the module as for Circos.

Alternatively, you can grab the module from CPAN directly. Use search.cpan.org to find
the module.

> wget http://search.cpan.org/~tlinden/Config-General-2.31/General.pm
> tar xvfz Config-General-x.xx.tgz
> cd Config-General-x.xx.tgz
> perl Makefile.PL ; make ; make test
> make install

If you are getting 'permission denied' errors during installation of
the module, then you're likely attempting to write into your system's
default Perl install, and don't have permission to do so. To fix this,
repeat the module installation as root (administrator).

> sudo su
> perl -MCPAN -e shell
...


4. OTHER ISSUES

4.a  Configuration paths

If you look inside one of the configuration files you'll find
that it includes other configuration files using <<include>> and
makes relative mention of data files, such as

  file = data/5/segdup.txt

Circos tries to find the file regardless where you are running the binary from, but 
may still run into trouble finding files specified using a relative path.

To avoid problems, run circos from its distribution directory

> cd circos-x.xxx
> bin/circos -conf ...

Alternative, change all the paths in the .conf file to absolute paths. For example, from

  <<include etc/colors.conf>>

to

  <<include /path/to/your/install/circos-x.xx/etc/colors.conf>>

For details about the configuration files, see etc/README and

  http://www.circos.ca/documentation/tutorials/configuration/configuration_files

4.b  Typical errors and how to fix them

4.b.1 Dealing with errors

  http://www.circos.ca/documentation/tutorials/configuration/errors

4.b.2 No text in figures

If Circos is creating images, but without any text (ideogram labels,
tick labels, etc), it is almost certain that your GD Perl module was
compiled without True Type support.

See the note about gddiag above.

This may be due to the fact that you don't have the True Type library
on your system (freetype), or a configuration error during GD
installation.

You'll need to reinstall GD.

  http://search.cpan.org/dist/GD/

This issue comes up a lot. Circos has this to say about it

circos -fake font,ttf

and many threads about it have been created on the message boards

  http://groups.google.com/group/circos-data-visualization/browse_thread/thread/c893b8b612c2c5cf


README HISTORY

2013 Feb 12 - standardized URLs for /documentation/tutorials

2012 Feb 20 - added link to thread about TTF support and a command to fake TTF font error

2012 Feb 5 - modified note on errors, added reference to external tutorials

2011 Jul 25 - split Circos, tutorials and tools into separate archives

2011 Jun 04 - started keeping track of history

2011 Jul 07 - updated links to ciros.ca
