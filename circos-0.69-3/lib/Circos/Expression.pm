package Circos::Expression;

=pod

=head1 NAME

Circos::Expression - expression and text parsing routines for Geometry in Circos

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
);

use Carp qw( carp confess croak );
use Data::Dumper;
use FindBin;
use Params::Validate qw(:all);
use Math::Round;
use Math::VecStat qw(average);
use List::Util qw(min max);
use Text::Balanced qw(extract_bracketed);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration;
use Circos::Constants;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;

use Memoize;

for my $f (qw(format_condition)) {
	memoize($f);
}

# -------------------------------------------------------------------
sub format_condition {
  #
  # apply suffixes kb, Mb, Gb (case-insensitive) trailing any numbers
  # and apply appropriate multiplier to the number
  #
  my $condition = shift;
  $condition =~ s/([\d\.]+)kb/sprintf("%d",$1*1e3)/eig;
  $condition =~ s/([\d\.]+)Mb/sprintf("%d",$1*1e6)/eig;
  $condition =~ s/([\d\.]+)Gb/sprintf("%d",$1*1e9)/eig;
  $condition =~ s/(\d+)bp/$1/ig;
  return $condition;
}

# -------------------------------------------------------------------
# The check for eval() has been moved to this function. The expression
# will be evaluated if it is wrapped in eval(...) or if
# -force_eval=>1 is passed in %args
sub eval_expression {
	my ($datum,$expr,$param_path,%args) = @_;
	return if ! defined $expr;
	my $auto_eval = fetch_conf("auto_eval");
	my $debug = 0;
	while(1) {
		my $expr_parsed = parse_expression($datum,$expr,$param_path,%args);
		$debug && printinfo("expr->parse",$expr,$expr_parsed);
		$debug && printinfo("parsing",$expr_parsed);
		if($expr_parsed ne $expr) {
			printdebug_group("parse","expression",$expr,"->",$expr_parsed);
		}
		my $for_eval;
		if ( $expr_parsed =~ /^eval\(\s*(.*)\s*\)\s*$/ ) {
			$for_eval = $1;
		} elsif ($args{-force_eval} || $auto_eval) {
			$for_eval = $expr_parsed;
		}
		$debug && printinfo("for_eval",$for_eval);
		if(defined $for_eval) {
			no warnings 'all';
			my $eval = eval format_condition($for_eval);
			if($@) {
				if($auto_eval) {
					# assume everything is ok -- we can't know any different
					$eval = $expr_parsed;
				} else {
					if($@ =~ /bareword/i) {
						# couldn't parse further
						$eval = $expr_parsed;
					} else {
						fatal_error("rules","parse_error",$expr,$@) if $@;
					}
				}
			} else {
				printdebug_group("eval","expression",$expr_parsed,"->",$eval) if $eval ne $for_eval;
			}
			$expr = $eval;
		} else {
			$expr = $expr_parsed;
		}
		$debug && printinfo("parse->eval",$expr_parsed,$expr);
		last if ! $expr || $expr eq $expr_parsed;
	}
	return $expr;
}

# -------------------------------------------------------------------
sub parse_expression {
	#
	# var(VAR) refers to variable VAR in the point's data structure
	#
	# e.g.
	#
	# var(CHR)	var(START)  var(END)
	#
	# When the variable name is suffixed with a number, this number
	# indexes the points coordinate. For links, a point has two
	# coordinates 
	#
	# var(CHR1)  var(CHR2)
	#
	# If a point has two coordinates and the non-suffixed version is
	# used, then an error is returned unless the value is the same 
	# for both ends
	#
	# Dynamically generated variables are
	#
	# SIZE
	# POS
	# INTERCHR
	# INTRACHR

	my ( $datum, $expr, $param_path, %args ) = @_;

	printdebug_group("rule","eval expression",$expr);

	return 1 if true_or_yes($expr);
	return 0 if false_or_no($expr);

	my $expr_orig = $expr;
	my $num_coord = @{$datum->{data}} if ref $datum eq "HASH" && exists $datum->{data};

	# (.+?) replaced by (\w+)
	# parse _field_ and var(field)
	my $delim_rx   = qr/(_(\w+)_)/;
	my $var_rx     = qr/(var\((?!var)'?([\w\?|]+)'?\))/;
	my $track_rx   = qr/(track\((?!track)'?([\w|]+)'?\))/;
	while ( $expr  =~ /$var_rx/i || 
					(fetch_conf("legacy_underline_expression_syntax") && $expr =~ /$delim_rx/i) ) {
		my ($template,$var) = ($1,$2);
		if($var eq "?") {
			Circos::Debug::list_var_options($datum,$expr,$param_path);
			exit;
		}
		$var = lc $var unless fetch_conf("case_sensitive_parameter_names");
		my ($varroot,$varnum);
		if ($var =~ /^([^|]+?)(\d+)$/ ) {
			($varroot,$varnum) = ($1,$2);
		} else {
			($varroot,$varnum) = ($var,undef);
		}
		my $vardef;
		if($varroot =~ /(.+)[|](.+)/) {
			($varroot,$vardef) = ($1,$2);
		}
		my $value = fetch_variable($datum,$expr,$varroot,$varnum,$param_path);
		#printinfo($varroot,"num",$varnum,"def",$vardef,"value",$value);
		if(! defined $value && defined $vardef) {
			$value = $vardef;
		}
		replace_string( \$expr, $template, $value, %args );
		#printinfo($expr,$template,$value);
	}
	# parse functions f(var)
	for my $f (qw(conf on within between fromto tofrom from to chrlen)) {
		# for perl 5.10 using recursive rx
		# my $parens = qr/(\((?:[^()]++|(?-1))*+\))/;
		# no longer using this, to make the code compatible with 5.8
		# while( $expr =~ /($f$parens)/ ) {
	    while(my ($template,$arg) = extract_balanced($expr,$f,"(",")")) {
				$template = $f . $template;
				if($f eq "conf") {
					my @path = split(",",$arg);
					$expr = parse_conf_fn($expr,undef,undef);
					#printinfo($expr);
				}elsif($f eq "on") {
					my ($arg1,$arg2,$arg3) = split(",",$arg);
					fatal_error("rule","fn_wrong_arg",$f,$expr_orig,1) if ! defined $arg1;
					my $c0 = $datum->{data}[0]{chr} =~ /^$arg1/;
					my $c1 = $datum->{data}[1]{chr} =~ /^$arg1/ if exists $datum->{data}[1];
					if(defined $arg2 && defined $arg3) {
						if($c0) {
							my $d0 = span_distance($arg2,$arg3,$datum->{data}[0]{start},$datum->{data}[0]{end});
							$c0 &&= $d0 < 0;
						}
						if($c1) {
							my $d1 = span_distance($arg2,$arg3,$datum->{data}[1]{start},$datum->{data}[1]{end});
							$c1 &&= $d1 < 0;
						}
					}
					my $result = $c0 || $c1 || 0;
					replace_string( \$expr, $template, $result);
				} elsif ($f eq "within") {
					my ($arg1,$arg2,$arg3) = split(",",$arg);
					fatal_error("rule","fn_wrong_arg",$f,$expr_orig,1) if ! defined $arg1;
					my $c0 = $datum->{data}[0]{chr} =~ /^$arg1/;
					my $c1 = $datum->{data}[1]{chr} =~ /^$arg1/ if exists $datum->{data}[1];
					if(defined $arg2 && defined $arg3) {
						if($c0) {
							my $d0 = span_distance($arg2,$arg3,$datum->{data}[0]{start},$datum->{data}[0]{end});
							$c0 &&= -$d0 == $datum->{data}[0]{set}->cardinality-1;
						}
			if($c1) {
			    my $d1 = span_distance($arg2,$arg3,$datum->{data}[1]{start},$datum->{data}[1]{end});
			    $c1 &&= -$d1 == $datum->{data}[0]{set}->cardinality-1;
			}
		    }
		    my $result = $c0 || $c1 || 0;
		    replace_string( \$expr, $template, $result);
		} elsif ($f eq "between") {
		    my ($arg1,$arg2) = split(",",$arg);
		    fatal_error("rule","fn_wrong_arg",$f,$expr_orig,2) if ! defined $arg1 || ! defined $arg2;
		    fatal_error("rule","fn_need_2_coord",$f,$expr_orig,$arg1,$arg2) if $num_coord != 2;
		    my $result = 
			($datum->{data}[0]{chr} =~ /^$arg1$/i && $datum->{data}[1]{chr} =~ /^$arg2$/i) 
			||
			($datum->{data}[0]{chr} =~ /^$arg2$/i && $datum->{data}[1]{chr} =~ /^$arg1$/i);
		    replace_string( \$expr, $template, $result || 0);
		} elsif ($f eq "fromto") {
		    my ($arg1,$arg2) = split(",",$arg);
		    fatal_error("rule","fn_wrong_arg",$f,$expr_orig,2) if ! defined $arg1 || ! defined $arg2;
		    fatal_error("rule","fn_need_2_coord",$f,$expr_orig,$arg1,$arg2) if $num_coord != 2;
		    my $result = $datum->{data}[0]{chr} =~ /^$arg1$/i && $datum->{data}[1]{chr} =~ /^$arg2$/i;
		    replace_string( \$expr, $template, $result || 0);
		} elsif ($f eq "tofrom") {
		    my ($arg1,$arg2) = split(",",$arg);
		    fatal_error("rule","fn_wrong_arg",$f,$expr_orig,2) if ! defined $arg1 || ! defined $arg2;
		    fatal_error("rule","fn_need_2_coord",$f,$expr_orig,$arg1,$arg2) if $num_coord != 2;
		    my $result = $datum->{data}[0]{chr} =~ /^$arg2$/i && $datum->{data}[1]{chr} =~ /^$arg1$/i;
		    replace_string( \$expr, $template, $result || 0);
		} elsif ($f eq "to") {
		    my ($arg1) = split(",",$arg);
		    fatal_error("rule","fn_wrong_arg",$f,$expr_orig,1) if ! defined $arg1;
		    fatal_error("rule","fn_need_2_coord",$f,$expr_orig,"-",$arg1) if $num_coord != 2;
		    my $result = $datum->{data}[1]{chr} =~ /^$arg1$/i;
		    replace_string( \$expr, $template, $result || 0);
		} elsif ($f eq "from") {
		    my ($arg1) = split(",",$arg);
		    fatal_error("rule","fn_wrong_arg",$f,$expr_orig,1) if ! defined $arg1;
		    fatal_error("rule","fn_need_2_coord",$f,$expr_orig,$arg1,"-") if $num_coord != 2;
		    my $result = $datum->{data}[0]{chr} =~ /^$arg1$/i;
		    replace_string( \$expr, $template, $result || 0);
		} elsif ($f eq "chrlen") {
		    my ($arg) = split(",",$arg);
		    $arg =~ s/[\'\"]//g;
		    my $ideograms = Circos::get_ideograms_by_name($arg);
		    my $result = $ideograms->[0]->{chrlength};
		    replace_string( \$expr, $template, $result);
		}
	    }
									}
	return $expr;
}

sub fetch_variable {
	my ($datum,$expr,$var,$varnum,$param_path) = @_;
	my $num_coord = @{$datum->{data}};
	# If this data collection has only one data value (e.g. scatter plot)
	# then assume that any expression without an explicit number is refering
	# to the data point (e.g. _SIZE_ acts like _SIZE1_)
	my $varname = defined $varnum ? $var.$varnum : $var;
	if($param_path && defined seek_parameter( $varname, @$param_path )) {
		# if the variable 'var$varnum' exists, just return it without
		# doing any checkingv
		return seek_parameter( $varname, @$param_path );
	}
	if($num_coord == 1) {
		if(! defined $varnum) {
			# var(START) treated like var(START1)
			$varnum = 1;
		} elsif ($varnum != 1) {
			# var(STARTN) must have N=1
			fatal_error("rule","bad_coord",$var,$varnum,$num_coord);
		}
	} elsif ($num_coord == 2) {
		if(! defined $varnum) {
			# var(START) treated like var(START1) but only if var(START1) eq var(START2)
			my $v1 = fetch_variable($datum,$expr,$var,1,$param_path);
			my $v2 = fetch_variable($datum,$expr,$var,2,$param_path);
			if( (! defined $v1 && ! defined $v2) || ($v1 eq $v2) ) {
		    # the only consistent conditions are
		    # - neither is defined
		    # - both are defined and equal
		    return $v1;
			} else {
		    fatal_error("rule","conflicting_coord",
										$var,$num_coord,
				$v1,$v2,
										$var,$var);
			}
		} elsif ($varnum != 1 && $varnum != 2) {
			# var(STARTN) must have N=1 or N=2
			fatal_error("rule","bad_coord",$var,$varnum,$num_coord);					
		}
	} else {
		fatal_error("rule","wrong_coord_num",$num_coord);
	}

	my $varidx = $varnum - 1;
	my $data = $datum->{data};
	my $value;
	$var = lc $var unless fetch_conf("case_sensitive_parameter_names");
	if( exists $datum->{param}{$var} ) {
		$value = $datum->{param}{$var};
	} elsif ( exists $data->[$varidx]{$var} ) {
		$value = $data->[$varidx]{$var};
	} elsif ( $param_path && defined seek_parameter( $var, @$param_path ) ) {
		$value = seek_parameter( $var, @$param_path );
	} elsif ( $var eq "size" ) {
		$value = $data->[$varidx]{end} - $data->[$varidx]{start} + 1;
	} elsif ( $var eq "pos" ) {
		$value = round ($data->[$varidx]{start}+$data->[$varidx]{end})/2;
	} elsif ( $var eq "intrachr" ) {
		fatal_error("rule","need_2_coord","intrachr",$num_coord) if $num_coord != 2;
		$value = $data->[0]{chr} eq $data->[1]{chr} ? 1 : 0;
	} elsif ( $var eq "interchr" ) {
		fatal_error("rule","need_2_coord","intrachr",$num_coord) if $num_coord != 2;
		$value = $data->[0]{chr} ne $data->[1]{chr} ? 1 : 0;
	} else {
		if(fetch_conf("skip_missing_expression_vars")) {
	    $value = undef;
		} else {
			$value = seek_parameter($var.$varnum,@$param_path);
			if(! defined $value) {
				fatal_error("rules","no_such_field",$expr,$var,Dumper($datum));
			}
		}
	}
	#$value = Circos::unit_strip($value);
	printdebug_group("rule","found variable",$var."[$varnum]","value",$value);
	return $value;
}

# -------------------------------------------------------------------
sub replace_string {
  my ( $target, $source, $value, %args ) = @_;
	$value = 0 if ! defined $value;
	if ( $value =~ /[^0-9-.]/ && $value ne "undef" ) {
		if($args{-noquote}) {
			$$target =~ s/\Q$source\E/$value/g;
		} else {
			$$target =~ s/\Q$source\E/'$value'/g;
		}
	} else {
		$$target =~ s/\Q$source\E/$value/g;
	}
}

################################################################
# Given an expression (e.g. var(abc) == 1) and a prefix (e.g. var)
# extract arguments that follow the prefix which are encapsulated
# in balanced delimiters (delim_start, delim_end)
#
# Returns the raw arguments and a version stripped of delimiters
#
# var (abc ( def ) )def(a) 
#
# returns
#
# (abc ( def ) )
# abc ( def )
#
# If no balanced argument is found, returns undef

sub extract_balanced {
	my ($expr,$prefix,$delim_start,$delim_end) = @_;
	if($expr =~ /($prefix\s*)(\Q$delim_start\E.*)/) {
		my $arg = $2;
		my @result = extract_bracketed($arg,$delim_start);
		if(defined $result[0]) {
			my $balanced = $result[0];
			$balanced =~ s/^\s*\Q$delim_start\E\s*//;
			$balanced =~ s/\s*\Q$delim_end\E\s*$//;
			return ($result[0],$balanced);
		}
	}
	return;
}

1;
