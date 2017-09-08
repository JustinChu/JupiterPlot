package Circos::DataPoint;

=pod

=head1 NAME

Circos::DataPoint - routines for handling data points in Circos

=head1 SYNOPSIS

This module is not meant to be used directly.

=head1 DESCRIPTION

Circos is an application for the generation of publication-quality,
circularly composited renditions of genomic data and related
annotations.

Circos is particularly suited for visualizing alignments, conservation
and intra and inter-chromosomal relationships. However, Circos can be
used to plot any kind of 2D data in a circular layout - its use is not
limited to genomics. Circos' use of lines to relate position pairs
(ribbons add a thickness parameter to each end) is effective to
display relationships between objects or positions on one or more
scales.

All documentation is in the form of tutorials at L<http://www.circos.ca>.

=cut

# -------------------------------------------------------------------

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw();

use Carp qw( carp confess croak );
use Data::Dumper;
use FindBin;
use GD::Image;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; # qw(%CONF $DIMS);
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Expression;
use Circos::Utils;

use Memoize;

for my $f ( qw() ) { }

sub apply_filter {
	my ($filter,@args) = @_;
	if($filter eq "minsize") {
		_apply_filter_minsize(@args);
	}
}

sub _apply_filter_minsize {
	my ($value,$datum) = @_;
	for my $point (@{$datum->{data}}) {
		my $size = $point->{end}-$point->{start}+1;
		my $d    = $value-$size;
		if($d > 0) {
			$point->{start}   -= int($d/2);
			if($point->{start} > 0) {
				$point->{end}   = $point->{start}+$value-1;
			} else {
				$point->{start} = 0;
				$point->{end}   = $value-1;
			}
			if($point->{set}) {
				$point->{set} = make_set( @{$point}{qw(start end)});
			}
		}
	}
}

1;
