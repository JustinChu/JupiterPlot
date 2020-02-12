3-Way Assembly Consistency Hiveplot
======================
This is a pipeline for generating a 3-way hiveplot genome assembly consistency plot given 2 runs of Jupiter plot using the same reference.

<img src="./Hive_CE.svg">

Example plot on 2 C. elegans assemblies.

We use a modified version of [hiveplot \(linnet\)](http://www.hiveplot.com/distro/hiveplot-0.02.tgz) implemented by Martin K.

### Installing Hiveplot

Perl Modules Needed:
* Statistics::Descriptive

### Starting inputs:

* 2 Runs of Circos with the *.karyotype, *.links.final and *.seqOrder.txt files run on the same reference

### Usage:

Simply run:
```{bash}
hiveplot name=$prefix prefix1=$cirosRunPrefix1 prefix2=$cirosRunPrefix2
```

If everything runs smoothly it will generate the following files:
```
prefix.png
```