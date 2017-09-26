#!/usr/bin/env perl

#Written by Justin Chu 2017
#generate a bedfile given sam file format

use strict;
use warnings;

my %chrlengths;
my %bandStr;

while (<>) {
	my @line = split( /\t/, $_ );
	print "$line[2]\t$line[3]\t"
	  . ( $line[3] + length( $line[9] ) )
	  . "\t$line[0]\t$line[4]\t";
	if ( $line[1] & 16 == 0 ) {
		print "-\n";
	}
	else {
		print "+\n";
	}
}
