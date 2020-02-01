
package linnet::image;

use linnet::conf;
use linnet::color;
use linnet::debug;

# create an true-color (24bit) image of a given size
# - allocate colors
# - fill image with background color
# returns image and color hash
sub create {
  my $size = shift;
  linnet::debug::printdie("image size [$size] must be positive") unless linnet::util::is_positive($size);
  my $im  = GD::Image->new( $size, $size, 1 );
  my $imc = linnet::color::allocate_colors($im);
  my $bg  = linnet::conf::getitem( "image", "background" );
  $im->fill( 0, 0, $imc->{$bg} );
  return ( $im, $imc );
}

sub get_size {
	my $size = linnet::conf::getitem("image","size");
	return $size;
}

sub get_center {
	my $size = linnet::conf::getitem("image","size");
	return ($size/2,$size/2);
}

# write the image to a file
sub write {
  my $image   = shift;
  my $outfile = linnet::conf::getitem( "image", "file" ) || "triangle.png";
  my $outdir  = linnet::conf::getitem( "image", "dir" ) || ".";
  open( PNG, ">$outdir/$outfile" )
    || linnet::debug::printdie("cannot write to output file [$outdir/$outfile]");
  binmode PNG;
  print PNG $image->png;
  close(PNG);
  linnet::debug::printdebug( 1, "wrote", $outfile );
}

# given a brush size, color and image brush hash,
# fetch/create a brush
sub getbrush {
  my ( $size, $color, $imb ) = @_;
  my ( $h, $w ) = ( $size, $size );
  my $brush;
  my $brush_colors;
  if ( exists $imb->{size}{$w}{$h}{brush} ) {
    ( $brush, $brush_colors ) = @{ $imb->{size}{$w}{$h} }{qw(brush colors)};
  }
  else {
		($brush, $bc) = create($size);
    if ( !$brush ) {
      linnet::debug::printdie("could not create brush of size $size");
    }
    @{ $imb->{size}{$w}{$h} }{qw(brush colors)} = ( $brush, $brush_colors );
  }
  if ( defined $color ) {
    $brush->fill( 0, 0, $brush_colors->{$color} );
  }
  return ( $brush, $brush_colors );
}

1;
