package Circos::Text;

=pod

=head1 NAME

Circos::Font - utility routines for text handling in Circos

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
text_angle_2
textoffset
textangle
textanglesvg
);

use Carp qw( carp confess croak );
use FindBin;
use GD::Image;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; # qw(%CONF $DIMS);
use Circos::Constants;
use Circos::Colors;
use Circos::Debug;
use Circos::Error;
use Circos::Font;
use Circos::Geometry;
use Circos::SVG;
use Circos::Image;
use Circos::Utils;

use Memoize;

for my $f ( qw ( ) ) {
memoize($f);
}

our $default_font_name  = "Arial";
our $default_font       = "default";
our $default_font_color = "black";

sub draw_text {
	my %params;
	my @args = remove_undef_keys(@_);
	if (fetch_conf("debug_validate")) {
		%params = validate( @args, 
												{
												 text      => 1,
												 font      => { default => fetch_conf("default_font") || $default_font },
												 size      => 1,
												 color     => { default => fetch_conf("default_font_color") || $default_font_color },
					
												 angle     => 1,
												 radius    => 1,
					
												 is_parallel => { default => 0 },
												 is_rotated  => { default => 1 },

												 rotation    => { default => 0 },
					
												 x_offset    => { default => 0 },
												 y_offset    => { default => 0 },
					
												 guides      => { default => 0 },

												 svg         => { optional => 1, type => HASHREF|UNDEF },
												 mapoptions  => { optional => 1, type => HASHREF },
												});
	} else {
		%params                = @args;
		$params{color}       ||= fetch_conf("default_font_color") || $default_font_color;
		$params{is_parallel} ||= 0;
		$params{x_offset}    ||= 0;
		$params{y_offset}    ||= 0;
	}
	$params{is_rotated} = not_defined_or_one($params{is_rotated});

	printdebug_group("text","label",map { $_,$params{$_} } (qw(text font size color angle radius is_rotated is_parallel rotation)));

	my $angle_quadrant = angle_quadrant($params{angle});    
	my $text_angle     = text_angle_2( angle       => $params{angle}, 
																		 is_rotated  => $params{is_rotated},
																		 is_parallel => $params{is_parallel} );

	if(my $label_rotation = $params{rotation}) {
		$text_angle += $label_rotation;
	}
	
	my ( $w, $h ) = get_label_size( text=>$params{text},size=>$params{size},font_file=>get_font_file_from_key($params{font}));
	
	my ($radius_offset,$angle_offset) = (0,0);
    
	# adjust angle
	if (! $params{is_parallel}) {
		my $offset = $RAD2DEG * $h/2 / $params{radius};
		if($params{rotation}) {
			$angle_offset += $RAD2DEG * $h * cos( $DEG2RAD * $params{rotation} ) / $params{radius};
		}
		if ($params{is_rotated}) {
			if ($angle_quadrant >= 2) {
				$angle_offset += - $offset;
	    } else {
				$angle_offset += $offset;
	    } 
		} else {
	    if ($angle_quadrant >= 2) {
				$angle_offset += $offset;
	    } else {
				$angle_offset += $offset;
	    } 
		}
	} else {
		my $offset = $RAD2DEG * $w/2 / $params{radius};
		if($params{rotation}) {
			$angle_offset += $RAD2DEG * $w * cos( $DEG2RAD * $params{rotation} ) / $params{radius};
		}
		if ($params{is_rotated}) {
	    if ($angle_quadrant == 0) {
				$angle_offset += -$offset;
	    } elsif ($angle_quadrant == 1 || $angle_quadrant == 2) {
				$angle_offset += $offset;
	    } else {
				$angle_offset += -$offset;
	    }
		} else {
	    $angle_offset += -$offset;
		}
	}

	# adjust radius
	if (! $params{is_parallel} ) {
		if ($params{is_rotated}) {
	    if ($angle_quadrant >= 2) {
				$radius_offset = $w;
	    }
		}
	} else {
		if ($params{is_rotated}) {
	    if ($angle_quadrant == 1 || $angle_quadrant == 2) {
				$radius_offset = $h;
	    }
		}
	}

	my ($x,$y) = getxypos( $params{angle}  + $angle_offset, 
												 $params{radius} + $radius_offset );

	if ($PNG_MAKE) {
		printdebug_group("text",
										 "labelpng",
										 "text",$params{text},
										 "x,y",(map { round_custom($_,"round") } $x,$y),
										 "angle,quadrant,offset",$params{angle},$angle_quadrant,$angle_offset,
										 "textangle",$text_angle,
										 "radius,offset",$params{radius},$radius_offset,
										 "w,h",(map { round_custom($_,"round") } $w,$h),
										);

		my @bounds = $IM->stringFT( fetch_color($params{color},$COLORS),
																get_font_file_from_key($params{font}),
																$params{size},
																$text_angle * $DEG2RAD,
																$x,$y,
																$params{text});

		if ($MAP_MAKE) {
			if($params{mapoptions}{url}) {
				my $xshift = $CONF{image}{image_map_xshift}||0;
				my $yshift = $CONF{image}{image_map_xshift}||0;
				my $xmult  = $CONF{image}{image_map_xfactor}||1;
				my $ymult  = $CONF{image}{image_map_yfactor}||1;
				my @coords = map { ( $_->[0]*$xmult + $xshift , $_->[1]*$ymult + $yshift ) } ([@bounds[0,1]],
																																											[@bounds[2,3]],
																																											[@bounds[4,5]],
																																											[@bounds[6,7]]);
				Circos::report_image_map(shape=>"poly",
																 coords=>\@coords,
																 href=>$params{mapoptions}{url});
			}
		}
	}

	if ($SVG_MAKE) {
		Circos::SVG::draw_text(%params,
													 svg         => undef,
													 attr        => $params{svg}{attr},
													 angle_offset=> $angle_offset);
	}

	if ($params{guides}) {
		my @bounds = string_ttf(font_file => get_font_file_from_key($params{font}),
														size      => $params{size},
														angle     => $text_angle * $DEG2RAD,
														x         => $x, 
														"y"       => $y,
														text      => $params{text});
		my $guide_size = fetch_conf("guides","size");
		my $color      = fetch_conf("guides","color","text") || fetch_conf("guides","color","default");
		my $thickness  = fetch_conf("guides","thickness") || 1;
		my $guide_type = fetch_conf("guides","type");
		if(! defined $guide_type || $guide_type =~ /cross|hatch|position/) {
			Circos::draw_line( [$x-$guide_size,$y,$x+$guide_size,$y],$thickness,$color );
			Circos::draw_line( [$x,$y-$guide_size,$x,$y+$guide_size],$thickness,$color );
		}
		if(! defined $guide_type || $guide_type =~ /outline|box/) {
			Circos::draw_line( [$bounds[6],$bounds[7],$bounds[4],$bounds[5]],$thickness, $color );
			Circos::draw_line( [$bounds[4],$bounds[5],$bounds[2],$bounds[3]],$thickness, $color );
			Circos::draw_line( [$bounds[2],$bounds[3],$bounds[0],$bounds[1]],$thickness, $color );
			Circos::draw_line( [$bounds[0],$bounds[1],$bounds[6],$bounds[7]],$thickness, $color );
		}
	}
}

sub text_angle_2 {
    my %params;
    if(fetch_conf("debug_validate")) {
	%params = validate(@_,
			   {
			       angle       => 1,
			       is_parallel => { default => 0 },
			       is_rotated  => { default => 0 },
			   });
    } else {
	%params = @_;
	$params{is_parallel} ||= 0;
	$params{is_rotated}  ||= 0;
    }

    my $angle = $params{angle};
    my $angle_quadrant = angle_quadrant($angle);
    my $textangle;
    if($angle_quadrant == 0) {
	$textangle = -$angle;
    } else {
	$textangle = 360 - $angle;
    }

    if($params{is_rotated}) {
	if($angle_quadrant >= 2) {
	    $textangle += 180;
	}
    }
    if( $params{is_parallel} ) {
	if($params{is_rotated}) {
	    if($angle_quadrant == 1) {
		$textangle += 90;
	    } elsif ($angle_quadrant == 3 ) {
		$textangle += 90;
	    } else {
		$textangle -= 90;
	    }
	} else {
	    $textangle -= 90;
	}
    }
    return $textangle;
}

# -------------------------------------------------------------------
sub textoffset {
  #
  # Drawing text with baseline parallel to radius requires that the
  # angle position be offset to maintain alignment of text to the
  # desired angle position. To make the centerline of the text align
  # with the desired text position, the text angle is offset (-'ve)
  # by an appropriate amount.
  #
  # The input angle is the angular position of the text, not the
  # angle to which the text is rotated.
  #
  # returns the appropriate angle/radius correction
  # - delta_angle
  # - delta_radius

  my ( $angle, $radius, $label_width, $label_height, $height_offset, $is_parallel, $no_rotation ) = @_;
  $height_offset ||= 0;
  my $angle_offset = 0;
  if($is_parallel) {
      if($angle < 0 || ( $angle > 90 && $angle < 180)) {
	  $angle_offset    = - $RAD2DEG * ( ( $label_width / 2 ) / $radius );
      } else {
	  $angle_offset    = $RAD2DEG * ( ( $label_width / 2 ) / $radius );
      }
  } else {
      $angle_offset    = $RAD2DEG * ( ( $label_height / 2 + $height_offset ) / $radius );
  }
  my $radius_offset = $label_width - 1;
  $angle = anglemod($angle);
  if($is_parallel) {
      if ($angle < 0 ) {
	  $radius_offset = 0;
      } elsif ($angle > 0 && $angle < 180) {
	  # v0.55 - height should be used, not width
	  $radius_offset = $label_height; #$label_width;
      } else {
	  $radius_offset = 0;
      }
  }
  # returns $angle_offset $radius_offset
  if($no_rotation) {
      return ( $angle_offset, !$is_parallel ? 0 : $radius_offset );
  } else {
      if ( $angle > 90 && $angle < 270 ) {
	  return ( -$angle_offset, $radius_offset );
      } else {
	  return ( $angle_offset, !$is_parallel ? 0 : $radius_offset );
      }
  }
}

# -------------------------------------------------------------------
sub anglemod {
  #
  # Given an an angle, return the angle of rotation of corresponding
  # text label. The angle is adjusted so that text is always
  # right-side up.
  #
  # The angle is purposed for text rotation using GD's stringFT.
  #
  # SVG rotates text in the opposite direction from GD, and this is
  # handled elsewhere.
  #
  my $angle = shift;

  if ( $angle < 0 ) {
    $angle += 360;
  } elsif ( $angle > 360 ) {
    $angle -= 360;
  }

  return $angle;
}

################################################################
# Given an angle, determine the rotation of text that will make
# the text perpendicular to the angle.
#
# If $rotate=1, then the text will be parallel to the angle.
#
sub textangle {
  my ($angle,$is_parallel,$no_rotation) = @_;
  $angle = anglemod($angle);
  my $textangle;
  if($no_rotation) {
      $textangle = 360 - $angle;
  } else {
      if ( $angle <= 90 ) {
	  $textangle = 360 - $angle;
      } elsif ( $angle < 180 ) {
	  $textangle = 180 - $angle;
      } elsif ( $angle < 270 ) {
	  $textangle = 360 - ( $angle - 180 );
      } else {
	  $textangle = 360 - $angle;
      }
  }
  if($is_parallel) {
    # v0.52 if the ideogram label is to be parallel to the ideogram by setting
    # label_parallel = yes
    # then the text direction is adjusted    
    my $oldtextangle = $textangle;
    if($oldtextangle <= 90 && $oldtextangle >= 0) {
      $textangle -= 90;
    } elsif ($oldtextangle >= 270) {
      $textangle += 90;
    }
  }
  return $textangle;
}

# -------------------------------------------------------------------
sub textanglesvg {
  my ($angle,$is_parallel) = @_;

  #$angle = $angle % 360;
  my $svgangle = 360 - textangle($angle,$is_parallel);

  #$svgangle += 0.01 if $svgangle == 90;
  return $svgangle;
}

1;
