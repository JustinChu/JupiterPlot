package Circos::Division;

=pod

=head1 NAME

Circos::Division - axis and tick spacing routines in Circos

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
use FindBin;
use GD;
use Math::Round;
use List::MoreUtils qw(uniq);
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration;
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;

use Memoize;

for my $f ( qw ( ) ) {
  memoize($f);
}

sub make_ranges {
	my ($blocks,$param_path,$min,$max,$set) = @_;
	return unless $blocks;
	my $divisions;
	if(! defined $min && ! defined $max) {
		for my $block (make_list($blocks)) {
			push @$divisions, {y0=>undef,
												 y1=>undef,
												 block=>$block};
		}
		return $divisions;
	} else {
		return unless defined $max && defined $min && defined $max;
		for my $block (make_list($blocks)) {
			my @pp     = ($block, @$param_path);
			next if hide(@pp);
			my $ystart = parse_value(seek_parameter("y0",@pp),$min,$max);
			my $yend   = parse_value(seek_parameter("y1",@pp),$min,$max);
			$ystart = $min if ! defined $ystart || $ystart < $min;
			$yend   = $max if ! defined $yend || $yend > $max;

			push @{$divisions->{$yend-$ystart}{$ystart}}, {y0=>$ystart,
																										 y1=>$yend,
																										 block=>$block};
		}
		my $divisions_sorted = [];
		for my $size (sort {$b <=> $a} keys %$divisions) {
			for my $y0 (sort {$a <=> $b} keys %{$divisions->{$size}}) {
				push @$divisions_sorted, @{ $divisions->{$size}{$y0} };
			}
		}
		return $divisions_sorted;
	}
}

sub make_divisions {
	my ($blocks,$param_path,$min,$max,$r0,$r1) = @_;
	return unless $blocks;
	if(defined $min && defined $max) {

	} elsif (defined $r0 && defined $r1) {
		$min = $r0;
		$max = $r1;
	} else {
		return;
	}
	my $divisions;
	for my $block (make_list($blocks)) {
		my @pp      = ($block, @$param_path);
		next if hide(@pp);

		# positions to skip
		my @skip    = parse_position( seek_parameter("position_skip",@pp),\@pp,$min,$max);
		my %skip    = map { $_=>1 } @skip;

		# specific positions
		my @pos     = parse_position( seek_parameter("position",@pp),\@pp,$min,$max);
		# positions determined with fixed or relative spacing
		my $spacing = parse_value(seek_parameter("spacing",@pp),$max-$min);

		# optional y start/end values
		my $ystart = parse_value(seek_parameter("y0",@pp),$min,$max);
		my $yend   = parse_value(seek_parameter("y1",@pp),$min,$max);
		$ystart = $min if ! defined $ystart || $ystart < $min;
		$yend   = $max if ! defined $yend || $yend > $max;

		$block->{spacing} = $spacing;
		my @posauto = parse_spacing( $spacing , \@pp, $min, $max);
		my $TOL = ($spacing||0)/1000; # float roundoff causes problems without TOL
		for my $pos (sort {$a <=> $b} uniq (@pos,@posauto)) {
			my $skip =  $skip{$pos} || $pos < $ystart - $TOL || $pos > $yend + $TOL;
			printdebug_group("axis","line", $skip?" ":"+",$spacing,$pos,$block->{color});
			next if $skip;
	    push @{$divisions->{$spacing || 0}{$pos}}, $block;
		}
	}

	my $sorted_divisions = [];
	my $seen_division;

	for my $spacing (sort {$b <=> $a} keys %$divisions) {
		for my $pos (sort {$a <=> $b} keys %{$divisions->{$spacing}}) {
	    # if this division is generated with non-zero spacing (i.e. automatic)
	    # only accept the first one (largest spacing).
	    next if $spacing && $seen_division->{$pos}++;
			#printinfo($spacing,$pos,$divisions->{$spacing}{$pos}[0]{color});
	    push @{$sorted_divisions}, {spacing => $spacing,
																	pos     => $pos,
																	block   => $divisions->{$spacing}{$pos}[0]};
		}
	}
	# division blocks
	return $sorted_divisions;
}

sub parse_position {
	my ($str,$pp,$min,$max) = @_;
	return unless defined $str;
	my @pos;
	for my $p (split(/\s*$COMMA\s*/,$str)) {
		$p = parse_value($p,$min,$max);
		push @pos, $p;
	}
	return @pos;
}

sub parse_spacing {
	my ($str,$pp,$min,$max) = @_;
	return unless defined $str;

	my $spacing = parse_value($str,$max-$min);

	if($spacing) {
		if(my $num_axes = ($max-$min)/$spacing > 1000) {
			fatal_error("track","too_many_axes",$spacing,$num_axes);
		}
	} else {
		return;
	}

	#fatal_error("track","division",$min,$max,$str) if ! $spacing;

	my $ystart = first_defined(seek_parameter("y0",@$pp),$min);
	my $yend   = first_defined(seek_parameter("y1",@$pp),$max);

	$ystart    = parse_value($ystart,$max-$min);
	$yend      = parse_value($yend,  $max-$min);

	my @ypos;
	my $TOL = $spacing/1000; # float roundoff causes problems without TOL
	for (my $y = $min; $y <= $max + $TOL; $y += $spacing) {
		next if $y < $ystart - $TOL;
		last if $y > $yend + $TOL;
		push @ypos, $y;
	}
	return @ypos;
}

################################################################
# Parse a relative value, given a range or min/max
#
# 0.1r from a range of 20
# parse_value($str,$range) -> 2
#
# 0.1r from a range 10-30
# parse_value($str,10,30) -> 12
#
# $min + parse_value($str,$max-$min) = parse_value($str,$min,$max)
#
sub parse_value {
	my ($value,@range) = @_;
	return if ! defined $value;
	if($value =~ /(.+)r$/) {
		if(@range == 2) {
	    my ($min,$max) = @range;
	    return $min + $1*($max-$min);
		} elsif (@range == 1) {
	    my ($range)    = @range;
	    return $1 * $range;
		} else {
	    die "wrong number of range arguments";
		}
	} else {
		return $value;
	}
}

1;
