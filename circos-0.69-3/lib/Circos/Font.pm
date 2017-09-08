package Circos::Font;

=pod

=head1 NAME

Circos::Font - utility routines for font handling in Circos

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
get_font_name_from_file
get_font_def_from_key
get_font_name_from_key
get_font_file_from_key
get_label_wh_from_bounds
get_label_size
string_ttf
);

use Carp qw( carp confess croak );
use FindBin;
use GD::Image;
use Font::TTF::Font;
use Params::Validate qw(:all);

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Configuration; # qw(%CONF $DIMS fetch_conf);
use Circos::Constants;
use Circos::Colors;
use Circos::Debug;
use Circos::Error;
use Circos::Utils;
#use Circos::Text;

use Memoize;

our $default_font_name  = "Arial";
our $default_font       = "default";
our $default_font_color = "black";
our $font_table;

for my $f ( qw ( get_font_def_from_key get_font_file_from_key get_font_name_from_key ) ) {
memoize($f);
}

################################################################
# Font name, definition and file handling routines.
#
# for a font key, return the file and name string
#
# e.g. 
# serif_roman -> fonts/modern/cmunrm.otf,CMUSerif-Roman
sub get_font_def_from_key {
    my ($font_key,$role) = @_;
    if(! defined $font_table->{$font_key}{def}) {
	my $font_key_default = fetch_conf("default_font") || $default_font;
	my $font_def         = fetch_conf("fonts",$font_key);
	fatal_error("font","no_def",$font_key,$role||"?") if ! $font_def;
	$font_table->{$font_key}{def} = $font_def;
    }
    return $font_table->{$font_key}{def};
}

# for a font key, return the file
# 
# serif_roman -> fonts/modern/cmunrm.otf
sub get_font_file_from_key {
    my ($font_key,$role) = @_;
    if(! defined $font_table->{$font_key}{file}) {
	my $font_def  = get_font_def_from_key($font_key,$role);
	# file name component of the definition
	my $font_file = locate_file( file => $font_def, name=> $role );
	fatal_error("font","no_file",$font_key,$font_def,$role||"?") if ! $font_file;
	$font_table->{$font_key}{file} = $font_file;
    }
    return $font_table->{$font_key}{file};

}

# for a font key, return the name
#
# serif_roman -> CMUSerif-Roman
#
# if the name is not defined, return 'default_font_name' parameter
sub get_font_name_from_key {
    my ($font_key,$role) = @_;
    if(! defined $font_table->{$font_key}{name}) {
	my $font_def  = get_font_def_from_key($font_key,$role);
	my $font_name = get_file_annotation( file => $font_def, name=> $role );
	if(! $font_name) {
	    my $font_file = get_font_file_from_key($font_key,$role);
	    $font_name    = get_font_name_from_file($font_file);
	}
	#$font_name ||= fetch_conf("default_font_name") || $default_font_name;
	fatal_error("font","no_name",$font_key,$font_def,$role||"?") if ! $font_name;
	$font_table->{$font_key}{name} = $font_name;
    }
    return $font_table->{$font_key}{name};
}

sub get_font_name_from_file {
    my $font_file   = shift;
    if(! defined $font_table->{$font_file}{name}) {
	my $font_ttf    = Font::TTF::Font->open($font_file);
	fatal_error("font","init_error",$font_file) unless $font_ttf;
	my ($font_name) = $font_ttf->{name}->read->find_name(6);
	fatal_error("font","no_name_in_font",$font_file) unless $font_name;
	$font_table->{$font_file}{name} = $font_name;
    }
    return $font_table->{$font_file}{name};
}

################################################################
# Return the bounds of a string
sub string_ttf {
	my %params;
	if(fetch_conf("debug_validate")) {
		%params = validate(@_,
											 {
												color     => { default => fetch_conf("default_font_color") || $default_font_color },
												font_file => 1,
												size      => 1,
												text      => { type => SCALAR },
												angle     => { default => 0 },
												"x"       => 1,
												"y"       => 1,
											 });
	} else {
		%params = @_;
		$params{color} ||= fetch_conf("default_font_color") || $default_font_color;
		$params{angle} ||= 0;
	}
	$params{color} = fetch_color($params{color});
	my @bounds = GD::Image->stringFT(@params{qw(color font_file size angle x y text)});
	return @bounds;
}

################################################################
# Return the width and height of text

sub get_label_size {
	my %params;
	if(fetch_conf("debug_validate")) {
		%params = validate(@_,{
													 color     => { default => fetch_conf("default_font_color") || $default_font_color },
													 font_file => 1,
													 size      => 1,
													 text      => { default => "M" },
													 angle     => { default => 0 },
													 "x"       => { default => 0 },
													 "y"       => { default => 0 },
													});
	} else {
		%params = @_;
		$params{color} ||= fetch_conf("default_font_color") || $default_font_color;
		$params{text}  ||= "M";
		$params{angle} ||= 0;
		$params{x}     ||= 0;
		$params{y}     ||= 0;
	}
	my @label_bounds = string_ttf(%params);
	if(grep(defined $_,@label_bounds) != 8) {
		fatal_error("font","no_ttf",$params{font_file});
	}
	my ($w,$h) = get_label_wh_from_bounds(@label_bounds);
	return ($w,$h);
}

################################################################
# Obtain width and height of label from bounds returned by
# string_ttf. If a string is rotated, the function returns
# the width and height of the unrotated string.
#
#  6,7   4,5     ulx,uly  urx,ury
#
#  0,1   2,3     llx,lly  lrx,lry
#

sub get_label_wh_from_bounds {
    my @bounds = @_;
    if(@bounds != 8) {
	fatal_error("argument","list_size",current_function(),current_package(),8,int(@bounds));
    }
    # llx lower left x
    # lly lower left y
    # lrx lower right x
    # lry lower right y
    # etc
    my ($llx,$lly,$lrx,$lry,$ulx,$uly,$urx,$ury) = @bounds;
    my ($w,$h);
    if ( $lly == $lry ) {
	# the string box is horizontal or vertical
	$w = abs( $lrx - $llx ) - 1;
	$h = abs( $uly - $lly ) - 1;
    } else {
	$w = sqrt( ( abs( $lrx - $llx ) - 1 )**2 + ( abs( $lry - $lly ) - 1 )**2 );
	$h = sqrt( ( abs( $ulx - $llx ) - 1 )**2 + ( abs( $uly - $lly ) - 1 )**2 );
    }
    return ($w,$h);
}

################################################################
# GD TTF sanity check - text must be rendered correctly by each font
sub sanity_check {
    my $fonts = fetch_conf( "fonts" );
    my $size  = 10;
    my $text  = "abc123";
    for my $font_key (keys %$fonts) {
	my $font_def  = get_font_def_from_key($font_key);
	my $font_file = get_font_file_from_key($font_key);
	my $font_name = get_font_name_from_key($font_key);

	my ( $label_width, $label_height ) = get_label_size(font_file=>$font_file,
							    size=>$size,
							    text=>$text);
	if(! $label_width || ! $label_height) {
	    fatal_error("font","no_ttf",$font_file);
	} else {
	    printdebug_group("font",$font_key,$font_name,$font_file);
	}
    }
}

1;
