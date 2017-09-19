#!/usr/bin/env perl
#Written By Justin Chu 2016
#Generates a links file, karyotype file and configuration file for circos

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $rawKaryotype    = "";
my $genomeIndexFile = "";
my $scaffoldFiles   = "";
my $scafftigsBED    = "";
my $agpFile         = "";
my $numScaff        = 90;
my $rawConf         = "rawConf.conf";
my $prefix          = "circos";
my $result          = GetOptions(
	'k=s' => \$rawKaryotype,
	's=s' => \$scaffoldFiles,
	'g=s' => \$genomeIndexFile,
	'n=i' => \$numScaff,
	'b=s' => \$scafftigsBED,
	'a=s' => \$agpFile,
	'r=s' => \$rawConf,
	'p=s' => \$prefix
);

my $outputkaryotype = $prefix . ".karyotype";

$numScaff = $numScaff / 100;

if ( $genomeIndexFile eq "" || $scaffoldFiles eq "" ) {
	die "-s -b and -g parameters needed";
}

my @chrOrder;
my %scaffolds;
my %scaffoldsSize;
my %direction;
my %refIDMap;

system( "cp " . $rawConf . " $prefix.conf -f" );
system( "sed -i -e 's/karyotype.txt/$prefix.karyotype/g' $prefix.conf");
system( "sed -i -e 's/links.txt/$prefix.links.bundled/g' $prefix.conf");
open( my $fd, ">>$prefix.conf" );

#create karyotype file
outputKaryotype();
outputLinks();
close($fd);

sub outputKaryotype {
	
	print STDERR "Generating Karyotype file\n";

	#load in genome file
	my $genomeFileFH = new IO::File($genomeIndexFile);
	my $line         = $genomeFileFH->getline();
	my $genomeSize   = 0;
	my $numChr       = 0;

	while ($line) {
		chomp($line);
		my @tempArray = split( "\t", $line );
		$genomeSize += $tempArray[1];
		$line = $genomeFileFH->getline();
		$numChr++;
	}
	$genomeFileFH->close();

	my $scaffFH = new IO::File($scaffoldFiles);
	$line = $scaffFH->getline();

	my %scaffoldLengths;
	my $karyotype = new IO::File(">$outputkaryotype");

	#load in fai file
	while ($line) {
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[0];
		chomp($line);
		$scaffoldLengths{$scaffoldID} = $tempArray[1];
		$line = $scaffFH->getline();
	}
	$scaffFH->close();

	my $rawKaryotypeFH = new IO::File($rawKaryotype);
	$line = $rawKaryotypeFH->getline();
	my $tempID = 1;

	#load in base karyotype
	while ($line) {
		#Generate circos friendly name
		chomp($line);
		my @tempArray = split( " ", $line );
		#chr - gi|453232067|ref|NC_003281.10| gi|453232067|ref|NC_003281.10| 0 13783801 greychr
		$refIDMap{$tempArray[2]} = "ref". $tempID;
		$tempArray[2] = "ref". $tempID;
		$tempArray[3] = "ref". $tempID;
		my $tempStr = join( " ", @tempArray ) . "\n";
		push(@chrOrder, $tempArray[2]);
		$karyotype->write($tempStr);
		$line = $rawKaryotypeFH->getline();
		$tempID++;
	}
	$rawKaryotypeFH->close();

	#sort by length
	my @lengthOrder =
	  sort { $scaffoldLengths{$a} <=> $scaffoldLengths{$b} }
	  keys %scaffoldLengths;

	my $count       = 1;
	my $scaffoldSum = 0;

	foreach my $scaffoldID ( reverse @lengthOrder ) {

		if ( ( $genomeSize * $numScaff ) <= $scaffoldSum ) {
			last;
		}

		#remove underscores
		$scaffolds{$scaffoldID} = "scaffold" . $count;
		$direction{$scaffoldID} = 0;
		$karyotype->write( "chr - "
			  . $scaffolds{$scaffoldID}
			  . " $scaffolds{$scaffoldID} 0 "
			  . $scaffoldLengths{$scaffoldID}
			  . " vvlgrey"
			  . "\n" );
		$scaffoldSum += $scaffoldLengths{$scaffoldID};
		$scaffoldsSize{$scaffoldID} = $scaffoldLengths{$scaffoldID};
		$count++;
	}
	print STDERR "Selecting " . $count . " contigs to render\n";

	#print out spacing information:
	my $defaultSpacing = 0.002;
	print $fd "<ideogram>\n<spacing>\ndefault = " . $defaultSpacing . "r\n";
	my $spacingSize = ($defaultSpacing*$numChr+($genomeSize-$scaffoldSum)/($genomeSize+$scaffoldSum))/$count/$defaultSpacing;

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

			#special removal for LINKS created scaffolds
#			if ( $contigID =~ /_[rf]/ ) {
#				$contigID =~ s/_([rf])/$1/g;
#			}
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

	my %bestScaffToChrCount;
	my %bestScaffToChrStart;

	my $bedFH = new IO::File($scafftigsBED);
	$line = $bedFH->getline();
	my $count2 = 0;

	while ($line) {
		chomp($line);
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[3];
		$count2++;
		unless ( defined $tempArray[3] ) {
			print $line . " $count2" . "\n";
			exit(1);
		}
		$scaffoldID =~ s/^contig//;
		$scaffoldID =~ s/_\d+$//;
		my $linkSize = $tempArray[2] - $tempArray[1];
		if ( exists $scaffolds{$scaffoldID} ) {
			my $contigID = $tempArray[3];
			if (
				!exists( $bestScaffToChrCount{$scaffoldID}->{ $refIDMap{$tempArray[0]} } )
			  )
			{
				$bestScaffToChrStart{$scaffoldID}->{ $refIDMap{$tempArray[0]} } =
				  $tempArray[1];
				$bestScaffToChrCount{$scaffoldID}->{ $refIDMap{$tempArray[0]} } = 0;
			}
			else {
				$bestScaffToChrCount{$scaffoldID}->{ $refIDMap{$tempArray[0]} }++;
			}

			if ( $tempArray[5] eq "+" ) {
				$direction{$scaffoldID}++;
			}
			else {
				$direction{$scaffoldID}--;
				my $contigID = $tempArray[3];
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
		if ( exists $scaffolds{$scaffoldID} ) {

			if ( $direction{$scaffoldID} >= 0 ) {
				my $contigID = $tempArray[3];
#				if ( !exists( $scafftigSize{$contigID} ) ) {
#					print $scaffoldID . " " . $contigID . "\n";
#					exit(1);
#				}
				$linkSize =
				    $linkSize < $scafftigSize{$contigID}
				  ? $linkSize
				  : $scafftigSize{$contigID};
				$links->write( $refIDMap{$tempArray[0]} . " "
					  . $tempArray[1] . " "
					  . $tempArray[2] . " "
					  . $scaffolds{$scaffoldID} . " "
					  . $scafftigLocationsRV{$contigID} . " "
					  . ( $scafftigLocationsRV{$contigID} + $linkSize )
					  . " color=grey_a5\n" );
			}
			else {
				my $contigID = $tempArray[3];
#				if ( !exists( $scafftigSize{$contigID} ) ) {
#					print $scaffoldID . "\n" . $contigID . "\n";
#					exit(1);
#				}
				$linkSize =
				    $linkSize < $scafftigSize{$contigID}
				  ? $linkSize
				  : $scafftigSize{$contigID};
				$links->write( $refIDMap{$tempArray[0]} . " "
					  . $tempArray[1] . " "
					  . $tempArray[2] . " "
					  . $scaffolds{$scaffoldID} . " "
					  . $scafftigLocationsFW{$contigID} . " "
					  . ( $scafftigLocationsFW{$contigID} + $linkSize )
					  . " color=grey_a5\n" );
			}
		}
		$line = $bedFH->getline();
	}

	my %scaffoldOrder;
	my %scaffoldStart;

	foreach my $key ( keys(%bestScaffToChrCount) ) {
		my $countsRef = $bestScaffToChrCount{$key};
		my $startsRef = $bestScaffToChrStart{$key};
		my $bestChr = 0;
		my $bestNum = 0;
		my $start = 0;
		foreach my $i ( keys(%{$countsRef})){
			if($countsRef->{$i} > $bestNum){
				$bestNum = $countsRef->{$i};
				$start = $startsRef->{$i};
				$bestChr = $i;
			}	
		}
		push(@{$scaffoldOrder{$bestChr}}, $scaffolds{$key});
		$scaffoldStart{$scaffolds{$key}} = $start;
	}
	
	print STDERR "chromosomes_order = ";
	print $fd "chromosomes_order = ";
	
	foreach ( reverse(@chrOrder) ) { 
		my @tempArray = sort { $scaffoldStart{$b} <=> $scaffoldStart{$a} } @{$scaffoldOrder{$_}};
		print $fd join(",", @tempArray) . ",";
		print STDERR join(",", @tempArray) . ",";
	}
	
	for(my $i = 0; $i < scalar(@chrOrder) - 1; ++$i ) {
		print $fd $chrOrder[$i] . ",";
		print STDERR $chrOrder[$i] . ",";
	}
	print $fd $chrOrder[scalar(@chrOrder) - 1] ."\n";
	print STDERR $chrOrder[scalar(@chrOrder) - 1] ."\n";
	
	foreach my $key ( keys(%scaffolds) ) {
		if(!exists $scaffoldStart{$scaffolds{$key}}){
			print STDERR $key . " has no alignments\n";
		}
	}

	$bedFH->close();
	$links->close();
}
