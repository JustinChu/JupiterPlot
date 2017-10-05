#!/usr/bin/env perl

#Written by Justin Chu 2017
#generate generic karyotype from fasta file
#Adds bands on chromosomes based on content of Ns (gaps) in the file
#colours the chromosomes
#Other features, like centromeres or other cytogentic bands must be added manually (i.e. by altering file and running again)

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $hueNum     = 0;
my $increment  = 0;
my $maxHue     = 360;
my $minChrSize = 100000;
my $result     = GetOptions(
	'i=i' => \$increment,
	'm=i' => \$minChrSize
);

my %chrlengths;
my %bandStr;
my @chrOrder;

my $line = <>;
srand($hueNum);

while ($line) {
	my $header = $line;
	$line = <>;
	my $currentStr = "";
	while ( $line && $line !~ /^>/ ) {
		chomp $line;
		$currentStr .= $line;
		$line = <>;
	}
	if ( length($currentStr) > $minChrSize ) {
		my ($chrName) = $header =~ /^>([^\s]+)\s/;
		$chrlengths{$chrName} = length($currentStr);
		while ( $currentStr =~ /([^ATCGatcg]+)/g ) {
			$bandStr{$chrName} .= "band $chrName N N $-[0] $+[0] black\n";
		}
		push(@chrOrder,$chrName);
	}
}
my $incSize = $maxHue/scalar( keys(%chrlengths) );
foreach my $chrName ( @chrOrder ) {
	#TODO assign colours in meaningful way
	print "chr - "
	  . $chrName . " "
	  . $chrName . " 0 "
	  . $chrlengths{$chrName} . " hue";
	if ( $increment > $maxHue ) {
		printf '%03s', int( rand( $maxHue + 1 ) );
	}
	else {
		printf '%03s', int( ($hueNum + $increment) % $maxHue );
		$hueNum += $incSize;
	}
	print "\n$bandStr{$chrName}";
}
