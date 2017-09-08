package Circos::IO;

=pod

=head1 NAME

Circos::Utils - IO routines for Circos

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
use Storable qw(dclone);
use Cwd;
use FindBin;
use Data::Dumper;
use File::Spec::Functions;
use Math::Round;
use Math::VecStat qw(sum);
use Params::Validate qw(:all);
use Regexp::Common qw(number);

use POSIX qw(floor ceil);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Constants;
use Circos::Colors;
use Circos::Configuration;
use Circos::Debug;
use Circos::Error;
use Circos::Ideogram;
use Circos::Utils;
use Circos::Unit;

sub band_to_coord {
	my ($chr,$band,$k) = @_;
	my $span = Set::IntSpan->new();
	for my $b (@{$k->{$chr}{band}}) {
		if($b->{name} =~ /$band( \. | $ )/xi || ( $band =~ /[pq]$/ && $b->{name} =~ /^$band/) ) {
			printdebug_group("band",$chr,$band,"includes",$b->{name},$b->{set}->min,$b->{set}->max);
			$span->U($b->{set});
		}
	}
	printdebug_group("band",$chr,$band,"span",$span->min,$span->max);
	return {chr=>$chr,start=>$span->min,end=>$span->max};
}

# -------------------------------------------------------------------
sub read_data_file {
  # Read a data file and associated options.
  #
  # Depending on the data type, the format is one of
  #
  # - interval data
  # chr start end options
  #
  # - interval data with value (or label)
  # chr start end value options
  #
  # where the options string is of the form
  #
  # var1=value1,var2=value2,...

  my ($file,$type,$options,$KARYOTYPE) = @_;

  open(F,$file) || fatal_error("io","cannot_read",$file,$type,$!);
  printdebug_group("io","reading input file",$file,"type",$type);

  # specify '-' if a field is not used and to be skipped

  my $line_type = {
									 coord_options       => [qw(chr start end options)],
									 coord_value_options => [qw(chr start end value options)],
									 coord_label_options => [qw(chr start end label options)],
									 link_twoline        => [qw(id chr start end options)],
									 link                => [qw(chr start end chr start end options)],
									 link_translocation  => [qw(kstring options)],
									};

  my $fields = {
								scatter      => $line_type->{coord_value_options},
								line         => $line_type->{coord_value_options},
								histogram    => $line_type->{coord_value_options},
								heatmap      => $line_type->{coord_value_options},
								highlight    => $line_type->{coord_value_options},
								tile         => $line_type->{coord_value_options},
								text         => $line_type->{coord_value_options},
								connector    => $line_type->{coord_value_options},
								link_translocation => $line_type->{link_translocation},
								link_twoline => $line_type->{link_twoline},
								link         => $line_type->{link},

							 };

	# The value can now be any string. This allows the same data files to be used
	# for text and data tracks.

  my $rx = {
						chr     => { rx => qr/^[\w.:&-]+$/,
												 comment => "word with optional -.:&" },
						start   => { rx => qr/^-?[\d,_]+$/,
												 sx_from => qr/[,_]/,
												 sx_to   => "",
												 comment => "integer" },
						end     => { rx => qr/^-?[\d,_]+$/,
												 sx_from => qr/[,_]/,
												 sx_to   => "",
												 comment => "integer" },
						value   => { rx => qr/^.+/,
												 comment => "non-empty string" },
						options => { rx => qr/=/,
												 comment => "variable value pair (x=y)" },
						kstring => { rx => qr/./,
												 comment => "ISCN string" },
					 };

  my ($data,$prev_value);
  my ($recnum,$linenum) = (0,0);

  start_timer("io");

  my $param_type = $type =~ /link/ ? "link" : $type;

  my $hide_link_twoline;

  my $delim_rx = fetch_conf("file_delim") || undef;
  if ($delim_rx && fetch_conf("file_delim_collapse")) {
    $delim_rx .= "+";
  }

 LINE:
  while (<F>) {
    chomp;
    s/^\s+//;										# strip leading spaces
    s/\s+\#.*//;								# strip comments
    s/\r$//;										# strip windows carriage return
    next if /^(#|$)/;						# skip empty lines
    next if $options->{file_rx} && ! /$options->{file_rx}/;
    $linenum++;
    my @tok = $delim_rx ? split(/$delim_rx/) : split;
		if ($type  =~ /link/) {
			if(@tok < 3) {
				$type = "link_translocation";
			} elsif (@tok < 6 ) {
				$type = "link_twoline";
			} else {
				$type = "link";
			}
		}

    my $line  = $_;
    my $datum = { data => [ ], param => { } };

		my @fields = @{$fields->{$type}};
		if($type !~ /link/) {
			if(@tok == @fields) {
				# all fields are being used
			} elsif (@tok == @fields-1) {
				# one of the fields is missing - either the value
				# or options. Figure out which.
				my $last_tok = $tok[-1];
				if($last_tok =~ /=/) {
					# look like the last field is the value, not options
					@fields = grep($_ !~ /value/, @fields);
				}
			} elsif (@tok == @fields-2 
							 && grep($type eq $_, qw(tile highlight connector))) {
				@fields = @fields[0..2];
			} else {
				fatal_error("parsedata","bad_field_count",$_,$file,$type,join(" ",@fields));
			}
		}

	FIELD:
    for my $i ( 0 .. @fields-1 ) {
      my $value = $tok[$i];
      next unless defined $value;
      my $field = $fields[$i];
			$field =~ s/\?$//;
      # make sure the value has the right format, if a format rx is available
      if ( $rx->{$field} ) {
				my ($rx_field,$rxcomment) = @{$rx->{$field}}{qw(rx comment)};
				if ( $value !~ /$rx_field/ ) {
					fatal_error("parsedata","bad_field_format",$field,$value,$rxcomment,$file,$line);
				}
				if(exists $rx->{$field}{sx_from} && exists $rx->{$field}{sx_to}) {
					$value =~ s/$rx->{$field}{sx_from}/$rx->{$field}{sx_to}/ig;
				}
      }

      # if this field is 'chr' make sure this chromosome exits
      if ($field eq "chr") {
				if ( ! exists $KARYOTYPE->{$value} ) {
					if (fetch_conf("undefined_ideogram") eq "exit") {
						fatal_error("parsedata","no_such_ideogram",$value,$file,$line);
					} else {
						next LINE;
					}
				} elsif ( ! $KARYOTYPE->{$value}{chr}{display} ) {
					# this chromosome is not displayed
					if ($type eq "link_twoline") {
						$hide_link_twoline->{$datum->{data}[0]{id}}++;
					}
					next LINE;
				}
      }
      if ($field eq "id" && $type eq "link_twoline" && $hide_link_twoline->{$value}) {
				next LINE;
      }

      # If this is an options field, store it in the 'param' key.
      if ( $field eq "options" && defined $value && $value ne $EMPTY_STR) {
				my $options = parse_options($value);
				$datum->{param} = $options;
			} elsif ($field eq "kstring") {
				$datum->{param} = { kstring=>$value };
      } else {
				# all fields are named
				my $field_name = $field eq "label" ? "value" : $field;
				# Store this field in the datum's point. If an entry
				# with this field already exists, another is created.
				# This automatically accommodates data with multiple
				# coordinates (e.g. link)
				if (! exists $datum->{data}[0]{$field_name}) {
					$datum->{data}[0]{$field_name} = $value;
				} else {
					$datum->{data}[1]{$field_name} = $value;
				}
      }
      if ( $field eq "value" && defined $prev_value) {
				# min_value_change requies that adjacent data points vary by a minimum amount
				if ($options->{min_value_change} && abs($value-$prev_value) < $options->{min_value_change} ) {
					next LINE;
				}
				# skip_run avoids consecutive data points with the same value
				if ($options->{skip_run} && $value eq $prev_value ) {
					next LINE;
				}
      }
    }

    $prev_value = $datum->{data}[0]{value};

		# parse karyotype strings that correspond to translocations
		if($type eq "link_translocation") {
			my $kstr = $datum->{param}{kstring};
			my ($chr1,$chr2,$b1,$b2) = ( $kstr =~ /t\((.+);(.+)\)\((.+);(.+)\)/ );
			$chr1 = "hs$chr1";
			$chr2 = "hs$chr2";
			
			$datum->{data} = [ band_to_coord($chr1,$b1,$KARYOTYPE),
												 band_to_coord($chr2,$b2,$KARYOTYPE) ];
			
		}
		
		#printdumper($datum);

    # verify that this data point is on a drawn ideogram
    if ( ! is_on_ideogram($datum) ) {
      if ($type eq "link_twoline") {
				$hide_link_twoline->{$datum->{data}[0]{id}}++;
      }
      next LINE;
    }
    # if the start/end values are reversed, i.e. end<start, then swap them and set rev flag
    my $num_rev = 0;
    for my $i (0..@{$datum->{data}}-1) {
      my $point = $datum->{data}[$i];
      if ($point->{start} > $point->{end}) {
				@{$point}{qw(start end)} = @{$point}{qw(end start)};
				$point->{rev} = 1;
				$num_rev++;
      } else {
				$point->{rev} = 0;
      }
    }

    # if an odd number of coordinates is inverted, label
    # this datum inverted
    if ($type =~ /link/ && ! defined $datum->{param}{inv}) {
      if ($num_rev % 2) {
				$datum->{param}{inv} = 1;
      } else {
				$datum->{param}{inv} = 0;
      }
    }

    # if padding is required, expand the coordinate
    if ($type ne "text" && $type ne "tile") {
      if (my $padding = $options->{padding} || $datum->{param}{padding} ) {
				for my $point (@{$datum->{data}}) {
					$point->{start} -= $padding;
					$point->{end}   += $padding;
				}
      }
    }

    # if the minsize parameter is set, then the coordinate span is
    # expanded to be at least this value
    if (my $minsize = $options->{minsize} || $datum->{param}{minsize}) {
			$minsize = unit_parse( $minsize );
      Circos::DataPoint::apply_filter("minsize",
																			$minsize,
																			$datum);
			
    }

    # if a set structure was requested, make it
    if ($options->{addset}) {
      for my $point (@{$datum->{data}}) {
				$point->{set} = make_set( @{$point}{qw(start end)});
      }
    }

    if ($type eq "link_twoline") {
      my $linkid = $datum->{data}[0]{id};
      die "no link id".Dumper($datum) if ! defined $linkid;
      if (! $hide_link_twoline->{$linkid}) {
				push @{$data->{$linkid}}, $datum;
      }
    } elsif ( $type eq "histogram" 
							&& 
							defined $datum->{data}[0]{value}
							&&
							$datum->{data}[0]{value} =~ /,/ ) {
      #
      # for stacked histograms where values are comma separated
      #
      my @values = split( /,/, $datum->{data}[0]{value} );
			my $sum    = sum(@values);
      my ( @values_sorted, @values_idx_sorted );
      if ( $options->{sort_bin_values} ) {
				@values_sorted = sort { $b <=> $a } @values;
				@values_idx_sorted =
					map  { $_->[0] }
						sort { $b->[1] <=> $a->[1] }
							map  { [ $_, $values[$_] ] } ( 0 .. @values - 1 );
			} else {
				@values_sorted     = @values;
				@values_idx_sorted = ( 0 .. @values - 1 );
      }
			if($options->{normalize_bin_values}) {
				if($sum) {
					@values_sorted = map { $_/$sum } @values_sorted;
				}
			}
			if ( my $n = $options->{bin_values_num} ) {
				#printdumper($options);
				@values_sorted     = @values[0..$n-1] if $n < @values_sorted;
				@values_idx_sorted = @values_idx_sorted[0..$n-1] if $n < @values_idx_sorted;
				@values            = @values_sorted;
			}

      for my $i ( 0 .. @values - 1 ) {
				# first value has the highest z
				my $z         = @values - $i;
				my $cumulsum  = sum( @values_sorted[ 0 .. $i ] );
				my $thisdatum = dclone($datum);

				$thisdatum->{data}[0]{value} = $cumulsum;
				$thisdatum->{param}{z}       = $z;

				if ( $options->{param} ) {
					for my $param ( keys %{ $options->{param} } ) {
						my $value = $datum->{param}{$param} || $options->{param}{$param};
						next unless defined $value;
						my @param_values;
						if ($param eq "fill_color") {
							#printinfo(Circos::color_to_list($value));
							@param_values = Circos::color_to_list($value);

						} else {
							@param_values = split(/\s*,\s*/,$value)
						}
						next unless @param_values;
						my $param_value = $param_values[ $values_idx_sorted[$i] % @param_values ];
						$thisdatum->{param}{$param}  = $param_value;
						$thisdatum->{param}{stacked} = 1;
					}
				}
				push @{$data}, $thisdatum;
      }
    } else {
      push @{$data}, $datum;
    }
    $recnum++;
    if ($options->{record_limit} && $recnum >= $options->{record_limit}) {
      if ($type eq "link_twoline") {
				$hide_link_twoline->{$datum->{data}[0]{id}}++;
      }
      last;
    }
  }
  stop_timer("io");
  printdebug_group("io","read",$recnum."/".$linenum,"records/lines");    
  # for old-style links (defined on two lines), collect the
  # individual link ends, keyed by the record number, into a single
  # data structure
  if ($type eq "link_twoline") {
    my $data_new = [];
    for my $linkid (sort keys %$data) {
      next if $hide_link_twoline->{$linkid};
      my $datum_new;
      for my $datum (@{$data->{$linkid}}) {
				push @{$datum_new->{data}}, $datum->{data}[0];
				for my $param (keys %{$datum->{param}}) {
					$datum_new->{param}{$param} = $datum->{param}{$param};
				}
      }
      my $num_coords = @{$datum_new->{data}};
      if ($num_coords == 1) {
				fatal_error("links","single_entry",$linkid,$file,Dumper($datum_new));
      } elsif ($num_coords > 2) {
				fatal_error("links","too_many_entries",$linkid,$file,$num_coords,Dumper($datum_new));
      }
      push @$data_new, $datum_new;
    }
    $data = $data_new;
  }
  # finally parse the params for data points that have been kept
	start_timer("dataparams");
	if ($data) {
		for my $i (0..@$data-1) {
			my $point = $data->[$i];
			if ($point->{param}) {
				#printdumper($point->{param});
				$point->{param} = Circos::parse_parameters($point->{param},$param_type);
			}
			$point->{param}{i} = $i;
			if ($type =~ /scatter|heatmap|hist|line/) {
				if (exists $data->[$i]{data}[0]{value}) {
					$point->{param}{prev_value} = $i > 0 ? $data->[$i-1]{data}[0]{value} : undef;
					$point->{param}{next_value} = $i < @$data-1 ? $data->[$i+1]{data}[0]{value} : undef;
					if(is_number($point->{data}[0]{value},"real",0)
						 &&
						 is_number($point->{param}{prev_value},"real",0)
						 &&
						 is_number($point->{param}{next_value},"real",0)
						) {
						$point->{param}{prev_delta} = $point->{data}[0]{value} - ($point->{param}{prev_value}||0);
						$point->{param}{next_delta} = ($point->{param}{next_value}||0) - $point->{data}[0]{value};
					}
				}
			}
		}
	}
	stop_timer("dataparams");
  return $data;
}

1;
