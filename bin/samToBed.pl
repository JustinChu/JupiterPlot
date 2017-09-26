#!/usr/bin/env perl

#Written by Justin Chu 2017
#generate a bedfile given sam file format

use strict;
use warnings;

my %chrlengths;
my %bandStr;

while (<>) {
	my @line = split( /\t/, $_ );
	print $line[2] . "\t"
	  . ( $line[3] - 1 ) . "\t"
	  . ( $line[3] - 1 + getPaddedReferenceLength( $line[5] ) ) . "\t"
	  . $line[0] . "\t"
	  . $line[4] . "\t";
	if ( $line[1] & 16 == 0 ) {
		print "-\n";
	}
	else {
		print "+\n";
	}
}

#parse from cigar string
sub getPaddedReferenceLength {
	my $cigar  = shift;
	my $length = 0;
	if ( $cigar =~ /\d+M|D|N|EQ|X|P/ ) {
		my @elements = ( $cigar =~ /(\d+)(?:M|D|N|EQ|X|P)/g );
		for my $value (@elements) {
			$length += $value;
		}
	}
	return $length;
}
