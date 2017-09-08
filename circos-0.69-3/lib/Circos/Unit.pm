package Circos::Unit;

=pod

=head1 NAME

Circos::Unit - utility routines for units in Circos

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
unit_fetch
unit_validate
unit_split
unit_strip
unit_test
unit_convert
unit_parse
parse_suffixed_number
);

use Carp qw( carp confess croak );
use FindBin;
use Data::Dumper;
use Params::Validate qw(:all);
use Regexp::Common qw(number);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration qw(%CONF $DIMS);
use Circos::Constants;
use Circos::Debug;
use Circos::Error;

use Memoize;

for my $f (qw(unit_fetch unit_validate unit_split unit_strip unit_test unit_parse )) {
memoize($f);
}
memoize("unit_convert",NORMALIZER=>"unit_convert_normalizer");

# -------------------------------------------------------------------
sub unit_fetch {
  # Return a value's unit, with sanity checks. The unit fetch is the
  # basic unit access function and it should be the basis for any
  # other unit access wrappers. This is the only function that
  # checks against a list of acceptable units.
  #
  # Returns the value of units_nounit if the value has no unit
  # (i.e., bare number)
  #
  # Returns undef if the value string does not end in one of the
  # valid unit types
  #
  # If you just want to test the sanity of a value's format, call
  # unit_fetch in void context

  my ($value,$param) = @_;

  printdebug_group("unit","fetching unit from",$value);
  if ( ! $CONF{units_ok} ) {
      fatal_error("system","missing_units_ok","bupr");
  }
  if ( ! $CONF{units_nounit} ) {
      fatal_error("system","missing_units_nounit","n");
  }
  if (! defined $value) {
      return $CONF{units_nounit};
  } elsif ( $value =~ /\d$/ ) {
      # any value that ends in a number has no u nit
      printdebug_group("unit",$value,"ends in number - no unit");
      return $CONF{units_nounit};
  } elsif ( $value =~ /^(.*)([$CONF{units_ok}$CONF{units_nounit}])$/ ) {
      my ($root,$unit) = ($1,$2);
      printdebug_group("unit",$value,"root",$root,"candidate unit",$unit);
      # in order for $unit to be considered a unit, $root must be a real number
      if($root =~ /$RE{num}{real}/) {
	  printdebug_group("unit",$value,"root",$root,"is a number - unit",$unit);
	  return $unit;
      } else {
	  printdebug_group("unit",$value,"root",$root,"is not a number - no unit");
	  return $CONF{units_nounit};
      }
      #return $1;
  } else {
      return $CONF{units_nounit};
      #confess "The parameter [$param] value [$value] is incorrectly formatted.";
  }
}

# -------------------------------------------------------------------
sub unit_validate {
  # Verify that a value's unit is one out of a provided list
  #
  # potential units are
  #
  # r : relative
  # p : pixel
  # u : chromosome unit (defined by chromosomes_unit parameter)
  # b : bases, or whatever your natural unit of distance is along the ideogram
  # n : no unit; value is expected to end in a digit
  #
  # If called without a list of acceptable units, unit_validate returns
  # the value if it is correctly formatted (i.e., an acceptable unit is found)
  # stripped of its unit

  my ( $value, $param, @unit ) = @_;
  confess "not units provided" unless @unit;

  # unit_fetch will die if $value isn't correctly formatted
  my $value_unit = unit_fetch( $value, $param );
  if ( grep( $_ eq $value_unit, @unit ) ) {
    return $value;
  } else {
      if(defined $value) {
				fatal_error("system","wrong_unit",$param,$value,$value_unit,join($COMMA,@unit));
      } else {
				fatal_error("system","undef_parameter",$param,join($COMMA,@unit));
      }
		}
}

# -------------------------------------------------------------------
sub unit_split {
  # Separate the unit from the value, and return the unit-less
  # number and the unit as a list
    my ($value,$param) = @_;
    my $unit         = unit_fetch( $value, $param );
    my $value_nounit = unit_strip( $value, $param );
    return ( $value_nounit, $unit );
}

# -------------------------------------------------------------------
sub unit_strip {
  # Remove the unit from a value and return the unit-less value
  my $value = shift;
  my $param = shift;
  return undef if ! defined $value;
  my $unit  = unit_fetch($value,$param);
  $value =~ s/$unit$// unless $unit eq $CONF{units_nounit};
  return $value;
}

# -------------------------------------------------------------------
sub unit_test {
  # Verify that a unit is acceptable. If so, return the unit, otherwise
  # die.
  my $unit = shift;
  if ( $unit =~ /[$CONF{units_ok}]/o || $unit eq $CONF{units_nounit} ) {
    return $unit;
  } else {
      fatal_error("system","unit_format_fail",$unit);
  }
}

# -------------------------------------------------------------------
# Create input string for unit_convert used by Memoize
sub unit_convert_normalizer {
	my %params = @_;
	my @norm;
	push @norm, $params{from};
	push @norm, $params{to};
	if(exists $params{factors}) {
		for my $key (sort keys %{$params{factors}}) {
	    push @norm, $key, $params{factors}{$key} || 0;
		}
	}
	return join(",",@norm);
}

# -------------------------------------------------------------------
sub unit_convert {
    # Convert a value from one unit to another.
    start_timer("unitconvert");
    $CONF{debug_validate} && validate(
	@_,
	{
	    from    => { type => SCALAR },
	    to      => { type => SCALAR },
	    factors => { type => HASHREF, optional => 1 },
	}
	);
    my %params = @_;
    start_timer("unitconvert_delegate");
    my ( $value, $unit_from ) = unit_split( $params{from} );
    my $unit_to               = unit_test(  $params{to} );
    stop_timer("unitconvert_delegate");
    my $factors = $params{factors};
    
    # by default, no unit is the same as pixel unit
    $factors->{"np"} ||= 1;
    $factors->{"pn"} ||= 1;
    $factors->{"nb"} ||= 1;
    $factors->{"ub"} ||= Circos::Configuration::fetch_conf("chromosomes_units");
	
    start_timer("unitconvert_decision");
    my $return;
    if ( $factors->{ $unit_from . $unit_to } ) {
	$return = $value * $factors->{ $unit_from . $unit_to };
    } elsif ( $factors->{ $unit_to . $unit_from } ) {
	$return = $value * 1 / $factors->{ $unit_from . $unit_to };
    } elsif ( $unit_to eq $unit_from ) {
	$return = $value;
    } else {
	fatal_error("unit","conversion_fail",
		    $value,$unit_from,$unit_to,
		    join(" ",map { join("->",split("",$_)) } 
			 grep($_ ne "np" && $_ ne "pn", keys %{$params{factors}})));
    }
    stop_timer("unitconvert_decision");
    stop_timer("unitconvert");
    return $return;
}

# -------------------------------------------------------------------
sub unit_parse {
    # Parses a variable value that contains units. The value can be a single
    # value like
    #
    # 0.1r
    #
    # or an arithmetic expression
    #
    # TERM +/- TERM +/- TERM ...
    #
    # where TERM is one of
    #
    # 1. single value with any supported unit
    # 2. the string "dims(a,b)" for some parameters a,b
    
    start_timer("unitparse");

    my $expression = shift;
    my $ideogram   = shift;
    my $side       = shift;
    my $relative   = shift;
    
    printdebug_group("unit","parse",$expression,$side,$relative);
    if(! defined $expression) {
			stop_timer("unitparse");
			return undef;
    }
    
    my $radius_flag;
    if ( defined $side ) {
			if ( $side eq $DASH || !$side || $side =~ /inner/i ) {
				$radius_flag = "radius_inner";
			} elsif ( $side eq $PLUS_SIGN || $side == 1 || $side =~ /outer/i ) {
				$radius_flag = "radius_outer";
			}
    }
    
    if ($ideogram) {
			$expression =~ s/ideogram,/ideogram,$ideogram->{tag},/g;
    } else {
			$expression =~ s/ideogram,/ideogram,default,/g;
		}
    
    while ( $expression =~ /(dims\(([^\)]+)\))/g ) {
			my $string = $1;
			my $hash   = "\$" . $string;
			my @args   = split( $COMMA, $2 );
			
			#printinfo("dims",$string,"args",@args);
			$hash = sprintf( "\$DIMS->%s",join( $EMPTY_STR, map { sprintf( "{'%s'}", $_ ) } @args ) );
			
			#printdumper($DIMS->{ideogram}{default});
			my $hash_value = eval $hash;
			if(! defined $hash_value) {
				printdumper($DIMS->{ideogram});
	    fatal_error("system","bad_dimension",$hash,$expression) if ! defined $hash_value;
			}
			$expression =~ s/\Q$string\E/$hash_value/g;
    }
    
    while ( $expression =~ /([\d\.]+[$CONF{units_ok}])/g ) {

			my $string = $1;
			my ( $value, $unit ) = unit_split($string);
			my $value_converted;
			
			if ( $unit eq "u" ) {
				
				# convert from chromosome units to bases
				$value_converted = unit_convert(
																				from    => $string,
																				to      => "b",
																				factors => { ub => $CONF{chromosomes_units} }
																			 );
			} else {
				
				# convert from relative or pixel to pixel
				my $rpfactor;
				my $tag = $ideogram ? $ideogram->{tag} : "default";
				#printdumper($ideogram) if $ideogram->{chr} eq "hs1";
				if ( $value < 1 ) {
					$rpfactor = $relative
						|| $DIMS->{ideogram}{$tag}{ $radius_flag || "radius_inner" };
				} else {
					$rpfactor = $relative
						|| $DIMS->{ideogram}{$tag}{ $radius_flag || "radius_outer" };
				}
				$value_converted = unit_convert(
																				from    => $string,
																				to      => "p",
																				factors => { rp => $rpfactor }
																			 );
			}
			$expression =~ s/$string/$value_converted/;
    }
    $expression = eval $expression;
    stop_timer("unitparse");
    return $expression;
	}

sub parse_suffixed_number {
	my $str          = shift;
	return if ! defined $str;
	my $suffix_power = { k=>3, m=>6, g=>9, t=>12 };
	my $parsed;
	while($str =~ /(([\d+.]+)([kmgt])b?)/ig) {
		$parsed = 1;
		my ($to_replace,$num,$suffix) = ($1,$2,$3);
		$suffix = lc $suffix;
		if(! defined $suffix_power->{$suffix}) {
			error("ticks","bad_suffix",$suffix,$to_replace);
		} else {
			my $multiplier = 10**$suffix_power->{$suffix};
			$str =~ s/$to_replace/($num*$multiplier)/;
		}
	}
	if($parsed) {
		my $str_eval = eval $str;
		if ($@) {
			error("ticks","unparsable",$str);
		}
		return $str_eval;
	} else {
		return $str;
	}
}

1;
