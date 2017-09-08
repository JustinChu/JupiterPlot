package Circos::Ideogram;

=pod

=head1 NAME

Circos::Ideogram - ideogram routines for Circos

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
is_on_ideogram
);

use Carp qw( carp confess croak );
use Cwd;
use FindBin;
use File::Spec::Functions;
use Math::Round;
use Math::VecStat qw(max);
#use Memoize;
use Params::Validate qw(:all);
#use Regexp::Common qw(number);

use POSIX qw(floor ceil);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration;
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;

################################################################
#
# Determine which chromosomes are going to be displayed. Several parameters
# are used together to determine the list and order of displayed chromosomes.
#
# - chromosomes
# - chromosomes_breaks
# - chromosomes_display_default
# - chromosomes_order_by_karyotype
#
# If chromosomes_display_default is set to 'yes', then any chromosomes that
# appear in the karyotype are appended to the 'chromosomes' parameter. 
# The order in which they are appended depends on the value of 'chromosomes_order_by_karyotype'.
# 
# If you want to display only those chromosomes that are mentioned in the 
# 'chromosomes' parameter, then set chromosomes_display_default=no.
#
# Both 'chromosomes' and 'chromosomes_breaks' define a list of chromosome regions
# to show, delimited by ;
#
# name{[tag]}{:runlist}
#
# e.g.   hs1
#        hs1[a]
#        hs1:0-100
#        hs1[a]:0-100
#        hs1[a]:0-100,150-200
#        hs1;hs2[a];hs3:0-100
#
# You can also use "=" as the field delimiter,
#
# e.g.   hs1=0-100
#        hs1[a]=0-100
#
# The functional role of 'chromosomes' and 'chromosomes_breaks' is the same. The latter
# gives an opportunity to separate definitions of regions which are not shown.
# 

sub parse_chromosomes {
  my $karyotype = shift;
	
  my @chrs;
  
  # get the chromosomes in the karyotype
  my @chrs_in_k = keys %$karyotype;
  # sort them by their appearance in the file
  @chrs_in_k = sort { $karyotype->{$a}{chr}{display_order} <=> $karyotype->{$b}{chr}{display_order} } @chrs_in_k;
  printdebug_group("chrfilter","karyotypeorder",@chrs_in_k);
  # sort them by digit in chromosome name (e.g. chr1 before chr11 before chrx) (done in Karyotype::sort_karyotype)
  my @chrs_in_k_native_sort = sort { $karyotype->{$a}{chr}{sort_idx} <=> $karyotype->{$b}{chr}{sort_idx} } @chrs_in_k;
  printdebug_group("chrfilter","nativesort",@chrs_in_k_native_sort);
	
  if ( $CONF{chromosomes_display_default} ) {
		#
		# The default order for chromosomes is string-then-number if
		# chromosomes contain a number, and if not then asciibetic
		#
		# I used to have this based on the order in the KARYOTYPE (use
		# {CHR}{chr}{display_order} field) but decided to change it.
		#
		if ( $CONF{chromosomes_order_by_karyotype} ) {
			# @chrs_in_k already ordered by appearance
			printdebug_group("chrfilter","using karyotypeorder");
		} else {
			# sort the chromosomes with digits in them
			@chrs_in_k = @chrs_in_k_native_sort;
			printdebug_group("chrfilter","using nativesort");
		}
		
		################################################################
		# Reconstruct the $CONF{chromosomes} argument using 
		# chromosomes from karyotype and those in $CONF{chromosomes}
		my ($chrs_in_c,@chrs_ordered);
		
		# First, parse chromosomes and regular expressions in the chromosomes string
		if ( $CONF{chromosomes} ) {
			$chrs_in_c = parse_chromosomes_string($CONF{chromosomes});
			#printdumper($chrs_in_c);exit;
		}
	CHR_IN_K:
		for my $chr (@chrs_in_k) {
			my $found;
			if ($chrs_in_c) {
	      my $accept = 1;
	      my @chr_in_c_found;
	      for my $isrx (1,0) {
					# for each chromosome in $CONF{chromosomes}
				CHR_IN_C:
					for my $chr_in_c (@$chrs_in_c) {
						next if $isrx && ! $chr_in_c->{rx};
						next if ! $isrx && $chr_in_c->{rx};
						my $reject = $chr_in_c->{reject};
						my $match  = 0;
						if ($isrx && $chr =~ $chr_in_c->{rx}) {
							$match = 1;
						}
						if (! $isrx && $chr eq $chr_in_c->{chr}) {
							$match = 1;
						}
						printdebug_group("chrfilter",$chr,"inchromosomes",$chr_in_c->{chr},"isrx",defined $chr_in_c->{rx},"match",$match,"reject",$reject);
						if ($match) {
							push @chr_in_c_found, $chr_in_c;
							if ($reject) {
								$accept = 0;
							} else {
								$accept = 1;
							}
							#last CHR_IN_C;
						}
					}
					printdebug_group("chrfilter",$chr,"rx",$isrx,"accept",$accept);
	      }
	      if ($accept) {
					if (@chr_in_c_found) {
						#printdumper(@chr_in_c_found);
						for my $c (@chr_in_c_found) {
							next if $c->{reject};
							# now both RX and literals will be processed
							# this is experimental 0.67-pre8
							if (1 || ! $c->{rx}) {
								my $str = $c->{chr};
								if ($c->{reject}) {
									$str = "-$str";
								}
								if ($c->{tag}) {
									$str .= sprintf("[%s]",$c->{tag});
								}
								if ($c->{runlist}) {
									$str .= sprintf(":%s",$c->{runlist});
								}
								push @chrs_ordered, $str;
							} else {
								push @chrs_ordered, $chr;
							}
						}
					} else {
						push @chrs_ordered, $chr;
					}
	      } else {
					push @chrs_ordered, "-$chr";
	      }
			} else {
	      push @chrs_ordered, $chr;
			}
		}
		$CONF{chromosomes} = join( $SEMICOLON, @chrs_ordered );
  }
  printdebug_group("chrfilter","effective 'chromosomes' parameter",$CONF{chromosomes});
  
  my %karyotype_chrs_seen;
  
  for my $isrx (1,0) {
		for my $pair ([$CONF{chromosomes},1],[$CONF{chromosomes_breaks},0]) {
			my ($string,$accept_default) = @$pair;
			my $chrstring_list = Circos::Configuration::make_parameter_list_array($string,qr/\s*;\s*/);
			for my $chrstring (@$chrstring_list) {
	      my $chr_record = parse_chromosomes_record($chrstring);
	      my ($reject,$chr,$runlist,$tag,$chrrx) = @{$chr_record}{qw(reject chr runlist tag rx)};
	      $tag       = $EMPTY_STR if !defined $tag;
	      $chr       = $EMPTY_STR if !defined $chr;
	      $runlist   = $EMPTY_STR if !defined $runlist;
	      if ($chr eq $EMPTY_STR) {
					fatal_error("ideogram","unparsable_def",$chrstring);
	      }
	      next if $isrx   && ! defined $chrrx;
	      next if ! $isrx && defined $chrrx;
	      # $accept identifies whether the regions indicate inclusions or exclusions
	      # $accept=1 this region is to be included
	      # $accept=0 this region is to be included (region prefixed by -)
	      my $accept = $accept_default;
	      $accept = 0 if $reject;
	      if ( $isrx && $tag) {
					fatal_error("ideogram","regex_tag",$chrstring,$tag);
	      }
	      my $chrkey = make_key($chr,$tag);
	      #printinfo($isrx, $chrrx, $isrx ? "RX" : "NOTRX", !$isrx && defined $chrrx ? "next" : "accept");
	      if ( ! $isrx && ! defined $karyotype->{$chr}{chr} ) {
					fatal_error("ideogram","use_undefined",$chrstring,$chr);
	      }
	      
	      my @chrs_to_store;
	      if ($isrx) {
					for my $c (@chrs_in_k_native_sort) {
						next if $accept && $karyotype_chrs_seen{ make_key($c,$tag) };
						if ($c =~ /$chrrx/i) {
							push @chrs_to_store, $c;
							$karyotype_chrs_seen{ make_key($c,$tag) }++;
							$karyotype_chrs_seen{ make_key($c,"") }++;
						}
					}
	      } else {
					for my $c (@chrs_in_k_native_sort) {
						next if $accept && $karyotype_chrs_seen{ make_key($c,$tag) };
						if ($c eq $chr) {
							push @chrs_to_store, $c;
							$karyotype_chrs_seen{ make_key($c,$tag) }++;
							$karyotype_chrs_seen{ make_key($c,"") }++;
						}
					}
	      }
	      #printdumper(\%karyotype_chrs_seen);
	      printdebug_group("chrfilter","chrrx",$chrstring,"rx?",$isrx,"accept",$accept,"tag",$tag || "-","chrs",@chrs_to_store);
	      next unless @chrs_to_store;
	      
	      sub make_key {
		  my ($chr,$tag) = @_;
		  $tag ||= "";
		  return sprintf("%s_%s",$chr,$tag);
	      }
	      
	      # all numbers in runlist are automatically multiplied by
	      # chromosomes_units value - this saves you from having to type
	      # a lot of zeroes in the runlists
	      
	      if ( $CONF{chromosomes_units} ) {
		  $runlist =~ s/([\.\d]+)/$1*$CONF{chromosomes_units}/eg;
	      }
	      
	      for my $c (@chrs_to_store) {
		  # are we trying to remove this chromosome?
		  printdebug_group("chrfilter","parsed chromosome range", $c, $runlist || $DASH );
		  my $set = $runlist ? Set::IntSpan->new($runlist) : $karyotype->{$c}{chr}{set};
		  
		  ################################################################
		  # uncertain - what was I trying to do here?
		  $set->remove($set->max) if $runlist;
		  if ( ! $accept ) {
		      $set->remove( $set->min ) if $set->min;
		      $set->remove( $set->max );
		  }
		  ################################################################
		  
		  if ($accept) {
		      push @chrs,
		      {
			  chr    => $c,
			  tag    => $tag || $c,
			  idx    => int(@chrs),
			  accept => $accept,
			  set    => $set
		      };
		      $karyotype->{$c}{chr}{display_region}{accept} ||= Set::IntSpan->new();
		      $karyotype->{$c}{chr}{display_region}{accept} = $karyotype->{$c}{chr}{display_region}{accept}->union($set);
		  } else {
		      if ($accept_default) {
			  @chrs = grep($_->{chr} ne $c && $_->{tag} ne $tag, @chrs);
		      }
		      $karyotype->{$c}{chr}{display_region}{reject} ||= Set::IntSpan->new();
		      $karyotype->{$c}{chr}{display_region}{reject} = $karyotype->{$c}{chr}{display_region}{reject}->union($set);
		  }
	      }
	  }
      }
  }
  
  if ( ! grep( $_->{accept}, @chrs ) ) {
      fatal_error("ideogram","no_ideograms_to_draw");
  }
  
  for my $c (@chrs) {
      printdebug_group("chrfilter","chrlist",sprintf("%2d %4s %4s %d %10s %10s",
						     $c->{idx},
						     $c->{chr},
						     $c->{tag}||$EMPTY_STR,
						     $c->{accept}||"-",
						     defined $c->{set}->min ? $c->{set}->min : "(-",
						     defined $c->{set}->max ? $c->{set}->max : "-)"));
  }
  return @chrs;
}

sub parse_chromosomes_string {
    my $str = shift;
    my $data;
    my $delim = ";";
    for my $record ( @{Circos::Configuration::make_parameter_list_array($str,qr/\s*$delim\s*/)} ) {
	push @$data, parse_chromosomes_record($record);
    }
    return $data;
}

#  hs1
# -hs1
#  hs1:1-10
#  hs1[a]:1-10
# -hs1:1-10
#  /h/
# -/h/
#
sub parse_chromosomes_record {
  my $str = shift;
  my $default_delim  = "[:=]";
  my ($chr,$runlist) = split(Circos::Configuration::fetch_configuration("list_field_delim") || $default_delim ,$str);
  $runlist = Circos::Configuration::parse_conf_fn($runlist) if defined $runlist;
  #printinfo($runlist);
  my ($tag,$reject,$rx);
  ( $reject, $chr, $tag ) = $chr =~ /([!-])?(.+?)(?:\[([^\[\]]+)\])?$/;
  $reject = $reject ? 1 : 0;
  $rx = parse_as_rx($chr) || undef;
  my $isrx = $rx ? 1 : 0;
  printdebug_group("chrfilter","parsed chr record",$str,"chr",$chr,"tag",$tag,"reject",$reject,"runlist",$runlist,"rx",$rx,"rx?",$isrx);
  return { chr=>$chr,
	   rx=>$rx,
	   isrx=>$isrx,
	   reject=> $reject ? 1 : 0,
	   accept=> $reject ? 0 : 1,
	   tag=>$tag || undef,
	   runlist=>$runlist };
}

# -------------------------------------------------------------------
sub report_chromosomes {
  my $karyotype = shift;
  for my $chr (
	       sort {
		 $karyotype->{$a}{chr}{display_order} <=> $karyotype->{$b}{chr}{display_order}
	       } keys %$karyotype
	      ) {
    next unless $karyotype->{$chr}{chr}{display};
    
    printinfo(
	      $chr,
	      $karyotype->{$chr}{chr}{display_order},
	      $karyotype->{$chr}{chr}{scale},
	      $karyotype->{$chr}{chr}{display_region}
	      ? $karyotype->{$chr}{chr}{display_region}->run_list
	      : $DASH,
	      $karyotype->{$chr}{chr}{length_cumul}
	     );
  }
}

# Quickly check whether a point appears on a drawn portion of
# a chromosome. An ideogram must exist and have a cover that
# intersects with the data point coordinate. Not using Set::IntSpan
# here because it is too slow.
sub is_on_ideogram {
	my $datum       = shift;
	my $on_ideogram = 1;
	for my $point ( @{$datum->{data}}) {
		my $chr       = $point->{chr};
		my $ideograms = Circos::get_ideograms_by_name($chr);
		# If the chromosome is not being displayed, it has no ideogram.
		return if ! defined $ideograms;
		my ($start,$end) = ($point->{start},$point->{end});
		for my $ideogram (@$ideograms) {
			for my $cover (@{$ideogram->{covers}}) {
				my ($cstart,$cend) = ($cover->{set}->min,$cover->{set}->max);
				if($cstart > $end || $cend < $start) {
					# not on ideogram
				} else {
					return 1;
				}
			}
		}
	}
	# none of the points coordinates fell inside any ideogram cover
	return;
}

1;
