#!/usr/bin/env perl
#Written By Justin Chu 2019
#Converts multiple circos karyotype files to hive plot compatible segment files

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $rawConf = "rawConfHive.conf";
my $prefix  = "circos";
my $result  = GetOptions(
	'r=s' => \$rawConf,
	'p=s' => \$prefix
);

#input: karyotype files, seqorder files, specifed by prefix
#relies on stable prefixes to work correctly
#example input: perl karyotypeHive.pl Pre Post

#ID->chrName
my %ordering;
my %segmentStrs;
my %ref;
my $genomeSize = 0;
my $imgSize = 1500;

main();

sub main {
	system( "cp " . $rawConf . " $prefix.conf -f" );
	system("sed -i -e 's/segment_filename/$prefix.segments/g' $prefix.conf");
	system("sed -i -e 's/links_filename/$prefix.links/g' $prefix.conf");
	system("sed -i -e 's/output_prefix/$prefix.png/g' $prefix.conf");

	my $segmentFH = new IO::File(">$prefix.segments");
	#parse the filenames
	foreach my $circoRunPrefix (@ARGV) {

		#read in seqOrder files
		my $fh = new IO::File( $circoRunPrefix . ".seqOrder.txt" )
		  or die "Could not open file '$prefix.seqOrder.txt' $!";
		my $line = $fh->getline();
		while ($line) {

			#ref5	gi|453232919|ref|NC_003284.9|	scaf15	68	-
			my @tempArr = split( /\t/, $line );
			unless ( exists( $ref{ $tempArr[0] } ) ) {
				push( @{ $ordering{"ref"} }, $tempArr[0] );
				$ref{ $tempArr[0] } = 1;
			}
			push(
				@{ $ordering{$circoRunPrefix} },
				$circoRunPrefix . "_" . $tempArr[2] . "_$circoRunPrefix"
			);
			$line = $fh->getline();
		}
		$fh->close();

		my $fhSeg = new IO::File( $circoRunPrefix . ".karyotype" )
		  or die "Could not open file '$prefix.karyotype' $!";
		$line = $fhSeg->getline();
		while ($line) {

			#chr - ref0 gi|453232067|ref|NC003281.10| 0 13783801 hue000
			#ref0 0 13783801 gi|453232067|ref|NC003281.10| chr0
			my @tempArr = split( /\s/, $line );
			my $chrName = $tempArr[2];
			if ( exists( $ref{ $chrName } ) ) {
				$genomeSize += $tempArr[5];
			}
			else{
				$chrName = $circoRunPrefix . "_" . $chrName . "_" . $circoRunPrefix;
			}
			unless ( exists( $segmentStrs{ $tempArr[2] } ) ) {
				my $str = $chrName . " "
				  . $tempArr[4] . " "
				  . $tempArr[5] . " "
				  . $tempArr[3] . " "
				  . $tempArr[6] . "\n";
				$segmentStrs{ $chrName } = $str;
				$segmentFH->print($str);
			}
			$line = $fhSeg->getline();
		}
		$fhSeg->close();

	}
	
	my $scaleFactor = int(($genomeSize/$imgSize)*2);
	
	system("sed -i -e 's/scale_factor/$scaleFactor/g' $prefix.conf");
	
	my $orderStr = join( ",", reverse @{$ordering{"ref"}} );
	
	system("sed -i -e 's/axis_ref_order/$orderStr/g' $prefix.conf");

	my $orderCount = 1;
	foreach my $circoRunPrefix (@ARGV) {
		$orderStr = join( ",", @{$ordering{$circoRunPrefix}} );

		#axis_1_order
		system( "sed -i -e 's/axis_"
			  . $orderCount
			  . "_order/$orderStr/g' $prefix.conf" );
		$orderCount++;
	}

	$segmentFH->close();
}

