
package linnet::util;

use strict;
use Set::IntSpan;
use Math::Round;
use Math::VecStat qw(min);
use Math::Trig;
use IO::File;
use Readonly;

use linnet::debug;
use linnet::image;

Readonly my $DEG2RAD => 0.0174532925;
Readonly my $RAD2DEG => 57.29577951;

sub makespan {
  my ( $x, $y ) = @_;
  if ( !defined $y ) {
    return Set::IntSpan->new($x);
  }
  else {
    if ( $x > $y ) {
      &main::printdie("Tried to create a span with end < start [$x,$y]");
    }
    elsif ( $x == $y ) {
      return Set::IntSpan->new($x);
    }
    else {
      return Set::IntSpan->new( sprintf( "%d-%d", $x, $y ) );
    }
  }
}

sub parseoptions {
  my $str     = shift;
  my @options = split( /\s*,\s*/, $str );
  my $options = {};
  for my $optionpair (@options) {
    my ( $var, $value ) = split( /\s*=\s*/, $optionpair );
    if ( defined $options->{$var} ) {
      &main::printdie("option [$var] has multiple definitions");
    }
    $options->{$var} = $value;
  }
  return $options;
}

sub tolist {
  my $x = shift;
  if ( ref($x) eq "ARRAY" ) {
    return @$x;
  }
  else {
    return ($x);
  }
}

# given a distance in native units, convert to pixels
# - scale parameters are not included
sub d2pix {
  my $d = shift;
  return $d / linnet::conf::getitem( "scale", "pixsize" );
}

# return (x,y) coordinate for a given (radius,angle)
#     0
# 270 + 90
#    180
#
# optionally, provide the origin
sub ra2xy {
  my ( $radius, $angle, $xc, $yc ) = @_;
  if ( !defined $xc || !defined $yc ) {
    ( $xc, $yc ) = linnet::image::get_center();
  }
  $angle = angle_rotccw($angle);
  my $cos = cos( deg2rad($angle) );
  my $sin = sin( deg2rad($angle) );
  my ( $x, $y ) = ( $cos * $radius, $sin * $radius );
  return map { round $_ } ( $x + $xc, $y + $yc );
}

# return (x,y) coordinate for a given (radius,angle,tangent distance)
#     0
# 270 + 90
#    180
#
#         distance
#       |---X
#      |
#     | radius
#    |
#   |angle
#  |--------
#
sub rad2xy {
  my ( $radius, $angle, $distance ) = @_;
  my ( $xc, $yc ) = linnet::image::get_center();
  my ( $x, $y ) = ra2xy( $radius, $angle );
  my $dx = $distance * cos( deg2rad($angle) );
  my $dy = $distance * sin( deg2rad($angle) );

  #my $radius_new = sqrt( $radius**2 + $distance**2 );
  #my $angle_new  = angle_remap( $angle + $RAD2DEG * atan2( $distance, $radius ) );
  #my $cos        = cos( $DEG2RAD * $angle_new );
  #my $sin        = sin( $DEG2RAD * $angle_new );
  #my ( $x, $y ) = ( $cos * $radius_new, $sin * $radius_new );
  return map { round $_ } ( $x + $dx, $y + $dy );
}

# return radius,angle for a given x,y
# optionally xc,yc are provided as an origin
# angle is in degrees
#     0
# 270 + 90
#    180
sub xy2ra {
  my ( $x, $y, $xc, $yc ) = @_;
  if ( !defined $xc || !defined $yc ) {
    ( $xc, $yc ) = linnet::image::get_center();
  }
  my $dx = defined $xc ? $x - $xc : $x;
  my $dy = defined $yc ? $y - $yc : $y;
  my $r  = sqrt( $dx**2 + $dy**2 );
  my $angle = rad2deg( atan2( $dy, $dx ) );
  return ( $r, angle_rotcw($angle) );
}

# given a position x,y and optional center xc,yc
# return position xnew,ynew that is formed by
# moving distance d perpendicularly to (x,y)-origin
#
# d>0 - clockwise
# d<0 - counterclockwise
sub xyd2xy {
  my ( $x, $y, $d, $xc, $yc, $rotation_angle ) = @_;
  return ( $x, $y ) if !$d;
  if ( !defined $xc || !defined $yc ) {
    ( $xc, $yc ) = linnet::image::get_center();
  }
  $rotation_angle = 90 if !defined $rotation_angle;
  my ( $radius, $angle ) = linnet::util::xy2ra( $x, $y, $xc, $yc );
  $angle = angle_rotate( $angle, $rotation_angle );
  my ( $xnew, $ynew ) = ra2xy( $d, $angle, $x, $y );
  return ( $xnew, $ynew );

}

# given two angles, return the angle that bisects them
sub anglemiddle {
  my ( $a1, $a2 ) = @_;
  my $middleangle =
    abs( $a2 - $a1 ) > 180
    ? ( $a1 + $a2 + 360 ) / 2 - 360
    : ( $a2 + $a1 ) / 2;
  return $middleangle;
}

# given two angles a1,a2 return 1 if the
# closest distance is +'ve (clockwise) or
# -1 if closest distance is -'ve (counterclockwise)
sub angleorient {
  my ( $a1, $a2 ) = @_;
	my $da = get_aa_distance($a1,$a2);
	return $da > 0 ? 1 : -1;
  $a1 = 180 + abs($a1) if $a1 < 0;
  $a2 = 180 + abs($a2) if $a2 < 0;
  # ($a1,$a2) = sort {$b <=> $a} ($a1,$a2);
  if ( $a2 > $a1 ) {
    if ( $a2 - $a1 < ( 360 - $a2 ) + $a1 ) {
      return 1;
    }
    else {
      return -1;
    }
  }
  else {
    if ( $a1 - $a2 < ( 360 - $a1 ) + $a2 ) {
      return -1;
    }
    else {
      return 1;
    }
  }

}

sub get_xyxy_middle {
  my ( $x1, $y1, $x2, $y2 ) = @_;
  return ( ( $x1 + $x2 ) / 2, ( $y1 + $y2 ) / 2 );
}

sub get_xyxy_distance {
  my ( $x1, $y1, $x2, $y2 ) = @_;
  return sqrt( ( $x1 - $x2 )**2 + ( $y1 - $y2 )**2 );
}

sub get_xyxy_ra {
  my ( $x1, $y1, $x2, $y2, $xc, $yc ) = @_;
  if ( !defined $xc || !defined $yc ) {
    ( $xc, $yc ) = linnet::image::get_center();
  }
  my ( $r1, $a1 ) = xy2ra( $x1, $y1, $xc, $yc );
  my ( $r2, $a2 ) = xy2ra( $x2, $y2, $xc, $yc );

  my $da = get_aa_distance( $a2, $a1 );

  return ( $r2 - $r1, $da );
}

sub get_aa_distance {
  my ( $a1, $a2 ) = @_;
  my @v = ( $a2 - $a1, $a2 - $a1 + 360, $a2 - $a1 - 360 );
  my ( $min, $minat ) = min( map { abs($_) } @v );
  return $v[$minat];
}

sub bezier_crest {
	my ( $x1, $y1, $x2, $y2, $crest ) = @_;
	
	my ( $r1, $a1 ) = xy2ra( $x1, $y1 );
  my ( $r2, $a2 ) = xy2ra( $x2, $y2 );
  my $angleo = linnet::util::angleorient( $a1, $a2 );
	#linnet::debug::printdebug(1,"crest",map { sprintf("%.0f", $_)}$a1,$a2,$angleo);
	my $d = get_xyxy_distance($x1,$y1,$x2,$y2);
	$crest = min($d/4,$crest);
	my $c1 = [xyd2xy($x1,$y1,$crest*$angleo)];
	my $c2 = [xyd2xy($x2,$y2,-$crest*$angleo)];
	return ($c1,$c2);
}

sub bezier_control {
  my ( $x1, $y1, $x2, $y2, $k ) = @_;
  my ( $px, $py );

  my ( $r1, $a1 ) = xy2ra( $x1, $y1 );
  my ( $r2, $a2 ) = xy2ra( $x2, $y2 );

  my ( $dr, $da ) = get_xyxy_ra( $x1, $y1, $x2, $y2 );

  my $anglem = linnet::util::anglemiddle( $a1, $a2 );
  my $angleo = linnet::util::angleorient( $a1, $a2 );

  my $pr = ( $r1 + $r2 ) / 2;

  # modify the radius based on the angle distance
  if ( defined $k ) {
    $pr *= ( 1 + ( abs($da) / 180 )**$k );
  }
  return ra2xy( $pr, $anglem );

}

#
# given a list of control points for a bezier curve, return
# $CONF{beziersamples}
# points on the curve as a list
#
# ( [x1,y1], [x2,y2], ... )
#
sub bezier_points {
  my @control_points = @_;
  my $bezier         = Math::Bezier->new(@control_points);
  my @points         = $bezier->curve(40);
  my @bezier_points;
  while (@points) {
    push @bezier_points, [ splice( @points, 0, 2 ) ];
  }
  return @bezier_points;
}

# global angle remapping
sub angle_remap {
  my $angle    = shift;
  my $rotation = shift;

  #$angle -= 90;
  return angle_wrap($angle);
}

# rotate angle counter-clockwise by 90deg
sub angle_rotccw {
  my $angle = shift;

  # nested call keeps the angle within [0,360)
  my $new_angle = angle_wrap( $angle - 90 );
  return angle_remap($new_angle);
}

# rotate angle clockwise by 90deg
sub angle_rotcw {
  my $angle     = shift;
  my $new_angle = angle_wrap( $angle + 90 );
  return angle_remap($new_angle);
}

sub angle_rotate {
  my ( $angle, $rotation ) = @_;
  my $new_angle = angle_wrap( $angle + $rotation );
  return $new_angle;
}

# nested call to rad/deg conversion keeps the angle within [0,360)
sub angle_wrap {
  my $angle = shift;
  return rad2deg( deg2rad($angle) );
}

sub is_positive {
  my $x = shift;
  return defined $x && $x > 0;
}

sub open_file {
  my $filename = shift;
  linnet::debug::printdie("file [$filename] cannot be found.")            unless -e $filename;
  linnet::debug::printdie("file [$filename] exists, but cannot be read.") unless -r $filename;
  my $fh = IO::File->new($filename);
  linnet::debug::printdie(
                    "file [$filename] could be read, but there was a problem getting a filehandle.")
    unless defined $fh;
  return $fh;
}

1;
