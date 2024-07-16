#!/usr/bin/env perl

#Written by Justin Chu 2019
#Collapse links using simple rules
#currently only collapses edges that apear in colinear stretches
#requires sorted links file

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $minDist       = 0;
my $minBundleSize = 0;
my $result        = GetOptions( 'm=i' => \$minDist, 'b=i' => \$minBundleSize );

my $line = <>;
chomp($line);

#ref0 281924 283348 scaf5 280845733 280847156 color=hue000_a5
my @dataArray = split( / /, $line );
my $currChr   = $dataArray[0];

my $currStart    = $dataArray[1];
my $currEnd      = $dataArray[2];
my $currContigID = $dataArray[3];

my $currContigStart = $dataArray[4];
my $currContigEnd   = $dataArray[5];
my $currColour      = $dataArray[6];

my $count      = 0;
my $countTotal = 0;

my $maxContigConnect = 0;
my $maxConnect       = 0;

while ($line) {
	chomp($line);
	@dataArray = split( / /, $line );

	#line is currently connected to previous
	unless ( $currChr eq $dataArray[0]
		&& ( $dataArray[1] - $currEnd ) < $minDist
		&& $currContigID eq $dataArray[3]
		&& ( $dataArray[4] - $currContigEnd ) < $minDist )
	{
		if (   $minBundleSize < ($currEnd - $currStart)
			&& $minBundleSize < ($currContigEnd - $currContigStart) )
		{
			#			print $currChr . " " . $currStart . " "
			#			  . $currEnd . " "
			#			  . $currContigID . " "
			#			  . $currContigStart . " "
			#			  . $currContigEnd . " ",
			#			  $currColour . " "
			#			  . ( $currEnd - $currStart ) . " "
			#			  . ( $currContigEnd - $currContigStart ) . "\n";
			#			my $geoMean = sqrt( ( $currEnd - $currStart ) *
			#				  ( $currContigEnd - $currContigStart ) );

			if ( $currColour =~ /([^_]+)_a\d/ ) {
				$currColour = $1;

				#				if ( $geoMean > 70000 ) {
				#					$currColour = $1 . "_a1";
				#				}
				#				elsif ( $geoMean > 60000 ) {
				#					$currColour = $1 . "_a2";
				#				}
				#				elsif ( $geoMean > 50000 ) {
				#					$currColour = $1 . "_a3";
				#				}
				#				elsif ( $geoMean > 40000 ) {
				#					$currColour = $1 . "_a4";
				#				}
				#				elsif ( $geoMean > 30000 ) {
				#					$currColour = $1 . "_a5";
				#				}
				#				elsif ( $geoMean > 20000 ) {
				#					$currColour = $1 . "_a6";
				#				}
				#				else {
				#					$currColour = $1 . "_a7";
				#				}
			}
			print $currChr . " "
			  . $currStart . " "
			  . $currEnd . " "
			  . $currContigID . " "
			  . $currContigStart . " "
			  . $currContigEnd . " ",
			  $currColour . "\n";
			if ( $maxContigConnect < $currContigEnd - $currContigStart ) {
				$maxContigConnect = $currContigEnd - $currContigStart;
			}
			if ( $maxConnect < $currEnd - $currStart ) {
				$maxConnect = $currEnd - $currStart;
			}
			$count++;
		}
		$currStart       = $dataArray[1];
		$currContigStart = $dataArray[4];
	}
	$currChr       = $dataArray[0];
	$currEnd       = $dataArray[2];
	$currContigID  = $dataArray[3];
	$currContigEnd = $dataArray[5];
	$currColour    = $dataArray[6];
	$line          = <>;
	$countTotal++;
}

#print out last one
if (   $minBundleSize < ($currEnd - $dataArray[1])
	&& $minBundleSize < ($currContigEnd - $dataArray[4]) )
{
	print $currChr . " "
	  . $dataArray[1] . " "
	  . $currEnd . " "
	  . $currContigID . " "
	  . $dataArray[4] . " "
	  . $currContigEnd
	  . " ", $dataArray[6] . "\n";
	$count++;

  #	my $geoMean =
  #	  sqrt( ( $currEnd - $dataArray[1] ) * ( $currContigEnd - $dataArray[4] ) );
	if ( $maxContigConnect < $currContigEnd - $dataArray[4] )
	{
		$maxContigConnect = $currContigEnd - $dataArray[4];
	}
	if ( $maxConnect < $currEnd - $dataArray[1] ) {
		$maxConnect = $currEnd - $dataArray[1];
	}
}

print STDERR "Total Number of edges: "
  . $count
  . " Inital Edges: "
  . $countTotal . " Max: " . $maxConnect . " " . $maxContigConnect . "\n";
