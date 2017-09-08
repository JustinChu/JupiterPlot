package Circos::Rule;

=pod

=head1 NAME

Circos::Rule - routines for handling rules in Circos

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
use Data::Dumper;
use FindBin;
use GD::Image;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; # qw(%CONF $DIMS);
use Circos::Constants;
use Circos::DataPoint;
use Circos::Debug;
use Circos::Error;
use Circos::Expression;
use Circos::Utils;

use Memoize;

for my $f ( qw() ) {
memoize($f);
}

sub make_rule_list {
	my $conf_leaf = shift;
	my @rules     = make_list( $conf_leaf );
	# first, grep out rules that have an importance value
	my @rules_ordered = sort { $b->{importance} <=> $a->{importance} } grep(defined $_->{importance}, @rules);
	# then add all remaining rules without importance
	push @rules_ordered, grep(! defined $_->{importance}, @rules);
	@rules = @rules_ordered;
	# sanity checks
	# - condition must exist
	# - assign tag automatically, if does not exist
	# - create a list of parameters that are being readjusted
	for my $i (0..@rules-1) {
		my $rule = $rules[$i];
		if(! exists $rule->{condition} && ! exists $rule->{flow}) {
	    $Data::Dumper::Sortkeys = 1;
	    $Data::Dumper::Terse    = 1;
	    fatal_error("rule","no_condition_no_flow",Dumper($rule));
		}
		if(! defined $rule->{tag}) {
	    my $tag = $i;
	    printdebug_group("rule","assigning auto rule tag [$tag]");
	    $rule->{tag} = $tag;
		}
		$rule->{__param} ||= {};
		for my $key (keys %$rule) {
			next if grep($key eq $_, qw(condition importance tag flow __param));
			$rule->{__param}{$key}++;
		}
	}
	return @rules;
}

sub apply_rules_to_track {
    my ($track, $rules, $param_path) = @_;
    
    my $goto_rule_tag;
    my $have_restarted;
  POINT:
    for my $point ( ref $track eq "HASH" && exists $track->{__data} ? @{ $track->{__data} } : @$track ) {
		RULE:
			for my $rule ( @$rules ) {
				if (defined $goto_rule_tag) {
					if ($rule->{tag} ne $goto_rule_tag) {
						printdebug_group("rule","going to rule [$goto_rule_tag] and skipping rule [$rule->{tag}]");
						next RULE;
					} else {
						printdebug_group("rule","found rule [$goto_rule_tag]");
						$goto_rule_tag = undef;
					}
				}
				my $condition = $rule->{condition};
				my @flows     = make_list(seek_parameter( "flow", $rule, $track->{rules} ));
				my $pass;
				if(ref $condition eq "ARRAY") {
					my $pass_iter = 1;
					for my $c (@$condition) {
						$pass_iter &&= test_rule( $point, $c, [ $point, @$param_path ] ) if defined $c;
					}
					$pass = $pass_iter;
				} else {
					$pass = test_rule( $point, $condition, [ $point, @$param_path ] ) if defined $condition;
				}
				
				apply_rule_to_point($point,$rule,$param_path) if $pass;
				
				# if flow is not defined
				if (! @flows) {
				if ($pass) {
					printdebug_group("rule","quitting rule chain");
					last RULE;
				} else {
					printdebug_group("rule","trying next rule");
					next RULE;
				}
			} else {
					for my $flow (@flows) {
						my @flow_tok = split(" ",$flow);
						# if the flow string ends with "if true" or "if false" register
						# whether the flow command should be executed based on whether
						# the rule has passed
						printdebug_group("rule","parsing flow",$flow);
						my $toggle_flow;
						if ($flow =~ /\s+if\s+/) {
							if ($flow =~ /\s+true\s*$/) {
								$toggle_flow = $pass ? 1 : 0;
							} elsif ($flow =~ /\s+false\s*$/) {
								$toggle_flow = !$pass ? 1 : 0;
							} else {
								fatal_error("rules","flow_syntax_error",$flow);
							}
						} else {
							# by default the flow will trigger
							$toggle_flow = 1;
						}
						printdebug_group("rule","rule pass",$pass,"flow",$toggle_flow);
						
						if ($flow =~ /^stop/) {
							if ($toggle_flow) {
								last RULE;
							}
						} elsif ($flow =~ /^goto/) {
							my (undef,$tag,$if,$ifcond) = @flow_tok;
							if ($toggle_flow) {
								$goto_rule_tag = $tag;
								printdebug_group("rule","goto to rule [$tag]");
								goto RULE;
							}
						} elsif ($flow =~ /^restart/) {
							if ($toggle_flow) {
								if (!$rule->{restart}) {
									$rule->{restart} = 1;
									$have_restarted  = 1;
									printdebug_group("rule","restarting rule chain");
									goto RULE;
								} else {
									printdebug_group("rule","cannot restart from rule more than once - quitting rule chain");
									last RULE;
								}
							}
						} elsif ($flow =~ /^continue/) {
							if ($toggle_flow) {
								printdebug_group("rule","continuing to next rule");
								next RULE;
							}
						} else {
							fatal_error("rules","flow_syntax_error",$flow,$rule->{tag});
						}
					}
				}
			}
		
			if (defined $goto_rule_tag) {
				fatal_error("rule","bad_tag",$goto_rule_tag);
			}
			# clear restart flags
			if ($have_restarted) {
				map { delete $_->{restart} } @$rules;
			}
		}
}

sub apply_rule_to_point {
	my ($point,$rule,$param_path) = @_;
	my %data_field = (chr=>1,start=>1,end=>1,value=>1,rev=>1);
	for my $param ( keys %{ $rule->{__param} } ) {
		my $value = $rule->{$param};
		printdebug_group("rule","applying rule var",$param,"value",$value);
		if ( defined $value ) { #  && $value =~ /^eval\(\s*(.*)\s*\)\s*$/ ) {
			#my $expr = $1;
			$value = Circos::Expression::eval_expression($point,$value,[ $point, @$param_path ]);
			printdebug_group("rule","parsed var",$param,"value",$value);
		}
		# filters
		if ( $param eq "minsize") {
			Circos::DataPoint::apply_filter("minsize",$value,$point);
		}  else {
			# parameters
			if ( ! defined $value || $value eq "undef" ) {
		    if ( $param =~ /^(start|end)\d*$/ ) {
					fatal_error("rule","cannot_undefine",$param);
		    } else {
					if($data_field{$param}) {
						$point->{data}[0]{ $param } = undef;
					} else {
						$point->{param}{ $param } = undef;
					}
					#delete $point->{data}[0]{ $param };
		    }
			} else {
		    my $apply_value = 0;
		    if ( not_defined_or_one( $rule->{overwrite} ) ) {
					$apply_value = 1;
		    } else {
					# do not overwrite - check that param does not exist
					if($data_field{$param}) {
						$apply_value = 1 if ! exists $point->{data}[0]{$param};
				} else {
			    $apply_value = 1 if ! exists $point->{param}{$param};
				}
		    }
		    if($apply_value) {
					if($data_field{$param}) {
						$point->{data}[0]{$param} = $value;
					} elsif ($param =~ /([12])$/ && 
									 @{$point->{data}} == 2 &&
									 $data_field{substr($param,0,-1)}) {
						my $num = $1;
						$point->{data}[ $num-1 ]{param}{_modpos} = 1;
						$point->{data}[ $num-1 ]{ substr($param,0,-1) } = $value;
					} else {
						$point->{param}{$param}   = $value;
					}
		    }
			}
		}

		# if ( $param eq "value" || $param eq "start" || $param eq "end" ) {
		# 	if($value eq "undef") {
		#     delete $point->{data}[0]{ $param };
		# 	} else {
		#     $point->{data}[0]{ $param } = $value;
		# 	}
		# } else {
		# 	if ( not_defined_or_one( $rule->{overwrite} ) ) {
		#     # overwrite is default
		#     if($value eq "undef") {
		# 			delete $point->{param}{ $param };
		#     } else {
		# 			$point->{param}{ $param } = $value;
		#     }
		# 	} elsif ( ! exists $point->{param}{$param} ) {
		#     # overwrite only if parameter doesn't exist
		# 		if($value ne "undef") {
		# 	    $point->{param}{$param} = $value;
		#     }
		# 	}
		# }

	}
}

# -------------------------------------------------------------------
sub test_rule {
  my ( $point, $condition, $param_path ) = @_;
  for my $c (make_list($condition)) {
		my $cfmt = Circos::Expression::format_condition($c);
		my $pass = Circos::Expression::eval_expression($point,$cfmt,$param_path,-force_eval=>1);
		printdebug_group("rule","condition [$condition] pass",$pass ? "PASS" : "FAIL");
		return 0 if ! $pass;
  }
  return 1;
}

1;
