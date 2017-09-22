Circos Assembly Consistency (Jupiter) plot
======================
Generates plots similar to those found in the [ABySS 2](http://genome.cshlp.org/content/27/5/768) paper, given only a refernce fasta file and an assembly fasta file. Good for getting a quick qualitative view of the missassemblies in a genome assembly.
Nicknamed after the type of plot you get if your assembly is relatively error free (looks like the planet Jupiter).

<img src="./dm.svg">

Example plot on a Drosophila assembly showing a misassembly (or possible chromosomal fusion event) between L2 and L3. There are also smaller events internal to 3R. Note that by default only large scale events (>10kb) can be see in this plot, and small misassemblies, possibly medidated by repeats cannot be seen (unless `maxBundleSize` is changed). The black lines on the reference indicate gaps of Ns, which can explain why some regions of the assembly are not covered (often found in telomeric or centromeric regions).

### Requirements (for full pipeline):
* [Circos and Circos tools](http:__circos.ca_software_download_) (currently included in repo)
* [bwa](https:__github.com_lh3_bwa)
* [samtools](https:__github.com_samtools_samtools)
* GNU make
* Some perl modules - Use CPAN when you encounter missing module errors

### Starting inputs:

* Set of scaffolds in fasta format
* Reference genome in fasta format

To generate a plot given these inputs all samtools and bwa must be in your path.

### Usage:

Simply run:
```{bash}
jupiter name=$prefix ref=$reference fa=$scaffolds
```

Optional commands:
```
ng=75               #use largest scaffolds that are equal to 75% of the genome 
maxGap=100000       #maximum alignment gap allowed to consider a region contiguous
maxBundleSize=10000 #maximum size of a contiguous region to render
m=100000            #only use genomic reference chromosomes larger than this value
i=0                 #increment for colouring chromosomes (HSV 1-360), when set to 0 it generates random colour for chromosomes.
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
prefix.svg
prefix.scaffold.txt
prefix-agp.sam
prefix.links
prefix.karyotype
prefix-agp.fa
prefix.conf
prefix.agp
```

Most likely, you will want to work with the svg file as perl image processing module Circos uses has difficulty rendering transparency on png files.

### Possible issues:
If you end up with too many chromosomes to render e.g.:
```
You have asked to draw [831] ideograms, but the maximum is currently set at
  [500]. To increase this number change max_ideograms in etc/housekeeping.conf.
  Keep in mind that drawing that many ideograms may create an image that is too
  busy and uninterpretable.
```
You can decrease `ng` to smaller value or alter the housekeeping.conf to allow for more scaffolds to render (keeping in mind it may become quite unwieldy.
