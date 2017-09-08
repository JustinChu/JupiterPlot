package Circos::URL;

=pod

=head1 NAME

Circos::URL - URL routines for PNG in Circos

=head1 SYNOPSIS

This module is not meant to be used directly.

=head1 DESCRIPTION

Circos is an application for the generation of publication-quality,
circularly composited renditions of genomic data and related
annotations.

Circos is particularly suited for visualizing alignments, conservation
and intra and inter-chromosomal relationships. However, Circos can be
used to plot any kind of 2D data in a circular layout - its use is not
limited to genomics. Circos' use of lines to relate position pairs
(ribbons add a thickness parameter to each end) is effective to
display relationships between objects or positions on one or more
scales.

All documentation is in the form of tutorials at L<http://www.circos.ca>.

=cut

# -------------------------------------------------------------------

use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(
format_url
);

use Carp qw( carp confess croak );
use FindBin;
use GD;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration;
#use Circos::Colors;
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
#use Circos::Image qw(!draw_line);
use Circos::Utils;

use Memoize;

for my $f ( qw ( ) ) {
  memoize($f);
}

sub format_url {
  # given a url (although the function can be applied to any string)
  # replace all instances of [PARAM] with the value of the parameter
  # named PARAM extracted from the elements passed in the param_path
  #
  # e.g. format_url(url=>"www.domain.com/param=[ID]",param_path=>[$datum,$data]);
  my %args        = @_;
  my $delim_left  = "\Q[\E";
  my $delim_right = "\Q]\E";
  my $url         = $args{url};
  return unless defined $url;
  my $ignore_param;
  while ($url =~ /$delim_left([^$delim_right$delim_left]+)$delim_right/g) {
    my $param = $1;
    my $value;
		if(exists $args{param_path}[0]{data}[0] && 
					 defined $args{param_path}[0]{data}[0]{$param}) {
			$value = $args{param_path}[0]{data}[0]{$param};
		} else {
			$value = seek_parameter($param,@{$args{param_path}});
		}
    printdebug_group("url","format_url",$url,$1,$value);
    if (! defined $value) {
      if ($CONF{image}{image_map_missing_parameter} eq "exit") {
				fatal_error("map","url_param_not_set",$url,$param);
      } elsif ($CONF{image}{image_map_missing_parameter} =~ /removeurl/) {
				# there is no value for this parameter, so return an empty url
				return undef;
      } elsif ($CONF{image}{image_map_missing_parameter} =~ /ignoreparam/) {
				$ignore_param->{$param}++;
      } elsif ($CONF{image}{image_map_missing_parameter} =~ /removeparam/ || 1) {
				printdumper($args{param_path});exit;
				# not defined - removeparam by default
				error("warning","general","You have tried to use the URL $url for an image map, but the parameter in the url [$param] has no value defined for this data point or data set. This parameter is being removed from the URL of this element. Use the image_map_missing_parameter setting in the <image> block to adjust this behaviour.");
				$url =~ s/$delim_left$param$delim_right//g;
      }
    } else {
			$url =~ s/$delim_left$param$delim_right/$value/g;
    }
  }
  printdebug_group("url","format_url_done",$url);
  return $url;
}

1;
