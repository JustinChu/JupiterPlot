Circos Assembly Consistency (Jupiter) plot
======================
Generates plots similar to those found in the [ABySS 2](http://genome.cshlp.org/content/27/5/768) paper. Good for getting a quick qualitative view of the missassemblies in a genome assembly.
Name after the type of plot you get if your assembly is relatively error free (looks like the planet Jupiter).

<img src="./dm.svg">

### Requires (for full pipeline):
* [Circos](http:__circos.ca_software_download_)
* [bwa](https:__github.com_lh3_bwa)
* [samtools](https:__github.com_samtools_samtools)
* GNU make
* Some perl modules - Use CPAN when you encounter missing module errors

### Starting inputs

* Set of scaffolds in fasta format
* Reference genome in fasta format

To generate a plot given these inputs all samtools and bwa must be in your path.

### Usage

Simply run:
```{bash}
jupiter name=$prefix ref=$reference fa=$scaffolds
```

Optional commands:
```
ng=75 #Use largest scaffolds that are equal to around 75% of the genome 
maxGap=10000 #maximum scaffold or alignment gap allowed to consider a region contiguous
maxBundleSize=10000 #maximum size of a contiguous region to render
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
prefix.sam
prefix.links
prefix.karyotype
prefix.fa
prefix.conf
prefix.agp
```

Most likely, you will want to work with the svg file as perl image processing module Circos uses has difficulty rendering transparency on png files.

