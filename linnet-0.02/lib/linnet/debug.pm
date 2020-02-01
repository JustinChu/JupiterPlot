
package linnet::debug;

use Data::Dumper;
use Carp;
use linnet::image;
use linnet::util;

$linnet::debug::fnstamp_debug_level = 2;
$linnet::debug::exit_on_dump        = 1;

sub printdebug {
  my ( $debug_level, @message ) = @_;
  $debug_level = $linnet::debug::fnstamp_debug_level if !defined $debug_level;
  if ( linnet::conf::getitem("debug") >= $debug_level ) {
    my @output = ( "debug", sprintf( "%s[%d] <- %s[%d]", ( caller(1) )[3], ( caller(0) )[2], (caller(2))[3], (caller(1))[2]) );
    if (@message) {
      push @output, @message;
    }
    else {
      push @output, "***STAMP***";
    }
    printinfo(@output);
  }
}

sub printdie {
  print "\n\n". "*" x 80 ."\n";
  print "FATAL ERROR\n\n";
  printf( "%s\n", join( " ", @_ ) );
  print "\n\n". "*" x 80 ."\n";
  print "STACK TRACE\n\n";
  confess();
}

sub printinfo {
  printf( "%s\n", join( " ", @_ ) );
}

sub printdumper {
  printinfo( Dumper(@_) );
exit if $linnet::debug::exit_on_dump;
}

sub test_boxes {
for my $i ( 1 .. 100 ) {
  my $length = 50;
  my $tip    = 15;
  my $size   = linnet::image::get_size();
  my ( $x1, $y1 ) = map { $_ * $size / 12 + 2 * $length } ( $i % 10, int( $i / 10 ) );
  my ( $r, $angle ) = ( $length, 360 / 100 * $i );
  my ( $x2, $y2 ) = linnet::util::ra2xy( $r, $angle, $x1, $y1 );
  linnet::draw::line( $im, $imc, [ $x1, $y1 ], [ $x2, $y2 ], "black", 1 );
	linnet::draw::box( $im, $imc, [ $x1, $y1 ], [ $x2, $y2 ], "black_a5", 10 );
  my ( $xd, $yd ) = linnet::util::xyd2xy( $x2, $y2, $tip, $x1, $y1,90);
  linnet::draw::line( $im, $imc, [ $x2, $y2 ], [ $xd, $yd ], "blue", 1 );
  linnet::draw::box( $im, $imc, [ $x2, $y2 ], [ $xd, $yd ], "blue_a5", 10 );
  my ( $xd, $yd ) = linnet::util::xyd2xy( $x2, $y2, -$tip, $x1, $y1,90);
  linnet::draw::line( $im, $imc, [ $x2, $y2 ], [ $xd, $yd ], "red", 1 );
  linnet::draw::box( $im, $imc, [ $x2, $y2 ], [ $xd, $yd ], "red_a5", 10 );
  my ( $r2, $a2 ) = linnet::util::xy2ra( $x2, $y2, $x1, $y1 );
}
}


1;
