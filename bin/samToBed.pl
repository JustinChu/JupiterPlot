#!/usr/bin/env perl

#Written by Justin Chu 2017
#generate a bedfile given sam file format

use strict;
use warnings;

my %chrlengths;
my %bandStr;

while (<>) {
	my $line = $_;
	my @line = split( /\t/, $line );
	print $line[2] . "\t"
	  . ( $line[3] - 1 ) . "\t"
	  . ( $line[3] - 1 + getPaddedReferenceLength( $line[5] ) ) . "\t"
	  . $line[0] . "\t"
	  . $line[4] . "\t";
	if ( $line[1] & 16 ) {
		print "-";
	}
	else {
		print "+";
	}
	print "\t"
	  . getStartQueryAlignment( $line[5] ) . "\t"
	  . (
		getStartQueryAlignment( $line[5] ) + getPaddedQueryLength( $line[5] ) );
	print "\n";
#	if ( $line[1] != 16 && $line[1] != 0 ) {
#		print $line;
#	}
}

#parse from cigar string
sub getPaddedReferenceLength {
	my $cigar    = shift;
	my $length   = 0;
	my @elements = ( $cigar =~ /(\d+)(?:M|D|N|=|X)/g );
	for my $value (@elements) {
		$length += $value;
	}
	return $length;
}

#parse from cigar string
sub getPaddedQueryLength {
	my $cigar    = shift;
	my $length   = 0;
	my @elements = ( $cigar =~ /(\d+)(?:M|I|=|X|P)/g );
	for my $value (@elements) {
		$length += $value;
	}
	return $length;
}

#get start of read alignment
sub getStartQueryAlignment {
	my $cigar = shift;
	if ( $cigar =~ /^(\d+)(?:S|G|H)/ ) {
		return $1 - 1;
	}
	return 0;
}

