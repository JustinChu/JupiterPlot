#!/usr/bin/env perl

#Written by Justin Chu 2017
#generate generic karyotype from fasta file
#Adds bands on chromosomes based on content of Ns (gaps) in the file
#Other features, like centromeres or other cytogentic bands must be added manually (i.e. by altering file and running again)

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $hueNum    = 0;
my $increment = 53;
my $maxHue    = 360;
my $random    = 1;
my $result    = GetOptions(
	'r'   => \!$random,
	'i=i' => \$increment
);

my $line = <>;

while ($line) {
	my $header = $line;
	$line = <>;
	my $currentStr = "";
	while ( $line && $line !~ /^>/ ) {
		chomp $line;
		$currentStr .= $line;
		$line = <>;
	}
	my ($chrName) = $header =~ /^>([^\s]+)\s/;

	#TODO assign colours in meaningful way
	print "chr - "
	  . $chrName . " "
	  . $chrName . " 0 "
	  . length($currentStr) . " hue";
	if ($random) {
		printf '%03s', int( rand( $maxHue + 1 ) );
	}
	else {
		printf '%03s', $hueNum;
	}
	$hueNum += $increment;
	if ( $hueNum > $maxHue ) {
		$hueNum = $hueNum - $maxHue;
	}
	print "\n";
	while ( $currentStr =~ /([^ATCGatcg]+)/g ) {
		print "band $chrName N N $-[0] $+[0] black\n";
	}
}
