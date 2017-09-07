Jupiter Assembly Consistency plot
======================
### Requires (for full pipeline):
* [Circos](http:__circos.ca_software_download_)
* [bwa](https:__github.com_lh3_bwa)
* [samtools](https:__github.com_samtools_samtools)
* GNU make
* Some perl modules - Use CPAN when you encounter missing module errors

###Usage

###Starting inputs

* Set of scaffolds in fasta format
* Reference genome in fasta format

To generate a plot given these inputs all samtools and bwa must be in your path.

Simply run:
```
jupiter name=$prefix ref=$reference fa=$scaffolds
```

If everything runs smoothly it will generate the following files:
```
prefix_reference.fa (symlink)
prefix_reference.fa.fai
prefix_reference.fa.karyotype
prefix_reference.fa.bwt
prefix_scaffolds.fa (symlink)
prefix_scaffolds.fa.fai
prefix_scaftigs.fa
prefix.agp
prefix.bam
prefix.bed
prefix.conf
prefix.png
prefix.svg
```

Most likely, you will want to work with the svg file as perl image processing module Circos uses has difficulty rendering transparency on png files.

