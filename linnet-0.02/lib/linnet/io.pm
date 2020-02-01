
package linnet::io;

use Cwd qw(getcwd);
use linnet::debug;

sub findfile {
  my $file = shift;
  my $cwd  = getcwd();
  my @files = (
                $file,
                "$FindBin::RealBin/$file",
                "$FindBin::RealBin/etc/$file",
                "$FindBin::RealBin/../etc/$file",
                "$cwd/$file",
                "$cwd/etc/$file",
  );
  my $fpick;
  for my $f (@files) {
    linnet::debug::printdebug( 2, "looking for config [$f]" );
    if ( -e $f && -r _ ) {
      $fpick = $f;
      last;
    }
  }
  return ( $fpick, @files );
}


1;
