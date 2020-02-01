
#####################################################
# Color handling routines

package linnet::color;

use Math::Round qw(round);
use linnet::conf;

# From $CONF{colors}, allocate all RGB color definitions.
#
# triplets are RGB
# triplets+1 are RGB+alpha

sub allocate_colors {

  my $image            = shift;
  my $allocated_colors = 0;
  my $colors;

  for my $color ( sort keys %{ linnet::conf::getitem("colors") } ) {
    my $colorvalue = linnet::conf::getitem("colors",$color);
		# a color can refer to another color ... look up names
		# until the definition has no synonym
		while(defined linnet::conf::getitem("colors",$colorvalue)) {
			$colorvalue = linnet::conf::getitem("colors",$color);
		}
		linnet::debug::printdebug(2,"allocating",$color,$colorvalue);
		# color value must be an RGB triplet
		if($colorvalue !~ /^\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}/) {
			die "color definition for [$colorvalue] = $colorvalue is not an RGB triplet.";
		} 
    my @rgb = split( /[, ]+/, $colorvalue );
    if ( @rgb == 3 ) {
			$colors->{$color} = $image->colorResolve(@rgb);
    } elsif ( @rgb == 4 ) {
			$colors->{$color} = $image->colorAllocateAlpha(@rgb);
    };
  }

  # Automatically allocate colors with alpha values, if asked for.
  # The number of steps is determined by auto_alpha_steps in the
  # <image> block
  # Colors with alpha values have names COLOR_aN for N=1..num_steps
  # The alpha value (out of max 127) for step i is 127*i/(num_steps+1)
  #
  # For example, if the number of steps is 5, then for the color
  # chr19=153,0,204, the follow additional 5 colors will be
  # allocated (see full list with -debug)
  #
  # auto_alpha_color chr19_a1 153 0 204 21 17%
  # auto_alpha_color chr19_a2 153 0 204 42 33%
  # auto_alpha_color chr19_a3 153 0 204 64 50%
  # auto_alpha_color chr19_a4 153 0 204 85 67%
  # auto_alpha_color chr19_a5 153 0 204 106 83%
  #
	if ( linnet::conf::getitem("image","auto_alpha_steps")) {
		my @c = keys %$colors;
		for my $colorname (@c) {
			my @rgb = $image->rgb( $colors->{$colorname} );
			my $nsteps = linnet::conf::getitem("image","auto_alpha_steps");
			for my $i ( 1 .. $nsteps ) {
				my $alpha = round( 127 * $i / ( $nsteps + 1 ) );
				my $aname = $colorname . "_a$i";
				$colors->{$aname} = $image->colorAllocateAlpha( @rgb, $alpha );
				linnet::debug::printdebug(2,"allocated color auto",$aname,@rgb,"alpha",$alpha);
			}
		}
	}
  return $colors;
}

# Using the color name, return its opacity. The color does not
# have to be defined. 
#
# 0 - transparent
# 1 - opaque
#
sub get_coloropacity {
  my $color = shift;
  if ( $color =~ /(.+)_a(\d+)/ ) {
    if ( not linnet::conf::getitem( "image", "auto_alpha_steps" ) ) {
      &main::printdie(
"you are trying to process a transparent color [$color] but do not have auto_alpha_steps defined"
      );
    }
    my $color_root = $1;
    my $nsteps     = linnet::conf::getitem( "image", "auto_alpha_steps" );
    my $opacity    = 1 - $2 / $nsteps;
  }
  else {
    return 1;
  }
  return $opacity;
}


		# transparency is 1-opacity
#
# 0 - opaque
# 1 - transparent
sub get_colortransparency {
  my $color = shift;
  return 1 - get_coloropacity($color);
}
# 0 - opaque
# 127 - transparent
sub get_coloralpha {
	my $color = shift;
	return 127 * get_colortransparency($color);
}

# retrieve the @rgb and alpha value of a color
sub get_colorrgb {
	my ($color,$colors,$image) = @_;
	my $color_idx = $colors->{$color};
	if(! defined $color_idx) {
		&main::printdie("color [$color] is not defined.");
	} 
	else {
		return ($image->rgb($colors->{$color}),get_coloralpha($color));
	}
}


1;
