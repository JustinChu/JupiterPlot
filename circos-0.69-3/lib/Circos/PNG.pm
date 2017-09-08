package Circos::PNG;

=pod

=head1 NAME

Circos::PNG - PNG routines for PNG in Circos

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
use Math::VecStat qw(min max);
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration;
use Circos::Colors;
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Image qw(!draw_line);
use Circos::Utils;

use Memoize;

our $default_color = "black";

for my $f ( qw ( ) ) {
  memoize($f);
}

################################################################
# Draw a line

sub draw_arc {
  my %params;
  if( fetch_conf("debug_validate") ) {
		%params = validate(@_,{
													 point            => { type    => ARRAYREF },
													 width            => 1,
													 height           => 0,
													 angle_start      => { default => 0 },
													 angle_end        => { default => 360 },
													 stroke_color     => 0,
													 stroke_thickness => 0,
													 color            => 0,
													});
  } else {
		%params = @_;
		$params{angle_start}      ||= 0;
		$params{angle_end}        ||= 360;
  }
  $params{height} ||= $params{width};
  if(@{$params{point}} != 2) {
		fatal_error("argument","list_size",current_function(),current_package(),2,int(@{$params{point}}));
  }
  printdebug_group("png","arc",@{$params{point}},@params{qw(width height angle_start angle_end)});

  # first fill the arc
  if(my $color = $params{color}) {
		#printinfo($color);
		my $color_obj = aa_color($color,$IM,$COLORS);
		if($params{angle_start} == 0 && $params{angle_end} == 360 && rgb_color_opacity($color) !=1) {
			my $sections = 2*max(3,$params{width},$params{height});
			# approximate a circle with a polygon, since GD's filledArc and filledEllipse
			# don't work well with transparent colors
			my $poly = new GD::Polygon;
			my ($x,$y)   = @{$params{point}};
			my ($rx,$ry) = map { $_/2 } @params{qw(width height)};
			for my $i (0..$sections-1) {
				my $angle = 2*$PI*$i/$sections;
				$poly->addPt($x + $rx * cos($angle),
										 $y + $ry * sin($angle));
			}
			draw_polygon(polygon=>$poly,
									 color=>$params{stroke_color},
									 fill_color=>$params{color});
			#$IM->filledEllipse(@{$params{point}},@params{qw(width height)},$color_obj);
		} else {
			$IM->filledArc(@{$params{point}},@params{qw(width height angle_start angle_end)},$color_obj);
		}

  }
  # stroke the arc
  stroke($params{stroke_thickness},$params{stroke_color},"arc",@{$params{point}},@params{qw(width height angle_start angle_end)});
}

sub draw_polygon {
  my %params;
  if( fetch_conf("debug_validate") ) {
		%params = validate(@_,{
													 polygon          => 1,
													 color            => 0, # fetch_conf("default_color") || $default_color,
													 thickness        => 0,
													 pattern          => 0,
													 fill_color       => 0,
													});
  } else {
		%params = @_;
		#$params{color} ||= fetch_conf("default_color") || $default_color;
  }

  printdebug_group("png","polygon",map {@$_} $params{polygon}->vertices);

  if($params{pattern}) {
		my ($color_idx,$tile);
		if ($params{fill_color} ) {
			$tile = Circos::fetch_colored_fill_pattern($params{pattern},$params{fill_color});
		} elsif ($params{pattern}) {
			$tile = Circos::fetch_fill_pattern($params{pattern});
		}
		if (defined $tile) {
			$IM->setTile($tile);
			$IM->filledPolygon($params{polygon},gdTiled);
		}
  } elsif ($params{fill_color} && ref $params{polygon} eq "GD::Polygon") {
		my $color_obj = aa_color( $params{fill_color}, $IM, $COLORS );
		$IM->filledPolygon($params{polygon},$color_obj);
  }
  stroke($params{thickness},$params{color},"polydraw",$params{polygon});
}

sub draw_line {
  my %params;
  if( fetch_conf("debug_validate") ) {
    %params = validate(@_,{
													 points           => { type    => ARRAYREF },
													 color            => { default => fetch_conf("default_color") || $default_color  },
													 thickness        => { default => 1 },
		       });
  } else {
      %params = @_;
      $params{color}            ||= fetch_conf("default_color") || $default_color;
      $params{thickness}        ||= 1;
  }
  
  if(@{$params{points}} != 4) {
      fatal_error("argument","list_size",current_function(),current_package(),4,int(@{$params{points}}));
  }
  
  printdebug_group("png","line",@{$params{points}},$params{color},$params{thickness});

  stroke($params{thickness},$params{color},"line",@{$params{points}});
}

# -------------------------------------------------------------------
sub draw_bezier {
  my %params;
  if( fetch_conf("debug_validate") ) {
    %params = validate(@_,{
													 points           => { type    => ARRAYREF },
													 color            => { default => fetch_conf("default_color") || $default_color  },
													 thickness        => { default => 1 },
													});
  } else {
		%params = @_;
		$params{color}            ||= fetch_conf("default_color") || $default_color;
		$params{thickness}        ||= 1;
  }
  
  if ( $params{thickness} > 100 ) {
		fatal_error("links","too_thick",$params{thickness});
  } elsif ( $params{thickness} < 1 ) {
		fatal_error("links","too_thin",$params{thickness});
  }
  
  # In the current implementation of gd (2.0.35) antialiasing is
  # incompatible with thick lines and transparency. Thus, antialiased lines
  # are available only when thickness=1 and the color has no alpha channel.
	
  printdebug_group("link","thickness",$params{thickness},"color",$params{color});
	
  my $bezier_poly_line = GD::Polyline->new();
  for my $point ( @{$params{points}} ) {
		$bezier_poly_line->addPt(@$point);
  }
  stroke($params{thickness},$params{color},"polydraw",$bezier_poly_line);
}

# applies a stroke to a GD object drawn by function $fn
# added on island of Capri :)
sub stroke {
	my ($st,$sc,$fn,@args) = @_;
	return unless $st;
	return unless $sc;
	my $color_obj;
	$sc ||= fetch_conf("default_color") || $default_color;
	my ($b,$bc,$buse);
	if(fetch_conf("anti_aliasing") && $st == 1 && rgb_color_opacity($sc) == 1) {
		$IM->setAntiAliased(fetch_color($sc));
		$color_obj = gdAntiAliased;
	} else {
		# When the element is thicker than round_brush_min_thickness, use a round brush instead
		# of the default square one. This fixes jaggies on thick links.
		$buse = fetch_conf("round_brush_use") && $st >= fetch_conf("round_brush_min_thickness");
		if($buse) {
			($b,$bc) = Circos::fetch_brush($st,$st,$sc);
			$IM->setBrush($b);
		} else {
			$IM->setThickness($st) if $st > 1;
		}
		$color_obj = fetch_color($sc);
	}
	if($buse) {
		$IM->$fn(@args,gdBrushed);
	} else {
		$IM->$fn(@args,$color_obj);
		$IM->setThickness(1) if $st > 1;
	}
}

1;
