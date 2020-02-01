
package linnet::axis;

use vars qw( $axes );
use strict;
use linnet::conf;
use linnet::segment;
use linnet::debug;

use Math::VecStat qw(sum);

# create the axis data structure
# - associate segments with axes
# - calculate segment and axis pixel length
# - assign start/end pixel position of axis
sub create {
  linnet::debug::printdebug();
  my $segments = shift;
  $axes = linnet::conf::getitem( "axes", "axis" );
  for my $aid ( get_ids($axes) ) {
    my $axis = $axes->{$aid};
    $axis->{id} = $aid;
    linnet::debug::printdie("axis [$aid] has no segments defined") unless $axis->{segments};
    my @axis_segment_ids =
      linnet::segment::select_by_rx( [ split( /\s*,\s*/, $axis->{segments} ) ], $segments );
    linnet::debug::printdie("axis [$aid] segment definition [$axis->{segments}] matches no segments.")
      if !@axis_segment_ids;
    $axis->{_segments} = \@axis_segment_ids;
    $axis->{_length} = sum( map { linnet::segment::get_by_id($_)->{_length} } @axis_segment_ids );
    linnet::debug::printdebug( 1, "axis created", $aid, "length", $axis->{_length}, "segments",
                               @axis_segment_ids );
  }

  # assign axis to each segment
  linnet::segment::assign_axis($axes);

  # compute the pixel length of each segment
  for my $aid ( get_ids($axes) ) {
    my $axis = $axes->{$aid};
    for my $sid ( get_segment_ids($axis) ) {
      linnet::segment::compute_pixel_length($sid);
    }
  }

  # compute the pixel length of each axis
  # compute x,y start/end positions of axis
  for my $aid ( get_ids($axes) ) {
    compute_pixel_length($aid);
    compute_pixel_ends($aid);
    my $axis = $axes->{$aid};
    for my $sid ( get_segment_ids($axis) ) {

      # compute x,y start/end positions of segments in an axis
      linnet::segment::compute_pixel_ends($sid);
    }
  }
  return $axes;
}

# compute pixel length of an axis
sub compute_pixel_length {
  linnet::debug::printdebug();
  my $aid          = shift;
  my $axis         = $axes->{$aid};
  my $pixel_length = 0;
  my $pix_spacing  = linnet::conf::getitem( "segments", "spacing" );
  for my $sid ( get_segment_ids($axis) ) {
    my $s = linnet::segment::get_by_id($sid);
    linnet::debug::printdebug( 2, "axis pixel length", $aid, "segment", $sid, $s->{_pixel_length} );
    $pixel_length += $s->{_pixel_length};
    $pixel_length += $pix_spacing;
  }
  $pixel_length -= $pix_spacing;
  $axis->{_pixel_length} = $pixel_length;
  linnet::debug::printdebug( 1, "axis pixel length", $aid, $axis->{_pixel_length} );
}

# compute the start and end x,y coordinates of an axis
sub compute_pixel_ends {
  linnet::debug::printdebug();
  my $aid          = shift;
  my $axis         = $axes->{$aid};
  my $pixel_length = $axis->{_pixel_length};
  linnet::debug::printdie("axis [$aid] pixel length is not defined.") if !defined $pixel_length;
  my $r0 = linnet::conf::getitem( "segments", "radius" );
  my ( $x0, $y0 ) = linnet::util::ra2xy( $r0, $axis->{angle} );
  my ( $x1, $y1 ) = linnet::util::ra2xy( $r0 + $axis->{_pixel_length}, $axis->{angle} );
  $axis->{xy}[ is_reversed($axis) ]  = [ $x0, $y0 ];
  $axis->{xy}[ !is_reversed($axis) ] = [ $x1, $y1 ];
  linnet::debug::printdebug( 1, "axis x0,y0", $aid, @{ $axis->{xy}[0] } );
  linnet::debug::printdebug( 1, "axis x1,y1", $aid, @{ $axis->{xy}[1] } );
}

# given an axis and a distance (intra-segment), compute the pixel distance
sub pixel_distance {
  linnet::debug::printdebug();
  my $axis       = shift;
  my $d          = shift;
  my @axis_sids  = get_segment_ids($axis);
  my $axis_scale = get_scale($axis);
  my $d_pix      = $axis_scale * linnet::util::d2pix($d);
  return $d_pix;
}

# given an axis, segment id and position on the segment, return
# the pixel xy position
sub xy_pos {
  linnet::debug::printdebug();
  my $axis     = shift;
  my $segments = shift;
  my $sid      = shift;
  my $pos      = shift;
  my $u        = $axis->{xy}[0];
  &main::printdie("axis [$axis->{id}] has no start point.") if !$u;
  my $t = t_pos( $axis, $segments, $sid, $pos );
  return [ map { $u->[$_] + $t } ( 0, 1 ) ];
}

# given an axis, segment id and position on the segment, return the
# parameterized pixel position (t=0..num_pixels) along the axis
#
# pixel_pos($axis,$segments,$sid,$pos)
#
# $d is the tangential offset
sub pixel_pos {
  linnet::debug::printdebug();
  my ( $aid, $sid, $pos, $d ) = @_;

  my $axis      = get_by_id($aid);
  my @axis_sids = get_segment_ids($axis);

  my $segment = linnet::segment::get_by_id($sid);
  my $t = $pos / $segment->{_length};
  
  # axis must have this segment
  if ( !has_segment_id( $axis, $sid ) ) {
    my $sids = join( ",", @axis_sids );
    linnet::debug::printdie("axis [$axis->{id}] does not contain segment [$sid] - it has segments [$sids]");
  }

  # the position must be within the segment
  if ( $pos - $segment->{start} < -$segment->{start}/1000 || $pos - $segment->{end} > $segment->{end}/1000) {
      linnet::debug::printdie("the position [$pos] is outside of the segment [$sid] on axis [$aid]. Segment range is [$segment->{start} to $segment->{end}]");
  }
  
  my ( $x0, $y0 ) = @{ $segment->{xy}[0] };
  my ( $x1, $y1 ) = @{ $segment->{xy}[1] };
  
  my ( $x, $y ) = ( $x0 + ( $x1 - $x0 ) * $t, $y0 + ( $y1 - $y0 ) * $t );
  
  my ($xoffset,$yoffset) = linnet::util::xyd2xy($x,$y,$d);
  
  #my $xc = linnet::conf::getitem( "image", "size" ) / 2;
  #my $yc = linnet::conf::getitem( "image", "size" ) / 2;
  #my $r = sqrt(($x - $xc)**2 + ($y - $yc)**2);
  #my $angle = $axis->{angle};
  #($x,$y) = linnet::util::rad2xy($r,$angle,$d);
  
  return ( $xoffset, $yoffset );
}

# get the scale of the axis, which is a function of
# - scale
# - scale_norm
# when called first, the scale is calculated using scale and scale_norm,
# and stored in _scale
sub get_scale {
  my $axis = shift;
  my $aid  = $axis->{id};
  if ( !defined $axis->{_scale} ) {
    linnet::debug::printdie(
                "cannot calculate scale for axis [$aid] because its length has not been calculated")
      unless defined $axis->{_length};
    linnet::debug::printdie("scale parameter for axis [$aid] must be >0.")
      unless !defined $axis->{scale} || linnet::util::is_positive( $axis->{scale} );
    my $axis_scale =
      ( $axis->{scale} || 1 ) * ( $axis->{scale_norm} || $axis->{_length} ) / $axis->{_length};
    $axis->{_scale} = $axis_scale;
  }
  return $axis->{_scale};
}

# determine whether the axis is reversed
sub is_reversed {
  my $axis = shift;
  return $axis->{reverse};
}

# get axis by id
sub get_by_id {
  my $id = shift;
  linnet::debug::printdie("axis with id [$id] does not exist.") unless defined $axes->{$id};
  return $axes->{$id};
}

# get ids of all axes
sub get_ids {
  return sort keys %$axes;
}

# verify that an axis has a segment with this id
sub has_segment_id {
  my $axis = shift;
  my $sid  = shift;
  return grep( $_ eq $sid, @{ $axis->{_segments} } );
}

# fetch all segment ids on axis
sub get_segment_ids {
  my $axis = shift;
  return @{ $axis->{_segments} };
}

# fetch all segments on axis
sub get_segments {
  my $axis     = shift;
  my $segments = shift;
  return map { $segments->{$_} } get_segment_ids($axis);
}

1;
