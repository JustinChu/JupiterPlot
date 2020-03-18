#!/usr/bin/env perl
#Written By Justin Chu 2019
#Converts multiple circos karyotype files to hive plot compatible segment files

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $rawConf        = "rawConfHive.conf";
my $prefix         = "circos";
my $imgSize        = 1500;
my $radius         = 0.05;
my $defaultSpacing = 0.05;
my $width          = 0.01;
my $result         = GetOptions(
	'r=s' => \$rawConf,
	'p=s' => \$prefix,
	's=s' => \$imgSize
);

$radius *= $imgSize;
$width  *= $imgSize;

#input: karyotype files, seqorder files, specifed by prefix
#relies on stable prefixes to work correctly
#example input: perl karyotypeHive.pl Pre Post

#ID->chrName
my %ordering;
my %segmentStrs;
my %ref;
my %prefixSizes;

main();

sub main {
	system( "cp " . $rawConf . " $prefix.conf -f" );
	system("sed -i -e 's/segment_filename/$prefix.segments/g' $prefix.conf");
	system("sed -i -e 's/links_filename/$prefix.links/g' $prefix.conf");
	system("sed -i -e 's/output_prefix/$prefix.svg/g' $prefix.conf");

	my $segmentFH = new IO::File(">$prefix.segments");

	my $spacingStr   = "";
	my $maxSum       = 0;
	my $maxSumPrefix = "ref";

	#parse the filenames
	foreach my $circoRunPrefix (@ARGV) {

		my $refSum = 0;
		my $curSum = 0;

		#read in seqOrder files
		my $fh = new IO::File( $circoRunPrefix . ".seqOrder.txt" )
		  or die "Could not open file '$prefix.seqOrder.txt' $!";
		my $line = $fh->getline();
		while ($line) {

			#ref5	gi|453232919|ref|NC_003284.9|	scaf15	68	-
			my @tempArr = split( /\t/, $line );
			unless ( exists( $ref{ $tempArr[0] } ) ) {
				push( @{ $ordering{"ref"} }, $tempArr[0] . "_" );
				$ref{ $tempArr[0] } = 1;
			}
			push(
				@{ $ordering{$circoRunPrefix} },
				$circoRunPrefix . "_" . $tempArr[2] . "_"
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
			unless ( $tempArr[0] eq "band" ) {
				my $chrName = $tempArr[2];
				if ( exists( $ref{$chrName} ) ) {
					$refSum += $tempArr[5];
				}
				else {
					$chrName = $circoRunPrefix . "_" . $chrName;
					$curSum += $tempArr[5];
				}
				unless ( exists( $segmentStrs{ $tempArr[2] } ) ) {
					my $str =
						$chrName . "_ "
					  . $tempArr[4] . " "
					  . $tempArr[5] . " "
					  . $tempArr[3] . " "
					  . $tempArr[6] . "\n";
					$segmentStrs{$chrName} = $str;
					$segmentFH->print($str);
				}
			}
			$line = $fhSeg->getline();
		}
		$prefixSizes{"ref"} = $refSum;
		if ( $maxSum < $refSum ) {
			$maxSum       = $refSum;
			$maxSumPrefix = "ref";
		}
		$prefixSizes{$circoRunPrefix} = $curSum;
		if ( $maxSum < $curSum ) {
			$maxSum       = $curSum;
			$maxSumPrefix = $circoRunPrefix;
		}
		$fhSeg->close();
	}

	print STDERR "Max Prefix: " . $maxSumPrefix . " at " . $maxSum . "\n";

	#spacing
	$defaultSpacing /= scalar( @{ $ordering{$maxSumPrefix} } );
	$defaultSpacing *= $imgSize;

	system("sed -i -e 's/image_size/$imgSize/g' $prefix.conf");
	my $scaleFactor = int(
		(
			$maxSum / (
				($imgSize) / 2 -
				  $radius -
				  scalar( @{ $ordering{$maxSumPrefix} } + 1 ) * $defaultSpacing
			)
		)
	);
	print STDERR "Scale factor:" . $scaleFactor . "\n";
	system("sed -i -e 's/scale_factor/$scaleFactor/g' $prefix.conf");

	open( my $fd, ">>$prefix.conf" );

	print $fd "\nwidth=$width\nradius=$radius\n<spacing>\ndefault = "
	  . $defaultSpacing . "\n";
	foreach my $id ( keys %prefixSizes ) {
		unless ( $maxSumPrefix eq $id ) {
			my $spacingSize =
			  ( $defaultSpacing * scalar( @{ $ordering{$maxSumPrefix} } ) +
				  ( $maxSum - $prefixSizes{$id} ) / $scaleFactor ) /
			  scalar( @{ $ordering{$id} } );
			foreach ( @{ $ordering{$id} } ) {
				$spacingStr .=
					"<pairwise "
				  . $_
				  . ">\nspacing = "
				  . $spacingSize
				  . "\n</pairwise>\n";
			}
			print STDERR "Prefix: "
			  . $id
			  . " Pixel size: "
			  . $prefixSizes{$id} / $scaleFactor
			  . " Pixel size spacers: "
			  . ( $spacingSize * scalar( @{ $ordering{$id} } ) ) . "\n";
		}
		else {
			print STDERR "Prefix: "
			  . $id
			  . " Pixel size: "
			  . $prefixSizes{$id} / $scaleFactor
			  . " Pixel size spacers: "
			  . ( $defaultSpacing * scalar( @{ $ordering{$maxSumPrefix} } ) )
			  . "\n";
		}
	}
	print $fd $spacingStr;
	print $fd "</spacing>\n</segments>\n";
	close($fd);

	my $orderStr = join( ",", reverse @{ $ordering{"ref"} } );

	system("sed -i -e 's/axis_ref_order/$orderStr/g' $prefix.conf");

	my $orderCount = 1;
	foreach my $circoRunPrefix (@ARGV) {
		my $tempFH = new IO::File(">$prefix$orderCount.order.temp");
		$orderStr =
			"'s/axis_"
		  . $orderCount
		  . "_order/"
		  . join( ",", @{ $ordering{$circoRunPrefix} } ). "/g";
		$tempFH->print($orderStr);
		$tempFH->close();
		system( "sed -i -f $prefix$orderCount.order.temp $prefix.conf" );
		system("rm $prefix$orderCount.order.temp");
		$orderCount++;
	}

	$segmentFH->close();
}

