Circos Assembly Consistency (Jupiter) plot
======================
[![DOI](https://zenodo.org/badge/83077852.svg)](https://zenodo.org/badge/latestdoi/83077852)

This is a pipeline for generating a Circos based genome assembly consistency plot given a set of contigs relative to reference genome. Intended to visualize large scale translocation or missassemblies. 

Generates plots similar to those found in the [ABySS 2](http://genome.cshlp.org/content/27/5/768) paper, given only a reference genome fasta file and an assembly scaffolds fasta file. Good for getting a quick qualitative view of the missassemblies in a genome assembly.
Nicknamed after the type of plot you get if your assembly is relatively error free (looks like the planet Jupiter). If you think of features or some useful auxiliary information (e.g. for tracing back where a translocation event occurred) that the plot uses that I could report better let me know. 

<img src="./dm.svg">

Example plot on a Drosophila assembly showing a misassembly (or possible chromosomal fusion event) between L2 and L3. There are also smaller events internal to 3R. Note that by default only large scale events (>10kb) can be see in this plot, and small misassemblies, possibly medidated by repeats, cannot be seen (unless `maxBundleSize` is changed). The black lines on the reference indicate gaps of Ns, which can explain why some regions of the assembly are not covered (often found in telomeric or centromeric regions). Default settings except for ng=80 used.

### Requirements (for full pipeline):
* [Circos and Circos tools](http://circos.ca/software/download/circos/) (currently included in repo)
* [bwa](https://github.com/lh3/bwa)
* [samtools](https://github.com/samtools/samtools)
* GNU make

Perl Modules Needed:
* Config::General.pm
* Math::VecStat
* Set::IntSpan
* List::MoreUtils
* Modules needed for Circos: [http://www.circos.ca/documentation/tutorials/configuration/perl_and_modules/](http://www.circos.ca/documentation/tutorials/configuration/perl_and_modules/)

### Starting inputs:

* Set of scaffolds in fasta format
* Reference genome in fasta format

To generate a plot given these inputs, samtools and bwa must be in your path.

### Usage:

Simply run:
```{bash}
jupiter name=$prefix ref=$reference fa=$scaffolds
```

Optional commands:
```
sam=                #Specify an existing alignment of scafftigs to if they already exist (naming convention that fatoagp.pl produces must be consistent)
ng=75               #use largest scaffolds that are equal to 75% of the genome 
maxGap=100000       #maximum alignment gap allowed to consider a region contiguous
minBundleSize=10000 #minimum size of a contiguous region to render
m=100000            #only use genomic reference chromosomes larger than this value
i=0                 #increment for colouring chromosomes (HSV colour shift by setting 0-360), when set to >360 it generates random colours
t=8                 #number of threads to use for bwa
```

If everything runs smoothly it will generate the following files:
```
prefix_scaffolds.fa (symlink)
prefix_reference.karyotype
prefix_reference.fa.sa
prefix_reference.fa.pac
prefix_reference.fa.ann
prefix_reference.fa.amb
prefix_reference.fa (symlink)
prefix.seqOrder.txt
prefix.svg
prefix-agp.sam
prefix.links
prefix.karyotype
prefix-agp.fa
prefix.conf
prefix.agp
```

Most likely, you will want to work with the svg file as perl image processing module Circos uses has difficulty rendering transparency on png files.

### Relating image back to assembly:
`prefix.seqOrder.txt` file:
This file is a way of mapping the scaffold order back to the chromosomes listed. It lists which scaffold aligned in its order relative to each from top to bottom.

Here is the format:
```
internalRefID	refID	internalScaffoldID	scaffoldID strand
```

For example:
```
ref5	X	scaf109	361740	-
ref5	X	scaf120	361915	+
ref5	X	scaf68	361536	+
...
```

Chromosome X matches scaffold 361740 as the first segment (in the - direction relative to the orignal sequence) then scaffold 361915 (in the + direction relative to the orignal sequence) occurs as the next alignment (ordered in the 5'->3' direction relative to the reference). 

### Possible issues:
 1. Error regarding too mamy ideograms - Example:
```
You have asked to draw [831] ideograms, but the maximum is currently set at
  [500]. To increase this number change max_ideograms in etc/housekeeping.conf.
  Keep in mind that drawing that many ideograms may create an image that is too
  busy and uninterpretable.
```
This basically means the assembly may be too fragmented. You can decrease `ng` to smaller value or alter the housekeeping.conf to allow for more scaffolds to render (keeping in mind it may become quite unwieldy).
