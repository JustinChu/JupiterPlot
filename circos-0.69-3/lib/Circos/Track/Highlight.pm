package Circos::Track::Highlight;

=pod

=head1 NAME

Circos::Track::Highlight - routines for highlight tracks in Circos

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
use GD::Image;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; # qw(%CONF $DIMS);
use Circos::Constants;
#use Circos::Colors;
use Circos::Debug;
use Circos::Image;
use Circos::Error;
#use Circos::Font;
#use Circos::Geometry;
#use Circos::SVG;
#use Circos::Image;
use Circos::Unit;
use Circos::Utils;
use Circos::URL;

use Memoize;

for my $f ( qw ( ) ) {
memoize($f);
}

# -------------------------------------------------------------------
sub draw_highlights {
  # Draw hilight data for a given ideogram. If a test
  # is included, then only highlights whose options pass
  # the test will be drawn.
  #
  # The test is a hash of variable=>value pairs.

  my ( $tracks, $default, $chr, $set, $ideogram, $test ) = @_;

  for my $track ( sort { $a->{z} <=> $b->{z} } @$tracks ) {
		my @param_path = ($track,$default);
		next unless $track->{__data};
		my $track_id = $track->{id};
		my $svg_header_done;
   # create a working list of highlights at a given z-depth
		for my $datum ( sort {$a->{param}{z} <=> $b->{param}{z} } @{$track->{__data}} ) {

      next unless $datum->{data}[0]{chr} eq $chr;

			#my $intersection = $datum->{data}[0]{set}->intersect( $Circos::KARYOTYPE->{$chr}{chr}{display_region}{accept} );
			# call to old routine
			#my $intersection = Circos::filter_data($datum->{data}[0]{set},$chr);
			#next unless $intersection->cardinality;

			# intersect the data point with the current ideogram's extent
			my $intersection = $datum->{data}[0]{set}->intersect( $set );
			next unless $intersection->cardinality;

			my $r0  = seek_parameter( "r0", $datum, @param_path );
			my $r1  = seek_parameter( "r1", $datum, @param_path );
			$r0 = unit_parse( $r0, $ideogram );
			$r1 = unit_parse( $r1, $ideogram );

			my $accept = 1;
			if ($test) {
				for my $param ( keys %$test ) {
					my $value = seek_parameter( $param, $datum, @param_path ) || 0;
					$accept &&= $value == $test->{$param};
				}
			}
			next unless $accept;

			if ( seek_parameter( "ideogram", $datum, @param_path ) ) {
				$r0 = $DIMS->{ideogram}{ $ideogram->{tag} }{radius_inner};
				$r1 = $DIMS->{ideogram}{ $ideogram->{tag} }{radius_outer};
			} else {
				my $offset = seek_parameter( "offset", $datum, @param_path );
				$r0 += $offset if $offset;
				$r1 += $offset if $offset;
			}

			my $url = seek_parameter( "url", $datum, @param_path );
			$url    = format_url(url=>$url,param_path=>[ $datum, @param_path]);

			for my $subset ( $intersection->sets) {
				if(! $svg_header_done++) {
					Circos::printsvg(qq{<g id="highlight$track_id">}) if $SVG_MAKE;
				}
				Circos::slice(
											image       => $IM,
											start       => $subset->min,
											end         => $subset->max,
											chr         => $datum->{data}[0]{chr},
											radius_from => $r0,
											radius_to   => $r1,
											edgecolor   => seek_parameter("stroke_color", $datum, @param_path),
											edgestroke  => seek_parameter("stroke_thickness", $datum, @param_path),
											fillcolor   => seek_parameter("fill_color", $datum, @param_path),
											mapoptions  => { url => $url },
										 );
			}
		}
		if($svg_header_done) {
			Circos::printsvg(qq{</g>}) if $SVG_MAKE;
		}
	}
}

1;
