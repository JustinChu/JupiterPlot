package Circos::Configuration;

=pod

=head1 NAME

Circos::Configuration - Configuration handling for Circos

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
our @EXPORT_OK = qw(%CONF $DIMS);
our @EXPORT    = qw(
										 fetch_configuration
										 fetch_conf
										 get_counter
										 exists_counter
										 dump_config
										 parse_conf_fn
										 %CONF
										 $DIMS
									);

use Carp qw( carp confess croak );
use Config::General 2.50;
use Clone;
use File::Basename;
use File::Spec::Functions;
use Data::Dumper;
use Math::VecStat qw(sum min max average);
use Math::Round qw(round);
use FindBin;
use IO::File;
use Params::Validate qw(:all);
use List::MoreUtils qw(uniq);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Constants;
use Circos::Debug;
use Circos::Utils;
use Circos::Error;

our %CONF;
our $DIMS;

our $COUNTER;

# -------------------------------------------------------------------
# Return the configuration hash leaf for a parameter path.
#
# fetch_configuration("ideogram","spacing") -> $CONF{ideogram}{spacing}
#
# alias: fetch_conf("ideogramn","spacing")
#
# fetch_configuration() -> $CONF
#
# If the leaf, or any of its parents, do not exist, undef is returned.
sub fetch_configuration {
    my @config_path = @_;
    my $node        = \%CONF;
    if(! @config_path) {
	return \%CONF;
    }
    for my $path_element (@config_path) {
	if (! exists $node->{$path_element}) {
	    return undef;
	} else {
	    $node = $node->{$path_element};
	}
    }
    return $node;
}

sub fetch_conf {
	return fetch_configuration(@_);
}

# -------------------------------------------------------------------
#
sub fetch_parameter_list_item {
	my ($list,$item,$delim) = @_;
	my $parameter_hash = make_parameter_list_hash($list,$delim);
	return $parameter_hash->{$item};
}

sub dump_config {
	my %OPT = @_;
	$Data::Dumper::Indent    = 2;
	$Data::Dumper::Quotekeys = 0;
	$Data::Dumper::Terse     = 0;
	$Data::Dumper::Sortkeys  = 1;
	$Data::Dumper::Varname   = "CONF";
	if ($OPT{cdump}) {
		my ($path,$rx) = split(":",$OPT{cdump});
		my @path       = split(/[.\/]/,$path);
		if($rx) {
			$Data::Dumper::Varname .= join(":",join("_",@path),$rx);
			$Data::Dumper::Sortkeys = sub { 
				my ($h) = @_;
				return [sort grep($_ =~ /$rx/, keys %$h)];
			}
		} else {
			$Data::Dumper::Varname .= join("_",@path);
		}
		if(@path) {
			printdumper(get_hash_leaf(\%CONF,@path));
		} else {
			printdumper(\%CONF);
		}
	} else {

		printdumper(\%CONF);
	}
	exit
}

# -------------------------------------------------------------------
# Given a string that contains a list, like
#
# hs1:0.5;hs2:0.25;hs3:0.10;...
#
# returns a hash keyed by the first field before the delimiter with
# the second field as value.
#
# { hs1=>0.5, hs2=>0.25, hs3=>0.10, ... }
#
# The delimiter can be set as an optional second field. By default,
# the delimiter is \s*[;,]\s*
#
sub make_parameter_list_hash {
	my ($list_str,$record_delim,$field_delim) = @_;
	$record_delim ||= fetch_configuration("list_record_delim") || qr/\s*[;,]\s*/;
	$field_delim  ||= fetch_configuration("list_field_delim")  || qr/\s*[:=]\s*/;
	my $parameter_hash;
	for my $pair_str (split($record_delim,$list_str)) {
		my ($parameter,$value) = split($field_delim,$pair_str);
		if (exists $parameter_hash->{$parameter}) {
	    fatal_error("configuration","multiple_defn_in_list",$list_str,$parameter);
		} else {
	    $parameter_hash->{$parameter} = $value;
		}
	}
	return $parameter_hash;
}

# -------------------------------------------------------------------
# Given a string that contains a list, like
#
# file1,file2,...
#
# returns an array of these strings.
#
# [ "file1", "file2", ... ]
#
# The delimiter can be set as an optional second field. By default,
# the delimiter is \s*[;,]\s*
#
sub make_parameter_list_array {
	my ($list_str,$record_delim) = @_;
	$record_delim ||= fetch_configuration("list_record_delim") || qr/\s*[;,]\s*/;
	my $parameter_array;
	for my $str (split($record_delim,$list_str)) {
		push @$parameter_array, $str;
	}
	return $parameter_array;
}

# -------------------------------------------------------------------
# Parse a variable/value assignment.
sub parse_var_value {
	my $str = shift;
	my $delim = fetch_configuration("list_field_delim") || qr/\s*=\s*/;
	my ($var,$value) = $str =~ /(.+)?$delim(.+)/;
	if(! defined $var || ! defined $value) {
		fatal_error("configuration","bad_var_value",$str,$delim);
	} else {
		return ($var,$value);
	}
}

# -------------------------------------------------------------------
sub populateconfiguration {

  my %OPT = @_;

  for my $key ( keys %OPT ) {
		if (defined $OPT{$key}) {
			if ($key eq "debug_group") {
				my @new_groups      = split(",",$OPT{$key});
				my @existing_groups = split(",",$CONF{$key});
				my $reset = 0;
				for my $new_group (@new_groups) {
					if($new_group =~ /^([-+])(.+)/) {
						my ($flag,$new_group_name) = ($1,$2);
						if($flag eq "-") {
							@existing_groups = grep($_ ne $new_group_name, @existing_groups);
						} elsif ($flag eq "+") {
							push @existing_groups, $new_group_name;
						}
					} else {
						@existing_groups = () if ! $reset++;
						push @existing_groups, $new_group;
					}
				}
				@existing_groups = grep(defined $_, @existing_groups);
	      $CONF{$key} = join($COMMA,sort(uniq(@existing_groups))) if uniq(@existing_groups);
			} elsif ($key eq "param") {
				for my $pair (@{$OPT{$key}}) {
					my ($param,$value) = split(/=/,$pair);
					$value = 0 if lc $value eq "no"  || lc $value eq "n";
					$value = 1 if lc $value eq "yes" || lc $value eq "y";
					my @param_path = split("/",$param);
					my $leaf = \%CONF;
					for my $path (@param_path[0..@param_path-2]) {
						if(exists $leaf->{$path}) {
							if(ref $leaf->{$path} eq "HASH") {
								$leaf = $leaf->{$path};
							} elsif (ref $leaf->{$path} eq "ARRAY") {
								$leaf = $leaf->{$path};
							} else {
								fatal_error("configuration","parampath_missing",$param,$value,$path);
							}
						} else {
							fatal_error("configuration","parampath_nothash",$param,$value,$path);
						}
					}
					if(ref $leaf eq "HASH") {
						$leaf->{ $param_path[-1] } = $value;
					} elsif (ref $leaf eq "ARRAY") {
						for my $l (@$leaf) {
							$l->{ $param_path[-1] } = $value;
						}
					}
				}
			} else {
	      $CONF{$key} = $OPT{$key};
			}
		}
  }
	
	# Combine top level hashes. This allows overriding values in blocks
	# that are included.
	#
	# <<include ideogram.conf>>
	# <ideogram>
	# label_size* = 12
	# </ideogram>

	merge_top_hashes( \%CONF );
  resolve_synonyms( \%CONF, [] );

  # Fields like conf(key1,key2,...) are replaced by $CONF{key1}{key2}
  #
  # If you want to perform arithmetic, you'll need to use eval()
  #
  # eval(2*conf(image,radius))
  #
  # The configuration can therefore depend on itself. For example, if
  #
  # flag = 10
  # note = eval(2*conf(flag))
  repopulateconfiguration( \%CONF, undef, undef, undef, 1 );
  repopulateconfiguration( \%CONF, undef, undef, undef, 0 );

  override_values( \%CONF );
  check_multivalues( \%CONF, undef );

  postprocess_values(\%CONF);

  fatal_error("configuration","no_housekeeping") if ! $CONF{housekeeping};
  
}

#-------------------------------------------------------------------
# Iteratively run apply_synonym() on all configuration tree nodes.
sub resolve_synonyms {
	my $root = shift;
	my $tree = shift;
	if (ref $root eq "HASH") {
		for my $key (keys %$root) {
	    my $value = $root->{$key};
	    if (ref $value eq "HASH" ) {
				resolve_synonyms($value, [ @$tree, $key ]);
	    } elsif (ref $value eq "ARRAY") {
				map { resolve_synonyms($_, [ @$tree, $key ]) } @$value;
	    } else {
				my ($new_key,$action) = apply_synonym($value,$key,$tree);
				if (defined $new_key) {
					if ($action eq "copy") {
						$root->{$new_key} = $root->{$key};
					} else {
						$root->{$new_key} = $root->{$key};
						delete $root->{$key};
					}
				}
	    }
		}
	}
}

#-------------------------------------------------------------------
# Some configuration items may have more than one addressable name. 
sub apply_synonym {
	my ($value,$key,$tree) = @_;
	my @synonyms = (
									{
									 key_rx => ".*::label_tangential", new_key => "label_parallel", action => "copy" },
								 );
	my $key_name  = join(":",@$tree)."::".$key;
	my ($new_key,$action);
	for my $s (@synonyms) {
		printdebug_group("conf","testing synonym",$s->{key_rx},$key_name);
		if ($key_name =~ /$s->{key_rx}/) {
	    $new_key = $s->{new_key};
	    $action  = $s->{action};
	    printdebug_group("conf","applying synonym",$action,$key_name,$new_key);
	    return ($new_key,$action);
		}
	}
	return;
}

# -------------------------------------------------------------------
# Parameters with *, **, ***, etc suffixes override those with fewer "*";
sub override_values {
	my $root = shift;
	my $parameter_missing_ok = 1;
	if (ref $root eq "HASH") {
		my @keys = keys %$root;
		# do we have any parameters to override?
		my @lengths = uniq ( map { length($_) } ( map { $_ =~ /([*]+)$/ } @keys ) );
		my @delete_queue;
		for my $len (sort {$a <=> $b} @lengths) {
	    for my $key (@keys) {
				my $rx = qr/^(.+)[*]{$len}$/;
				#printinfo("rx",$rx,"key",$key);
				if ($key =~ $rx) {
					my $key_name = $1;
					# do not require that the parameter be present to override it
					if ($parameter_missing_ok || grep($_ eq $key_name, @keys)) {
						#printinfo("overriding",$key_name,$root->{$key_name},$key,$root->{$key});
						$root->{$key_name} = $root->{$key};
						# delete old key suffixed with *
						push @delete_queue, $key;
					}
				}
	    }
		}
		map { delete $root->{$_} } @delete_queue;
		for my $key (keys %$root) {
			my @values = make_list($root->{$key});
			for my $value (@values) {
				if (ref $value eq "HASH" ) {
					#printinfo("iter",$key);
					override_values($value);
				}
			}
		}
	}
}

sub merge_top_hashes {
	my $root = shift;
	my @ok = qw(ideogram colors fonts patterns image plots links highlights);
	for my $key (keys %$root) {
		my $value = $root->{$key};
		if (ref $value eq "ARRAY" && is_in_list($key,@ok)) {
			printdebug_group("conf","merging top level block [$key]");
			$root->{$key} = clone_merge(@$value);
		}
	}
}

# -------------------------------------------------------------------
# multiple parameters are allowed if
# parent block name must match 'pass' regular expression
# parent block name must fail 'fail' regular expression
{
	my $ok = {
						flow       => { pass => qr/rule/ },
						condition  => { pass => qr/rule/ },
						radius     => { pass => qr/tick/ },
						axis       => { pass => qr/axes/ },
            param      => { pass => qr/_root/},
						post_increment_counter => { pass => qr/plot/ },
					 };

	sub check_multivalues {
		my ($root,$root_name,$level) = @_;

		return unless ref $root eq "HASH";
		$level ||= 0;

		$root_name = "_root" if ! defined $root_name;

		my @keys = keys %$root;
		for my $key (@keys) {
	    my $value = $root->{$key};
	    my $pass;
	    if (ref $value eq "ARRAY") {
				if ($root_name eq $key."s") {
					# parent block is plural of this block (e.g. backgrounds > background)
					$pass = 1;
				}
				if (my $passrx = $ok->{$key}{pass} ) {
					$pass = $root_name =~ /$passrx/i;
				}
				if (my $failrx = $ok->{$key}{fail} ) {
					$pass = $root_name !~ /$failrx/i;
				}
				if (! $pass) {
					printdumper($root);
					fatal_error("configuration","multivalue",$key,$root_name);
				}
			} elsif (ref $value eq "HASH") {
				# this is a block
	    }
			#printinfo($level,$key,$value);
		}
		for my $key (keys %$root) {
	    my $value = $root->{$key};
	    if (ref $value eq "HASH" ) {
				check_multivalues($value,$key,$level+1);
	    } elsif (ref $value eq "ARRAY") {
				map { check_multivalues($_,$key,$level+1) } @$value;
	    }
		}
	}
}

# -------------------------------------------------------------------
# Generic configuration iterator
sub postprocess_values {
	my $node = shift;
	if (ref $node eq "HASH") {
		for my $key (keys %$node) {
	    my $value = $node->{$key};
	    if (ref $value eq "HASH" ) {
				#printinfo("conf_iterate","hash",$key);
				postprocess_values($value);
	    } elsif (ref $value eq "ARRAY") {
				#printinfo("conf_iterate","list",$key);
				map { postprocess_values($_) } @$value;
	    } else {
				#printinfo("conf_iterate","value",$key,$value);
				if($value =~ /undef/i) {
					#delete $node->{$key};
					$node->{$key} = undef;
				}
			}
		}
	}
}

# -------------------------------------------------------------------
# Generic configuration iterator
sub conf_iterate {
	my $node = shift;
	if (ref $node eq "HASH") {
		for my $key (keys %$node) {
	    my $value = $node->{$key};
	    if (ref $value eq "HASH" ) {
				#printinfo("conf_iterate","hash",$key);
				conf_iterate($value);
	    } elsif (ref $value eq "ARRAY") {
				#printinfo("conf_iterate","list",$key);
				map { conf_iterate($_) } @$value;
	    } else {
				#printinfo("conf_iterate","value",$key,$value);
				# do something with the value
			}
		}
	}
}

sub set_counters {
	my ($node,$parent_node_name,$parent_node,@paramfn) = @_;
	my %set_counter_names;
	for my $paramfn (@paramfn) {
		my ($param,$fn) = @{$paramfn}{qw(param fn)};
		next if ! defined $node->{$param};
		my @values      = make_list($node->{$param});
		for my $value (grep(defined $_,@values)) {
			for my $counter_txt (split(",",$value)) {
				my ($counter,$incr);
				if($counter_txt =~ /:/) {
					($counter,$incr) = split(":",$counter_txt);
				} else {
					$counter = $parent_node_name;
					$incr    = $counter_txt;
				}
				#printinfo($node,$parent_node_name,$counter,$incr);
				$fn->($counter,$incr);
				$set_counter_names{$counter}++;

				# also increment counter of the node's type

				if($parent_node_name eq "plot" && 
					 ($node->{type} || ($parent_node && $parent_node->{type}))) {
					my $counter_name = $node->{type} || $parent_node->{type};
					$fn->( $counter_name, $incr );
					$set_counter_names{ $counter_name }++;
				}
			}
		}
	}
	return %set_counter_names;
}

# -------------------------------------------------------------------
# Merge two or more hashes together.
# Code from http://search.cpan.org/~rokr/Hash-Merge-Simple-0.051/lib/Hash/Merge/Simple.pm
sub merge {
	my ($left,@right) = @_;
	return $left unless @right;
	return merge($left, merge(@right)) if @right > 1;
	my ($right) = @right;
	my %merge = %$left;
	for my $key (keys %$right) {
		my ($hr, $hl) = map { ref $_->{$key} eq 'HASH' } ($right, $left);
		if (ref $right->{$key} eq "HASH" && ref $left->{$key} eq "HASH") {
			$merge{$key} = merge($left->{$key},$right->{$key});
		} else {
			$merge{$key} = $right->{$key};
		}
	}
	return \%merge;
}

sub clone_merge {
	my $result = merge @_;
	return Clone::clone($result);
}

# -------------------------------------------------------------------
sub repopulateconfiguration {
  my ($node,$parent_node_name,$parent_node,$curr,$do_counter) = @_;

  # compile current view of configuration paramters, respecting hierarchy
  $curr ||= {};
  $curr = { %$curr, %$node };

	my %set_counter_names = set_counters(
																			 $node,
																			 $parent_node_name,
																			 $parent_node,
																			 { param=>"init_counter",				   fn=>\&init_counter 	   },
																			 { param=>"pre_increment_counter", fn=>\&increment_counter },
																			 { param=>"pre_set_counter",       fn=>\&set_counter       },
																			) if $do_counter;

	if($do_counter) {
		# default initializer, if init_counter was not called
		if (ref $node && defined $parent_node_name) {
			init_counter($parent_node_name,0) if ! $set_counter_names{$parent_node_name};
			if($parent_node_name eq "plot" &&
				 ($node->{type} || ($parent_node && $parent_node->{type}))) {
				my $counter_name = $node->{type} || $parent_node->{type};
				init_counter($counter_name,0) if ! $set_counter_names{$counter_name};
			}
		}
	}

  for my $key ( sort keys %$node ) {
		my $value = $node->{$key};
		if ( ref $value eq 'HASH' ) {
			repopulateconfiguration($value,$key,$node,$curr,$do_counter);
		} elsif ( ref $value eq 'ARRAY' ) {
			for my $i (0..@$value-1) {
				my $item = $value->[$i];
				#printinfo($i,$key,$item);
				if ( ref $item ) {
					repopulateconfiguration($item,$key,$node,$curr,$do_counter);
				} else {
					my $new_value     = parse_field($item,$key,$parent_node_name,$node,$curr);
					$node->{$key}[$i] = $new_value;
				}
				#printinfo($i,$key,$node->{$key}[$i]);
			}
		} else {
			# excluding the counter key is required because blocks like
			# <pairwise /hs/ /hs/ >
			# will trigger the multi_word_key error
			if ($key =~ /\s+/ && $parent_node_name ne "counter") { 
	      fatal_error("configuration","multi_word_key",$key);
      } else {
				my $new_value = parse_field($value,$key,$parent_node_name,$node,$curr);
				$node->{$key} = $new_value;
			}
    }
  }

	if($do_counter) {
		%set_counter_names = set_counters(
																			$node,
																			$parent_node_name,
																			$parent_node,
																			{ param=>"post_increment_counter", fn=>\&increment_counter },
																			{ param=>"post_set_counter",       fn=>\&set_counter       },
																		 );

  # default post increment counter
		if (ref $node && defined $parent_node_name) {
			my $default_increment = defined $COUNTER->{$parent_node_name}{increment} ? $COUNTER->{$parent_node_name}{increment} : 1;
			if($parent_node_name eq "plot" &&
				 ($node->{type} || ($parent_node && $parent_node->{type}))) {
				my $counter_name = $node->{type} || $parent_node->{type};
				increment_counter($counter_name,$default_increment) if ! $set_counter_names{$counter_name};
			}
			increment_counter($parent_node_name,$default_increment) if ! $set_counter_names{$parent_node_name};
		}
	}
}

sub parse_field {

	my ($str,$key,$parent_node_name,$node,$curr) = @_;
	my $delim    = "__";

	if(! defined $str) {
		printdumper($node); 
		fatal_error("configuration","undefined_string",$key,$parent_node_name || "_root");
	}

	# replace counters
	# counter(NAME)
	while ( $str =~ /(counter\(\s*(.+?)\s*\))/g ) {
		my ($template,$counter) = ($1,$2);
		if (defined $template && defined $counter) {
		    my $new_template = get_counter($counter);
		    printdebug_group("counter","fetch",$template,$counter,$new_template);
		    $str =~ s/\Q$template\E/$new_template/g;
		}
	}

	# replace configuration field
	# conf(LEAF,LEAF,...)
	$str = parse_conf_fn($str,$node,$curr);

	# this is going to be deprecated
	if( $str =~ /$delim([^_].+?)$delim/g ) {
		fatal_error("configuration","deprecated","__FIELD__","var(FIELD)");
	}
	
	$str = eval_conf($str) if $str !~ /var\s*\(/ && (! defined $parent_node_name || $parent_node_name ne "rule");

	#$redo = undef;
	#while(! defined $redo || $redo) {
	#	$redo = 0;
	#	while ($str =~ /\s*eval\s*\(\s*(.+)\s*\)/ && $parent_node_name ne "rule" && $str !~ /var\s*\(/) {
	#		my $fn = $1;
	#		printinfo($str,$fn);
	#		printinfo(Circos::Expression::extract_balanced($fn,"eval","(",")"));
	#		if($fn =~ /eval\(/) {
	#			$redo = 1;
	#			next;
	#		}
	#		$str = eval $fn;
	#		if ($@) {
	#			fatal_error("rules","parse_error",$fn,$@);
	#		}
	#		printdebug_group("conf","repopulateeval",$fn,$str);
	#	}
	#}

	return $str;
}

sub parse_conf_fn {
	my ($str,$node,$curr) = @_;
	my $redo;
	while( ! defined $redo || $redo) {
		$redo = 0;
		while ( $str =~ /((opt)?conf\(\s*([^\(\)]+?)\s*\))/g ) {
	    my ($template,$checkonly,$leaf) = ($1,$2,$3);
	    if($leaf =~ /conf\(/) {
				$redo = 1;
				next;
	    }
	    if (defined $template && defined $leaf) {
				my @leaf  = split(/\s*,\s*/,$leaf);
				my $new_template;
				if (@leaf == 2 && $leaf[0] eq ".") {
					if(defined $curr && exists $curr->{$leaf[1]}) {
						$new_template = $curr->{$leaf[1]};
					} else {
						$new_template = $node->{$leaf[1]};
					}
				} else {
					$new_template = fetch_conf(@leaf);
				}
				if(! defined $new_template && ! $checkonly) {
					fatal_error("configuration","no_such_conf_item",$template,$leaf);
				}
				printdebug_group("conf","fetch",$template,join(",",@leaf),$new_template);
				if(defined $new_template) {
					if($new_template =~ /(var|eval)\(/) {

					} else {
						$str =~ s/\Q$template\E/$new_template/g;
					}
				} else {
					$str =~ s/\Q$template\E/undef/g;
				}
			}
		}
	}
	return $str;
}

sub eval_conf {
	my $str = shift;
	#printinfo("eval_conf",$str);
	my ($template,$arg) = Circos::Expression::extract_balanced($str,"eval","(",")");
	if(defined $arg) {
		#printinfo("eval_conf template",$template);
		#printinfo("eval_conf      arg",$arg);
		my $for_eval;
		if(Circos::Expression::extract_balanced($arg,"eval","(",")")
			 ||
			 Circos::Expression::extract_balanced($arg,"counter","(",")")
			 ||
			 Circos::Expression::extract_balanced($arg,"conf","(",")")) {
			$for_eval = parse_field($arg);
		} else {
			$for_eval = $arg;
		}
		my $value = eval $for_eval;
		if ($@) {
			fatal_error("rules","parse_error",$for_eval,$@);
		}
		#printinfo("eval_conf    value",$value);
		$str =~ s/\Qeval$template\E/$value/;
		#printinfo("eval_conf     nstr",$str);
	}
	if(Circos::Expression::extract_balanced($str,"eval","(",")")) {
		return eval_conf($str);
	} else {
		return $str;
	}
}

# -------------------------------------------------------------------
sub loadconfiguration {
  my ($arg,$return) = @_;
  printdebug_group("conf","looking for conf file",$arg);
  my @possibilities = (
											 $arg,
											 catfile( $FindBin::RealBin, $arg ),
											 catfile( $FindBin::RealBin, '..', $arg ),
											 catfile( $FindBin::RealBin, 'etc', $arg ),
											 catfile( $FindBin::RealBin, '..', 'etc', $arg ),
											 catfile( '/home', $ENV{'LOGNAME'}, ".${APP_NAME}.conf" ),
											 catfile( $FindBin::RealBin, "${APP_NAME}.conf" ),
											 catfile( $FindBin::RealBin, 'etc', "${APP_NAME}.conf"),
											 catfile( $FindBin::RealBin, '..', 'etc', "${APP_NAME}.conf"),
											);
  
  my $file;
  for my $f ( @possibilities ) { 
    if ( -e $f && -r _ ) {
      printdebug_group("summary","found conf file",$f);
      $file = $f;
      last;
    }
  }

  if ( !$file ) {
    fatal_error("configuration","missing",$arg);
  }

  my @configpath = (
										dirname($file),
										dirname($file)."/etc",
										"$FindBin::RealBin/etc", 
										"$FindBin::RealBin/../etc",
										"$FindBin::RealBin/..",  
										$FindBin::RealBin,
									 );

	my $conf;
	eval {
		$conf = Config::General->new(
																 -SplitPolicy       => 'equalsign',
																 -ConfigFile        => $file,
																 -AllowMultiOptions => 1,
																 -LowerCaseNames    => 1,
																 -IncludeAgain      => 1,
																 -CComments         => 0,
																 -NormalizeBlock    => sub { my $x = shift; $x =~ s/\s*$//; $x; },
																 -ConfigPath        => \@configpath,
																 -AutoTrue => 1
																);
	};
	if ($@) {
		if ($@ =~ /does not exist within configpath/i) {
			fatal_error("configuration","cannot_find_include",join("\n",@configpath),$@);
		} else {
			fatal_error("configuration","cannot_parse_file",$@);
		}
  }
	if ($return) {
		return { $conf->getall } ;
	} else {
		%CONF = $conf->getall;
	}
}

# -------------------------------------------------------------------
sub validateconfiguration {

	$CONF{chromosomes_display_default} = 1 if ! defined $CONF{chromosomes_display_default};
	$CONF{chromosomes_units} ||= 1;
	$CONF{svg_font_scale}    ||= 1;

	if ( ! $CONF{karyotype} ) {
		fatal_error("configuration","no_karyotype");
	}

	for my $block (qw(ideogram image colors fonts)) {
		if ( ! $CONF{$block} ) {
			fatal_error("configuration","no_block",$block);
		}
	}

	$CONF{image}{image_map_name} ||= $CONF{image_map_name};
	$CONF{image}{image_map_use}  ||= $CONF{image_map_use};
	$CONF{image}{image_map_file} ||= $CONF{image_map_file};
	$CONF{image}{image_map_missing_parameter} ||= $CONF{image_map_missing_parameter};
	$CONF{image}{"24bit"} = 1;
	$CONF{image}{png}  = $CONF{png} if exists $CONF{png};
	$CONF{image}{svg}  = $CONF{svg} if exists $CONF{svg};
	if(my $file = $CONF{outputfile} || $CONF{file}) {
		$CONF{image}{file} = $file;
	}
	if(my $dir = $CONF{outputdir} || $CONF{dir}) {
		$CONF{image}{dir} = $dir;
	}
	$CONF{image}{background} = $CONF{background} if $CONF{background};

	while($CONF{image}{angle_offset} > 0 ) {
		$CONF{image}{angle_offset} -= 360;
	}

	#
	# Make sure these fields are initialized
	#

	for my $f ( qw(chromosomes chromosomes_breaks chromosomes_radius) ) {
		$CONF{ $f } = $EMPTY_STR if ! defined $CONF{ $f };
	}

}

# -------------------------------------------------------------------
# Counters

# -------------------------------------------------------------------
sub get_counter {
	my $counter = shift;
	confess if ! defined $counter;
	if (! exists_counter($counter)) {
		fatal_error("configuration","no_counter",$counter);
	} else {
		return $CONF{counter}{$counter};
	}
}

# -------------------------------------------------------------------
sub exists_counter {
	my $counter = shift;
	return defined $CONF{counter}{$counter};
}

# -------------------------------------------------------------------
sub increment_counter {
  my ($counter,$value) = @_;
  init_counter($counter,0);
	if (defined $value) {
		$COUNTER->{$counter}{increment}  = $value;
		$CONF{counter}{$counter}        += $value;
		printdebug_group("counter","incrementing counter",$counter,$value,"now",get_counter($counter));
	}
}

sub set_counter {
  my ($counter,$value) = @_;
	if (defined $value) {
		$CONF{counter}{$counter} = $value;
		printdebug_group("counter","set counter",$counter,$value,"now",get_counter($counter));
	}
}

{
	my %seen;
	sub init_counter {
		my ($counter,$value) = @_;
		if (! $seen{$counter}++) {
			if (defined $value) {
				$CONF{counter}{$counter} = $value;
				printdebug_group("counter","init counter",$counter,"with value",$value,"new value",get_counter($counter));
			}
		}
	}
}

1;
