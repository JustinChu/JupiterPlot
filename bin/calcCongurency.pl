#!/usr/bin/env perl

#Written by Justin Chu 2019
#taking a bed file, calculate the number of congurent bases scaffold
#congurency is determined by the number of bases aligned to best reference sequence
#vs the number of aligned bases to other parts of the reference

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

#algorithm:
#Determine the best scaffold
#Compute table of contigID->scaffoldID->alignedBases
#Compute table of contigIDs->totalAlignedBases
#for each contigID find best count
#Report best count and ID compared to percentage of IDs

my $minScaffoldSize = 0;
my $faiFile         = "";
my $result = GetOptions( 'm=i' => \$minScaffoldSize, 'f=s' => \$faiFile );

unless ($faiFile) {
	print "Fai file needed (-f).\n";
	exit(1);
}

my %contigToScafoldBases;
my %totalAlignedBases;
my %whiteList;

my $fh   = new IO::File( $faiFile, "r" );
my $line = $fh->getline();

while ($line) {
	chomp($line);

	#LG01	317859041	6	317859041	317859042
	my @dataArray = split( /\s+/, $line );
	if ( $dataArray[1] > $minScaffoldSize ) {
		$whiteList{ $dataArray[0] } = 1;
	}
	$line = $fh->getline();
}

$fh->close();

$line = <>;
while ($line) {
	chomp($line);

	#LG06	96984201	96984778	contigLG01_15	60	-	0	577
	my @dataArray = split( /\s+/, $line );
	if ( exists( $whiteList{ $dataArray[0] } ) ) {
		my $contigID = $dataArray[3];
		if ( $contigID =~ /contig([^_]+)_\d+/ ) {
			$contigID = $1;
		}
		$contigToScafoldBases{$contigID}{ $dataArray[0] } +=
		  $dataArray[7] - $dataArray[6];
		$totalAlignedBases{$contigID} += $dataArray[7] - $dataArray[6];
	}
	$line = <>;
}

my $sum      = 0;
my $sumBases = 0;

foreach my $contigID ( keys(%contigToScafoldBases) ) {
	my $max   = 0;
	my $maxID = "";
	foreach my $scaffoldID ( keys( %{ $contigToScafoldBases{$contigID} } ) ) {

#			print $faiFile . "\t" .$contigID . "\t"
#	  . $scaffoldID . "\t"
#	  . $contigToScafoldBases{$contigID}{$scaffoldID} . "\t"
#	  . $totalAlignedBases{$contigID} . "\t"
#	  . ( $contigToScafoldBases{$contigID}{$scaffoldID} / $totalAlignedBases{$contigID} ) . "\n";
		if ( $max < $contigToScafoldBases{$contigID}{$scaffoldID} ) {
			$max   = $contigToScafoldBases{$contigID}{$scaffoldID};
			$maxID = $scaffoldID;
		}
	}
	$sum      += $max;
	$sumBases += $totalAlignedBases{$contigID};
	print $faiFile . "\t"
	  . $contigID . "\t"
	  . $maxID . "\t"
	  . $max . "\t"
	  . $totalAlignedBases{$contigID} . "\t"
	  . ( $max / $totalAlignedBases{$contigID} ) . "\n";
}

print $faiFile
  . "\tall\tall\t"
  . $sum . "\t"
  . $sumBases . "\t"
  . ( $sum / $sumBases )
  . "\n";

