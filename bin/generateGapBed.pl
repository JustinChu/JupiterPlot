#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Std qw'getopts';

my %opt;
getopts 'l:', \%opt;
my $opt_min_scaf_len = defined $opt{'l'} ? $opt{'l'} : 150;

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
	while ( $currentStr =~ /([^ATCGatcg]+)/g ) {
		my @start = @-;
		my @end   = @+;
		print $chrName . "\t" . $start[0] . "\t" . $end[0] . "\n";
	}
}
