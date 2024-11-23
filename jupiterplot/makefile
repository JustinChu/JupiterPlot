ifdef profile
SHELL=/usr/bin/time -f '=> jupiter: %e %C' /bin/bash -o pipefail
else
SHELL=/bin/bash -o pipefail
endif

ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

#------------------------------------------------------------
# params
#------------------------------------------------------------

#General Parameters
t=4                 #number of threads to use for minimap2

#Karyotype options
m=100000            #only use genomic reference chromosomes larger than this value
ng=75               #use largest scaffolds that are equal to 75% of the genome. when set to 0 all scaffolds are used.
maxScaff=-1         #Instead of ng filter by this number of scaffolds
i=0                 #increment for colouring chromosomes (HSV colour shift by setting 0-360), when set to >360 it generates random colours
g=1                 #minimum gap size in reference to render
gScaff=100000       #minimum gap size in scaffolds to render
labels = ref        #Shows reference chromosome name "ref", scaffolds "scaf" or "both".

#Link optinosn
maxGap=100000       #maximum alignment gap allowed to consider a region contiguous
minBundleSize=50000 #minimum size of a contiguous region to render
MAPQ=50				#maximum mapping quality allowed when filtering
linkAlpha=5			#alpha of links 1 = 17% , 2 = 33%, 3 = 50%, 4 = 67% and 5 = 83%.

#------------------------------------------------------------
# meta rules
#------------------------------------------------------------

.PRECIOUS: %-agp.sam %.agp %.bed %.links.final %.fai
.DELETE_ON_ERROR:
.PHONY: check-params generateplot

default: generateplot

generateplot: check-params $(name).svg

check-name-param:
ifndef name
	$(error missing required param 'name' (output file prefix))
endif

check-params: check-name-param
ifndef ref
	$(error missing required param 'ref' (FASTA reference file))
endif
ifndef fa
	$(error missing required param 'fa' (FASTA contigs file))
endif

#optional command for sam files
ifdef sam
	$(attempting to skip alignments given $(sam))
endif

#------------------------------------------------------------
# pipeline rules
#------------------------------------------------------------

$(name)_reference.fa: $(ref)
	ln -s $< $@
	
$(name)_scaffolds.fa: $(fa)
	ln -s $< $@

# index FASTA file
%.fa.fai: %.fa
	samtools faidx $<
	
%.agp %-agp.fa : %_scaffolds.fa
	perl $(ROOT_DIR)/bin/fatoagp.pl -f $*-agp.fa $< > $*.agp

ifdef sam
$(name)-agp.sam: $(sam)
	ln -s $< $@
else
%-agp.sam: %_reference.fa %-agp.fa
	minimap2 -ax asm20 -t $(t) $*_reference.fa $*-agp.fa > $@
endif

%.bed: %.sam
	grep -E -v '^@' $< | awk '{if($$5 >= $(MAPQ)) print}' | perl $(ROOT_DIR)/bin/samToBed.pl > $@

%.conf %.karyotype %.rv.links %.fw.links %.seqOrder.txt: %.agp %-agp.bed %_reference.karyotype %_scaffolds.fa
	perl $(ROOT_DIR)/bin/generateConf.pl -n $(ng) -m $(maxScaff) \
	-r $(ROOT_DIR)/config/rawConf.conf -p $* -s $*_scaffolds.fa \
	-b $*-agp.bed -a $*.agp -k $*_reference.karyotype -g $(gScaff) \
	-t $(linkAlpha) -l $(labels)

$(name)_reference.karyotype: $(name)_reference.fa
	perl $(ROOT_DIR)/bin/generateKaryotype.pl -g $(g) -i $(i) -m $(m) $(name)_reference.fa > $@

%.links.bundled: %.links
	cat $< | bundlelinks -max_gap $(maxGap) -min_bundle_size $(minBundleSize) > $@
	#cat $< | perl $(ROOT_DIR)/bin/linkCollapse.pl -m $(maxGap) -b $(minBundleSize) > $@ #simple bundle

%.fw.links.bundled.flipped : %.fw.links.bundled
	awk ' { t = $$5; $$5 = $$6; $$6 = t; print; } ' $< > $@

%.links.final : %.rv.links.bundled %.fw.links.bundled.flipped
	cat $^ > $@

%.svg: %.conf %.karyotype %.links.final 
	circos -noparanoid -conf $<
 
