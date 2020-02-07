
package linnet::link;

use vars qw( $links );

use strict;
use Math::VecStat qw(min);
use linnet::axis;
use linnet::segment;
use linnet::conf;
use linnet::debug;
use linnet::util;

sub read {
  my $link_conf = linnet::conf::getitem("links");
  for my $linkdata ( linnet::util::tolist( $link_conf->{link} ) ) {
    my ( $file, @files ) = linnet::io::findfile( $linkdata->{file} );
    linnet::debug::printdebug( 1, "reading links from file [$file]" );
    my $fh         = linnet::util::open_file($file);
    my $link_track = $linkdata;
    my $link_cnt_limit = $linkdata->{record_limit} || 0;
    my $link_cnt   = 0;
    while (<$fh>) {
      chomp;
      s/\s*\#.*//;
      my @tok = split;
      my ( $id1, $start1, $end1, $id2, $start2, $end2, $options ) = @tok;
      my $link = {
        s1 => {
          id      => $id1,
          x       => $start1,
          y       => $end1,
          middle  => ( $start1 + $end1 ) / 2,
          _length => $start1 - $end1,

              },
        s2 => {
          id      => $id2,
          x       => $start2,
          y       => $end2,
          middle  => ( $start2 + $end2 ) / 2,
          _length => $end2 - $start2,

              },
        options => linnet::util::parseoptions($options),
                 };
      push @{ $link_track->{_data} }, $link;
      $link_cnt++;
      last if $link_cnt_limit && $link_cnt >= $link_cnt_limit;
    }
    push @$links, $link_track;
  }
}

sub process {
  for my $link_track (@$links) {
    for my $link ( @{ $link_track->{_data} } ) {
      validate_coordinate( $link->{s1} );
      validate_coordinate( $link->{s2} );
    }
  }
}

sub validate_coordinate {
  my $span = shift;
  my $s    = linnet::segment::get_by_id( $span->{id} );
  if ( !$s->{set}->member( int( $span->{x} ) ) ) {
    linnet::debug::printdie("link start [$span->{x}] is not on segment [$span->{id}] ");
  }
  if ( !$s->{set}->member( int( $span->{y} ) ) ) {
    linnet::debug::printdie("link end [$span->{y}] is not on segment [$span->{id}] ");
  }
}

sub get_link_tracks {
  return @$links;
}

sub get_links {
  my $track = shift;
  linnet::debug::printdie("link track is not a reference.") unless ref($track) eq "HASH";
  linnet::debug::printdie("link track does not have _data structure") unless exists $track->{_data};
  linnet::debug::printdie("link track _data structure is not a list ")
    unless ref( $track->{_data} ) eq "ARRAY";
  return @{ $track->{_data} };
}

# calculate the x,y positions of the ends of each link
# each link end has a start and end
#
# $link->{s1}{xy} = [ [startx1,starty1],[startx2,starty2] ]
# $link->{s2}{xy} = [ [endx1,endy1],[endx2,endy2] ]
# $link->{xy}     = [ [startx1,starty1],[startx2,starty2],[endx1,endy1],[endx2,endy2] ];
sub compute_pixel_ends {
  my ( $link_track, $link ) = @_;

  my ( $sid1, $sid2 ) = ( $link->{s1}{id}, $link->{s2}{id} );
  my ( $s1,   $s2 )   = ( linnet::segment::get_by_id($sid1), linnet::segment::get_by_id($sid2) );
  my ( $aid1, $aid2 ) = ( linnet::segment::get_axis($s1),    linnet::segment::get_axis($s2) );
  my ( $a1,   $a2 );

  # if the segments for the link are not on any axis, move to next link
  eval { ( $a1, $a2 ) = ( linnet::axis::get_by_id($aid1), linnet::axis::get_by_id($aid2) ); };
  if ($@) {
    $link->{xy} = [];
    $link->{s1}{xy} = [];
    return;
  }
  my ( $angle1, $angle2 ) = ( $a1->{angle}, $a2->{angle} );
  my $anglem = linnet::util::anglemiddle( $angle1, $angle2 );
  my $angleo = linnet::util::angleorient( $angle1, $angle2 );

  my $crest = $link_track->{crest} || 0;

  # crest is the minimum of
  # - user supplied crest
  # - 1/4 of the distance between start of link ends
  # - 1/4 of the distance between end of link ends
  $crest = min(
    $crest,
    linnet::util::get_xyxy_distance(
                                     linnet::axis::pixel_pos( $aid1, $sid1, $link->{s1}{x} ),
                                     linnet::axis::pixel_pos( $aid2, $sid2, $link->{s2}{x} ),
      ) / 4,
    linnet::util::get_xyxy_distance(
                                     linnet::axis::pixel_pos( $aid1, $sid1, $link->{s1}{y} ),
                                     linnet::axis::pixel_pos( $aid2, $sid2, $link->{s2}{y} ),
      ) / 4

  );

  my $segment_width = linnet::conf::getitem( "segments", "width" );
  my $offset1 = $link_track->{offset_start} || 0;
  my $offset2 = $link_track->{offset_end}   || 0;
  my $d       = $segment_width / 2;

  # start of link: start xy coordinate
  $link->{s1}{xy}[0] =
    [ linnet::axis::pixel_pos( $aid1, $sid1, $link->{s1}{x}, $angleo * ( $d + $offset1 ) ) ];

  # start of link: end xy coordinate
  $link->{s1}{xy}[1] =
    [ linnet::axis::pixel_pos( $aid1, $sid1, $link->{s1}{y}, $angleo * ( $d + $offset1 ) ) ];

  # end of link: start xy coordinate
  $link->{s2}{xy}[0] =
    [ linnet::axis::pixel_pos( $aid2, $sid2, $link->{s2}{x}, -$angleo * ( $d + $offset2 ) ) ];

  # end of link: end xy coordinate
  $link->{s2}{xy}[1] =
    [ linnet::axis::pixel_pos( $aid2, $sid2, $link->{s2}{y}, -$angleo * ( $d + $offset2 ) ) ];

  $link->{xy} = [ @{ $link->{s1}{xy} }, @{ $link->{s2}{xy} } ];
}

# given a link track and a link, draw the link
sub draw {
  linnet::debug::printdebug();
  my ( $im, $imc, $link_track, $link ) = @_;
  compute_pixel_ends( $link_track, $link );

  my $color = defined $link->{options}{color} ? $link->{options}{color} : $link_track->{color};
  my $thickness = defined $link->{options}{thickness} ? $link->{options}{thickness} : $link_track->{thickness};
  my $as_ribbon = $link_track->{ribbon};
  my $ribbon_edge_color = linnet::conf::getitem( "links", "link", "color" );

  # ribbon is drawn only if the ends of the link are > 1 pixel in size
  my $d1 = linnet::util::get_xyxy_distance( @{ $link->{s1}{xy}[0] }, @{ $link->{s1}{xy}[1] } );
  my $d2 = linnet::util::get_xyxy_distance( @{ $link->{s2}{xy}[0] }, @{ $link->{s2}{xy}[1] } );
  $as_ribbon &&= $d1 > 1 || $d2 > 1;

  if ($as_ribbon) {

    my $u1 = $link->{s1}{xy}[0];
    my $v1 = $link->{s2}{xy}[0];
    my @p01 =
      ( [ linnet::util::bezier_control( @$u1, @$v1, $link_track->{bezier_radius_power} ) ] );

    my $u2 = $link->{s2}{xy}[1];
    my $v2 = $link->{s1}{xy}[1];
    my @p02 =
      ( [ linnet::util::bezier_control( @$u2, @$v2, $link_track->{bezier_radius_power} ) ] );

    my ( @p1, @p2 );
    if ( $link_track->{crest} ) {
      my @p1c = ( linnet::util::bezier_crest( @$u1, @$v1, $link_track->{crest} ) );
      my @p2c = ( linnet::util::bezier_crest( @$u2, @$v2, $link_track->{crest} ) );
      @p1 = ( $p1c[0], @p01, $p1c[1] );
      @p2 = ( $p2c[0], @p02, $p2c[1] );
    }
    else {
      @p1 = @p01;
      @p2 = @p02;
    }

    # bezier curves for the two sides of the ribbon
    my $b1 = [ $u1, $v1, \@p1 ];
    my $b2 = [ $u2, $v2, \@p2 ];

    #linnet::debug::printdumper($b2);
    linnet::draw::bezier_curve( $im, $imc, $b1, $ribbon_edge_color, $link_track->{thickness} );
    linnet::draw::bezier_curve( $im, $imc, $b2, $ribbon_edge_color, $link_track->{thickness} );
    linnet::draw::bezier_polygon( $im, $imc, $b1, $b2, $color );
  }
  else {

    # bezier curve between middle of link ends
    my $u = [ linnet::util::get_xyxy_middle( @{ $link->{s1}{xy}[0] }, @{ $link->{s1}{xy}[1] } ) ];
    my $v = [ linnet::util::get_xyxy_middle( @{ $link->{s2}{xy}[0] }, @{ $link->{s2}{xy}[1] } ) ];
    my @p0 = ( [ linnet::util::bezier_control( @$u, @$v, $link_track->{bezier_radius_power} ) ] );
    my @p;
    if ( $link_track->{crest} ) {
      my @pc = ( linnet::util::bezier_crest( @$u, @$v, $link_track->{crest} ) );
      @p = ( $pc[0], @p0, $pc[1] );
    }
    else {
      @p = @p0;
    }
    my $b = [ $u, $v, \@p ];

    #linnet::debug::printdumper($b);

    my $cap_thickness = $thickness;
    if($link_track->{polarity}) {
	if($link_track->{polarity_thickness_mult}) {
	    $cap_thickness = $thickness * $link_track->{polarity_thickness_mult};
	} elsif ($link_track->{polarity_thickness}) {
	    $cap_thickness = $link_track->{polarity_thickness};
	} else {
	    $cap_thickness = $thickness * 2;
	}
    }
    linnet::draw::bezier_curve( $im, $imc, $b, $color, $thickness, $cap_thickness );
  }

  #linnet::draw::line( $im, $imc, $link->{s1}{xy}[0], $link->{s2}{xy}[0], $color, 2 );
  #linnet::draw::line( $im, $imc, $link->{s1}{xy}[1], $link->{s2}{xy}[1], $color, 2 );

  return;


}

1;
