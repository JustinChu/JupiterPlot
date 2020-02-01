
package linnet::conf;

use linnet::debug;
use strict;
use File::Basename;
use FindBin;
use Data::Dumper;

sub dump {
    $Data::Dumper::Indent    = 1;
    $Data::Dumper::Quotekeys = 0;
    $Data::Dumper::Terse     = 1;
    print Dumper( \%main::CONF );
    exit;
}
sub getitem {
    my @name = @_;
    my $node = \%main::CONF;
    my $value;
    my @tree = @name;
    if(@tree == 1 && $tree[0] eq "debug") {
	return $node->{debug};
    }
    while(@tree > 0) {
	if(@tree == 1) 	{
	    my $name = shift @tree;
	    linnet::debug::printdebug(3,"fetching conf leaf [$name]");
	    $value = $node->{$name};		
	} 
	else {
	    my $name = shift @tree;
	    linnet::debug::printdebug(3,"fetching conf tree [$name]");
	    $node = $node->{$name};
	    if(! defined $node) {
		linnet::debug::printdie("configuration node for",join(":",@tree),"does not exist.");
	    }
	}
    }
    return $value;
}

# try to find a file in several paths related
# to script source and current working directory

sub loadconfiguration {
  my ($scriptname) = fileparse($0);
  my $file = shift || "$scriptname.conf";
  my ( $fpick, @files ) = linnet::io::findfile($file);

  if ( !defined $fpick ) {
    linnet::debug::printinfo("Could not find configuration file [$file]. Looked in");
    linnet::debug::printinfo( join( "\n", @files ) );
    linnet::debug::printdie();
  }
  linnet::debug::printdebug( 1, "loading configuration from", $fpick );
  $main::OPT{configfile} = $fpick;
  my $conf = new Config::General(
      -ConfigFile        => $fpick,
      -AllowMultiOptions => "yes",
      -LowerCaseNames    => 1,
      -IncludeAgain      => 1,
      -AutoTrue          => 1,
      -ConfigPath => ["$FindBin::RealBin",
		      "$FindBin::RealBin/..",
		      "$FindBin::RealBin/../etc"],
      );
  return $conf->getall;
}


1;
