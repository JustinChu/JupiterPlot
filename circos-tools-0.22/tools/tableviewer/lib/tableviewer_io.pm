
use strict;

sub prep_handle {
  my $file = shift;
  my $inputhandle;
  if($file) {
    die "No such file $file" unless -e $file;
    open(FILE,$file) || die "cannot open file $file";
    $inputhandle = \*FILE;
  } else {
    printdebug("using STDIN");
    $inputhandle = \*STDIN;
  }
}

return 1;
