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
my $numScaff      = 90;
my $rawConf       = "rawConf.conf";
my $prefix        = "circos";
my $result        = GetOptions(
	'k=s' => \$rawKaryotype,
	's=s' => \$scaffoldFiles,
	'n=i' => \$numScaff,
	'b=s' => \$scafftigsBED,
	'a=s' => \$agpFile,
	'r=s' => \$rawConf,
	'p=s' => \$prefix
);

my $outputkaryotype = $prefix . ".karyotype";

$numScaff = $numScaff / 100;

if ( $scaffoldFiles eq "" ) {
	die "-s -b and parameters needed";
}

my @chrOrder;
my %scaffolds;
my %scaffoldsSize;
my %direction;
my %refIDMap;
my %chrColorMap;

system( "cp " . $rawConf . " $prefix.conf -f" );
system("sed -i -e 's/karyotype.txt/$prefix.karyotype/g' $prefix.conf");
system("sed -i -e 's/links.txt/$prefix.links.bundled/g' $prefix.conf");
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

	#load in fai file
	while ($line) {
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[0];
		chomp($line);
		$scaffoldsSize{$scaffoldID} = $tempArray[1];
		$line = $scaffFH->getline();
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
		if ( $tempArray[0] eq "band" && exists( $refIDMap{ $tempArray[1] } ) ) {
			$tempArray[1] = $refIDMap{ $tempArray[1] };
			my $tempStr = join( " ", @tempArray ) . "\n";
			$karyotype->write($tempStr);
		}
		else {
			$refIDMap{ $tempArray[2] }    = "ref" . $numChr;
			$chrColorMap{ $tempArray[2] } = $tempArray[6];
			$tempArray[2]                 = "ref" . $numChr;

			#Generate circos friendly label
			$tempArray[3] =~ s/[_]//g;
			my $tempStr = join( " ", @tempArray ) . "\n";
			push( @chrOrder, $tempArray[2] );
			$karyotype->write($tempStr);
			$numChr++;
			$genomeSize += $tempArray[5];
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

		#remove underscores
		$scaffolds{$scaffoldID} = "scaf" . $count;
		$direction{$scaffoldID} = 0;
		$karyotype->write( "chr - "
			  . $scaffolds{$scaffoldID}
			  . " $scaffolds{$scaffoldID} 0 "
			  . $scaffoldsSize{$scaffoldID}
			  . " vvlgrey"
			  . "\n" );
		$scaffoldSum += $scaffoldsSize{$scaffoldID};
		$count++;
	}
	print STDERR "Selecting " . $count . " scaffolds to render\n";

	#print out spacing information:
	my $defaultSpacing = 0.002;
	print $fd "<ideogram>\n<spacing>\ndefault = " . $defaultSpacing . "r\n";
	my $spacingSize =
	  ( $defaultSpacing * $numChr +
		  ( $genomeSize - $scaffoldSum ) / ( $genomeSize + $scaffoldSum ) ) /
	  $count / $defaultSpacing;

	foreach ( keys(%scaffolds) ) {
		print $fd "<pairwise "
		  . $scaffolds{$_}
		  . ">\nspacing = "
		  . $spacingSize
		  . "r\n</pairwise>\n";
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
		my @tempArray = split( /\t/, $line );
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
			$scafftigLocationsFW{$contigID} = $tempArray[1];
			$scafftigLocationsRV{$contigID} =
			  ( $scaffoldsSize{$scaffoldID} - $tempArray[2] );
			$scafftigSize{$contigID} = $tempArray[2] - $tempArray[1];
		}
		$line = $agpFH->getline();
	}
	$agpFH->close();

	my %bestScaffToChrSize;
	my %bestScaffToChrStart;

	my $bedFH = new IO::File($scafftigsBED);
	$line = $bedFH->getline();
	my $count2 = 0;

	while ($line) {
		chomp($line);
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[3];
		$count2++;
		$scaffoldID =~ s/^contig//;
		$scaffoldID =~ s/_\d+$//;
		my $linkSize = $tempArray[2] - $tempArray[1];
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
				$direction{$scaffoldID}++;
			}
			else {
				$direction{$scaffoldID}--;
			}
		}
		$line = $bedFH->getline();
	}
	$bedFH->close();

	my $links = new IO::File(">$prefix.links");
	$bedFH = new IO::File($scafftigsBED);
	$line  = $bedFH->getline();

	while ($line) {
		chomp($line);
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[3];
		$scaffoldID =~ s/^contig//;
		$scaffoldID =~ s/_\d+$//;
		my $linkSize = $tempArray[2] - $tempArray[1];
		if ( exists $scaffolds{$scaffoldID} && $refIDMap{ $tempArray[0] } ) {

			if ( $direction{$scaffoldID} >= 0 ) {
				my $contigID = $tempArray[3];
				$linkSize =
				    $linkSize < $scafftigSize{$contigID}
				  ? $linkSize
				  : $scafftigSize{$contigID};
				$links->write( $refIDMap{ $tempArray[0] } . " "
					  . $tempArray[1] . " "
					  . $tempArray[2] . " "
					  . $scaffolds{$scaffoldID} . " "
					  . $scafftigLocationsRV{$contigID} . " "
					  . ( $scafftigLocationsRV{$contigID} + $linkSize )
					  . " color=$chrColorMap{$tempArray[0]}_a5\n" );
			}
			else {
				my $contigID = $tempArray[3];
				$linkSize =
				    $linkSize < $scafftigSize{$contigID}
				  ? $linkSize
				  : $scafftigSize{$contigID};
				$links->write( $refIDMap{ $tempArray[0] } . " "
					  . $tempArray[1] . " "
					  . $tempArray[2] . " "
					  . $scaffolds{$scaffoldID} . " "
					  . $scafftigLocationsFW{$contigID} . " "
					  . ( $scafftigLocationsFW{$contigID} + $linkSize )
					  . " color=$chrColorMap{$tempArray[0]}_a5\n" );
			}
		}
		$line = $bedFH->getline();
	}

	my %scaffoldOrder;
	my %scaffoldStart;

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
	}

	print STDERR "chromosomes_order = ";
	print $fd "chromosomes_order = ";

	foreach my $key (reverse(@chrOrder) ) {
		if ( exists $scaffoldOrder{$key} ) {
			my @tempArray = sort { $scaffoldStart{$b} <=> $scaffoldStart{$a} }
			  @{ $scaffoldOrder{$key} };
			if ( scalar(@tempArray) != 0 ) {
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

	foreach my $key (reverse(@chrOrder) ) {
		if ( !exists $scaffoldOrder{$key} ) {
			print STDERR $key . " has no alignments\n";
		}
	}

	my $scaffoldFD = new IO::File( ">" . $prefix . ".scaffold.txt" );

	foreach my $key ( keys(%scaffolds) ) {
		$scaffoldFD->write( $scaffolds{$key} . "\t" . $key . "\n" );
		if ( !exists $scaffoldStart{ $scaffolds{$key} } ) {
			print STDERR $key . " has no alignments\n";
		}
	}

	$scaffoldFD->close();
	$bedFH->close();
	$links->close();
}

#taken from http://www.perlmonks.org/?node_id=474564
sub median {
	my @vals = sort { $a <=> $b } @_;
	my $len = @vals;
	if ( $len % 2 )    #odd?
	{
		return $vals[ int( $len / 2 ) ];
	}
	else               #even
	{
		return ( $vals[ int( $len / 2 ) - 1 ] + $vals[ int( $len / 2 ) ] ) / 2;
	}
}
