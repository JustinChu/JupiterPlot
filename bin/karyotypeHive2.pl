#!/usr/bin/env perl
#Written By Justin Chu 2019
#Converts multiple circos karyotype files to hive plot compatible segment files

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;
use Math::Trig;
use Math::Trig ':pi';

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
my %angleStrs;
my %prefixSizes;

main();

sub main {
	system( "cp " . $rawConf . " $prefix.conf -f" );

	#	system("sed -i -e 's/segment_filename/$prefix.segments/g' $prefix.conf");
	system("sed -i -e 's/links_filename/$prefix.links/g' $prefix.conf");
	system("sed -i -e 's/output_prefix/$prefix.svg/g' $prefix.conf");

	my $segmentFH = new IO::File(">$prefix.segments");

	my $spacingStr   = "";
	my $maxSum       = 0;
	my $maxSumPrefix = "ref";

	#parse the filenames
	foreach my $pair (@ARGV) {
		my @tempArray = split( /\./, $pair );    #angle1.angle2
		my $pair1     = $tempArray[0];
		my $pair2     = $tempArray[1];

		#read in seqOrder files for first pair
		my $fh = new IO::File( $prefix . "." . $pair1 . ".seqOrder.txt" )
		  or die "Could not open file '$prefix.$pair1.seqOrder.txt' $!";
		my $line = $fh->getline();
		while ($line) {

			#ref5	gi|453232919|ref|NC_003284.9|	scaf15	68	-
			my @tempArr = split( /\t/, $line );

			my $refStr   = $pair . "_" . $tempArr[0] . "_";
			my $angleStr = $pair1 . "_" . $tempArr[2] . "_";

			#populate ref1
			unless ( exists( $angleStrs{$refStr} ) ) {
				push( @{ $ordering{$pair} }, $refStr );
				$angleStrs{$refStr} = 1;
			}
			unless ( exists( $angleStrs{$angleStr} ) ) {
				push( @{ $ordering{$pair1} }, $angleStr );
			}
			$line = $fh->getline();
		}
		$fh->close();

		#read in seqOrder files for second pair
		$fh = new IO::File( $prefix . "." . $pair2 . ".seqOrder.txt" )
		  or die "Could not open file '$prefix.$pair2.seqOrder.txt' $!";
		$line = $fh->getline();
		while ($line) {

			#ref5	gi|453232919|ref|NC_003284.9|	scaf15	68	-
			my @tempArr = split( /\t/, $line );

			my $refStr   = $pair . "_" . $tempArr[0] . "_";
			my $angleStr = $pair2 . "_" . $tempArr[2] . "_";

			#populate ref1
			unless ( exists( $angleStrs{$refStr} ) ) {
				push( @{ $ordering{$pair} }, $refStr );
				$angleStrs{$refStr} = 1;
			}
			unless ( exists( $angleStrs{$angleStr} ) ) {
				push( @{ $ordering{$pair2} }, $angleStr );
			}
			$line = $fh->getline();
		}
		$fh->close();

		my $refSum = 0;
		my $curSum = 0;
		my $fhSeg  = new IO::File( $prefix . "." . $pair1 . ".karyotype" )
		  or die "Could not open file '$prefix.$pair1.karyotype' $!";
		$line = $fhSeg->getline();
		while ($line) {

			#chr - ref0 gi|453232067|ref|NC003281.10| 0 13783801 hue000
			#ref0 0 13783801 gi|453232067|ref|NC003281.10| chr0
			my @tempArr = split( /\s/, $line );
			unless ( $tempArr[0] eq "band" ) {
				my $chrName = $pair . "_" . $tempArr[2] . "_";
				if ( exists( $angleStrs{$chrName} ) ) {
					$refSum += $tempArr[5];
				}
				else {
					$chrName = $pair2 . "_" . $tempArr[2] . "_";
					$curSum += $tempArr[5];
				}
				unless ( exists( $segmentStrs{$chrName} ) ) {
					my $str =
						$chrName . " "
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
		$fhSeg->close();
		$prefixSizes{$pair}  = $refSum;
		$prefixSizes{$pair1} = $curSum;
		if ( $maxSum < $refSum ) {
			$maxSum       = $refSum;
			$maxSumPrefix = $pair;
		}
		if ( $maxSum < $curSum ) {
			$maxSum       = $curSum;
			$maxSumPrefix = $pair1;
		}
		$fhSeg = new IO::File( $prefix . "." . $pair2 . ".karyotype" )
		  or die "Could not open file '$prefix.$pair2.karyotype' $!";
		$line = $fhSeg->getline();
		while ($line) {

			#chr - ref0 gi|453232067|ref|NC003281.10| 0 13783801 hue000
			#ref0 0 13783801 gi|453232067|ref|NC003281.10| chr0
			my @tempArr = split( /\s/, $line );
			unless ( $tempArr[0] eq "band" ) {
				my $chrName = $pair . "_" . $tempArr[2] . "_";
				if ( exists( $angleStrs{$chrName} ) ) {
					$refSum += $tempArr[5];
				}
				else {
					$chrName = $pair2 . "_" . $tempArr[2] . "_";
					$curSum += $tempArr[5];
				}
				unless ( exists( $segmentStrs{$chrName} ) ) {
					my $str =
						$chrName . " "
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
		$fhSeg->close();
		$prefixSizes{$pair}  = $refSum;
		$prefixSizes{$pair2} = $curSum;
		if ( $maxSum < $refSum ) {
			$maxSum       = $refSum;
			$maxSumPrefix = $pair;
		}
		if ( $maxSum < $curSum ) {
			$maxSum       = $curSum;
			$maxSumPrefix = $pair2;
		}
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

	#print out segment information
	print $fd
"<segments>\nfile = $prefix.segments\nwidth=$width\nradius=$radius\n<spacing>\ndefault = "
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
	print $fd
	  "</spacing>\n</segments>\n<axes>\nthickness = 2\ncolor = vdgrey\n";
	  
	  my %nonRefSet;

	foreach my $pair (@ARGV) {
		my @tempArray = split( /\./, $pair );    #angle1.angle2
		my $pair1     = $tempArray[0];
		my $pair2     = $tempArray[1];
		
		unless(exists $nonRefSet{$pair1} ){
			#create order string for segment
			my $orderStr = join( ",", @{ $ordering{$pair1} } );
			#print out axis
			printAxisStr( $fd, $pair1, $pair1, "no", $orderStr );
		}
		
		unless(exists $nonRefSet{$pair2} ){
			#create order string for segment
			my $orderStr = join( ",", @{ $ordering{$pair2} } );
			#print out axis
			printAxisStr( $fd, $pair2, $pair2, "no", $orderStr );
		}
		
		#create order string for reference
		my $orderStr = join( ",", reverse @{ $ordering{$pair2} } );
		#compute new angle, assumes shortest angle when possible
		printAxisStr( $fd, $pair, meandegrees($pair1, $pair2), "yes", $orderStr );
	}

	#print out axis information

	print $fd "</axes>\n";
	close($fd);
	$segmentFH->close();
}

#https://rosettacode.org/wiki/Averages/Mean_angle#Perl
sub meanangle {
  my($x, $y) = (0,0);
  ($x,$y) = ($x + sin($_), $y + cos($_)) for @_;
  my $atan = atan2($x,$y);
  $atan += 2*pi while $atan < 0;    # Ghetto fmod
  $atan -= 2*pi while $atan > 2*pi;
  $atan;
}

sub meandegrees {
  meanangle( map { $_ * pi/180 } @_ ) * 180/pi;
}

#<axis ref>
#angle          = 0
#scale          = 1
#reverse        = yes
#segments       = axis_ref_order
#</axis>
sub printAxisStr {
	my $fd         = shift;
	my $prefix     = shift;
	my $angle      = shift;
	my $reverse    = shift;
	my $segmentStr = shift;
	print $fd
"<axis $prefix>\nangle = $angle\nscale = 1\n reverse = $reverse\nsegements = $segmentStr\n</axis>\n";

}

