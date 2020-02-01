#!/usr/bin/env perl
#Written By Justin Chu 2019
#Converts circos links to hiveplot compatible ones (based on orientation) and adds z-depth per entry

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

#invert link positions relative to scaffolds
#path to scaffold sizes to invert alignments
#my $invert = "";
my $prefix = "";

my $linksLeft = "";
my $result    = GetOptions(
#	'i=s' => \$invert,
	"p=s" => \$prefix
);

#my %scaffoldSizes;
#
#if ($invert) {
#	my $scaffFH = new IO::File($invert);
#	my $line    = $scaffFH->getline();
#
#	#load in fai file
#	while ($line) {
#		my @tempArray  = split( /\s/, $line );
#		my $scaffoldID = $tempArray[0];
#		chomp($line);
#		$scaffoldSizes{$scaffoldID} = $tempArray[1];
#		$line = $scaffFH->getline();
#	}
#	$scaffFH->close();
#}

my %linkSizes;
my %linkStrs;

my $line = <>;

while ($line) {
	chomp($line);
#	print $line . "\n";
	my @tempArray = split( / /, $line );
	my $tempStr   = "";
	
	#parse out colour
	$tempArray[6] =~ s/_a\d//g;

#re-arrange positions & store
#ref1 2732 697618 scaf4 15442510 14748173 nlinks=2,bsize1=693789,bsize2=693241,bidentity1=0.998420,bidentity2=0.998420,depth1=0,depth2=0,color=hue060_a5
#ref1 697618 2732 Post_scaf4 15442510 14748173 color=chr1
#	if ($invert) {
#		$tempStr =
#			$tempArray[0] . " "
#		  . $tempArray[2] . " "
#		  . $tempArray[1] . " "
#		  . $prefix . "_"
#		  . $tempArray[3] . " "
#		  . $scaffoldSizes{$tempArray[3]} - $tempArray[4] . " "
#		  . $scaffoldSizes{$tempArray[3]} - $tempArray[5] . " "
#		  . $tempArray[6];
#	}
#	else {
		$tempStr =
			$tempArray[0] . " "
		  . $tempArray[1] . " "
		  . $tempArray[2] . " "
		  . $prefix . "_"
		  . $tempArray[3] . " "
		  . $tempArray[4] . " "
		  . $tempArray[5] . " "
		  . $tempArray[6];
#	}
	
	#record length lengths for computing correct z-depth
	$linkSizes{$tempArray[4]-$tempArray[5]} = 0;
	$linkStrs{$tempStr} = $tempArray[4]-$tempArray[5];

	$line = <>;
}

#determine zscale for values
my $zCounter = 0;
foreach my $length (sort(keys(%linkSizes))){
	$linkSizes{$length} = $zCounter++;
}

#print out links with added z-depth
foreach my $linkStr (keys(%linkStrs)){
	print $linkStr . ",z=". $linkSizes{$linkStrs{$linkStr}} . "\n";
}

