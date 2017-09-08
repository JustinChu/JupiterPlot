package Circos::Geometry;

=pod

=head1 NAME

Circos::Geometry - utility routines for Geometry in Circos

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
our @EXPORT = qw(
getxypos
angle_quadrant
getu
);

use Carp qw( carp confess croak );
use FindBin;
use GD::Image;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; # qw(%CONF $DIMS fetch_conf);
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;

use Memoize;

for my $f ( qw ( angle_quadrant ) ) {
memoize($f);
}

################################################################
# given an angle, get the xy position for a certain radius
#
sub getxypos {
	if(! defined $_[0] || ! defined $_[1]) {
		fatal_error("geometry","bad_angle_or_radius",$_[0],$_[1]);
	}
	#return (10*$_[0],$_[1]);
	return (
					$DIMS->{image}{radius} + $_[1] * cos( $_[0] * $DEG2RAD ),
					$DIMS->{image}{radius} + $_[1] * sin( $_[0] * $DEG2RAD )
				 );
}

sub angle_quadrant {
	my $angle = shift;
	# added tests in 0.56-2
	while($angle < -90) { $angle += 360; }
	while($angle > 270) { $angle -= 360; }
	
	if($angle < -90 || $angle > 270) {
		fatal_error("geometry","angle_out_of_bounds",$angle);
	} else {
		if($angle <= 0) {
	    return 0;
		} elsif ($angle <= 90) {
	    return 1;
		} elsif ($angle <= 180) {
	    return 2;
		} else {
	    return 3;
		}
	}
}

sub getu {
	my ( $x1, $y1, $x2, $y2, $x3, $y3 ) = @_;
	my $x21 = $x2 - $x1;
	my $y21 = $y2 - $y1;
	my $u =	( ( $x3 - $x1 ) * $x21 + ( $y3 - $y2 ) * $y21 ) / ( $y21**2 + $x21**2 );
	my $x = $x1 + $u * $x21;
	my $y = $y1 + $u * $y21;
	return ( $x, $y, $u );
};

1;
