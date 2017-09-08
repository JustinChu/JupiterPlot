package Circos::Karyotype;

=pod

=head1 NAME

Circos::Karyotype - karyotype routines for Circos

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
use Cwd;
use FindBin;
use Math::Round;
use Math::VecStat qw(max);
use Params::Validate qw(:all);

#use File::Spec::Functions;
#use Memoize;
#use Regexp::Common qw(number);
#use POSIX qw(floor ceil);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration;
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;

################################################################
# Read the karyotype file and parsed chromosome and band locations.
#
# Chromosomes have the format
#
# chr hs1 1 0 247249719 green
# chr hs2 2 0 242951149 green
#
# and bands
#
# band hs1 p36.33 p36.33 0 2300000 gneg
# band hs1 p36.32 p36.32 2300000 5300000 gpos25
#
# The fields are
#
# field name label start end color options
#
# Note that name and label can be different. The label (e.g. 1) is what appears
# on the image, but the name (e.g. hs1) is what is used in the input data file.
#
# v0.57 - parent field of chr is no longer required
#           - old 7-field karyotype still supported
# v0.52 - additional error checks and tidying
#

sub read_karyotype {
	fetch_conf("debug_validate") && validate( @_, { file => 1 } );
	my %params = @_;
	my $files = Circos::Configuration::make_parameter_list_array($params{file});
	my $karyotype = {};
	for my $file (@$files) {
		read_karyotype_file($file,$karyotype);
	}
	return $karyotype;
}

sub read_karyotype_file {
	my ($file,$karyotype) = @_;
	my $file_located      = locate_file(file=>$file,name=>"karyotype",return_undef=>1);
	fatal_error("io","cannot_read",$file,"karyotype",$!) if ! $file_located;
	my $chr_index;
	if (! keys %$karyotype) {
		$chr_index = 0;
	} else {
		my @prev_index = map { $_->{chr}{display_order} } values %$karyotype;
		$chr_index = 1 + max @prev_index;
	}

	my $delim_rx = fetch_conf("file_delim") || undef;
	if ($delim_rx && fetch_conf("file_delim_collapse")) {
		$delim_rx .= "+";
	}

	open(F,$file_located) or fatal_error("io","cannot_read",$file_located,"karyotype",$!);

	while (<F>) {
		chomp;
		my $line = $_;
		next if is_blank($line);
		next if is_comment($line);

		my @tok = $delim_rx ? split($delim_rx,$line) : split;

		my ($field,$parent,$name,$label,$start,$end,$color,$options) = @tok;

		#fatal_error("data","bad_karyotype_format",$file,$line);

		$start =~ s/[,_]//g;
		$end   =~ s/[,_]//g;

		if ( ! is_number($start,"int") || ! is_number($end,"int") ) {
	    fatal_error("data","malformed_karyotype_coordinates",$start,$end);
		}
		if ( $end <= $start ) {
	    fatal_error("data","inconsistent_karyotype_coordinates",$start,$end);
		}
		if (@tok != 7 && @tok != 8) {
	    fatal_error("data","bad_karyotype_format",$line);
		}

		my $set  = make_set($start,$end,norev=>1);

		# karyotype data structure is a hash with each chromosome being a value
		# keyed by chromosome name. Bands form a list within the chromosome
		# data structure, keyed by 'band'.

		my $data = {
								start   => $start,
								end     => $end,
								set     => $set,
								size    => $set->cardinality,
								name    => $name,
								label   => $label,
								parent  => $parent,
								color   => lc $color,
								options => parse_options($options)
							 };

		if ( $field =~ /chr/ ) {
			# chromosome entries have a few additional fields
			# chr, scale, display_order
			$data->{chr}           = $name;
			$data->{scale}         = 1;
			$data->{display_order} = $chr_index++;
			if ( $karyotype->{$data->{chr}}{chr} ) {
				fatal_error("data","repeated_chr_in_karyotype",$data->{chr});
			}
			# check if color override has been specified
			my $color_conf_str = fetch_conf("chromosomes_color") || fetch_conf("chromosome_color");
	    if ($color_conf_str) {
				my @color_list = @{Circos::Configuration::make_parameter_list_array($color_conf_str)};
				for my $is_rx (1,0) {
					for my $color_pair (@color_list) {
						my ($key,$value) = Circos::Configuration::parse_var_value($color_pair);
						my $rx           = parse_as_rx($key);
						if ($is_rx) {
							next unless $rx;
						} else {
							next if $rx;
						}
						my $match = match_string($name,$rx||$key);
						$data->{color} = $value if $match;
					}
				}
	    }
	    # chromosome is keyed by its name
	    $karyotype->{ $name }{chr} = $data;
		} elsif ( $field =~ /band/ ) {
	    # band entries have the 'chr' key point to the name of parent chromosome
	    $data->{chr} = $parent;
	    push @{ $karyotype->{ $parent }{band} }, $data;
		} else {
	    # for now, die hard here. There are no other line types supported.
	    fatal_error("data","unknown_karyotype_line",$field,$line);
		}
	}
	return $karyotype;
}

################################################################
#
# Verify the contents of the karyotype data structure. Basic
# error checking also happens in read_karyotype (above). Here,
# we perform more detailed diagnostics.
#
# The following are checked
#
# error  condition
# FATAL  a band has no associated chromosome
# FATAL  band coordinates extend outside chromosome
# FATAL  two bands overlap by more than max_band_overlap
# WARN   a chromosome has a parent field definition
# WARN   bands do not completely cover the chromosome

sub validate_karyotype {
	fetch_conf("debug_validate") && validate( @_, { karyotype => 1 } );
	my %params    = @_;
	my $karyotype = $params{karyotype};
	for my $chr ( keys %$karyotype ) {
		if ( !$karyotype->{$chr}{chr} ) {
			fatal_error("data","band_on_missing_chr",$chr);
		}
		if ( $karyotype->{$chr}{chr}{parent} ne $DASH ) {
			printwarning("Chromosome [$chr] has a parent field. Chromosome parents are not currently supported");
		}
		
		my $chrset           = $karyotype->{$chr}{chr}{set};
		my $bandcoverage     = Set::IntSpan->new();
		
		for my $band ( make_list( $karyotype->{$chr}{band} ) ) {
			if ( $band->{set}->diff($chrset)->cardinality ) {
				fatal_error("data","band_sticks_out",$band->{name},$chr);
			} elsif ( $band->{set}->intersect($bandcoverage)->cardinality > 1 ) {
				printwarning("data","Band [$band->{name}] for chromosome [$chr] overlaps with other bands");
			}
			$bandcoverage = $bandcoverage->union( $band->{set} );
		}
		if ($bandcoverage->cardinality && $bandcoverage->cardinality < $chrset->cardinality ) {
			printwarning("Bands for chromosome [$chr] do not cover entire chromosome");
		}
	}
}

################################################################
# Assign sort_idx key to each chromosome derived by sorting
# the chromosomes by an internal digit in the chromosome name,
# if it is found. Any other chromosomes are sorted
# asciibetically.
#
sub sort_karyotype {
	fetch_conf("debug_validate") && validate( @_, { karyotype => 1 } );
	my %params = @_;
	my $k = $params{karyotype};
    
	my @chrs = sort { $k->{$a}{chr}{display_order} <=> $k->{$b}{chr}{display_order} } keys %$k;
    
	my @chrs_native_sort;

	if (my @chrs_w_num = grep($_ =~ /\d/, @chrs)) {
		# if there are any chromosomes with a number in them, place them first and
		# sort them by the (preceeding) non-numerical string first, then the number
		my $rxnd = qr/^(\D+)/;
		my $rxd  = qr/(\d+)/;
		my @chrs_for_sort;
		for my $c (@chrs_w_num) {
	    my ($non_digit) = $c =~ /$rxnd/;
	    my ($digit)     = $c =~ /$rxd/;
	    push @chrs_for_sort, {chr       => $c,
														non_digit => $non_digit || $EMPTY_STR,
														digit     => $digit     || 0};
		}
		push @chrs_native_sort, map { $_->{chr} } sort { ( $a->{non_digit} cmp $b->{non_digit} ) ||
																											 ( $a->{digit} <=> $b->{digit} ) } @chrs_for_sort;
	}
	push @chrs_native_sort, sort { $a cmp $b } grep($_ !~ /\d/, @chrs);
	for my $i (0..@chrs_native_sort-1) {
		my $chr = $chrs_native_sort[$i];
		$k->{$chr}{chr}{sort_idx} = $i;
	}
}

1;
