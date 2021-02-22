#!/usr/bin/env perl
#Written By Justin Chu 2016
#Generates a links file, karyotype file and configuration file for circos

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $rawKaryotype  = "";
my $scaffoldFiles = "";
my $scafftigsBED  = "";
my $agpFile       = "";
my $maxCount      = -1;
my $numScaff      = 90;
my $rawConf       = "rawConf.conf";
my $prefix        = "circos";
my $gScaff        = 1;
my $result        = GetOptions(
	'k=s' => \$rawKaryotype,
	's=s' => \$scaffoldFiles,
	'n=i' => \$numScaff,
	'm=i' => \$maxCount,
	'b=s' => \$scafftigsBED,
	'a=s' => \$agpFile,
	'r=s' => \$rawConf,
	'p=s' => \$prefix,
	'g=i' => \$gScaff
);

my $outputkaryotype = $prefix . ".karyotype";

$numScaff = $numScaff / 100;

if ( $scaffoldFiles eq "" ) {
	die "-s -b and parameters needed";
}

my @chrOrder;
my %scaffolds;
my %scaffoldsSize;
my %scaffoldIDMap;
my %refIDMap;
my %chrColorMap;
my %chromosomes;
my %scaffoldGaps;

system( "cp " . $rawConf . " $prefix.conf -f" );
system("sed -i -e 's/karyotype.txt/$prefix.karyotype/g' $prefix.conf");
system("sed -i -e 's/links.txt/$prefix.links.final/g' $prefix.conf");
open( my $fd, ">>$prefix.conf" );

#create karyotype file
outputKaryotype();
outputLinks();
close($fd);

sub outputKaryotype {

	print STDERR "Generating Karyotype file\n";

	my $scaffFH = new IO::File($scaffoldFiles);
	my $line    = $scaffFH->getline();

	#	my %scaffoldLengths;
	my $karyotype = new IO::File(">$outputkaryotype");

	#load in fasta file
	while ($line) {
		my $header = $line;
		$line = $scaffFH->getline();
		my $currentStr = "";
		while ( $line && $line !~ /^>/ ) {
			chomp $line;
			$currentStr .= $line;
			$line = $scaffFH->getline();
		}
		my ($scaffoldID) = $header =~ /^>([^\s]+)\s/;
		$scaffoldsSize{$scaffoldID} = length($currentStr);
		while ( $currentStr =~ /([^ATCGatcg]+)/g ) {
			if ( $gScaff < ( $+[0] - $-[0] ) ) {
				push( @{ $scaffoldGaps{$scaffoldID} }, "$-[0] $+[0]" );
			}
		}
	}
	$scaffFH->close();

	my $rawKaryotypeFH = new IO::File($rawKaryotype);
	$line = $rawKaryotypeFH->getline();
	my $genomeSize = 0;
	my $numChr     = 0;

	#load in base karyotype
	while ($line) {
		chomp($line);
		my @tempArray = split( " ", $line );
		if ( scalar(@tempArray) ) {
			if ( $tempArray[0] eq "band"
				&& exists( $refIDMap{ $tempArray[1] } ) )
			{
				$tempArray[1] = $refIDMap{ $tempArray[1] };
				my $tempStr = join( " ", @tempArray ) . "\n";
				$karyotype->write($tempStr);
			}
			else {
				$refIDMap{ $tempArray[2] }    = "ref" . $numChr;
				$chrColorMap{ $tempArray[2] } = $tempArray[6];
				$tempArray[2]                 = "ref" . $numChr;
				$chromosomes{ $tempArray[2] } = $tempArray[3];

				#Generate circos friendly label
				$tempArray[3] =~ s/[_]//g;
				my $tempStr = join( " ", @tempArray ) . "\n";
				push( @chrOrder, $tempArray[2] );
				$karyotype->write($tempStr);
				$numChr++;
				$genomeSize += $tempArray[5];
			}
		}
		$line = $rawKaryotypeFH->getline();
	}
	$rawKaryotypeFH->close();

	#sort by length
	my @lengthOrder =
	  sort { $scaffoldsSize{$a} <=> $scaffoldsSize{$b} }
	  keys %scaffoldsSize;

	my $count       = 1;
	my $scaffoldSum = 0;

	foreach my $scaffoldID ( reverse @lengthOrder ) {

		if ( ( $genomeSize * $numScaff ) <= $scaffoldSum ) {
			last;
		}

		if ( $count == $maxCount + 1 ) {
			last;
		}

		#remove underscores
		$scaffolds{$scaffoldID} = "scaf" . $count;
		$scaffoldIDMap{ "scaf" . $count } = $scaffoldID;
		$karyotype->write( "chr - "
			  . $scaffolds{$scaffoldID}
			  . " $scaffolds{$scaffoldID} 0 "
			  . $scaffoldsSize{$scaffoldID}
			  . " vvlgrey"
			  . "\n" );
		if ( exists( $scaffoldGaps{$scaffoldID} ) ) {
			foreach my $gap ( @{ $scaffoldGaps{$scaffoldID} } ) {
				$karyotype->write(
					"band $scaffolds{$scaffoldID} N N $gap black\n");
			}
		}
		$scaffoldSum += $scaffoldsSize{$scaffoldID};
		$count++;
	}
	print STDERR "Selecting " . $count . " scaffolds to render\n";

	#print out spacing information:
	my $defaultSpacing = 0.002;
	print $fd "<ideogram>\n<spacing>\ndefault = " . $defaultSpacing . "r\n";
	if ( $genomeSize > $scaffoldSum ) {
		my $spacingSize =
		  ( $defaultSpacing * $numChr +
			  ( $genomeSize - $scaffoldSum ) / ( $genomeSize + $scaffoldSum ) )
		  / $count / $defaultSpacing;

		foreach ( keys(%scaffolds) ) {
			print $fd "<pairwise "
			  . $scaffolds{$_}
			  . ">\nspacing = "
			  . $spacingSize
			  . "r\n</pairwise>\n";
		}
	}
	else {
		my $spacingSize =
		  ( $defaultSpacing * $count +
			  ( $scaffoldSum - $genomeSize ) / ( $scaffoldSum + $genomeSize ) )
		  / $numChr / $defaultSpacing;

		foreach ( keys(%chromosomes) ) {
			print $fd "<pairwise "
			  . $_
			  . ">\nspacing = "
			  . $spacingSize
			  . "r\n</pairwise>\n";
		}
	}
	print $fd "</spacing>\n</ideogram>\n";
	print $fd "<image>\nfile  = $prefix.png\n</image>\n";
	$karyotype->close();
}

#create links file
sub outputLinks {

	print STDERR "Generating Links file\n";

	my $agpFH = new IO::File($agpFile);
	my $line  = $agpFH->getline();
	my %scafftigLocationsFW;
	my %scafftigLocationsRV;
	my %scafftigSize;

	while ($line) {
		chomp($line);
		my @tempArray  = split( /\t/, $line );
		my $scaffoldID = $tempArray[0];
		$scaffoldID =~ s/^scaffold//;

		if ( exists( $scaffolds{$scaffoldID} ) && $tempArray[4] eq "W" ) {
			my $contigID = $tempArray[5];
			if ( exists( $scafftigSize{$contigID} ) ) {
				print STDERR "$tempArray[5] exists!\n";
				print STDERR $scafftigLocationsFW{$contigID} . "\n";
				exit(1);
			}

			#correct for 0th position? (index starts at 1)
			$scafftigLocationsFW{$contigID} = $tempArray[1] - 1;
			$scafftigLocationsRV{$contigID} =
			  ( $scaffoldsSize{$scaffoldID} - $tempArray[2] );
			$scafftigSize{$contigID} = $tempArray[2] - $tempArray[1];
		}
		$line = $agpFH->getline();
	}
	$agpFH->close();

	my %bestScaffToChrSize;
	my %bestScaffToChrStart;
	my %direction;

	my $bedFH = new IO::File($scafftigsBED);
	$line = $bedFH->getline();

	while ($line) {
		chomp($line);
		my @tempArray  = split( /\t/, $line );
		my $scaffoldID = $tempArray[3];
		$scaffoldID =~ s/^contig//;
		$scaffoldID =~ s/_\d+$//;
		my $linkSize = $tempArray[7] - $tempArray[6];
		if (   exists $scaffolds{$scaffoldID}
			&& exists $refIDMap{ $tempArray[0] } )
		{

			if (
				!exists(
					$bestScaffToChrSize{$scaffoldID}
					  ->{ $refIDMap{ $tempArray[0] } }
				)
			  )
			{
				$bestScaffToChrStart{$scaffoldID}
				  ->{ $refIDMap{ $tempArray[0] } } = [];
				$bestScaffToChrSize{$scaffoldID}->{ $refIDMap{ $tempArray[0] } }
				  = 0;
				$direction{$scaffoldID}->{ $refIDMap{ $tempArray[0] } } = 0;
			}
			$bestScaffToChrSize{$scaffoldID}->{ $refIDMap{ $tempArray[0] } } +=
			  $linkSize;
			push(
				@{
					$bestScaffToChrStart{$scaffoldID}
					  ->{ $refIDMap{ $tempArray[0] } }
				},
				$tempArray[1]
			);

			if ( $tempArray[5] eq "+" ) {
				$direction{$scaffoldID}->{ $refIDMap{ $tempArray[0] } } +=
				  $linkSize;
			}
			else {
				$direction{$scaffoldID}->{ $refIDMap{ $tempArray[0] } } -=
				  $linkSize;
			}
		}
		$line = $bedFH->getline();
	}
	$bedFH->close();

	my %scaffoldOrder;
	my %scaffoldStart;
	my %bestDirection;

	#for reordering the scaffolds to best location
	foreach my $key ( keys(%bestScaffToChrSize) ) {
		my $sizeRef   = $bestScaffToChrSize{$key};
		my $startsRef = $bestScaffToChrStart{$key};
		my $bestChr   = 0;
		my $bestNum   = 0;
		my $start     = 0;
		foreach my $i ( keys( %{$sizeRef} ) ) {
			if ( $sizeRef->{$i} > $bestNum ) {
				$bestNum = $sizeRef->{$i};
				$start   = median( @{ $startsRef->{$i} } );
				$bestChr = $i;
			}
		}
		push( @{ $scaffoldOrder{$bestChr} }, $scaffolds{$key} );
		$scaffoldStart{ $scaffolds{$key} } = $start;
		$bestDirection{$key} = $direction{$key}->{$bestChr};
	}

	my $linksRV = new IO::File(">$prefix.rv.links");
	my $linksFW = new IO::File(">$prefix.fw.links");
	$bedFH = new IO::File($scafftigsBED);
	$line  = $bedFH->getline();

	while ($line) {
		chomp($line);
		my @tempArray  = split( /\t/, $line );
		my $scaffoldID = $tempArray[3];
		$scaffoldID =~ s/^contig//;
		$scaffoldID =~ s/_\d+$//;
		if ( exists $scaffolds{$scaffoldID} && $refIDMap{ $tempArray[0] } ) {
			my $contigID = $tempArray[3];
			if ( $bestDirection{$scaffoldID} >= 0 ) {
				if ( $tempArray[5] eq "+" ) {

		#this is LocationsRV (flipped) because we want to mirror the orientation
					$linksFW->write( $refIDMap{ $tempArray[0] } . " "
						  . $tempArray[1] . " "
						  . $tempArray[2] . " "
						  . $scaffolds{$scaffoldID} . " "
						  . ( $scafftigLocationsRV{$contigID} + $tempArray[6] )
						  . " "
						  . ( $scafftigLocationsRV{$contigID} + $tempArray[7] )
						  . " color=$chrColorMap{$tempArray[0]}_a5\n" );
				}
				else {
					$linksRV->write( $refIDMap{ $tempArray[0] } . " "
						  . $tempArray[1] . " "
						  . $tempArray[2] . " "
						  . $scaffolds{$scaffoldID} . " "
						  . ( $scafftigLocationsRV{$contigID} + $tempArray[6] )
						  . " "
						  . ( $scafftigLocationsRV{$contigID} + $tempArray[7] )
						  . " color=$chrColorMap{$tempArray[0]}_a5\n" );
				}
			}
			else {
				if ( $tempArray[5] eq "-" ) {
					$linksFW->write( $refIDMap{ $tempArray[0] } . " "
						  . $tempArray[1] . " "
						  . $tempArray[2] . " "
						  . $scaffolds{$scaffoldID} . " "
						  . ( $scafftigLocationsFW{$contigID} + $tempArray[6] )
						  . " "
						  . ( $scafftigLocationsFW{$contigID} + $tempArray[7] )
						  . " color=$chrColorMap{$tempArray[0]}_a5\n" );
				}
				else {
					$linksRV->write( $refIDMap{ $tempArray[0] } . " "
						  . $tempArray[1] . " "
						  . $tempArray[2] . " "
						  . $scaffolds{$scaffoldID} . " "
						  . ( $scafftigLocationsFW{$contigID} + $tempArray[6] )
						  . " "
						  . ( $scafftigLocationsFW{$contigID} + $tempArray[7] )
						  . " color=$chrColorMap{$tempArray[0]}_a5\n" );
				}
			}
		}
		$line = $bedFH->getline();
	}

	print STDERR "chromosomes_order = ";
	print $fd "chromosomes_order = ";

	my $scaffoldFH = new IO::File( ">" . $prefix . ".seqOrder.txt" );

	foreach my $key ( reverse(@chrOrder) ) {
		if ( exists $scaffoldOrder{$key} ) {
			my @tempArray = sort { $scaffoldStart{$b} <=> $scaffoldStart{$a} }
			  @{ $scaffoldOrder{$key} };
			if ( scalar(@tempArray) != 0 ) {
				foreach my $scaffoldKey (@tempArray) {

					#I:scaffold876:1
					$scaffoldFH->write(
							$key . "\t"
						  . $chromosomes{$key} . "\t"
						  . $scaffoldKey . "\t"
						  . $scaffoldIDMap{$scaffoldKey} . "\t"
						  . (
							$bestDirection{ $scaffoldIDMap{$scaffoldKey} } > 0
							? "+"
							: "-"
						  )
						  . "\n"
					);
				}
				print $fd join( ",", @tempArray ) . ",";
				print STDERR join( ",", @tempArray ) . ",";
			}
		}
	}

	for ( my $i = 0 ; $i < scalar(@chrOrder) - 1 ; ++$i ) {
		print $fd $chrOrder[$i] . ",";
		print STDERR $chrOrder[$i] . ",";
	}
	print $fd $chrOrder[ scalar(@chrOrder) - 1 ] . "\n";
	print STDERR $chrOrder[ scalar(@chrOrder) - 1 ] . "\n";

	foreach my $key (@chrOrder) {

		#		$scaffoldFH->write( $key . "\t" . $chromosomes{$key} . "\n" );
		if ( !exists $scaffoldOrder{$key} ) {
			print STDERR $chromosomes{$key} . " has no alignments\n";
		}
	}

	foreach my $key ( keys(%scaffolds) ) {

		#		$scaffoldFH->write( $scaffolds{$key} . "\t" . $key . "\n" );
		if ( !exists $scaffoldStart{ $scaffolds{$key} } ) {
			print STDERR $key . " has no alignments\n";
		}
	}

	$scaffoldFH->close();
	$bedFH->close();
	$linksRV->close();
	$linksFW->close();
}

#taken from http://www.perlmonks.org/?node_id=474564
sub median {
	my @vals = sort { $a <=> $b } @_;
	my $len  = @vals;
	if ( $len % 2 )    #odd?
	{
		return $vals[ int( $len / 2 ) ];
	}
	else               #even
	{
		return ( $vals[ int( $len / 2 ) - 1 ] + $vals[ int( $len / 2 ) ] ) / 2;
	}
}
