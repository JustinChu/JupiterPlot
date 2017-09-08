package Circos::Image;

=pod

=head1 NAME

Circos::Image - utility routines for bitmap images and drawing in Circos

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

our @EXPORT_OK = qw($IM $COLORS $PNG_MAKE $SVG_MAKE $MAP_MAKE draw_line);
our @EXPORT = qw(
$IM
$COLORS
$PNG_MAKE
$SVG_MAKE
$MAP_MAKE
draw_line
);

use Carp qw( carp confess croak );
use FindBin;
use GD::Image;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; 
use Circos::Colors;
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;

our ($IM,$COLORS,$PNG_MAKE,$SVG_MAKE,$MAP_MAKE);

our $default_color = "black";

sub draw_line {
	my ($points, $thickness, $color, $svg) = @_;

	$color ||= fetch_conf("default_color") || $default_color;

	if($PNG_MAKE) {
		Circos::PNG::draw_line( points    => $points,
														thickness => $thickness,
														color     => $color );
		
	}
	if($SVG_MAKE) {
		Circos::SVG::draw_line( points    => $points,
														thickness => $thickness,
														color     => $color,
														attr      => $svg->{attr},
													);
	}
}

1;
