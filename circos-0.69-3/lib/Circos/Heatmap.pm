package Circos::Heatmap;

=pod

=head1 NAME

Circos::Heatmap - heatmap routines in Circos

=head1 SYNOPSIS

This module is not meant to be used directly.

=cut

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(
encode_mapping
report_mapping
);

use Carp qw( carp confess croak );
use Clone;
use Data::Dumper;
use FindBin;
use GD::Image;
use Math::VecStat qw(min max);
use Params::Validate qw(:all);
use List::MoreUtils qw(uniq);
use Regexp::Common qw(number);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration;
use Circos::Constants;
use Circos::Colors;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;

use Memoize;

for my $f ( qw ( ) ) {
memoize($f);
}

################################################################
#
# encodings: 0,1,2,3,...,n,n+1
#
#  method      min             max
#     0,1      0|0 1 2 ... n n+1|n+1
#       0      0|001122...445577|7     [min,max] divided uniformly
#       1      0|01122...4455667|7               division at edges 1/2 of others
#       2      0|1  2  ... n-1 n|n+1             divided uniformly, 0,n+1 encode data extremes 


sub report_mapping {
	my ($mapping,$id) = @_;
	for my $item (@$mapping) {
		printdebug_group("legend",
										 $id,
										 defined $item->{min} ? sprintf("%4.1f",$item->{min}) : "-inf",
										 defined $item->{max} ? sprintf("%4.1f",$item->{max}) : "+inf",
										 defined $item->{max} && defined $item->{min} ? sprintf("%4.1f",$item->{max}-$item->{min}) : " inf",
										 defined $item->{min_remap} ? sprintf("%4.1f",$item->{min_remap}) : "-inf",
										 defined $item->{max_remap} ? sprintf("%4.1f",$item->{max_remap}) : "+inf",
										 defined $item->{max_remap} && defined $item->{min_remap} ? sprintf("%4.1f",$item->{max_remap}-$item->{min_remap}) : " inf",
										 sprintf("%2d",$item->{i}),
										 $item->{value},
										 join(",",rgb_color($item->{value})));
	}
}

sub encode_mapping {
	my ($plot_min,$plot_max,$encodings,$method,$base,$boundaries_string) = @_;
	my @legend;
	my $nencodings = @$encodings;
	# value, encoding
	if($nencodings == 1) {
		push @legend, {min=>undef,
									 max=>undef,
									 i=>0};
	} else {
		push @legend, {min=>undef,
									 max=>$plot_min,
									 i=>0};
		push @legend, encode_mapping_region($plot_min,$plot_max,$encodings,$method,$base);
		push @legend, {min=>$plot_max,
									 max=>undef,
									 i=>$nencodings-1};
	}
	# populate legend with encoding values
	for my $item (@legend) {
		$item->{value} = $encodings->[ $item->{i} ];
	}
	my @boundaries = parse_boundaries($boundaries_string,$plot_min,$plot_max) if $boundaries_string;
	if($nencodings > 1) {
		rescale_boundary_check(\@boundaries,$encodings,$plot_min,$plot_max);
		rescale_mapping(\@legend,\@boundaries);
	}
	return \@legend;
}

sub parse_boundaries {
	my ($str,$plot_min,$plot_max) = @_;
	fatal_error("heatmap","rescale_boundary_bad_fmt",$str) if $str !~ /:/;
	my @boundaries;
	for my $b (split(/\s*,\s*/,$str)) {
		my ($pos,$i) = split(/\s*:\s*/,$b);
		if(! defined $pos || ! defined $i) {
			fatal_error("heatmap","rescale_boundary_bad_fmt",$str);
		}
		fatal_error("heatmap","rescale_boundary_bad_value",$i)      if $i !~ /^$RE{num}{int}$/;
		fatal_error("heatmap","rescale_boundary_bad_position",$pos) if $pos !~ /^$RE{num}{real}$/;
		if($pos =~ /(.*)r/) {
			$pos = $plot_min + $1 * ($plot_max - $plot_min);
		}
		push @boundaries, {pos=>$pos,i=>$i};
	}
	return @boundaries;
}

################################################################
# Sanity check on rescaling boundaries.

sub rescale_boundary_check {
	my ($boundaries,$encodings,$plot_min,$plot_max) = @_;
	my $nencodings = @$encodings;
	for my $bidx (0..@$boundaries-1) {
		my $b = $boundaries->[$bidx];
		if($b->{i} < 0 || $b->{i} >= $nencodings) {
			fatal_error("heatmap","rescale_boundary_value_out_of_bounds",$b->{i},$b->{pos},
									$nencodings,
									$nencodings-1);
		}
		if($b->{pos} <= $plot_min || $b->{pos} >= $plot_max) {
			fatal_error("heatmap","rescale_boundary_position_out_of_bounds",$b->{pos},$plot_min,$plot_max);
		}
		if($bidx) {
			my $bprev = $boundaries->[$bidx-1];
			if($b->{i} <= $bprev->{i}) {
				fatal_error("heatmap","rescale_boundary_value_not_increasing",$bprev->{i},$b->{i});
			}
			if($b->{pos} <= $bprev->{pos}) {
				fatal_error("heatmap","rescale_boundary_position_not_increasing",$bprev->{pos},$b->{pos});
			}
		}
	}
}

################################################################
# Given a legend with mappings from positions [xi,yi] to values zi
#
# [xi,yi) -> zi
#
# rescale the values of xi,yi so specified values (u1,u2,...) map onto
# specified values (v1,v2,...). 
# 
# For example if u1=3 and v1=5 then the value 3 will be mapped onto 5. This is done
# by finding the region [xi,yi] that maps to 5 and rescaling it so that its
# middle will center on 3.
#
#
#   z0        z1        z2
# x0  y0    x1  y1    x2  y2   ...
#             /
#        ----/
#       /
#      |
#   x1' y1'

sub rescale_mapping {

	my ($legend,$boundaries) = @_;

	for my $b (@$boundaries) {
		for my $l (@$legend) {
			next if ! defined $l->{min} || ! defined $l->{max};
			if($l->{i} == $b->{i}) {
				$b->{from} = ($l->{min} + $l->{max})/2;
			}
		}
	}

	for my $l (@$legend) {
		# first and last elements of the legend are never rescaled
		if(! defined $l->{min} || ! defined $l->{max}) {
			$l->{min_remap} = $l->{min};
			$l->{max_remap} = $l->{max};
			next;
		}
		# find the left/right rescale boundary for xi yi of this region
		my ($from_min,$from_max,$to_min,$to_max);
		for my $b (@$boundaries) {
			# [0] - min scaling
			# [1] - max scaling
			if($l->{i} < $b->{i}) {
				$from_max->[0] = $b->{from} if ! defined $from_max->[0];
				$from_max->[1] = $b->{from} if ! defined $from_max->[1];
				$to_max->[0]   = $b->{pos}  if ! defined $to_max->[0];
				$to_max->[1]   = $b->{pos}  if ! defined $to_max->[1];
			} elsif ($l->{i} > $b->{i}) {
				$from_min->[0] = $from_min->[1] = $b->{from};
				$to_min->[0]   = $to_min->[1]   = $b->{pos};
			} else {
				$from_max->[0] = $b->{from};
				$to_max->[0]   = $b->{pos};
				$from_min->[1] = $b->{from};
				$to_min->[1]   = $b->{pos};
			}
		}

		for my $i (0,1) {
			$from_min->[$i] = $legend->[0]{max}  if ! defined $from_min->[$i];
			$from_max->[$i] = $legend->[-1]{min} if ! defined $from_max->[$i];
			$to_min->[$i]   = $legend->[0]{max}  if ! defined $to_min->[$i];
			$to_max->[$i]   = $legend->[-1]{min} if ! defined $to_max->[$i];
		}

		$l->{min_remap} = $to_min->[0] + ($l->{min} - $from_min->[0])/($from_max->[0] - $from_min->[0]) * ($to_max->[0] - $to_min->[0]);
		$l->{max_remap} = $to_min->[1] + ($l->{max} - $from_min->[1])/($from_max->[1] - $from_min->[1]) * ($to_max->[1] - $to_min->[1]);

		printdebug_group("legend",
										 sprintf("[%2d] min [%4.1f %4.1f] -> [%4.1f %4.1f] %4.1f -> %4.1f",
														 $l->{i},
														 $from_min->[0],$from_max->[0],
														 $to_min->[0],$to_max->[0],
														 $l->{min},$l->{min_remap}));
		printdebug_group("legend",
										 sprintf("[%2d] max [%4.1f %4.1f] -> [%4.1f %4.1f] %4.1f -> %4.1f",
														 $l->{i},
														 $from_min->[1],$from_max->[1],
														 $to_min->[1],$to_max->[1],
														 $l->{max},$l->{max_remap}));
	}
}

sub encode_mapping_region {
	my ($plot_min,$plot_max,$encodings,$method,$base) = @_;
	my @encodings  = @$encodings;
	my $nencodings = @encodings;
	my @legend;
	# there is only one encoding value -- everything is mapped to this
	if($nencodings == 1) {
		push @legend, {min=>$plot_min,
									 max=>$plot_max,
									 i=>0};
	} else {
		my $range_divisions;
		if($method == 0) {
			$range_divisions = $nencodings;
		} elsif ($method == 1) {
			$range_divisions = $nencodings;
		} elsif ($method == 2) {
			$range_divisions = $nencodings - 2;
		}
		if(! $range_divisions) {
			push @legend, {min=>$plot_min,
										 max=>$plot_max,
										 i=>0};
		} else {
			my $range = $plot_max - $plot_min;
			my $d     = $method == 1 ? $range / ($range_divisions - 1) : $range / $range_divisions;
			for my $i (0..$range_divisions-1) {
				my ($min,$max,$idx);
				if($method == 0) {
					$min = $plot_min + $i*$d;
					$max = $plot_min + ($i+1)*$d;
					$idx = $i;
				} elsif ($method == 1) {
					$min = $plot_min + max($plot_min,($i-0.5)*$d);
					$max = $plot_min + min($plot_max,($i+0.5)*$d);
					$idx = $i;
				} elsif ($method == 2) {
					$min = $plot_min + $i*$d;
					$max = $plot_min + ($i+1)*$d;
					$idx = $i+1;
				} else {
					confess "Encoding color_mapping [$method] is not supported";
				}
				# remap min/max if base
				if(defined $base && $base > 0 && $base != 1) {
					$min = $plot_min + (($min-$plot_min)/$range)**(1/$base) * $range;
					$max = $plot_min + (($max-$plot_min)/$range)**(1/$base) * $range;
				}
				push @legend, {min=>$min,
											 max=>$max,
											 i=>$idx};
			}
		}
	}
	return @legend;
}

1;
