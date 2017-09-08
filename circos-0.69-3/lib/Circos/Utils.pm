package Circos::Utils;

=pod

=head1 NAME

Circos::Utils - utility routines for Circos

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
add_thousands_separator
compare_str 
compare_strs 
current_function
current_package
defined_and_zero
exists_parameter 
extract_number
false_or_no
first_defined
get_file_annotation
get_hash_leaf
hide
is_blank
is_comment
is_hidden 
is_in_list
is_integer
is_num_equal
is_num_notequal
is_number
list_has_defined
list_parameters
locate_file
log10
log2
make_list
make_set
match_string
not_defined_or_one
pairwise_and
pairwise_or
parse_as_rx
parse_csv
parse_options
put_between
remap
remap_int
remap_round
remap_to_list
remove_undef_keys
replace
round_custom
round_up 
sample_list 
seek_parameter 
seek_parameter_glob
show
span_distance
str_to_list 
strip_quotes
to_number
track_r0
track_r1
true_or_yes
use_set
);

use Carp qw( carp confess croak );
use Cwd;
use FindBin;
use File::Spec::Functions;
use Math::Round;
#use Memoize;
use List::MoreUtils qw(uniq);
use Params::Validate qw(:all);
use Regexp::Common qw(number);

use POSIX qw(floor ceil);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Constants;
use Circos::Debug;
use Circos::Error;

# -------------------------------------------------------------------
sub strip_quotes {
	my $str = shift;
	$str =~ s/^['"]//;
	$str =~ s/['"]$//;
  return $str;
}
# -------------------------------------------------------------------
sub make_list {
  #
  # if passed an array ref, dereferences it and returns a list
  # if passed a list, returns the list
  # if passed undef/false returns an empty list
  #
  my $obj = shift or return ();

  if ( ref $obj eq 'ARRAY' ) {
    return @$obj;
  } else {
    return ( $obj );
  }
}

sub round_custom {
	my ($x,$round_type) = @_;
	if (! defined $round_type) {
		return int $x;
	} elsif ($round_type eq "round") {
		return round $x;
	} elsif ($round_type eq "floor") {
		return floor $x;
	} elsif ($round_type eq "ceil") {
		return ceil $x;
	}
}

sub to_number {
	my $x = shift;
	if($x =~ /($RE{num}{real})/) {
		$x = $1;
	}
	return $x;
}

#################################################################
# 
# 0  1  2  3  ...  k  k+1=list_max_idx
#
# 0     if  value < min
# 1..k  if          min <= value <= max
# k     if                          max < value

#
sub remap_to_list {
	my ($value,$min,$max,$base,$list) = @_;
	return undef if ref($list) ne "ARRAY";
	my $list_max_idx = @$list-1;
	my $idx;
	if($list_max_idx == 0) {
		$idx = 0;
	} elsif ($value < $min) {
		$idx = 0;
	} elsif ($value >= $max) {
		$idx = $list_max_idx;
	} elsif ($list_max_idx == 1) {
		# if we have only two elements, any value <= max is the first color
		$idx = 0;
	} elsif ($list_max_idx == 2) {
		# if we have three elements, any  min <= value <= max is the middle element
		$idx = 1;
	} else {
		my $value_remap = remap($value,$min,$max,1,$list_max_idx);
		$value_remap = $value_remap ** (1/$base) if defined $base;
		$idx = int $value_remap;
	}
	return $list->[$idx];
}

sub remap {
	my ($value,$min,$max,$remap_min,$remap_max) = @_;
	if (! defined $value ||
			! defined $min ||
			! defined $max ||
			! defined $remap_min ||
			! defined $remap_max) {
		fatal_error("function","remap_wrong_num_args");
	}

	return $remap_min if $value <= $min;
	return $remap_max if $value >= $max;

	if ($min == $max) {
		if ($remap_min == $remap_max) {
	    return $remap_min;
		} else {
	    fatal_error("function","remap_min_max",$min,$max,$remap_min,$remap_max);
		}
	}
	my $f = ( $value - $min ) / ( $max - $min );
	my $value_remap = $remap_min + $f * ($remap_max - $remap_min);
	#printinfo($value,$min,$max,$remap_min,$remap_max,$value_remap);
	return $value_remap;
}

sub pairwise_or {
	my ($a,$b,$x,$y) = @_;
	if (! defined $a || ! defined $b || ! defined $x || ! defined $y) {
		fatal_error("function","pairwise","pairwise_or",$a,$b,$x,$y);
	} else {
		return ($a eq $x && $b eq $y) || ($a eq $y && $b eq $x)
	}
}

sub pairwise_and {
	my ($a,$b,$x,$y) = @_;
	if (! defined $a || ! defined $b || ! defined $x || ! defined $y) {
		fatal_error("function","pairwise","pairwise_and",$a,$b,$x,$y);
	} else {
		return $a eq $x && $b eq $y;
	}
}

sub remap_int {
	return int remap(@_);
}

sub remap_round {
	return round remap(@_);
}

sub track_r1 {
	my ($counter,$t0,$tw,$tp) = @_;
	my $r1 = sprintf("%fr",$t0+$counter*($tw+$tp)+$tw);
	#printinfo("r1",$r1);
	return $r1;
}
sub track_r0 {
	my ($counter,$t0,$tw,$tp) = @_;
	my $r0 = sprintf("%fr",$t0+$counter*($tw+$tp));
	#printinfo("r0",$r0);
	return $r0;
}
sub replace {
	my ($x,$from,$to) = @_;
	$x =~ s/$from/$to/ig;
	return $x;
}

sub str_to_list {
	my $str = shift;
	return split(/\s*,\s*/, $str);
}

# -------------------------------------------------------------------
sub sample_list {
	# Given a list and regular expression, return the elements in the
	# list that match the regular expression.
	#
	# The results are sorted based on capture buffers from the regular expression.
	my ($rx,$list) = @_;
	my $rev = 0;
	if ($rx =~ /rev\((.+)\)/) {
		$rx  = $1;
		$rev = 1;
	}
	fatal_error("function","sample_list_bad_arg",$list,ref $list) unless ref($list) eq "ARRAY";
	return undef if ! $list;
	my @matches;
	for my $item (@$list) {
		if ($item =~ /^$rx$/) {
	    # pull out captured strings
	    my @captures = ();
	    for my $i (1..@+ - 1) {
				my $str = substr($item,$-[$i],$+[$i]-$-[$i]);
				push @captures, $str;
	    }
	    push @matches, {item=>$item,captures=>\@captures};
		}
	}
	my @result = map { $_->{item} } sort { compare_strs($a->{captures},$b->{captures}) } @matches;
	if ($rev) {
		return reverse @result;
	} else {
		return @result;
	}
}

sub parse_as_rx {
	my $rx = shift;
	return if ! defined $rx;
	if ($rx =~ /^\s*-?\/(.+)\/\s*$/) {
		return qr/$1/;
	} else {
		return;
	}
}

sub is_num_equal {
	my ($x,$y) = @_;
	return unless defined $x && defined $y;
	return $x == $y;
}

sub is_num_notequal {
	my ($x,$y) = @_;
	# return undef of neither inputs are defined
	return if ! defined $x && ! defined $y;
	# return true if only one input is undefined 
	return 1 if ! defined $x or ! defined $y;
	# if both are defined, check if they match
	return $x != $y;
}

sub match_string {
	my ($str,$rx) = @_;
	return unless defined $str;
	return unless defined $rx;
	if (ref($rx)) {
		return $str =~ /$rx/;
	} else {
		return $str eq $rx;
	}
}

# -------------------------------------------------------------------
sub compare_strs {
	my ($list1,$list2) = @_;
	my $result = 0;
	for my $i (0..@$list1-1) {
		return $result if ! defined $list1->[$i] || ! defined $list2->[$i];
		$result ||= compare_str($list1->[$i],$list2->[$i]);
	}
	return $result;
}

# -------------------------------------------------------------------
sub extract_number {
	my $str = shift;
	if ($str =~ /0*(\d+)/) {
		return $1;
	} else {
		return "";
	}
}

# -------------------------------------------------------------------
sub compare_str {
	my ($x,$y) = @_;
	if ( $x =~ /$RE{num}{real}/ && $y =~ /$RE{num}{real}/ ) {
		$x =~ s/^0*//;
		$y =~ s/^0*//;
		$x ||= 0;
		$y ||= 0;
		return $x <=> $y;
	} else {
		return $x cmp $y;
	}
}

# -------------------------------------------------------------------
sub round_up {
	my $value = shift;
	if ($value > int($value)) {
		return 1 + int($value);
	} else {
		return $value;
	}
}

# -------------------------------------------------------------------
sub put_between {
	my ($x,$min,$max) = @_;
	return $min if $x < $min;
	return $max if $x > $max;
	return $x;
}

################################################################
# 
sub is_number {
	my ($x,$rxtype,$strict,$min,$max) = @_;
	return if ! defined $x;
	$strict = 1 if ! defined $strict;
	my $pass = 1;
	eval {
		if ($x !~ /^$RE{num}{$rxtype}$/) {
			$pass = 0;
			fatal_error("parsedata","bad_number",$x,$rxtype) if $strict;
		}
	};
	if ($@) {
		fatal_error("parsedata","no_such_re",$x,$rxtype,$@);
	}
	return if ! $pass;
	if ( (defined $min && $x < $min)
			 ||
			 (defined $max && $x > $max)) {
		my $min_text = defined $min ? $min : "(";
		my $max_text = defined $max ? $max : ")";
		$pass = 0;
		fatal_error("parsedata","bad_number_range",$x,$rxtype,$min_text,$max_text) if $strict;
	}
	$pass ? return 1 : return;
}

sub is_integer {
  return $_[0] == int( $_[0] );
}

sub is_blank {
  my $string = shift;
  return $string =~ /^\s*$/;
}

sub is_comment {
  my $string = shift;
  return $string =~ /^\s*\#/;
}

# -------------------------------------------------------------------
sub seek_parameter_glob {
  my ( $param_name, $rewrite_rx, @data_structs ) = @_;
  my @target_string = split( /\|/, $param_name );
	my @param_rx      = list_parameters(@data_structs);
	my $params = {};
	for my $param (@param_rx) {
		if(grep($param =~ /$_/, @target_string)) {
			my $value = seek_parameter($param,@data_structs);
			if(defined $value) {
				my $param_name = $param;
				if($rewrite_rx) {
					$param_name =~ s/$rewrite_rx//;
				}
				$params->{$param_name} = $value;
			}
		}
	}
	return $params;
}

# -------------------------------------------------------------------
sub seek_parameter {
  # Given a parameter name and a list of hash references (or list
  # references to hashes), looks for the parameter and returns the
  # associated value. The parameter will also be extracted from any
  # hash pointed to by the "param" key in the data structure.
  #
  # If the parameter name contains "|" then this is used as a
  # delimiter to define synonyms of the parameter. This is helpful
  # when parameters have changed names but you wish to maintain
  # backward compatibility.
  #
  # value of x returned from $hash
  # seek_parameter("x",$hash);
  # value of x returned from $hash, and if not found, $anotherhash is tried
  # seek_parameter("x",$hash,$anotherhash);
  # value of x or y, whichever is seen first is returned
  # seek_parameter("x|y",$hash,$anotherhash);
  my ( $param_name, @data_structs ) = @_;
	return seek_parameter_glob($param_name, @data_structs) if $param_name =~ /[*]/;
  my @target_string = split( /\|/, $param_name );
	my $not_def_ok = 1;
  start_timer("parameter_seek");
  for my $str (@target_string) {
    for my $struct (@data_structs) {
      if ( ref($struct) eq "ARRAY" ) {
				for my $substruct (@$struct) {
					if (exists $substruct->{param} &&
							exists $substruct->{param}{$str} && ($not_def_ok || defined $substruct->{param}{$str})) {
						stop_timer("parameter_seek");
						return $substruct->{param}{$str};
					}
					if (exists $substruct->{$str} && ($not_def_ok || defined $substruct->{$str})) {
						stop_timer("parameter_seek");
						return $substruct->{$str};
					}
				}
      } elsif ( ref($struct) eq "HASH" ) {
				if (exists $struct->{param} &&
						exists $struct->{param}{$str} &&
						($not_def_ok || defined $struct->{param}{$str})) {
					stop_timer("parameter_seek");
					return $struct->{param}{$str};
				}
				if (exists $struct->{$str} && ($not_def_ok || defined $struct->{$str})) {
					stop_timer("parameter_seek");
					return $struct->{$str};
				}
      } else {
				printdumper(\@data_structs);
				confess "cannot extract parameter from this data structure (shown above - report this please)";
      }
    }
  }
  stop_timer("parameter_seek");
  return undef;
}

# -------------------------------------------------------------------
sub exists_parameter {
  # Like seek_parameter, but checks whether a parameter exists.
  my ( $param_name, @data_structs ) = @_;
  my @target_string = split( /\|/, $param_name );
  start_timer("parameter_seek");
  for my $str (@target_string) {
    for my $struct (@data_structs) {
      if ( ref($struct) eq "ARRAY" ) {
				for my $substruct (@$struct) {
					if (exists $substruct->{param} && exists $substruct->{param}{$str}) {
						stop_timer("parameter_seek");
						return 1;
					}
					if (exists $substruct->{$str}) {
						stop_timer("parameter_seek");
						return 1;
					}
				}
      } elsif ( ref($struct) eq "HASH" ) {
				if (exists $struct->{param} && exists $struct->{param}{$str}) {
					stop_timer("parameter_seek");
					return 1;
				}
				if (exists $struct->{$str}) {
					stop_timer("parameter_seek");
					return 1;
				}
      } else {
				printdumper(\@data_structs);
				confess "cannot extract parameter from this data structure (shown above - report this please)";
      }
    }
  }
  stop_timer("parameter_seek");
  return 0;
}

# -------------------------------------------------------------------
sub list_parameters {
  # List all populated parameters.
	#
  # list_parameters($hash);
  # list_parameters($hash,$anotherhash);
  my ( @data_structs ) = @_;
	my @params = ();
  start_timer("parameter_seek");
	for my $struct (@data_structs) {
		if ( ref($struct) eq "ARRAY" ) {
			for my $substruct (@$struct) {
				if (ref $substruct->{param} eq "HASH") {
					push @params, grep(defined $substruct->{param}{$_}, keys %{$substruct->{param}});
				}
				if (ref $substruct eq "HASH") {
					push @params, grep(defined $substruct->{$_}, keys %$substruct);
				}
			}
		} elsif ( ref($struct) eq "HASH" ) {
			if (ref $struct->{param} eq "HASH") {
				push @params, grep(defined $struct->{param}{$_}, keys %{$struct->{param}});
			}
			if (ref $struct eq "HASH") {
				push @params, grep(defined $struct->{$_}, keys %$struct);
			}
		}
	}
  stop_timer("parameter_seek");
	return uniq @params;
}


sub is_hidden {
	my @datapath   = @_;
	my $show_state = seek_parameter("show", @datapath);
	return defined_and_zero($show_state);
}

sub get_file_annotation {
	my %params = @_;
	my $file   = $params{file};
	my ($filename,@annot) = split(",",$file);
	return join(",",@annot);
}

# -------------------------------------------------------------------
sub locate_file {
	my %params;
	if ($Circos::Configuration::CONF{debug_validate}) {
		%params = validate(@_,{ 
													 file => 1, 
													 name => 0,
													 path => { type => ARRAYREF | UNDEF, optional => 1 },
													 return_undef => 0 
													});
	} else {
		%params = @_;
	}

	# v0.63 added configuration directory to dir_1
	my @dir_1 = grep($_,getcwd,Circos::Configuration::fetch_conf("configdir"),$FindBin::RealBin);
	my @dir_2 = qw(. .. ../.. ../../..);
	my @dir_3 = qw(. etc data);

	my $file   = $params{file};
	# remove any comma-delimited elements from the file
	$file =~ s/,.*//;
	# remove any trailing rx brackets from file
	$file =~ s/\(.+?\)$//;
	printdebug_group("io","locating file",$file,"role",$params{name});

	if (! defined $file) {
		confess "Attempted to locate an undefined file name for [$params{name}]";
	}

	my @path;
	if (file_name_is_absolute($file)) {
		@path = ($EMPTY_STR);
	} else {
		# first add any custom path directories
		push @path, @{$params{path}} if defined $params{path};
		if ( my $path_list = Circos::Configuration::fetch_conf("data_path") ) {
	    push @path, split($COMMA,$path_list);
		}
		# now the default locations
		for my $d1 (@dir_1) {
	    for my $d2 (@dir_2) {
				for my $d3 (@dir_3) {
					push @path, catfile($d1,$d2,$d3);
				}
	    }
		}
	}
	printdebug_group("io","trying path",@path);
	for my $path (@path) {
		my $file_path = $path ? catfile($path,$file) : $file;
		printdebug_group("io","trying $file_path");
		if ( -e $file_path) {
	    if (! -r $file_path) {
				fatal_error("io","cannot_read",$file,"with locate_file",$!);
	    } else {
				printdebug_group("io","$file found in $file_path");
				return $file_path;
	    }
		}
	}
	if ( $params{return_undef} ) {
		return undef;
	} else {
		fatal_error("io","cannot_find",$file,join("\n",map { " $_" } @path));
	}
}

# -------------------------------------------------------------------
sub add_thousands_separator {
  my $str = shift;
  my $sep = shift || $COMMA;
  if ( $str =~ /\./ ) {
    $str =~ s/(?<=\d)(?=(\d{3})+\.)/,/g;
  } else {
    $str =~ s/(?<=\d)(?=(\d{3})+$)/,/g;
  }
  return $str;
}

# -------------------------------------------------------------------
sub not_defined_or_one {
	return !defined $_[0] || $_[0];
}

# -------------------------------------------------------------------
sub defined_and_zero {
	return defined $_[0] && !$_[0];
}

sub first_defined {
	for (@_) {
		return $_ if defined $_;
	}
	return;
}

sub list_has_defined {
	return grep(defined $_, @_);
}

sub is_in_list {
	my ($item,@list) = @_;
	return scalar grep($item eq $_, @list);
}

# -------------------------------------------------------------------
sub current_function {
	my ($package,$filename,$line,$function) = caller(1);
	$function =~ s/.*:://g;
	return $function;
}

sub current_package {
	my ($package,$filename,$line,$function) = caller(1);
	return $package;
}

# -------------------------------------------------------------------
# Parse a CSV list, respecting brackets and ,'s in values
#
# var1=a,var2=rgb(a,b,c),var3=a,b,var4=c
sub parse_csv {
	my $str    = shift;
	my $delim  = Circos::Configuration::fetch_conf("options_record_delim") || $COMMA;
	my $assign = Circos::Configuration::fetch_conf("options_field_delim")  || $EQUAL_SIGN;
	my @elems  = split("",$str);
	my @params;
	my $buffer = $EMPTY_STR;
	my $paren_level;
	while (scalar @elems) {
		my $elem = shift @elems;
		if ($elem eq "(") {
			$paren_level++;
		} elsif ($elem eq ")") {
			$paren_level--;
		} elsif ($elem !~ /$delim/i) {
			$buffer .= $elem;
		} elsif ($elem =~ /$delim/i) {
			if (! $paren_level && $buffer =~ /$assign/i) {
				$buffer =~ s/^$delim//g;
				push @params, $buffer;
				$buffer = $elem;
			} elsif ($buffer !~ /$assign/i) {
				$params[-1] .= $buffer;
				$buffer      = $elem;
			} else {
				$buffer .= $elem;
			}
		}
	}
	if($buffer ne $EMPTY_STR) {
		if($buffer =~ /$assign/i) {
			$buffer =~ s/^$delim//g;
			push @params, $buffer if $buffer ne $EMPTY_STR;
		} else {
			$params[-1] .= $buffer;
		}
	}
	if ($paren_level) {
		fatal_error("parsedata","bad_csv",$str,$paren_level);
	}
	return @params;
}

sub remove_undef_keys {
	my %x = @_;
	return map { ($_,$x{$_}) } grep(defined $x{$_}, keys %x);
}

# return the distance between the span
# [x1,y1] and [x2,y2]
# if the spans overlap, the distance is negative
sub span_distance {
  my ($x1,$y1,$x2,$y2) = @_;
  # flip the coordinates if they are reversed
  ($x1,$y1) = ($y1,$x1) if $x1 > $y1;
  ($x2,$y2) = ($y2,$x2) if $x2 > $y2;
  # flip intervals so that x1,y1 is always to the left
  ($x1,$y1,$x2,$y2) = ($x2,$y2,$x1,$y1) if ($x1 > $x2);
  my $d;
  if ($x2 >= $y1) {
    # x1 y1
    # -----  
    #        x2  y2
    #        ------
    $d = $x2 - $y1;
  } else {
    if ($y2 >= $y1) {
      # x1     y1
      # ---------
      #     x2    y2
      #     --------
      $d = -($y1 - $x2);
    } else {
      # x1     y1
      # ---------
      #   x2  y2
      #   ------
      $d = -($y2-$x2);
    }
  }
  die "did not calculate distance between intervals [$x1,$y1] and [$x2,$y2] correctly." unless defined $d;
  return $d;

  # test
  for my $i (0..100000) {
    my @coords = map { sprintf("%.1f",100*rand()) } (0..3);
    my $s1 = Set::IntSpan->new(sprintf("%d-%d",sort {$a <=> $b} ($coords[0]*1000,$coords[1]*1000)));
    my $s2 = Set::IntSpan->new(sprintf("%d-%d",sort {$a <=> $b} ($coords[2]*1000,$coords[3]*1000)));
    my $int = $s1->intersect($s2)->cardinality;
    my $d   = span_distance(@coords);
    if ($int) {
      $int = ($int-1)/1000 if $int;
      if ($int && (-$d - $int) > 0.002) {
				die();
      }
    } else {
      $int = min ( abs($coords[0] - $coords[2]),
									 abs($coords[0] - $coords[3]),
									 abs($coords[1] - $coords[2]),
									 abs($coords[1] - $coords[3]) );
      if ($d - $int > 0.002) {
				die();
      }
    }
    printinfo(@coords,$d,$int);
  }
}

sub make_set {
	my ($x,$y,%args) = @_;
	if (! defined $x) {
		return Set::IntSpan->new();
	} elsif (! defined $y || $x == $y) {
		return Set::IntSpan->new(round $x);
	} elsif ($x > $y) {
		if ($args{norev} || defined_and_zero($args{rev})) {
			fatal_error("data","malformed_span",$x,$y);
		}
		return Set::IntSpan->new( (round $y) . "-" . (round $x) );
	} else {
		return Set::IntSpan->new( (round $x) . "-" . (round $y) );
	}
}

sub hide {
	my @path = @_;
	return defined_and_zero(seek_parameter("show|use",@path)) || seek_parameter("hide",@path);
}

sub use_set {
	my @path = @_;
	return not_defined_or_one(seek_parameter("use",@path))
}

sub show {
	my @path = @_;
	return ! hide(@path);
}

sub true_or_yes {
	my $x = shift;
	return if $x eq 1 || $x =~ /^y(es)?$/i;
}

sub false_or_no {
	my $x = shift;
	return if $x eq 0 || $x =~ /^no?$/i;
}

sub get_hash_leaf {
	my ($hash,@path) = @_;
	return $hash if ! @path;
	my $key = shift @path;
	if(! exists $hash->{$key}) {
		fatal_error("system","hash_leaf_undef",$key);
	} else {
		return get_hash_leaf($hash->{$key},@path);
	}
}

# -------------------------------------------------------------------
# parse into a hash option string like
#   var1=value1,var2=value2,...
sub parse_options {
  my $string  = shift || $EMPTY_STR;
  my $options = {};
	my @option_pairs;
	if ($string =~ /,[^=]*,/ || $string =~ /[()]/) {
		# use the slower parser only when we know the options field includes brackets
		# color=(255,0,0),x=1 -> color=(255,0,0) x=1
		# or adjacent commas 
		@option_pairs = parse_csv($string);
	} else {
		@option_pairs = split(",",$string);
	}
	my %params;
	#printdumper(\@option_pairs);
	for my $option_pair ( @option_pairs ) {
		if ($option_pair =~ /^([^=]+)=(.+)$/) {
			$options->{$1} = $2;
		} else {
			fatal_error("parsedata","bad_options",$option_pair);
		}
	}
  return $options;
}

sub log10 {
	my $x = shift;
	return $x > 0 ? log($x)/log(10) : undef;
}

sub log2 {
	my $x = shift;
	return $x > 0 ? log($x)/log(2) : undef;
}

1;
