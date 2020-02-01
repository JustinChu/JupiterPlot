
package linnet::draw;

use strict;
use GD;
use GD::Polyline;
use Math::Trig;
use Readonly;

Readonly my $DEG2RAD => 0.0174532925;
Readonly my $RAD2DEG => 57.29577951;

sub line {
  my ( $im, $imc, $u, $v, $color, $thickness ) = @_;
  $thickness = 1 if $thickness < 1;
  $im->setThickness($thickness);
  if ($thickness) {
    #my ($b,$bc) = linnet::image::getbrush($thickness,$color,$imb);
    #$im->setBrush($b);
    #$im->line(@$u,@$v,gdBrushed);
  }
  linnet::debug::printdebug( 2, "line", @$u, @$v, $color, $thickness );
  $im->line( @$u, @$v, $imc->{$color} );
  $im->setThickness(1);
}

# draw a rectangle from $u to $v of thickness $thickness. This is different
# than using GD to draw a line with a thickness, because the line's
# ends are always vertical, whereas this box function's ends are
# perpendicular to segment u,v.
sub box {
  my ( $im, $imc, $u, $v, $color, $thickness ) = @_;
	return if ! $thickness;
  $thickness ||= 1;
  my $xc = linnet::conf::getitem( "image", "size" ) / 2;
  my $yc = linnet::conf::getitem( "image", "size" ) / 2;

  my $poly = GD::Polygon->new();
  my $d    = $thickness / 2;

  my @x1 = linnet::util::xyd2xy( @$v, $d, @$u );
  my @x2 = linnet::util::xyd2xy( @$u, $d, @$v, -90 );
  my @x3 = linnet::util::xyd2xy( @$u, $d, @$v );
  my @x4 = linnet::util::xyd2xy( @$v, $d, @$u, -90 );

  $poly->addPt(@x1);
  $poly->addPt(@x2);
  $poly->addPt(@x3);
  $poly->addPt(@x4);
  # filledPolygon doesn't seem to support transparency???
  #$im->setAntiAliased($imc->{$color});
  #$im->filledPolygon( $poly, gdAntiAliased );
  $im->filledPolygon( $poly, $imc->{$color} );

}

# draw a bezier curve from $u to $v with control points @$p
# these coordinates are packed into $b = [$u,$v,$p]
sub bezier_curve {
  my ( $im, $imc, $b, $color, $thickness, $cap_thickness ) = @_;

  # unpack the bezier points
  my ( $u, $v, $p ) = @$b;

  # unpack the control points
  my @p = map { @$_ } @$p;
  my @bezier_points = linnet::util::bezier_points( @$u, @p, @$v );
  line_segments( $im, $imc, \@bezier_points, $color, $thickness, $cap_thickness );
}

# draw a bezier polygon bounded by two curves
sub bezier_polygon {
  my ( $im, $imc, $b1, $b2, $color, $thickness ) = @_;
  #linnet::debug::printdumper($b1);
  my ( $u1, $v1, $p1 ) = @$b1;
  my ( $u2, $v2, $p2 ) = @$b2;
  my @p1 = map { @$_ } @$p1;
  my @p2 = map { @$_ } @$p2;
  my @bezier1_points = linnet::util::bezier_points(@$u1,@p1,@$v1);
  my @bezier2_points = linnet::util::bezier_points(@$u2,@p2,@$v2);

  my $poly           = GD::Polygon->new();

  for my $pt ( @bezier1_points, @bezier2_points ) {
    $poly->addPt(@$pt);
  }
  $im->filledPolygon( $poly, $imc->{$color} );
}

# draw line segments between @$points
sub line_segments {
  my ( $im, $imc, $points, $color, $thickness, $cap_thickness ) = @_;
  #my $polyline = GD::Polyline->new();
  #for my $i ( 0 .. @$points - 1 ) {
  #  $polyline->addPt(@{$points->[$i]});
  #}
  #$im->polydraw($polyline,$imc->{$color});
  #return;
  for my $i ( 0 .. @$points - 2 ) {
    line( $im, $imc, $points->[$i], $points->[ $i + 1 ], $color, $thickness );
    # contribution by Tommaso Leonardi - adds polarity to edge if
    # -polarity flag is included. Polarity is indicated by a thick mark at the
    # end of every segment.
    #
    # I've added to this by including polarity_thickness and polarity_thickness_factor, 
    # which determine the thickness of the ribbon ends
    if ( defined $cap_thickness && $i == @$points - 2) {
	line($im,$imc,$points->[$i],$points->[$i+1],$color,$cap_thickness);
    } else {
	line($im,$imc,$points->[$i],$points->[$i+1],$color,$thickness);
    }
  }
}

1;
