
use strict;

# parse an input line from the table and return
# its fields as a list

sub clean_and_split_line {
  my $line = shift;
  chomp $line;
  return () if $line =~ /^\s*$/;
  $line =~ s/^\s*// if $CONF{strip_leading_space};
  return () unless $line;
  #printinfo(join(":",split_line($line)));
  my @tok = map {clean_field($_)} split_line($line);
  return @tok;
}

sub split_line {
  my $str = shift;
  if($CONF{field_delim}) {
    if($CONF{field_delim_collapse}) {
      return split(/$CONF{field_delim}+/,$str);
    } else {
      return split(/$CONF{field_delim}/,$str);
    }
  } else {
    if($CONF{field_delim_collapse}) {
      return split(/[\s\t]/,$str);
    } else {
      return split(/[\s\t]+/,$str);
    }
  }
}

sub clean_field {
  my $str = shift;
  if($CONF{remove_cell_rx}) {
    $str =~ s/[\Q$CONF{remove_cell_rx}\E]//g;
  }
  return $str;
}

sub shorten_text {
  my $string = shift;
  if($CONF{shorten_text} && ref($CONF{string_replace}) eq "HASH") {
    for my $word (sort {length($b) <=> length($a)} keys %{$CONF{string_replace}}) {
      $string =~ s/$word/$CONF{string_replace}{$word}/i;
    }
  }
  return $string;
}

sub parse_label {
  my $string = shift;
  if($CONF{segment_remap}) {
  LABEL:
    for my $new_label (keys %{$CONF{segment_remap}}) {
      my @old_labels = split(/\s*,\s*/, $CONF{segment_remap}{$new_label});
      if(grep($_ eq $string, @old_labels)) {
	$string = $new_label;
	last LABEL;
      }
    }
  }
  return shorten_text($string);
}

sub shorten_text {
  my $string = shift;
  if($CONF{shorten_text}) {
    if(ref($CONF{string_replace}) eq "HASH") {
      for my $word (sort {length($b) <=> length($a)} keys %{$CONF{string_replace}}) {
	$string =~ s/$word/$CONF{string_replace}{$word}/i;
      }
    } else {
      print Dumper($CONF{string_replace});
      die "You've set shorten_text=yes but do not have the required <string_replace> block that defines the replacement strings.";
    }
  }
  return $string;
}

sub clean_value {
  my ($val,$row_name,$col_name) = @_;
  (my $new_val = $val) =~ s/[^\w.\-+$CONF{missing_cell_value}]*//g;
  if($val eq "") {
    if($CONF{blank_means_missing}) {
      report_warning("Interpreting blank value at row,col $row_name,$col_name as missing data");
      $new_val = $CONF{missing_cell_value};
    } else {
      report_error("Cell value at row,col $row_name,$col_name is blank. If you want this to represent missing data, set blank_means_missing=yes");
    }
  }
  if($CONF{use_cell_remap}) {
    my $expr = $CONF{cell_remap_formula};
    $expr =~ s/X/$new_val/g;
    my $expr_value = eval $expr;
    if($@) {
      report_error("Remapping the cell value ($new_val) using the expression ($expr) failed - the expression could not be parsed.");
    } else {
      printdebug("remapped cell",$new_val,$expr,$expr_value);
    }
    $new_val = $expr_value;
  }
  return $new_val;
}


return 1;
