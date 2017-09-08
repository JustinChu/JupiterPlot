package Circos::Track::Link;

=pod

=head1 NAME

Circos::Track::Link - routines for link handling in Circos

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
our @EXPORT = qw();

use Carp qw( carp confess croak );
use FindBin;
use GD::Image;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; # qw(%CONF $DIMS);
use Circos::Constants;
#use Circos::Colors;
use Circos::Debug;
use Circos::Error;
#use Circos::Font;
#use Circos::Geometry;
#use Circos::SVG;
#use Circos::Image;
use Circos::Utils;

use Memoize;

for my $f ( qw ( ) ) {
memoize($f);
}

sub make_tracks {
	my $conf_leaf = shift;
	my @link_tracks;
	# If the links are stored in the old form (named block), associate the
	# name with the __id parameter for each link. Otherwise, generate __id
	# automatically using an index
	if(ref $conf_leaf eq "HASH") {
		# Could be one or more named blocks, or a single unnamed block.
		# If each value is a hash, then assume that we have named blocks
		my @values      = values %$conf_leaf;
		my $values_hash = grep(ref $_ eq "HASH", @values);
		if($values_hash == @values) {
	    # likely one or more named blocks
	    printdebug_group("conf","found multiple named link blocks");
	    for my $link_name (keys %$conf_leaf) {
				printdebug_group("conf","adding named link block [$link_name]");
				my $link_track      = $conf_leaf->{$link_name};
				if ( ref $link_track eq "ARRAY" ) {
					fatal_error("links","duplicate_names",$link_name);
				}
				if(defined $link_track->{id}) {
					$link_track->{__id} = $link_track->{id};
				} else {
					$link_track->{id}   = $link_track->{__id} = $link_name;
				}
				push @link_tracks, $link_track;
	    }
		} else {
	    # likely a single unnamed block
	    printdebug_group("conf","found single unnamed link block");
	    push @link_tracks, $CONF{links}{link};
		}
	} elsif(ref $conf_leaf eq "ARRAY") {
		# Multiple unnamed/named blocks. A named block will be a
		# hash with a single key.
		printdebug_group("conf","found multiple unnamed/named link blocks");
		for my $link_track (@$conf_leaf) {
	    if(ref $link_track eq "HASH" && keys %$link_track == 1) {
				my ($link_name) = keys %$link_track;
				$link_track = $link_track->{$link_name};
				if(defined $link_track->{id}) {
					$link_track->{__id} = $link_track->{id};
				} else {
					$link_track->{id}   = $link_track->{__id} = $link_name;
				}
				printdebug_group("conf","adding named link block [$link_name]");
				push @link_tracks, $link_track;
	    } else {
				printdebug_group("conf","adding unnamed link block");
				push @link_tracks, $link_track;
	    }
		}
	}
	for my $i (0..@link_tracks-1) {
		my $id = first_defined($link_tracks[$i]{id}, $link_tracks[$i]{__id});
		if(! defined $id) {
			$id = sprintf("link_%d",$i);
			printdebug_group("conf","adding automatic link id [$id]");
		}
		$link_tracks[$i]{id} = $link_tracks[$i]{__id} = $id;
	}
	return @link_tracks;
}

1;
