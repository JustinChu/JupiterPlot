
package linnet::segment;

# segments are stored in a package variable - to fetch
# them use linnet::segment::get_segments()
use vars qw( $segments );

use strict;
use linnet::util;
use linnet::debug;
use Set::IntSpan;

# Read segment file
# id start end name color options
sub read {
  linnet::debug::printdebug();
  my $file = shift;
  my $fh   = linnet::util::open_file($file);
  while (<$fh>) {
    chomp;
    my @tok = split;
    if ( @tok < 5 || @tok > 6 ) {
      linnet::debug::printdie("segment file must be either 5 or 6 columns.");
    }
    my ( $id, $start, $end, $name, $color, $options ) = @tok;
    my $s = {
              id      => $id,
              start   => $start,
              end     => $end,
              set     => linnet::util::makespan( $start, $end ),
              color   => $color,
              scale   => 1,
              reverse => 0,
              options => linnet::util::parseoptions($options),
              idx     => int( values %$segments ),
            };
    $s->{_length} = $s->{set}->cardinality;
    if ( defined $segments->{id} ) {
      linnet::debug::printdie("Segment with id [$id] has multiple definitions.");
    }
    linnet::debug::printdebug( 1, "created segment", $id );
    $segments->{$id} = $s;
  }
  linnet::debug::printdie("no segments were read from input file [$file]") unless $segments;
  $fh->close();
  return $segments;
}

sub process {
  assign_scale();
  assign_reverse();
}

# calculate x,y pixel coordinates of segment ends
sub compute_pixel_ends {
  linnet::debug::printdebug();
  my $sid  = shift;
  my $s    = $segments->{$sid};
  my $axis = linnet::axis::get_by_id( get_axis($s) );

  # compute pixel position of start and end of segments
  my ($r0,$dir);
  if ( linnet::axis::is_reversed($axis) ) {
    $r0 = linnet::conf::getitem( "segments", "radius" ) + $axis->{_pixel_length};
		$dir = -1;
  }
  else {
    $r0 = linnet::conf::getitem( "segments", "radius" );
		$dir = 1;
  }
  my $pix_spacing = linnet::conf::getitem( "segments", "spacing" );
  for my $axis_segment_id ( linnet::axis::get_segment_ids($axis) ) {
    linnet::debug::printdebug( 2, "segment", $axis_segment_id, $r0 );
    my $axis_segment = $segments->{$axis_segment_id};
    if ( $axis_segment_id eq $sid ) {
      my ( $x0, $y0 ) = linnet::util::ra2xy( $r0, $axis->{angle} );
      my ( $x1, $y1 ) = linnet::util::ra2xy( $r0 + $dir * $axis_segment->{_pixel_length}, $axis->{angle} );
      $axis_segment->{xy}[ is_reversed($s) ]  = [ $x0, $y0 ];
      $axis_segment->{xy}[ !is_reversed($s) ] = [ $x1, $y1 ];
      linnet::debug::printdebug( 1, "segment x0,y0", $sid, @{ $axis_segment->{xy}[0] } );
      linnet::debug::printdebug( 1, "segment x1,y1", $sid, @{ $axis_segment->{xy}[0] } );
      return;
    }
    else {
      $r0 += $dir * $axis_segment->{_pixel_length};
      $r0 += $dir * $pix_spacing;
    }
  }
  linnet::debug::printdie("could not calculate pixel ends for segment [$sid]");
}

# calculate the pixel length of a segment
sub compute_pixel_length {
  linnet::debug::printdebug();
  my $sid  = shift;
  my $s    = $segments->{$sid};
  my $axis = linnet::axis::get_by_id( get_axis($s) );

  my $pixel_length = linnet::util::d2pix( $s->{_length} );
  linnet::debug::printdebug( 2, "segment pixel size",
                             $sid, "length", $s->{_length}, "pixel_length", $pixel_length );

  # apply segment scaling
  $pixel_length *= get_scale($s);
  linnet::debug::printdebug( 2, "segment pixel size + segment_scale",
                             $sid, "length", $s->{_length}, "segment_scale", get_scale($s),
                             "pixel_length", $pixel_length );

  # apply axis scaling
  $pixel_length *= linnet::axis::get_scale($axis);
  linnet::debug::printdebug(
                  1,                              "segment pixel size + segment_scale + axis_scale",
                  $sid,                           "length",
                  $s->{_length},                  "segment_scale",
                  get_scale($s),                  "axis_scale",
                  linnet::axis::get_scale($axis), "pixel_length",
                  $pixel_length
                           );
  $s->{_pixel_length} = $pixel_length;
}

sub get_axis {
  my $segment = shift;
  return $segment->{_axis};
}

# $segments is a package variable
sub get_segments {
  return $segments;
}

# fetch a segment by id
sub get_by_id {
  my $sid = shift;
  linnet::debug::printdie("segment id [$sid] is not a scalar.") unless !ref($sid);
  my $s = $segments->{$sid};
  linnet::debug::printdie("segment with id [$sid] does not exist.") unless $s;
  return $s;
}

# get ids of all segments, by order of appearance in the segment file
sub get_ids {
  return sort { $segments->{$a}{idx} <=> $segments->{$b}{idx} } keys %$segments;
}

# get the scale of the segment
# - affects to the distance-to-pixel calculation
sub get_scale {
  my $segment = shift;
  return $segment->{scale};
}

# determine whether the ideogram is reversed
sub is_reversed {
  my $segment = shift;
  return $segment->{reverse};
}

# given a regular expression (list supported), return segments
# that are selected by the list
#
# select_by_rx("chr1",$segments)
# select_by_rx([".*","-chr1"],$segments)
# select_by_rx(["chr[1-9]","-chr[12]"],$segments)
#
# segments are tested in the order of their 'idx' value
# segments are selected in the order of matching regular expressions
sub select_by_rx {
  linnet::debug::printdebug();
  my $rx = shift;

  my %segment_ids_pass = ();
  my @segment_ids      = get_ids($segments);

  # first test regular expressions that select
  # and then test those that fail (preceded by "-")
  for my $negate ( 0, 1 ) {
    for my $r ( linnet::util::tolist($rx) ) {
      my ( $strnegate, $str ) = $r =~ /(-)?(.*)/;
      next if $negate != ( $strnegate eq "-" );
      for my $sid (@segment_ids) {
        my $match = $sid =~ /$str/i;
        linnet::debug::printdebug(
                                   2,    "segrxtest", $r,      "str",
                                   $str, "negate",    $negate, "segment",
                                   $sid, "match",     $match
                                 );
        if ( $match && !$negate ) {

          # passed segments are ordered by appearance
          $segment_ids_pass{$sid} = int( values %segment_ids_pass );
        }
        elsif ( $match && $negate ) {
          delete $segment_ids_pass{$sid};
        }
      }
    }
  }
  return sort { $segment_ids_pass{$a} <=> $segment_ids_pass{$b} } keys %segment_ids_pass;
}

# parse reverse parameter to calculate scale for each segment
# <segments>
# reverse = rx,rx,rx,...
sub assign_reverse {
  linnet::debug::printdebug();
  if ( my $str = linnet::conf::getitem( "segments", "reverse" ) ) {
    my @rx = split( /\s*,\s*/, $str );
    for my $rx (@rx) {
      my @sid = select_by_rx( $rx, $segments );
      for my $sid (@sid) {
        $segments->{$sid}{reverse} = 1;
      }
    }
  }
}

# parse scale parameter to calculate scale for each segment
# <segments>
# scale = rx:value,rx:value,...
sub assign_scale {
  linnet::debug::printdebug();
  if ( my $str = linnet::conf::getitem( "segments", "scale" ) ) {
    my @scales_str = split( /\s*,\s*/, $str );
    for my $scale_str (@scales_str) {
      my ( $rx, $scale ) = split( /\s*:\s*/, $scale_str );
      my @sid = select_by_rx( $rx, $segments );
      die "segment scale [$scale] for segments [" . join( ",", @sid ) . "] is not positive."
        unless linnet::util::is_positive($scale);
      for my $sid (@sid) {
        $segments->{$sid}{scale} *= $scale;
        linnet::debug::printdebug( 1, "segment scale", $sid, $scale, $segments->{$sid}{scale} );
      }
    }
  }
}

# given created segments and axes, assign axes to segments
sub assign_axis {
  linnet::debug::printdebug();
  my $axes = shift;
  for my $axisname ( keys %$axes ) {
    my $axisdata = $axes->{$axisname};
    for my $sid ( @{ $axisdata->{_segments} } ) {
      if ( exists $segments->{$sid}{_axis} ) {
        die
"segment [$sid] is already assigned to another axis [$segments->{$sid}{_axis}] and cannot be assigned to axis [$axisname].";
      }
      else {
        linnet::debug::printdebug( 1, "segment", $sid, "added to axis", $axisname );
        $segments->{$sid}{_axis} = $axisname;
      }
    }
  }
}

1;
