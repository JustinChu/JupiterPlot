package Circos::Constants;

=pod

=head1 NAME

Circos::Constants - Constants for Circos

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

use strict;
use warnings;

use base 'Exporter';
use Readonly;

Readonly our $APP_NAME   => 'circos';
Readonly our $CARAT      => q{^};
Readonly our $COLON      => q{:};
Readonly our $COMMA      => q{,};
Readonly our $DASH       => q{-};
Readonly our $DOLLAR     => q{$};
Readonly our $EMPTY_STR  => q{};
Readonly our $EMPTY_STRING => q{};
Readonly our $EQUAL_SIGN => q{=};
Readonly our $NEW_LINE   => qq{\n};
Readonly our $PERIOD     => q{.};
Readonly our $PIPE       => q{|};
Readonly our $PLUS_SIGN  => q{+};
Readonly our $SEMICOLON  => q{;};
Readonly our $SPACE      => q{ };
Readonly our $TAB        => qq{\t};

Readonly our $DEG2RAD    => 0.0174532925;
Readonly our $RAD2DEG    => 57.29577951;
Readonly our $DEGRANGE   => 360;
Readonly our $PI_HALF    => 1.570796327;
Readonly our $PI         => 3.141592654;
Readonly our $TWOPI      => 6.283185307;

Readonly our $SQRT2      => 1.414213562;
Readonly our $SQRT3      => 1.732050808;
Readonly our $SQRT3_HALF => 0.866025404;

our @EXPORT = qw($APP_NAME $CARAT $COLON $COMMA $DASH $DEG2RAD $DEGRANGE $DOLLAR $EMPTY_STR $EMPTY_STRING $EQUAL_SIGN $NEW_LINE $PERIOD $PI_HALF $PI $PIPE $PLUS_SIGN $RAD2DEG $SEMICOLON $SPACE $TWOPI $SQRT2 $SQRT3 $SQRT3_HALF $TAB);

1;
