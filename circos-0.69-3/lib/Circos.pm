package Circos;

our $VERSION      = "0.69-3";
our $VERSION_DATE = "24 Jun 2016";

=pod

=head1 NAME

Circos - Circular data visualizations for comparison of genomes, among other things

=head1 SYNOPSIS

  use Circos;
  Circos->run( %OPTIONS );

=head1 DESCRIPTION

Circos is an application for the generation circularly composited data visualizations. 

Circos is particularly suited for visualizing data in genomics
(alignments, conservation and intra and inter-chromosomal
relationships like fusions). However, Circos can be used to plot any
kind of 2D data in a circular layout - its use is not limited to
genomics. Circos' use of lines to relate position pairs (ribbons add a
thickness parameter to each end) is effective to display relationships
between objects or positions on one or more scales.

All documentation is in the form of tutorials at
L<http://www.circos.ca>.

=head1 IMPLEMENTATION

At this time, the module does not return any value, nor does it allow
for dynamic manipulation of the image creation process.

Pass in configuration parameters to generate an image. To create
another image, call run again with different options.

=head1 VERSION

Version 0.69-3

=head1 FUNCTIONS/METHODS

=cut

# -------------------------------------------------------------------

use strict;
use warnings;
use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

BEGIN {
	require Circos::Modules;
	exit if ! check_modules();
}

################################################################
# Globals

our ( %OPT,%RE,
      $IM_BRUSHES, $IM_TILES, $IM_TILES_COLORED, 
      $MAP_MAKE, @MAP_ELEMENTS,  
      @IDEOGRAMS, %IDEOGRAMS_LOOKUP,
      $KARYOTYPE, $GCIRCUM, $GCIRCUM360, $GSIZE_NOSCALE );
$GSIZE_NOSCALE = 0;
################################################################

use Circos::Configuration;
use Circos::Colors;
use Circos::Constants;
use Circos::DataPoint;
use Circos::Debug;
use Circos::Division;
use Circos::Error;
use Circos::Expression;
use Circos::Font;
use Circos::Geometry;
use Circos::Heatmap;
use Circos::Image;
use Circos::IO;
use Circos::Ideogram;
use Circos::Karyotype;
use Circos::PNG;
use Circos::SVG;
use Circos::Rule;
use Circos::Text;
use Circos::Track;
use Circos::Track::Highlight;
use Circos::Unit;
use Circos::Utils;
use Circos::URL;

# -------------------------------------------------------------------
=pod
	
  Circos->run( configfile =>$file  );
  Circos->run( config     =>\%CONF );

Runs the Circos code. You must pass either the C<configfile> location
or a hashref of the configuration options.
=cut
# -------------------------------------------------------------------

	sub run {
    start_timer("circos");
    my $package = shift;
    %OPT = ref $_[0] eq "HASH" ? %{$_[0]} : @_;
    Circos::Error::fake_error($OPT{fakeerror}) if defined $OPT{fakeerror};
    printinfoq(sprintf("%s | v %s | %s | Perl %s",$APP_NAME,$VERSION,$VERSION_DATE,$])) if $OPT{version};

    # Initialize the debug_group for the first time. 
    # This has to happen out-of-band of the loadconfiguration()
    # method, because we don't have access to the config tree yet, 
    # where debug_group has its default value set.
    #
    # By default, the following debug reports are produced
    #
    # always        summary
    # with -debug   io, karyotype, timer
    Circos::Debug::register_debug_groups(\%OPT,\%CONF);

    printdebug_group("summary",sprintf("welcome to circos v%s %s on Perl %s",$VERSION,$VERSION_DATE,$]));
    printdebug_group("summary",sprintf("current working directory %s",cwd()));
		printdebug_group("summary",sprintf("command %s %s",$0,$OPT{_argv} || "[no flags]"));

    if ( $OPT{config} ) {
			%CONF = %{ $OPT{config} };
    } else {
			my $cfile = $OPT{configfile};
			if ($cfile) {
				printdebug_group("summary","loading configuration from file",$cfile);
			} else {
				printdebug_group("summary","guessing configuration file");
				$cfile = locate_file(file=>"circos.conf",
														 name=>"main_configuration",
														 return_undef=>1);
				fatal_error("configuration","missing") if ! $cfile;
			}
			Circos::Configuration::loadconfiguration( $cfile );
			$CONF{configfile} = $cfile;
			$CONF{configdir}  = dirname($cfile);
    }
    # copy command line options to config hash
    Circos::Configuration::populateconfiguration(%OPT); 
    Circos::Configuration::validateconfiguration();
    Circos::Configuration::dump_config(%OPT) if exists $OPT{cdump};

    printdebug_group("summary","debug will appear for these features:",$CONF{debug_group});

    for my $f ( qw(unit_parse unit_strip locate_file getrelpos_scaled_ideogram_start is_counterclockwise debug_or_group unit_strip unit_validate getanglepos get_angle_pos)) {
			memoize($f);
    }

    $PNG_MAKE = $CONF{image}{file} =~ /\.png/ || $CONF{image}{png};
    $SVG_MAKE = $CONF{image}{file} =~ /\.svg/ || $CONF{image}{svg};
    $PNG_MAKE = 1 if ! $SVG_MAKE && ! $PNG_MAKE;

    my $outputfile = sprintf("%s/%s",
														 $CONF{image}{dir},
														 join("",grep($_ ne "./",
																					(fileparse($CONF{image}{file},qr/\.(png|svg)/i))[1,0])));
    $outputfile =~ s/\/+/\//g;
    fatal_error("io","no_directory",dirname($outputfile),"image files") if ! -d dirname($outputfile);
    
    # svg/png output files
    my $outputfile_png = sprintf("%s.png",$outputfile);
    my $outputfile_svg = sprintf("%s.svg",$outputfile);

    printdebug_group("summary","bitmap output image",$outputfile_png) if $PNG_MAKE;
    printdebug_group("summary","SVG output image",$outputfile_svg)    if $SVG_MAKE;

    my $outputfile_map;
    if ( $CONF{image}{image_map_use} ) {
			if ($outputfile_map = $CONF{image}{image_map_file}) {
				if (! file_name_is_absolute($outputfile_map)) {
					$outputfile_map = sprintf("%s/%s",$CONF{image}{dir},$outputfile_map);
				}
			} else {
				$outputfile_map = $CONF{image}{image_map_file} || $outputfile;
			}
			# make sure we have an html extension
			$outputfile_map .= ".html" if $outputfile !~ /\.html$/;
	
			# if the map name is not defined, derive it from the image output file
			$CONF{image}{image_map_name} ||= (fileparse($CONF{image}{file},qr/\.(png|svg)/i))[0];
			$MAP_MAKE = 1;
    }
    
    printdebug_group("summary","HTML map file",$outputfile_map) if $MAP_MAKE;
    
    if ($MAP_MAKE) {
			open MAP, ">$outputfile_map" or fatal_error("io","cannot_write","$outputfile_map","HTML map file",$!);
			printf MAP ("<map name='%s'>\n",$CONF{image}{image_map_name});
    }
    
    if ( $SVG_MAKE ) {
			open SVG, ">$outputfile_svg" or fatal_error("io","cannot_write","$outputfile_svg","SVG image file",$!);
    }

    printsvg(Circos::SVG::tag("xml")); 
    printsvg(Circos::SVG::tag("doctype"));
    printdebug_group("summary","parsing karyotype and organizing ideograms");

    ################################################################
    # Read karyotype and populate the KARYOTYPE data structure which
    # stores information about chromosomes and bands. 

    start_timer("karyotype");
    $KARYOTYPE = Circos::Karyotype::read_karyotype( file => $CONF{karyotype} );
    Circos::Karyotype::validate_karyotype( karyotype => $KARYOTYPE );
    Circos::Karyotype::sort_karyotype( karyotype => $KARYOTYPE );
    printdebug_group("summary","karyotype has",int(keys %$KARYOTYPE),"chromosomes of total size",add_thousands_separator(sum(map { $_->{chr}{set}->cardinality } values %$KARYOTYPE)));
    printdebug_group("karyotype","found",int( keys %$KARYOTYPE ),"chromosomes");
    stop_timer("karyotype");
    
    #printdumperq($KARYOTYPE);
    
    ################################################################
    # determine the chromosomes to be shown and their regions;
    # if a chromosome region has not been defined (e.g. 15 vs 15:x-y)
    # then set the region to be the entire chromosome
    #
    # if no chromosomes are specified, all chromosomes from the karyotype file
    # are displayed if chromosomes_display_default is set
    #
    # hs1,hs2,hs3
    # hs1:10-20,hs2,hs3
    # -hs1:10-20,hs2,hs3
    # hs1:10-20,hs1:40-50,hs2,hs3
    #
    # the ideogram can have an optional label, which can be
    # used in the chromosomes_order field
    #
    # hs1[a],hs2[b],hs3[c]:10-20

    start_timer("ideograms_processing");

    my @chrs = Circos::Ideogram::parse_chromosomes($KARYOTYPE);

    # refine accept/reject regions by
    # - removing reject regions (defined by breaks) from accept regions
    # - make sure that the accept/reject regions are within the chromosome (perform intersection)

    refine_display_regions();

    # create a list of structures to draw in the image

    @IDEOGRAMS = grep( $_->{set}->cardinality > 1, create_ideogram_set(@chrs) );

    ################################################################
    # process chr scaling factor; you can scale chromosomes
    # to enlarge/shrink their extent on the image. Without scaling,
    # each ideogram will occupy a fraction of the circle (not counting
    # spaces between the ideograms) proportional to its total size. Thus
    # a 200Mb chromosome will always be twice as long as a 100Mb chromosome,
    # regardless of any non-linear scale adjustments.
    #
    # with scaling, you can make a 100Mb chromosome occupy the same
    # extent by using a scale of 2.

    register_chromosomes_scale() if fetch_conf("chromosomes_scale") || fetch_conf("chromosome_scale");

    ################################################################
    # direction of individual ideograms can be reversed
    # chromosomes_reverse = tag,tag

    register_chromosomes_direction() if $CONF{chromosomes_reverse};

    ################################################################
    # process the order of appearance of the chromosomes on the image
    #
    # chromosome names can be labels associated with individual ranges
    #
    # ^, -, -, hs3, hs1, -, hs2
    #
    # ^, -, -, a, c, -, b
    #
    # the process of deteriming the final order is convoluted

    #printdumper(@IDEOGRAMS);
    #printdumperq($KARYOTYPE->{hs1}{chr});

    my @chrorder = read_chromosomes_order();

    #printdumperq(@chrorder);

    # construct ideogram groups based on the content of chromosomes_order, with
    # each group corresponding to a list of tags between breaks "|" in the
    # chromosomes_order string

    my $chrorder_groups = [ { idx => 0, cumulidx => 0 } ];
    $chrorder_groups = make_chrorder_groups($chrorder_groups, \@chrorder);
    
    #printdumperq(@IDEOGRAMS);
    #printdumperq($chrorder_groups);

    ################################################################
    #
    # Now comes the convoluted business. Here is where I set the display_idx
    # which is the order in which the ideograms are displayed.
    #
    # Iterate through each group, handling the those with start/end
    # anchors first, and assign the display_idx to each tag as follows
    #
    # - start at 0 if this is a group with start anchor
    # - start at num_ideograms (backwards) if this is a group with end anchor
    # - set display_idx <- ideogram_idx if this display_idx is not already defined
    #     (this anchors the position to be the same as the first placeable ideogram)
    #
    ################################################################
    set_display_index($chrorder_groups);

    #printdumperq($chrorder_groups);

    ################################################################
    #
    # now check each group and make sure that the display_idx values
    # don't overlap - if they do, shift each group (starting with
    # the first one that overlaps) until there is no more overlap
    #
    ################################################################

    reform_chrorder_groups($chrorder_groups);

    #printdumperq($chrorder_groups);

    recompute_chrorder_groups($chrorder_groups);

    #printdumperq($chrorder_groups);

    @IDEOGRAMS = sort { $a->{display_idx} <=> $b->{display_idx} } @IDEOGRAMS; 
		
    if (@IDEOGRAMS > fetch_conf("max_ideograms")) {
			fatal_error("ideogram","max_number",int(@IDEOGRAMS),fetch_conf("max_ideograms"));
    }

    # for each ideogram, record
    #  - prev/next ideogram
    #  - whether axis breaks may be required at ends

    for my $i ( 0 .. @IDEOGRAMS - 1 ) {
			my $this = $IDEOGRAMS[$i];
			my $chr  = $this->{chr};
			#printstructure("ideogram",$this);
			next unless defined $this->{display_idx};
			my $next = $i < @IDEOGRAMS - 1 ? $IDEOGRAMS[$i+1] : $IDEOGRAMS[0];
			my $prev = $IDEOGRAMS[$i-1];
			$this->{next} = $next;
			$this->{prev} = $prev;
			if ($next->{chr} ne $chr && $this->{set}->max < $KARYOTYPE->{ $chr }{chr}{set}->max ) {
				$this->{break}{end} = 1;
			}
			if ($prev->{chr} ne $chr && $this->{set}->min > $KARYOTYPE->{ $chr }{chr}{set}->min ) {
				$this->{break}{start} = 1;
			}
    }

    $CONF{chromosomes_units} = unit_convert(from=>$CONF{chromosomes_units},
																						to=>'b',
																						factors => {
																												nb => 1,
																												rb => 10**(round(log10(sum(map {$_->{set}->cardinality} @IDEOGRAMS )))),
																											 });
    printdebug_group("summary","applying global and local scaling");
    stop_timer("ideograms_processing");
		
    ################################################################
    # non-linear scale

    start_timer("ideograms_zoom");
    my @zooms = make_list( $CONF{zooms}{zoom} );
    for my $zoom (@zooms) {
			my @param_path = ($CONF{zooms});
			next unless show($zoom,@param_path);
			unit_validate( $zoom->{start}, 'zoom/start', qw(u b) );
			unit_validate( $zoom->{end},   'zoom/end',   qw(u b) );
			for my $pos (qw(start end)) {
				$zoom->{$pos} = unit_convert(
																		 from    => $zoom->{$pos},
																		 to      => 'b',
																		 factors => { ub => $CONF{chromosomes_units} }
																		);
			}
			$zoom->{set} = Set::IntSpan->new( sprintf( '%d-%d', $zoom->{start}, $zoom->{end} ) );
			my $smooth_distance = seek_parameter( 'smooth_distance', $zoom, @param_path );
			my $smooth_steps = seek_parameter( 'smooth_steps', $zoom, @param_path );
			next unless $smooth_distance && $smooth_steps;
			unit_validate( $smooth_distance, 'smooth_distance', qw(r u b) );
			$smooth_distance = unit_convert(from    => $smooth_distance,
																			to      => 'b',
																			factors => {ub => $CONF{chromosomes_units},
																									rb => $zoom->{set}->cardinality}
																		 );
			$zoom->{smooth}{distance} = $smooth_distance;
			$zoom->{smooth}{steps}    = $smooth_steps;
    }

    my $Gspans;

    for my $ideogram (@IDEOGRAMS) {
			my $chr = $ideogram->{chr};

			# create sets and level for zoom
			my @param_path = ( $CONF{zooms}{zoom} );

			# check which zooms apply to this ideogram
			my @ideogram_zooms = grep( $_->{chr} eq $ideogram->{chr}
																 && ( !defined $_->{use} || $_->{use} )
																 && $ideogram->{set}->intersect( $_->{set} )->cardinality,
																 @zooms );
			# construct a list of zoomed regions from smoothing parameters (smooth_distance, smooth_steps)
			my @zooms_smoothers;
			for my $zoom (@ideogram_zooms) {
				my $d = $zoom->{smooth}{distance};
				my $n = $zoom->{smooth}{steps};
				next unless $d && $n;
				my $subzoom_size = $d / $n;
				for my $i ( 1 .. $n ) {
					my $subzoom_scale = ( $zoom->{scale} * ( $n + 1 - $i ) + $ideogram->{scale} * $i ) / ( $n + 1 );
					0&&printinfo($chr,
											 $d,$i,$n,
											 $zoom->{set}->min,
											 $subzoom_size,$subzoom_scale);
					my $subzoom_start = $zoom->{set}->min - $i*$subzoom_size;
					my $subzoom_end   = $subzoom_start + $subzoom_size;
					my $zs1 = { set => Set::IntSpan->new(sprintf( '%d-%d', $subzoom_start, $subzoom_end ))->intersect( $ideogram->{set} ),
											scale => $subzoom_scale };
					push @zooms_smoothers, $zs1 if $zs1->{set}->cardinality;
					$subzoom_start = $zoom->{set}->max + ( $i - 1 ) * $subzoom_size;
					$subzoom_end = $subzoom_start + $subzoom_size;
					my $zs2 = {set => Set::IntSpan->new(sprintf( '%d-%d', $subzoom_start, $subzoom_end ))->intersect( $ideogram->{set} ),
										 scale => $subzoom_scale};
					push @zooms_smoothers, $zs2 if $zs2->{set}->cardinality;

				}
			}
			push @ideogram_zooms, @zooms_smoothers if @zooms_smoothers;
			push @ideogram_zooms, {set => $ideogram->{set}, scale => $ideogram->{scale}, null => 1 };

			my %boundaries;
			for my $zoom (@ideogram_zooms) {
				for my $pos ($zoom->{set}->min-1,
										 $zoom->{set}->min,
										 $zoom->{set}->max,
										 $zoom->{set}->max+1
										) {
					$boundaries{$pos}++;
				}
			}
			my @boundaries = sort { $a <=> $b } keys %boundaries;

			# the first and last boundary are, by construction, outside of any
			# zoom set, so we are rejecting these
			@boundaries = @boundaries[ 1 .. @boundaries - 2 ];
			my @covers;
			for my $i ( 0 .. @boundaries - 2 ) {
				my ( $x, $y ) = @boundaries[ $i, $i + 1 ];
				my $cover = { set => Set::IntSpan->new("$x-$y") };
				$cover->{set} = $cover->{set}->intersect( $ideogram->{set} );
				next unless $cover->{set}->cardinality;
				for my $zoom (@ideogram_zooms) {
					if ( $zoom->{set}->intersect( $cover->{set} )->cardinality ) {
						my $zoom_level = max( $zoom->{scale}, 1 / $zoom->{scale} );
						if ( ! defined $cover->{level} || ( !$zoom->{null} && $zoom_level > $cover->{level} ) ) {
							$cover->{level} = $zoom_level;
							$cover->{scale} = $zoom->{scale};
						}
					}
				}
				my $merged;
				for my $c (@covers) {
					if ( $c->{level} == $cover->{level} && $c->{scale} == $cover->{scale}
							 && 
							 ( ( $c->{set}->min == $cover->{set}->max )
								 || 
								 ( $c->{set}->max == $cover->{set}->min )
								 || 
								 ( $c->{set}->intersect( $cover->{set} )->cardinality )
							 )
						 ) {
						$c->{set} = $c->{set}->union( $cover->{set} );
						$merged = 1;
						last;
					}
				}
				if ( !$merged ) {
					push @covers, $cover;
				}
			}
			# make sure that covers don't overlap
			my $prev_cover;
			for my $cover (@covers) {
				$cover->{set}->D($prev_cover->{set}) if $prev_cover;
				printdebug_group("zoom",
												 sprintf(
																 "zoomregion ideogram %d chr %s %9d %9d scale %5.2f absolutescale %5.2f",
																 $ideogram->{idx},   $ideogram->{chr},
																 $cover->{set}->min, $cover->{set}->max,
																 $cover->{scale},    $cover->{level}
																)
												);
				$prev_cover = $cover;
			}

			# add up the zoomed distances for all zooms (zoom range * level) as well as size of all zooms
			my $sum_cover_sizescaled = sum( map { ( $_->{set}->cardinality - 1 ) * $_->{scale} } @covers );
			my $sum_cover_size       = sum( map { ( $_->{set}->cardinality - 1 ) } @covers );

			$ideogram->{covers}          = \@covers;
			$ideogram->{length}{scale}   = $sum_cover_sizescaled;
			$ideogram->{length}{noscale} = $ideogram->{set}->cardinality;
    }

    ################################################################
    # construct total size of all displayed ideograms and
    # cumulative size for each chromosome

    my $Gsize = 0;
    for my $ideogram (@IDEOGRAMS) {
			$ideogram->{length}{cumulative}{scale}   = $Gsize;
			$ideogram->{length}{cumulative}{noscale} = $GSIZE_NOSCALE;
			for my $cover ( @{ $ideogram->{covers} } ) {
				$Gsize         += ( $cover->{set}->cardinality - 1 ) * $cover->{scale};
				$GSIZE_NOSCALE += ( $cover->{set}->cardinality - 1 );
			}
    }
    printdebug_group("scale","total displayed chromosome size", $GSIZE_NOSCALE );
    printdebug_group("scale","total displayed and scaled chromosome size", $Gsize );

    $GCIRCUM = $Gsize;
    for my $i (0..@IDEOGRAMS-1) {
			my $id1     = $IDEOGRAMS[$i];
			my $id2     = $IDEOGRAMS[$i+1] || $IDEOGRAMS[0];
			my $spacing = ideogram_spacing($id1,$id2,0);
			printdebug_group("spacing","ideogramspacing",
											 $id1->{chr},$id1->{tag},
											 $id2->{chr},$id2->{tag},
											 $spacing);
			$GCIRCUM += $spacing;
    }

    # do any ideograms have relative scale?

    my $rel_scale_on       = grep($_->{scale_relative}, @IDEOGRAMS);
    my $rescale_iterations = (fetch_conf("relative_scale_iterations")||2) * $rel_scale_on;

    for my $iter (1..$rescale_iterations) {
			my %seen_chr;
			for my $i (0..@IDEOGRAMS-1) {
				my $id        = $IDEOGRAMS[$i];
				my $scale_rel = $id->{scale_relative};
				next if ! defined $scale_rel;
				if ($scale_rel >= 1 || $scale_rel <= 0) {
					fatal_error("ideogram","bad_relative_scale",$scale_rel,$id->{chr},$id->{tag});
				}
				# total scaled length of all covers for this ideogram
				my $displayed_len = sum (map { $_->{set}->cardinality * $_->{scale} } @{$id->{covers}});
				my $scale_mult    = $scale_rel * ($GCIRCUM - $displayed_len) / ( $displayed_len * ( 1 - $scale_rel ) );
				# adjust the cover scale so that the length is the fraction of displayed
				# genome given by scale_relative
				#
				# r = relative_scale
				# k = chr magnification
				# 
				# Assume genome is chromosomes x1, x2, x3. Let G = x1+x2+x3
				#
				# r = kx1/(kx1+x2+x3)
				# k = r(G-x1) / [x1(1-r)]
				for my $cover (@{$id->{covers}}) {
					$cover->{scale} *= $scale_mult; # ?:  *= or =  
					printdebug_group("scale","rescaling",$i,$id->{chr},
													 "displayed_len",sprintf("%.3f",$displayed_len/$CONF{chromosomes_units}),
													 "gcircum",sprintf("%.3f",$GCIRCUM/$CONF{chromosomes_units}),
													 "scale_mult",sprintf("%.3f",$scale_mult),
													 "cover_scale",sprintf("%.3f",$cover->{scale}));
				}
			}
	
			# We're interested in relative rescaling. Keep things sane by dividing every scale
			# by the largest one.
			my ($max_scale) = max ( map { $_->{scale} } (map { @{$_->{covers}} }  @IDEOGRAMS) ) || 1;
			my ($sum_scale) = sum ( map { $_->{scale} } (map { @{$_->{covers}} }  @IDEOGRAMS) ) || 1;
			for my $id (@IDEOGRAMS) {
				for my $cover (@{$id->{covers}}) {
					$cover->{scale} /= $sum_scale;
				}
			}

			$Gsize         = 0;
			$GSIZE_NOSCALE = 0;
			for my $ideogram (@IDEOGRAMS) {
				$ideogram->{length}{cumulative}{scale}   = $Gsize;
				$ideogram->{length}{cumulative}{noscale} = $GSIZE_NOSCALE;
				$ideogram->{length}{scale}               = 0;
				for my $cover ( @{ $ideogram->{covers} } ) {
					my $cover_len = $cover->{set}->cardinality * $cover->{scale};
					$ideogram->{length}{scale} += $cover_len;
					$Gsize         += $cover_len;
					$GSIZE_NOSCALE += ( $cover->{set}->cardinality );
				}
			}

			for my $ideogram (@IDEOGRAMS) {
				my $displayed_len = sum ( map { $_->{set}->cardinality * $_->{scale} } @{$ideogram->{covers}} );
				printdebug_group("scale","rescaling tally",$ideogram->{chr},
												 "displayed_len_new",sprintf("%.3f",$displayed_len/$CONF{chromosomes_units}),
												 "fraction",sprintf("%.3f",$displayed_len/$Gsize));
			}

			$GCIRCUM = $Gsize;
			for my $i (0..@IDEOGRAMS-1) {
				my $id1     = $IDEOGRAMS[$i];
				my $id2     = $IDEOGRAMS[$i+1] || $IDEOGRAMS[0];
				my $spacing = ideogram_spacing($id1,$id2,0);
				$GCIRCUM   += $spacing;
			}

			printdebug_group("scale","rescaling",
											 "gsize",
											 sprintf("%.3f",$Gsize/$CONF{chromosomes_units}),
											 "gsize_noscale",sprintf("%.3f",$GSIZE_NOSCALE/$CONF{chromosomes_units}),
											 "gcircum",$GCIRCUM/$CONF{chromosomes_units});

    }

    $GCIRCUM360 = 360/$GCIRCUM;

    $DIMS->{image}{radius} = unit_strip( $CONF{image}{radius}, 'p' );
    $DIMS->{image}{width}  = 2 * $DIMS->{image}{radius};
    $DIMS->{image}{height} = 2 * $DIMS->{image}{radius};
    
    stop_timer("ideograms_zoom");

    if (debug_or_group("scale")) {
			for my $id (@IDEOGRAMS) {
				my $a0 = getanglepos( $id->{set}->min,$id->{chr} );
				my $a1 = getanglepos( $id->{set}->max,$id->{chr} );
				my $a2 = getanglepos( $id->{next}{set}->min,$id->{next}{chr} );
				my $da = abs($a0 - $a1);
				my $ds = abs($a2 - $a1);
				printdebug_group("scale","final id",$id->{chr},sprintf("%.4f",$da/360));
				printdebug_group("scale","final sp",$id->{chr},$id->{next}{chr},sprintf("%.4f",$ds/360));
			}
    }
    
    printdebug_group("image",
										 'creating image template for circle',
										 $DIMS->{image}{radius},
										 'px diameter'
										);
    
    printsvg(qq{<svg width="$DIMS->{image}{width}px" height="$DIMS->{image}{height}px" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">});

    register_chromosomes_radius($CONF{chromosomes_radius});

    ################################################################
    # repeatedly creating brushes with color allocation can soak up
    # CPU time. This hash stores brushes of a given width/height size
    #
    # width=2 height=3 brush
    # $im_brushes->{size}{2}{3}

    printdebug_group("summary","allocating image, colors and brushes");

    my $bgfill;
    if ( $CONF{image}{background} && ! defined $CONF{colors}{ $CONF{image}{background} } && locate_file( file => $CONF{image}{background}, return_undef => 1 ) ) {
			GD::Image->trueColor(1);
			$IM = GD::Image->new( locate_file( file => $CONF{image}{background}, name=>"image background" ) );
    } else {
			eval {
				$IM = GD::Image->new( @{ $DIMS->{image} }{qw(height width)}, 1);
			};
			if ($@) {
				$IM = GD::Image->new( @{ $DIMS->{image} }{qw(height width)} );
			}
			$bgfill = 1;
    }

    start_timer("color");
    # Always allocate colors
    if (1 || $PNG_MAKE) {
			my $t = [gettimeofday()];
			$COLORS = allocate_colors( $IM );
			if (exists $COLORS->{transparent}) {
				$IM->transparent( $COLORS->{transparent} );
			} else {
				# if 'transparent' color was not explicitly defined, select one
				# starting at 1,0,0 - testing first whether this RGB value has
				# already been defined
				my @rgb = find_transparent();
				printdebug_group("color","allocate_color","default transparent color",@rgb);
				allocate_color("transparent",\@rgb,$COLORS,$IM);
				$IM->transparent( $COLORS->{transparent} );
			}
			if (exists $COLORS->{clear}) {
				fatal_error("color","clear_redefined");
			}
			$COLORS->{clear} = $COLORS->{transparent};
			printdebug_group("color","allocated", int( keys %$COLORS ), "colors in",tv_interval($t),"s" );

			# draw svg background
			#
			if($SVG_MAKE) {
				my @rgb = $IM->rgb( fetch_color($CONF{image}{background} || "white",$COLORS));
				my $rgb = join(",",@rgb);
				printsvg(qq{<g id="bg">});
				printsvg(qq{<rect x="0" y="0" width="$DIMS->{image}{width}px" height="$DIMS->{image}{height}px" style="fill:rgb($rgb);"/>});
				printsvg(qq{</g>});
			}
			if ($bgfill) {
				$IM->fill( 0, 0, fetch_color($CONF{image}{background} || "white", $COLORS) );
			}
    }
    stop_timer("color");

    # TTF sanity
    Circos::Font::sanity_check();

		printdebug_group("summary","drawing",int(@IDEOGRAMS),"ideograms of total size",add_thousands_separator(sum(map { $_->{set}->cardinality} @IDEOGRAMS)));

    if (debug_or_group("ideogram")) {
			my $max_chr_len   = max ( map { length($_->{chr}) } @IDEOGRAMS ) || 1;
			my $max_label_len = max ( map { length($_->{label}) } @IDEOGRAMS ) || 1;
			my $max_len       = max ( map { length($_->{set}->max) } @IDEOGRAMS ) || 1;
			my $fc = "%${max_chr_len}s";
			my $fs = "%${max_label_len}s";
			my $fd = "%${max_len}d";
			for my $ideogram (sort {$a->{display_idx} <=> $b->{display_idx}} @IDEOGRAMS) {
				printdebug_group("ideogram",
												 sprintf(
																 "%2d %2d $fc $fs $fs %s $fd $fd %s $fd z $fd $fd s %.2f r %d rad %d %d %d %d %d prev $fs $fs next $fs $fs",
																 $ideogram->{idx},
																 $ideogram->{display_idx},
																 $ideogram->{chr},
																 $ideogram->{tag},
																 $ideogram->{label},
																 $ideogram->{break}{start} ? "B" : "-",
																 $ideogram->{set}->min,
																 $ideogram->{set}->max,
																 $ideogram->{break}{end} ? "B" : "-",
																 $ideogram->{set}->size,
																 $ideogram->{length}{cumulative}{noscale},
																 $ideogram->{length}{cumulative}{scale},
																 $ideogram->{scale},
																 $ideogram->{reverse},
																 $ideogram->{radius},
																 $ideogram->{radius_inner},
																 $ideogram->{radius_outer},
																 $ideogram->{thickness},
																 getrelpos_scaled(0,$ideogram->{chr}),
																 @{$ideogram->{prev}}{qw(chr tag)},
																 @{$ideogram->{next}}{qw(chr tag)},

																)
												);
			}
    }
    if (debug_or_group("cover")) {
			for my $ideogram (sort {$a->{display_idx} <=> $b->{display_idx}} @IDEOGRAMS) {
				for my $cover (@{$ideogram->{covers}}) {
					printdebug_group("cover",sprintf("cover %8d %8d %8d %.2f",
																					 $cover->{set}->min,
																					 $cover->{set}->max,
																					 $cover->{set}->cardinality,
																					 $cover->{scale}));
				}
			}
    }
    if (debug_or_group("anglepos")) {
			for my $ideogram (@IDEOGRAMS) {
				for (
						 my $pos = $ideogram->{set}->min ;
						 $pos <= $ideogram->{set}->max ;
						 $pos += $CONF{chromosomes_units}
						) {
					printdebug_group("anglepos",
													 sprintf(
																	 'ideogrampositionreport %2d %5s pos %9s angle %f r %f',
																	 $ideogram->{idx}, $ideogram->{chr}, $pos,
																	 getanglepos( $pos, $ideogram->{chr}),
																	 $ideogram->{radius})
													);
				}
			}
    }

    # All data sets are stored in this structure. I'm making the
    # assumption that memory is not an issue.
    
    my $data;
    my $track_z;
    my @track_z;
    my $track_default;
    
    printdebug_group("summary","drawing highlights and ideograms");
    
    ################################################################
    #
    # chromosome ideograms and highlights
    #
    
    ################################################################
    #
    # Process data for highlights
    #
    # Highlights work differently than other data types, because they're
    # drawn underneath all othere data and figure elements,
    # including grids, tick marks and tick labels.
    #
    ################################################################
		
    start_timer("highlights");
    $track_default->{highlights} = parse_parameters( fetch_conf("highlights"), "highlight" );
		
    my @highlight_tracks = map { parse_parameters($_, "highlight", 0) } 
			Circos::Track::make_tracks( fetch_conf("highlights","highlight"), 
																	$track_default->{highlights},
																	"highlight.bg" );
		
    @highlight_tracks = grep(show($_,$track_default->{highlights}), @highlight_tracks);
		
    for my $track ( @highlight_tracks ) {
			my @param_path = ( $track, $track_default->{highlights} );

			my $track_type = "highlight";
			my $track_id   = $track->{id};
			my $track_file = locate_file( file => seek_parameter("file",@param_path), name=>"$track_type track id $track_id");

			printdebug_group("summary","process",$track_id,$track_type,$track_file);

			my $track_file_param = {
															addset       => 1,
															padding      => seek_parameter( 'padding',      @param_path ),
															file_rx      => seek_parameter( 'file_rx',      @param_path ),
															minsize      => seek_parameter( 'minsize',      @param_path ),
															record_limit => seek_parameter( 'record_limit', @param_path )
														 };

			$track->{__data}  = Circos::IO::read_data_file($track_file,
																										 $track_type,
																										 $track_file_param,
																										 $KARYOTYPE);


			# apply any rules to this highlight track
			my @rules = Circos::Rule::make_rule_list( $track->{rules}{rule} );
			# pick out only those rules that are used
			@rules = grep( use_set($_,$track->{rules}), @rules );

			start_timer("datarules");
			Circos::Rule::apply_rules_to_track($track,\@rules,\@param_path) if @rules;
			stop_timer("datarules");

			$track->{__data} = [ grep( show($_), @{$track->{__data}} ) ];

			$track->{z} = seek_parameter("z",@param_path) || 0;
			# compute z values for each data point

			if (@{$track->{__data}} > fetch_conf("max_points_per_track")) {
				fatal_error("track","max_number",int(@{$track->{__data}}),$track_type,$track_file,fetch_conf("max_points_per_track"));
			}

			for my $datum ( @{$track->{__data}} ) {
				$datum->{param}{z} = seek_parameter("z",$datum) || 0;
			}

    }
    stop_timer("highlights");

    ################################################################
    #
    # Draw ideograms
    #
    ################################################################

    printsvg(qq{<g id="ideograms">}) if $SVG_MAKE;

		# apply rules to ideograms
		# first, fake an ideogram track with __data and rules entries, so that
		# we can use rule application functions
		my $ideogram_track = { __data=>[ map { { data=>[$_],param=>{} } } @IDEOGRAMS ],
													 rules=>fetch_conf("ideogram","rules") };
		my @rules = Circos::Rule::make_rule_list( $ideogram_track->{rules}{rule} );
		# pick out only those rules that are used
		@rules = grep( use_set($_,$ideogram_track->{rules}), @rules );

		start_timer("datarules");
		Circos::Rule::apply_rules_to_track($ideogram_track,\@rules,[]) if @rules;
		stop_timer("datarules");

    start_timer("ideograms_draw");

		for my $datum (@{$ideogram_track->{__data}}) {
			my @param_path = ( fetch_conf("ideogram") );
			my $ideogram   = $datum->{data}[0];
			my $chr        = $ideogram->{chr};
			my $tag        = $ideogram->{tag};

			Circos::Track::Highlight::draw_highlights( \@highlight_tracks,
																								 $track_default->{highlights},
																								 $chr,
																								 $ideogram->{set},
																								 $ideogram,
																								 { ideogram => 0, layer_with_data => 0 } );

			next if hide($datum,@param_path);

			my ( $start, $end )     = ( $ideogram->{set}->min, $ideogram->{set}->max );
			my ( $start_a, $end_a ) = ( getanglepos( $start, $chr ), getanglepos( $end, $chr ) );

			printdebug_group("karyotype",
											 sprintf("ideogram %s scale %f idx %d base_range %d %d angle_range %.3f %.3f",
															 $chr, 
															 $ideogram->{scale}, 
															 $ideogram->{display_idx},
															 $start,$end,$start_a,$end_a
															)
											);

			# first pass at drawing ideogram - stroke and fill
			# TODO consider removing this if radius_from==radius_to

			my $url = seek_parameter("url",$ideogram) || $CONF{ideogram}{ideogram_url};
			$url = format_url(url=>$url,
												param_path=>[$ideogram, 
																		 {start=>$ideogram->{set}->min, end=>$ideogram->{set}->max}]);
			#printinfo($url);

			for my $svgparam_hash (seek_parameter_glob("^svg.*",undef,fetch_conf("ideogram"))) {
				for my $svgparam (keys %$svgparam_hash) {
					my $value = $svgparam_hash->{$svgparam};
					if (defined $value) { #  $value =~ /^eval\(\s*(.*)\s*\)\s*$/ ) {
						#my $expr = $1;
						$value = Circos::Expression::eval_expression( {data=>[$ideogram]}, $value );
					} else {
					}
					$ideogram->{$svgparam} = $value;
				}
			}
			my $color;
			if(seek_parameter("fill",$datum,@param_path)) {
				$color = seek_parameter("color|fill_color",$datum,$ideogram,$KARYOTYPE->{$chr}{chr},@param_path);
			}
			slice(
						image       => $IM,
						start       => $start,
						end         => $end,
						chr         => $chr,
						radius_from => $DIMS->{ideogram}{ $tag }{radius_inner},
						radius_to   => $DIMS->{ideogram}{ $tag }{radius_outer},
						edgecolor   => seek_parameter("stroke_color",$datum,@param_path),
						edgestroke  => seek_parameter("stroke_thickness",$datum,@param_path),
						fillcolor   => $color,
						pattern     => seek_parameter("fill_pattern",$datum,@param_path),
						mapoptions  => { url=>$url },
						svg         =>  { attr => seek_parameter_glob("^svg.*",qr/^svg/,$ideogram) },
						guides      => fetch_conf("guides","object","ideogram") || fetch_conf("guides","object","all"),
					 );

			# cytogenetic bands
			for my $band ( make_list( $KARYOTYPE->{$chr}{band} ) ) {
				next unless seek_parameter("show_bands",$datum,@param_path);
				my ( $bandstart, $bandend ) = @{$band}{qw(start end)};
				my $bandset = $band->{set}->intersect( $ideogram->{set} );
				next unless $bandset->cardinality;
				my $bt = seek_parameter("band_transparency",$datum,@param_path);
				my $fillcolor = $bt ? sprintf("%s_a%d", $band->{color}, $bt ) : $band->{color};
				#printdumper($band) if $band->{name} eq "p31.1" && $band->{chr} eq "hs1";
				my $url = seek_parameter("url",$band) || $CONF{ideogram}{band_url};
				$url = format_url(url=>$url,param_path=>[$band->{options}||{},$band]);
				slice(
							image       => $IM,
							start       => $bandset->min,
							end         => $bandset->max,
							chr         => $chr,
							radius_from => get_ideogram_radius($ideogram) -	$DIMS->{ideogram}{ $ideogram->{tag} }{thickness},
							radius_to  => get_ideogram_radius($ideogram),
							edgecolor  => seek_parameter("band_stroke_color|stroke_color",$datum,@param_path),
							edgestroke => seek_parameter("band_stroke_thickness",$datum,@param_path),
							mapoptions => { url=>$url },
							fillcolor => seek_parameter("fill_bands",$datum,@param_path) ? $fillcolor : undef
						 );
			}
			if (seek_parameter("show_label",$datum,@param_path)) {
				my $font_role = "ideogram label";
				# Circos font key, such as 'default', or 'condensed'
				my $font_key  = seek_parameter("label_font",$datum,@param_path) || fetch_conf("default_font") || "default";
				# font definition, which includes file name and font name, such as /path/to/symbols.ttf,Symbols
				my $font_def  = get_font_def_from_key($font_key,$font_role);
				# file name component of the definition
				my $font_file = get_font_file_from_key($font_key,$font_role);
				# font name component of the definition
				my $font_name = get_font_name_from_file($font_file);
				my $label  = $KARYOTYPE->{$chr}{chr}{label};
				if ( fetch_conf("ideogram","label_with_tag") ) {
					$label .= $tag if $tag ne $chr && $tag !~ /__/;
				}
				if ( my $fmt = seek_parameter("label|label_format",$datum,@param_path) ) {
					#if ( $fmt =~ /^eval\(\s*(.*)\s*\)\s*$/ ) {
					#my $expr = $1;
					$label = Circos::Expression::eval_expression( {data=>[$ideogram]}, $fmt );
					#} else {
					#$label = $fmt;
					#}
				}
				my $label_case = seek_parameter("label_case",$datum,@param_path) || $EMPTY_STR;
				if ($label_case eq "upper") {
					$label = uc $label;
				} elsif ($label_case eq "lower") {
					$label = lc $label;
				}
				my $label_size = unit_strip( seek_parameter("label_size",$datum,@param_path), 'p' );
				my ($label_width,$label_height) = get_label_size(font_file=>$font_file,
																												 size=>$label_size,
																												 text=>$label);
				my $pos          = get_set_middle( $ideogram->{set} );
				my $textangle    = get_angle_pos( $pos, $chr );
				my $svg_anchor   = "end";

				my $label_parallel = seek_parameter("label_parallel",$datum,@param_path);
				# centers the label radially - useful only when the label is radial, not parallel
				my $label_radius   = unit_parse(seek_parameter("label_radius",$datum,@param_path));
				#printinfo($tag,$label_radius,$DIMS->{ideogram}{$tag}{label}{radius});

				if (seek_parameter("label_center",$datum,@param_path)) {
					my $offset;
					if($label_parallel) {
						$offset = $label_height;
					} else {
						$offset = $label_width;
					}
					$svg_anchor = "middle";
					$label_radius -= $offset/2;
				}

				my ($offset_angle,$offset_radius) = textoffset($textangle,
																											 $label_radius,
																											 #$DIMS->{ideogram}{$tag}{label}{radius},
																											 $label_width, $label_height,
																											 0,
																											 $label_parallel);
				my $radius       = $offset_radius + $label_radius; # $DIMS->{ideogram}{$tag}{label}{radius};
				my $pangle       = getanglepos( $pos, $chr );
				my $pangle_shift = $label_parallel ? $RAD2DEG * ($label_width/2/$radius) : 0;

				#
				#   270 | -90
				#       |
				#  180 --- 0
				#       |
				#       90
				#

				if ($pangle > 180 || $pangle < 0) {
					$pangle_shift = -$pangle_shift;
				}

				my $label_color = seek_parameter("label_color",$datum,@param_path) || fetch_conf("default_color") || 'black';

				Circos::Text::draw_text (
																 text        => $label,
																 font        => seek_parameter("label_font",$datum,@param_path) || fetch_conf("default_font") || "default",
																 size        => $label_size,
																 color       => $label_color,
																 angle       => $textangle,
																 is_rotated  => seek_parameter("label_rotated",$datum,@param_path),
																 is_parallel => $label_parallel,
																 radius      => $label_radius, # $DIMS->{ideogram}{ $tag }{label}{radius},
																 guides      => fetch_conf("guides","object","ideogram_label") || fetch_conf("guides","object","all"),
																 svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$ideogram) },
																 mapoptions  => { url  => $url },
																);
			}

			# draw scale ticks
			if (seek_parameter("show_ticks",$datum,@param_path,\%CONF)) {
				start_timer("ideograms_ticks_draw");
				draw_ticks(ideogram => $ideogram);
				stop_timer("ideograms_ticks_draw");
			}

			# ideogram highlights
			Circos::Track::Highlight::draw_highlights( \@highlight_tracks,
																								 $track_default->{highlights},
																								 $chr, 
																								 $ideogram->{set}, 
																								 $ideogram,
																								 {
																									ideogram => 1, layer_with_data => 0 } );

			# ideogram outline - stroke only, not filled
			if (seek_parameter("stroke_thickness",$datum,@param_path)) {
				slice(
							image       => $IM,
							start       => $start,
							end         => $end,
							chr         => $chr,
							radius_from => get_ideogram_radius($ideogram) -	$DIMS->{ideogram}{ $ideogram->{tag} }{thickness},
							radius_to   => get_ideogram_radius($ideogram),
							edgecolor   => seek_parameter("stroke_color",$datum,@param_path),
							edgestroke  => seek_parameter("stroke_thickness",$datum,@param_path),
							fillcolor   => undef,
						 );
			}
		}
    
    for my $ideogram (@IDEOGRAMS) {
			next unless show($ideogram);
			if ( $ideogram->{chr} eq $ideogram->{next}{chr} || 
					 $ideogram->{break}{start} || $ideogram->{break}{end} ) {
				if (@IDEOGRAMS > 1 || $ideogram->{display_idx} < $ideogram->{next}{display_idx}) {
					draw_axis_break($ideogram);
				}
			}
    }

    stop_timer("ideograms_draw");

    printsvg(qq{</g>}) if $SVG_MAKE;

    #Circos::Ideogram::report_chromosomes($KARYOTYPE);exit;

    ################################################################
    #
    # Process Links
    #
    # Links are stored just like any other data structure, like histograms, but have
    # two data elements.
    #
    # $data->{links}{param}              -> global link parameters from <links> block
    # $data->{links}{track}[i]           -> individual link track
    # $data->{links}{track}[i]{param}          parameters
    # $data->{links}{track}[i]                 list of links
    # $data->{links}{track}[i]{data}[0]           links start
    # $data->{links}{track}[i]{data}[1]           links end
    # $data->{links}{track}[i]{param}             link parameters

    # First, initialize the global links parameters from <links> block, and
    # then intialize each link track.
    $track_default->{links} = parse_parameters( fetch_conf("links"), "link" );

    my $link_names;
    my @t = Circos::Track::make_tracks( fetch_conf("links","link"), 
																				$track_default->{links},
																				"link");
    #printdumper(\@t);exit;
    my @link_tracks = map { parse_parameters($_, "link", 0) } @t;
    #printdumper(\@link_tracks);exit;
    @link_tracks    = grep(show($_,$track_default->{links}), @link_tracks);

    for my $track ( @link_tracks ) {

			# Path to search for parameters: first the <link> block, then <links> block.
			my @param_path = ( $track, $track_default->{links} );
			my $track_id   = $track->{id};
			#printdumper($track);exit;
			my $track_file = locate_file( file => seek_parameter("file",@param_path), name=>"link $track_id");
			
			printdebug_group("summary","process",$track->{id},"link",$track_file);
			
			$track->{__data} = Circos::IO::read_data_file($track_file,"link",
																										{ addset       => 1,
																											minsize      => seek_parameter( 'minsize', @param_path ),
																											file_rx      => seek_parameter( 'file_rx', @param_path ),
																											padding      => seek_parameter( 'padding', @param_path ),
																											record_limit => seek_parameter( 'record_limit', @param_path )
																										},
																										$KARYOTYPE,
																									 );

			# apply any rules to this set of links
			my @rules = Circos::Rule::make_rule_list( $track->{rules}{rule} );
			# pick out only those rules that are used
			@rules = grep( use_set($_,$track->{rules}), @rules );

			start_timer("datarules");
			Circos::Rule::apply_rules_to_track($track,\@rules,\@param_path) if @rules;
			stop_timer("datarules");

			$track->{__data} = [ grep( show($_), @{$track->{__data}} ) ];

			# z-depth for this track
			$track->{z} = seek_parameter("z",@param_path) || 0;
			# compute z values for each link
			for my $link ( @{$track->{__data}} ) {
				$link->{param}{z} = seek_parameter("z",$link) || 0;
			}
    }

    my $link_report_seen;

    for my $track ( sort { $a->{z} <=> $b->{z} }  @link_tracks ) {

			my @param_path = ( $track, $track_default->{links} );
			printsvg(qq{<g id="$track->{id}">}) if $SVG_MAKE;

			printdebug_group("summary","drawing","link",$track->{id},"z",$track->{z});

			my $track_data = $track->{__data};

			if (@$track_data > fetch_conf("max_links")) {
				fatal_error("links","max_number",int(@$track_data),$track->{file},fetch_conf("max_links"));
			}

		LINK:
			for my $link ( sort { $a->{param}{z} <=> $b->{param}{z} } @$track_data ) {
				my @param_path_link = ( $link, @param_path );

				# Check whether the link falls within its ideograms. If not, skip, trim or quit.
				# Also check whether position needs to be updated.
				for my $link_end ( @{ $link->{data} } ) {
					my $chr = $link_end->{chr};
					if ($link_end->{param}{_modpos}) {
						$link_end->{set} = Set::IntSpan->new(sprintf("%d-%d",$link_end->{start},$link_end->{end}));
					}
					# undef is returend if the link is completely beyond the ideogram, otherwise
					# a clipped set
					my $set_checked = check_data_range($link_end->{set},"link",$chr);
					next LINK if ! defined $set_checked;
					$link_end->{set} = $set_checked;
				}
				#printdumper($link);

				my $linkradius = unit_parse( seek_parameter( "radius", @param_path_link ) || 0) +
					unit_parse( seek_parameter( "offset", @param_path_link ) || 0);

				my @i_param_path_link = @param_path_link;
				my $perturb = seek_parameter( "perturb", @i_param_path_link );
				my $ideogram1 = get_ideogram_by_idx(get_ideogram_idx($link->{data}[0]{set}->min,
																														 $link->{data}[0]{chr}));
				my $ideogram2 = get_ideogram_by_idx(get_ideogram_idx($link->{data}[1]{set}->min,
																														 $link->{data}[1]{chr}));
	    
				my $radius1 = unit_parse( seek_parameter( "radius1|radius", @i_param_path_link ), $ideogram1 ) ;
				#	+	unit_parse( seek_parameter( "offset", @param_path_link ) || 0 , $ideogram1) ;
				my $radius2 = unit_parse( seek_parameter( "radius2|radius", @i_param_path_link ), $ideogram2 ) ;
				#+	unit_parse( seek_parameter( "offset", @param_path_link ) || 0 , $ideogram2) ;

				#printinfo(seek_parameter("radius1|radius",@i_param_path_link));
				#printinfo($radius1,$radius2);

				#printinfo(seek_parameter("bezier_radius", @i_param_path_link));
				#printdumper(@param_path);

				if ( seek_parameter( "ribbon", @i_param_path_link ) ) {

					my ( $start1, $end1 ) = (max($link->{data}[0]{set}->min,$ideogram1->{set}->min),
																	 min($link->{data}[0]{set}->max,$ideogram1->{set}->max));
					my ( $start2, $end2 ) = (max($link->{data}[1]{set}->min,$ideogram2->{set}->min),
																	 min($link->{data}[1]{set}->max,$ideogram2->{set}->max));
				
					if ( $link->{data}[0]{rev} ) {
						( $start1, $end1 ) = ( $end1, $start1 );
					}
					if ( $link->{data}[1]{rev} ) {
						( $start2, $end2 ) = ( $end2, $start2 );
					}

					my $force_flat  = seek_parameter("flat",$link, @param_path_link);
					my $force_twist = seek_parameter("twist",$link, @param_path_link);

					if ($force_flat || $force_twist) {
						my %list = (
												s1 => [$start1, getanglepos($start1, $link->{data}[0]{chr}) ],
												e1 => [$end1,   getanglepos($end1,   $link->{data}[0]{chr}) ],
												s2 => [$start2, getanglepos($start2, $link->{data}[1]{chr}) ],
												e2 => [$end2,   getanglepos($end2,   $link->{data}[1]{chr}) ],
											 );
						my @ends = sort { $list{$a}[1] <=> $list{$b}[1] } keys %list;
						my $ends = join( $EMPTY_STR, @ends );
						if ($force_flat) {
							if ( $ends =~ /s1e2|s2e1|e1s2|e2s1/ ) {
								( $start1, $end1, $start2, $end2 ) = ( $start1, $end1, $end2, $start2 );
							}
						} elsif ($force_twist) {
							if ( $ends !~ /s1e2|s2e1|e1s2|e2s1/ ) {
								( $start1, $end1, $start2, $end2 ) = ( $start1, $end1, $end2, $start2 );
							}
						}
					}

					my $url   = seek_parameter("url",@i_param_path_link);

					$url = format_url(url=>$url,
														param_path=>[@i_param_path_link,
																				 {
																					start1=>$start1,
																					start2=>$start2,
																					end1=>$end1,
																					end2=>$end2,
																					size1=>$end1-$start1,
																					size2=>$end2-$start2,
																					start=>round(($start1+$end1)/2),
																					end=>round(($start2+$end2)/2)
																				 }
																				]
													 );

					ribbon(mapoptions => { url  => $url},
								 svg        => { attr => seek_parameter_glob("^svg.*",qr/^svg/,@i_param_path_link)},
								 image      => $IM,
								 start1     => $start1,
								 end1       => $end1,
								 chr1       => $link->{data}[0]{chr},
								 start2     => $start2,
								 end2       => $end2,
								 chr2       => $link->{data}[1]{chr},
								 radius1    => $radius1,
								 radius2    => $radius2,
								 edgecolor  => seek_parameter("stroke_color", @i_param_path_link),
								 edgestroke => unit_strip(seek_parameter("stroke_thickness", @i_param_path_link)),
								 fillcolor  => seek_parameter( "color", @i_param_path_link ),
								 pattern    => seek_parameter( "pattern", @i_param_path_link ),
								 bezier_radius         => seek_parameter("bezier_radius", @i_param_path_link),
								 perturb_bezier_radius => seek_parameter("perturb_bezier_radius", @i_param_path_link),
								 bezier_radius_purity  => seek_parameter("bezier_radius_purity", @i_param_path_link),
								 perturb_bezier_radius_purity => seek_parameter("perturb_bezier_radius_purity"),
								 crest         => seek_parameter( "crest", @i_param_path_link ),
								 perturb       => $perturb,
								 perturb_crest => seek_parameter("perturb_crest", @i_param_path_link),
								);

				} elsif ( defined seek_parameter( "bezier_radius", @i_param_path_link ) ) {
					#printinfo(seek_parameter( "bezier_radius", @i_param_path_link));
					my @bezier_control_points = 
						bezier_control_points(
																	pos1 => get_set_middle($link->{data}[0]{set}),
																	chr1 => $link->{data}[0]{chr},
																	pos2 => get_set_middle($link->{data}[1]{set}),
																	chr2 => $link->{data}[1]{chr},
																	radius1 => $radius1,
																	radius2 => $radius2,
																	bezier_radius => seek_parameter("bezier_radius", @i_param_path_link),
																	perturb_bezier_radius => seek_parameter("perturb_bezier_radius", @i_param_path_link),
																	bezier_radius_purity => seek_parameter("bezier_radius_purity", @i_param_path_link),
																	perturb_bezier_radius_purity => seek_parameter("perturb_bezier_radius_purity",@i_param_path_link),
																	crest => seek_parameter( "crest", @i_param_path_link ),
																	perturb => $perturb,
																	perturb_crest => seek_parameter("perturb_crest", @i_param_path_link)
																 );

					my $num_bezier_control_points = @bezier_control_points;
					my @bezier_points = bezier_points(@bezier_control_points);

					printdebug_group("bezier", "beziercontrols",int(@bezier_control_points), @bezier_control_points );

					my $svg;
					my $svg_attr = seek_parameter_glob("^svg.*",qr/^svg/,@i_param_path_link);
					if ( $num_bezier_control_points == 10 && $SVG_MAKE ) {
						# bezier control points P0..P4
						# P0 - start
						# P1,P2,P3 - controls
						# P4 - end
						# 
						# intersection between line P0-P1 and
						# perpendicular from P2
						# 
						my ( $x1, $y1, $u1 ) = getu( @bezier_control_points[ 0 .. 5 ] );
						# 
						# intersection between line P3-P4 and
						# perpendicular from P2
						# 
						my ( $x2, $y2, $u2 ) = getu( @bezier_control_points[ 6 .. 9 ], @bezier_control_points[ 4, 5 ] );
						my @c1 = @bezier_control_points[ 2, 3 ];
						my @c2 = @bezier_control_points[ 4, 5 ];
						my @c3 = @bezier_control_points[ 6, 7 ];
						my $point_string = "%.1f,%.1f " x ( @bezier_points - 1 );
						$svg = sprintf(
													 qq{<path d="M %.1f,%.1f L $point_string " style="stroke-opacity: %f; stroke-width: %.1f; stroke: rgb(%d,%d,%d); fill: none" %s />},
													 ( map { @$_ } @bezier_points[ 0, 1 ] ),
													 ( map { @$_ } @bezier_points[ 2 .. @bezier_points - 1 ] ),
													 rgb_color_opacity(seek_parameter("color",@i_param_path_link)),
													 unit_strip(seek_parameter("thickness", @i_param_path_link),"p"),
													 rgb_color(seek_parameter("color", @i_param_path_link)),
													 attr_string($svg_attr),
													);
					} elsif ( $num_bezier_control_points == 8 && $SVG_MAKE ) {
						my $point_string = join( $SPACE, map { sprintf( "%.1f", $_ ) } @bezier_control_points[ 2 .. $num_bezier_control_points - 1 ] );
						$svg = sprintf(
													 qq{<path d="M %.1f,%.1f C %s" style="stroke-opacity: %f; stroke-width: %.1f; stroke: rgb(%d,%d,%d); fill: none" %s />},
													 @bezier_control_points[ 0, 1 ],
													 $point_string,
													 rgb_color_opacity(seek_parameter("color",@i_param_path_link)),
													 unit_strip(seek_parameter("thickness", @i_param_path_link),"p"),
													 rgb_color(seek_parameter("color", @i_param_path_link)),
													 attr_string($svg_attr),
													);
					} elsif ( $num_bezier_control_points == 6 && $SVG_MAKE ) {
						$svg = sprintf(
													 qq{<path d="M %.1f,%.1f Q %.1f,%.1f %.1f,%.1f" style="stroke-opacity: %f; stroke-width: %.1f; stroke: rgb(%d,%d,%d); fill: none" %s />},
													 @bezier_control_points,
													 rgb_color_opacity(seek_parameter("color",@i_param_path_link)),
													 unit_strip(seek_parameter("thickness", @i_param_path_link),"p"),
													 rgb_color(seek_parameter("color", @i_param_path_link)),
													 attr_string($svg_attr),
													);
					}
					if ($SVG_MAKE) {
						printsvg($svg);
					}
					if ($PNG_MAKE) {
						Circos::PNG::draw_bezier(points=>\@bezier_points, 
																		 thickness=>round(unit_strip(seek_parameter("thickness",@i_param_path_link),"p")), 
																		 color=>seek_parameter("color",@i_param_path_link ));
					}
				} else {
					#printinfo($radius1,$radius2);
					my ( $a1, $a2 ) = (getanglepos(get_set_middle($link->{data}[0]{set}),$link->{data}[0]{chr}),
														 getanglepos(get_set_middle($link->{data}[1]{set}),$link->{data}[1]{chr}));
					my ( $x1, $y1 ) = getxypos( $a1, $radius1); #linkradius );
					my ( $x2, $y2 ) = getxypos( $a2, $radius2); #linkradius );
					my $svg_attr = seek_parameter_glob("^svg.*",qr/^svg/,@i_param_path_link);
					draw_line( [ $x1, $y1, $x2, $y2 ],
										 seek_parameter( "thickness", @i_param_path_link ),
										 seek_parameter( "color",     @i_param_path_link ),
										 {
											attr=>$svg_attr },
									 );
				}
			}
			printsvg(qq{</g>}) if $SVG_MAKE;
    }

    $track_default->{plots} = parse_parameters( fetch_conf("plots"), "plot" );

    #my @plot_tracks = map { parse_parameters($_, "plot", 0) } Circos::Track::make_tracks( fetch_conf("plots","plot"),
    #$track_default->{plots} );

    my @plot_tracks = map { parse_parameters($_, "plot", 0) } Circos::Track::make_tracks_v2( fetch_conf("plots"),
																																														 $track_default->{plots} );
    # keep only those tracks which are shown
    @plot_tracks    = grep(show($_,$track_default->{plots}), @plot_tracks);

    for my $track ( @plot_tracks ) {
			
			my @param_path = ( $track, $track_default->{plots} );
			my $track_type = seek_parameter( "type", @param_path );
			if (! track_type_ok($track_type) && !$track->{axes} & !$track->{backgrounds}) {
				fatal_error("track","bad_type",$track_type,join(",",get_track_types()),Dumper($track));
			}
			my $track_id   = $track->{id};
			
			my $track_file = seek_parameter("file",@param_path);
			if (defined $track_file) {
				$track_file = locate_file( file => $track_file, name=>"$track_type track id $track_id");
				printdebug_group("summary","processing",$track_id,$track_type,$track_file);
				my $track_file_param = { record_limit     => seek_parameter( "record_limit", @param_path ),
																 minsize          => seek_parameter( "minsize", @param_path ),
																 file_rx          => seek_parameter( "file_rx", @param_path ),
																 padding          => seek_parameter( "padding", @param_path ),
																 skip_run         => seek_parameter( "skip_run", @param_path ),
																 min_value_change => seek_parameter( "min_value_change", @param_path ),
															 };
				if ($track_type eq "histogram") {
					$track_file_param->{param}{fill_color} = seek_parameter( "fill_color", @param_path );
					$track_file_param->{param}{pattern}    = seek_parameter( "pattern", @param_path );
					$track_file_param->{param}{thickness}  = seek_parameter( "thickness", @param_path );
					$track_file_param->{param}{color}      = seek_parameter( "color", @param_path );
					$track_file_param->{sort_bin_values}   = seek_parameter( "sort_bin_values", @param_path ),
					$track_file_param->{normalize_bin_values}   = seek_parameter( "normalize_bin_values", @param_path ),
					$track_file_param->{bin_values_num}    = seek_parameter( "bin_values_num", @param_path ),
				}
				$track->{__data} = Circos::IO::read_data_file($track_file, $track_type, $track_file_param,$KARYOTYPE);
			} else {
				$track->{__data} = undef;
			}
			
			if ( defined seek_parameter("type",@param_path) && 
					 seek_parameter("type",@param_path) =~ /scatter|text|line|histogram|heatmap/ && 
					 fetch_conf("calculate_track_statistics")) {
				Circos::Track::calculate_track_statistics($track);
			}

			my @rules = Circos::Rule::make_rule_list( $track->{rules}{rule} );

			# pick out only those rules that are used
			@rules = grep( use_set($_,$track->{rules}), @rules );

			if ($track->{__data}) {
				start_timer("datarules");
				Circos::Rule::apply_rules_to_track($track,\@rules,\@param_path) if @rules;
				stop_timer("datarules");
				$track->{__data} = [ grep( show($_), @{$track->{__data}} ) ];
				# register this ideogram with the track
				for my $datum (@{$track->{__data}}) {
					for my $data_point (@{$datum->{data}}) {
						my $i = get_ideogram_idx($data_point->{start},$data_point->{chr});
						$track->{ideogram}{$i}++ if defined $i;
					}
				}
			}
	
			$track->{z} = seek_parameter("z",@param_path) || 0;

			# compute z values for each data point
			if ($track->{__data}) {
				for my $datum ( @{$track->{__data}} ) {
					$datum->{param}{z} = seek_parameter("z",$datum) || 0;
				}
			}
		}
		
    my $plotid = 0;
		
    for my $track ( sort {$a->{z} <=> $b->{z}} @plot_tracks ) {
			
			start_timer("track_preprocess");
			my @param_path = ( $track, $track_default->{plots} );
			my $this_track_z = seek_parameter("z",@param_path) || 0;
			
			printsvg(qq{<g id="plot$plotid">}) if $SVG_MAKE;

			my $track_data = $track->{__data};
			my $track_type = seek_parameter( "type", @param_path );

			# global properties of the plot
			my $orientation           = seek_parameter( "orientation", @param_path );
			my $orientation_direction = match_string($orientation,"in") ? -1 : 1;
	
			my $plot;
			my ($r0,$r1);
			if(seek_parameter("inside_ideogram",@param_path)) {
				$r0 = round(unit_parse("dims(ideogram,radius_inner)"));
				$r1 = round(unit_parse("dims(ideogram,radius_outer)"));
				$track->{r0} = $r0;
				$track->{r1} = $r1;
			} else {
				$r0 = round(unit_parse( seek_parameter( "r0", @param_path ) ));
				$r1 = round(unit_parse( seek_parameter( "r1", @param_path ) ));				
			}
			printdebug_group("summary",
											 "drawing",$track->{id},$track_type,
											 "z",$track->{z},
											 $track->{file} ? basename($track->{file}) : "no_file",
											 defined $orientation ? "orient $orientation" : "");
	
			my ( @tilelayers, $margin );
			if ( defined $track_type && $track_type eq "tile" ) {
				# the margin must be in bases
				$margin = seek_parameter( "margin", @param_path );
				unit_validate( $margin, "margin", qw(u b) );
				$margin    = unit_convert( from => $margin, to => "b" ) ; #, factors => { ub => $CONF{chromosomes_units} } ) ;
				my $layers = seek_parameter("layers",@param_path);
				for my $ideogram (@IDEOGRAMS) {
					my $idx = $ideogram->{idx};
					$tilelayers[$idx] =	[ map { { set => Set::IntSpan->new(), idx => $_ } } ( 0..$layers-1 ) ];
				}
			}

			my $plot_min = seek_parameter( "min", @param_path );
			my $plot_max = seek_parameter( "max", @param_path );

			if ($track_data && @$track_data > fetch_conf("max_points_per_track")) {
				fatal_error("track","max_number",int(@$track_data),$track_type,$track->{file},fetch_conf("max_points_per_track"));
			}

			# get some statistics for certain plot types, so that we
			# can set default if parameters are not defined
			if (( defined $track_type && $track_type =~ /scatter|text|tile|line|histogram|heatmap/ ) 
					&& 
					( !defined $plot_min || !defined $plot_max || fetch_conf("calculate_track_statistics")) ) {
				my @values;
				for my $datum ( @$track_data ) {
					next unless show($datum);
					my $value = $datum->{data}[0]{value};
					if (defined $value && $value =~ /^$RE{num}{real}$/) {
						$value =~ s/[,_]//g;
						push @values, $value;
					}
				}
				if (@values) {
					my $min   = min(@values);
					my $max   = max(@values);
					$plot_min = ($min||0) if ! defined $plot_min;
					$plot_max = ($max||0) if ! defined $plot_max;
					my $track_stats;
					$track_stats->{min} = $plot_min;
					$track_stats->{max} = $plot_max;
					$track_stats->{average} = average(@values);
					$track_stats->{avg} = $track_stats->{mean} = $track_stats->{average};
					$track_stats->{stddev} = stddev(@values);
					$track_stats->{var} = $track_stats->{stddev}**2;
					$track_stats->{n} = @values;
					$track->{__stats} = $track_stats;
					printdebug_group("layer","track $track_type $track->{id} auto min/max",$plot_min,$plot_max);
				}
			}

			if ( defined $plot_max && defined $plot_min && $plot_max < $plot_min ) {
				fatal_error("track","min_larger_than_max",$plot_min,$plot_max);
			}

			stop_timer("track_preprocess");

			################################################################
			# create a color and/or pattern legend for heatmaps
			my $legend;
			if ( defined $track_type && $track_type =~ /heatmap|scatter|tile/) {
				my $color_mapping            = seek_parameter("color_mapping",@param_path) || 0;
				my $color_mapping_boundaries = seek_parameter("color_mapping_boundaries",@param_path);
				my @colors                   = color_to_list( seek_parameter("color", @param_path));
				my $base = seek_parameter( "scale_log_base", @param_path);
				confess "The scale_log_base parameter [$base] for a heat map cannot be zero or negative. Please change it to a non-zero positive value or remove it." if defined $base && $base <= 0;
				$legend->{color}  = Circos::Heatmap::encode_mapping($plot_min,$plot_max,\@colors,$color_mapping,$base,$color_mapping_boundaries);
				if ( my $patterns = seek_parameter("pattern", @param_path)) {
					my $pattern_mapping = first_defined(seek_parameter("pattern_mapping",@param_path),$color_mapping,0);
					my @patterns = split(",",$patterns);
					$legend->{pattern} = Circos::Heatmap::encode_mapping($plot_min,$plot_max,\@patterns,$pattern_mapping,$base);
				}
				report_mapping($legend->{color},$track->{id});
				report_mapping($legend->{pattern},$track->{id});
			}
	
			if ( defined $track_type && $track_type =~ /text/ ) {
				start_timer("track_text_place");
				# 
				# number of discrete steps in a degree
				#
				# at r1, number of pixels per degree is
				# 
				#   2 * r1 * pi / 360 
				#
				# the resolution is given as
				#
				#   pixel_sub_sampling * pixels_in_degree
				# 
				# subsampling should be at least 2
				# 
				my $pixel_sub_sampling = $CONF{text_pixel_subsampling} || 2;
				my $pixels_in_degree   = $r1 * $TWOPI / 360;
				my $angular_resolution = seek_parameter( "resolution", @param_path ) || $pixel_sub_sampling * $pixels_in_degree;

				# label link dimensions - key
				#
				#      00112223344 (link dims)
				# LABEL  --\
				#           \
				#            \--  LABEL
				#
				#
				# assign immutable label properties
				# - pixel width, height
				# - original angular position
				# - angular width at base
				#
				# also tally up the number of labels for an angular bin

				printdebug_group("summary","placing text track",seek_parameter("file",@param_path));
				printdebug_group("summary","... see progress with -debug_group text");
				printdebug_group("summary","... see placement summary with -debug_group textplace");

				for my $datum ( @$track_data ) {
					start_timer("track_text_preprocess");
					next unless show($datum,@param_path);
					my $data_point = $datum->{data}[0];
					my $font_role  = "text track";
					my $font_key   = seek_parameter( "label_font", $datum, @param_path ) || fetch_conf("default_font") || "default";
					my $font_def   = get_font_def_from_key($font_key,"text track");
					my $font_file  = get_font_file_from_key($font_key,"text track");

					$data_point->{size} = unit_strip( unit_validate( seek_parameter( "label_size", $datum, @param_path ),
																													 "plots/plot/label_size",
																													 qw(p n)
																												 ));
		
					my ( $label_width, $label_height ) = get_label_size( font_file => $font_file,
																															 size      => $data_point->{size},
																															 text      => $data_point->{value} );
		
					# w0 h0 - width and height of label (irrespective of rotation)
					# w  h  - width at base (parallel to circle) of label and height (radial)
					# dimr  - size along radial direction (perpendicular to ideogram)
					# dima  - size along angular direction (parallel to ideogram)
					@{$data_point}{qw(w0 h0)}     = ( $label_width, $label_height );
					@{$data_point}{qw(w h)}       = ( $label_width, $label_height );
					@{$data_point}{qw(dimr dima)} = ( $label_width, $label_height );
					if (0 && defined_and_zero( seek_parameter( "label_rotate", $datum, @param_path ) )
							||
							seek_parameter("label_tangential", $datum, @param_path)) {
						# label is parallel to ideogram
						@{$data_point}{qw(w h)}       = @{$data_point}{qw(h0 w0)};
						@{$data_point}{qw(dimr dima)} = @{$data_point}{qw(h0 w0)};
						$data_point->{tangential}     = 1;
						$data_point->{parallel}       = 1;
						$data_point->{radial}         = 0;
						$data_point->{rotated}        = 0;
						#($label_width,$label_height) = ($label_height,$label_width);
					} elsif (0) { 
						# label is radial
						@{$data_point}{qw(w h)}       = @{$data_point}{qw(w0 h0)};
						@{$data_point}{qw(dimr dima)} = @{$data_point}{qw(w0 h0)};
						$data_point->{tangential}     = 0;
						$data_point->{parallel}       = 0;
						$data_point->{radial}         = 1;
						$data_point->{rotated}        = 1;
					}
		
					# radial padding is along radial direction - can
					# be absolute (p) or relative (r, to label width)
					#
					# computing padding here because it depends on the
					# label size
					$data_point->{rpadding} = unit_convert(
																								 from    => unit_validate( seek_parameter( "rpadding", $datum, @param_path ), "plots/plot/rpadding", qw(r p) ),
																								 to      => "p",
																								 factors => { rp => $data_point->{dimr} }
																								);

					if ( seek_parameter( "show_links", @param_path ) ) {
						my @link_dims = split( /[, ]+/, seek_parameter( "link_dims", @param_path ) );
						@link_dims = map { unit_convert(
																						from    => unit_validate( $_, "plots/plot/link_dims", qw(r p) ),
																						to      => "p",
																						factors => { rp => $data_point->{dimr} }
																					 ) } @link_dims;
						my $link_orientation = seek_parameter( "link_orientation", @param_path ) || "in";
						if ($link_orientation eq "out") {
							$data_point->{rpadding} -= sum(@link_dims);
						} else {
							$data_point->{rpadding} += sum(@link_dims);
							#printinfo(sum(@link_dims));
						}
					}
		
					# original angular position, radius
					# - inner layer radius includes padding for link lines
					my $angle  = getanglepos( ( $data_point->{start} + $data_point->{end} ) / 2, $data_point->{chr} );
		
					# radius, uncorrected for ideogram radial position
					my $radius = $r0;

					# correct radius to ideogram radial position 0.63-2
					my $ideogram_idx = get_ideogram_idx( $data_point->{start}, $data_point->{chr} );
					my $ideogram     = get_ideogram_by_idx($ideogram_idx);

					$radius = unit_parse( seek_parameter( "r0", $datum, @param_path ), $ideogram );
					#$r0 = unit_parse( seek_parameter( "r0", @param_path ), $ideogram );
					#$r1 = unit_parse( seek_parameter( "r1", @param_path ), $ideogram );

					@{$data_point}{qw(angle radius)} = ( $angle, $radius );
		
					# angular height, compensated for height
					# reduction, at the start (inner) and end (outer)
					# of the label; ah_outer < ah_inner because radius
					# of the former is larger

					$data_point->{ah_inner} = $RAD2DEG * $data_point->{dima} / $data_point->{radius};
					$data_point->{ah_outer} = $RAD2DEG * $data_point->{dima} / ( $data_point->{radius} + $data_point->{dimr} );
		
					# angular height set, in units of 1/angular_resolution, at the foot (inner) and
					# top (outer) of the label
		
					for my $x (qw(inner outer)) {
						$data_point->{"aset_$x"} = span_from_pair(
																											map { angle_to_span( $_, $angular_resolution ) } (
																																																				$data_point->{angle} - $data_point->{"ah_$x"} / 2,
																																																				$data_point->{angle} + $data_point->{"ah_$x"} / 2
																																																			 ));
					}
		
					if (debug_or_group("text")) {
						0&&printdebug_group("text", "label",
																sprintf( "label %s size %.1f w0 %d h0 %d dima %d dimr %d rp %.1f a %.2f r %d ah %.3f %.3f aseti %.2f %.2f aseto %.2f %.2f",
																				 @{$data_point}{
																					 qw(label size w0 h0 dima dimr rpadding angle radius ah_inner ah_outer)
																				 },
																				 (
																					map { $_ / $angular_resolution } (
																																						$data_point->{aset_inner}->min,
																																						$data_point->{aset_inner}->max
																																					 )
																				 ),
																				 (
																					map { $_ / $angular_resolution } (
																																						$data_point->{aset_outer}->min,
																																						$data_point->{aset_outer}->max
																																					 )
																				 )
																			 ));
					}
					stop_timer("track_text_preprocess");
				}												# each label
	    
				my $label_not_placed = 0;
				my $label_placed     = 0;
				my $all_label_placed = 0;
				my %all_label_placed_iters;
	    
				#
				# keep track of height values for each angular
				# position (sampled at $resolution)
				#

				if (seek_parameter( "snuggle_link_overlap_test|snuggle_refine", @param_path)) {
					$CONF{text_snuggle_method} = "span";
				} elsif (! defined $CONF{text_snuggle_method}) {
					$CONF{text_snuggle_method} = "array";
				}

				my @stackheight  = map { Set::IntSpan->new() } ( 0 .. 2 * $DEGRANGE * $angular_resolution );
				my @stackheight2 = map { 0 } ( 0 .. 2 * $DEGRANGE * $angular_resolution );

				#
				# angular coverage of previous labels to avoid placing
				# new labels which overlap
				#
				my $layer = 0;
				#
				# On the first iteration (seek_min_height=1), this is
				# the variable that holds the lowest maxheight found.
				# On subsequent iteration, labels that are near this
				# height are placed.
				#
				my $seek_min_height   = 1;
				my $global_min_height = 0;

				# Sort labels by size then angular position
				my @label_data = sort { ($a->{data}[0]{angle}||0) <=> ($b->{data}[0]{angle}||0) } @$track_data;

				#(
				#substr( $b->{data}[0]{param}{label_size}, 0, -1 ) <=>
				#substr( $a->{data}[0]{param}{label_size}, 0, -1 ) )
				#	  || 

				my $array_deg_offset = 45; # to avoid mapping deg=0 to start of array and having to look at end of array

				do {
					$label_placed = 0;
	      TEXTDATUM:
					for my $datum (@label_data) {
						start_timer("track_text_preashift");
						next if is_hidden($datum, @param_path);
						my $data_point = $datum->{data}[0];
						#
						# don't process this point if it has already
						# been assigned to a layer
						#
						next if defined $data_point->{layer};
						if ( $data_point->{skip} ) {
							delete $data_point->{skip};
							next TEXTDATUM;
						}

						# text snuggling parameters: maximum snuggle distance and sampling
						my $sd_max = seek_parameter("max_snuggle_distance", @param_path) || "1r";
						$sd_max    = unit_convert(from => unit_validate($sd_max,"plots/plot/max_snuggle_distance",qw(n r p)),
																			to      => "p",
																			factors => { rp => $data_point->{dima} }
																		 ) if defined $sd_max;
						my $ss     = seek_parameter("snuggle_sampling", @param_path) || "1";
						$ss = unit_convert(from => unit_validate($ss,"plots/plot/snuggle_sampling",qw(n r p)),
															 to      => "p",
															 factors => { rp => $data_point->{dima} }
															) if defined $ss;

						# determine maximum height of labels in this labels' angular span
						my @range;
						if ( ! seek_parameter( "label_snuggle", @param_path ) ) {
							@range = (0);
						} else {
							my $range_center = 0; 
							@range = sort { abs( $a - $range_center ) <=>  abs( $b - $range_center ) }
								map { round( $range_center - $_ * $ss, $range_center + $_ * $ss )} ( 0 .. $sd_max / $ss );
							@range = (0) if !@range;
						}
						my ( $aset_inner_best, $label_min_height, $angle_new, $pix_shift_best );
						stop_timer("track_text_preashift");
						my $shift_iterations = 1;
						start_timer("track_text_ashift");
						my $angle_new_mult = $RAD2DEG / $data_point->{radius};
					ASHIFT:
						for my $pix_shift (@range) {
							start_timer("track_text_ashiftiter");
							my $angle_new = $data_point->{angle} + $angle_new_mult * $pix_shift; #$RAD2DEG*$pix_shift / $data_point->{radius};
							my ($label_curr_height,$ah_inner);
							for my $iter ( 1 .. $shift_iterations ) {
								my $a  = $angle_new + $array_deg_offset - $CONF{image}{angle_offset};
								my $ar = int( $a * $angular_resolution);
								my $h;
								if (defined $label_curr_height) {
									$h = $label_curr_height;
								} elsif ( $CONF{text_snuggle_method} eq "array" && defined $stackheight2[ $ar ]) {
									$h = $stackheight2[ $ar ];
								} elsif ( $CONF{text_snuggle_method} eq "span" && $stackheight[ $ar ]->cardinality ) {
									$h = $stackheight[ $ar  ]->max;
								} else {
									$h = 0;
								}
								$ah_inner  = $RAD2DEG * $data_point->{dima} / ( $data_point->{radius} + $h );
								my $ashift = $ah_inner/2;
								my $a1 = $a - $ashift; 
								my $a2 = $a + $ashift; 
								#my @elems = ( round_custom($a1*$angular_resolution,"round")..round_custom($a2*$angular_resolution,"round") );
								# int is faster than round
								# use round_custom from Utils.pm to provide different rounding options (int,round,floor,ceil)
								my @elems = ( int($a1*$angular_resolution) .. int($a2*$angular_resolution) );
								if ($CONF{text_snuggle_method} eq "array") {
									$label_curr_height = max( @stackheight2[@elems] );
								} else {
									$label_curr_height = max( map { $_ ? $_->max : 0 } @stackheight[@elems] ) || 0;
								}
								$ah_inner = $RAD2DEG * $data_point->{dima} / ( $data_point->{radius} + $label_curr_height );	
							}
							stop_timer("track_text_ashiftiter");
							# label would stick past r1 - try next pixel shift
							if ( $data_point->{radius} + $label_curr_height + $data_point->{dimr} > $r1 ) {
								next ASHIFT;
							}
			
							my $d    = ($label_curr_height||0) - ($global_min_height||0);
							my $flag = $DASH;
							my $pass = 0;
			
							if ( !$seek_min_height ) {
								my $tol = 0;
								if ( seek_parameter( "snuggle_tolerance", @param_path )) {
									$tol = unit_convert(
																			from => unit_validate(seek_parameter("snuggle_tolerance", @param_path),
																														"plots/plot/snuggle_tolerance",
																														qw(n r p)
																													 ),
																			to      => "p",
																			factors => { rp => $data_point->{dimr} }
																		 );
								}
								if ( !defined $label_min_height ) {
									$pass = 1 if $d <= $tol;
								} else {
									if ( $d < 0 ) {
										#$pass = 1;
										;						# change condition here? - ky
									} elsif ( $d <= $tol ) {
										$pass = 1
											if abs($pix_shift) <
												abs($pix_shift_best);
									}
								}
							} else {
								# we're looking for the min height for this label
								if ( ! defined $label_min_height || $label_curr_height < $label_min_height) {
									$pass = 1;
								}
							}
			
							if ($pass) {
								$label_min_height = $label_curr_height;
								$data_point->{label_min_height} = $label_min_height;
			    
								$flag = $PLUS_SIGN;
			    
								if ( !$seek_min_height ) {
									$data_point->{angle_new} = $angle_new;
									$aset_inner_best = span_from_pair(
																										map { angle_to_span( $_,$angular_resolution ) } (
																																																		 $angle_new - $ah_inner / 2,
																																																		 $angle_new + $ah_inner / 2
																																																		));
									$pix_shift_best = $pix_shift;
									$flag           = "*";
								}
							}
			
							if (debug_or_group("text")) {
								printdebug_group("text",
																 "label",
																 "layer",
																 $layer,
																 "snuggle",
																 $seek_min_height ? "seek" : "mtch",
																 $flag,
																 $data_point->{value},
																 sprintf( "%.1f", $pix_shift ),
																 "d",
																 $d,
																 "label_min_height",
																 $label_min_height,
																 "global_min_height",
																 $global_min_height
																);
							}
						}										# ASHIFT
						stop_timer("track_text_ashift");
						stop_timer("track_text_preashift");
		    
						# store the lowest maxheight seen
						if ($seek_min_height) {
							my $d = ($label_min_height||0) - ($global_min_height||0);
							if ( ! defined $global_min_height || $d < 0 ) {
								$global_min_height = $label_min_height;
							} elsif ( $d > 0 ) {
								$data_point->{skip} = 1;
							}
							next TEXTDATUM;
						} else {
							# this label was not placed on this iteration - go to next label
							next TEXTDATUM if ! defined $data_point->{angle_new};
						}

						# if we got this far, at least one label was placed,
						# therefore reset the unplaced counter
						$label_not_placed = 0;
						# make sure that the label's link does not
						# interfere with previously placed labels
						if (! $seek_min_height 
								&& 
								seek_parameter("show_links",@param_path)
								&& 
								seek_parameter( "snuggle_link_overlap_test", @param_path ) ) {
							start_timer("track_text_snuggle_overlap");
							my ( $angle_from, $angle_to ) = sort { $a <=> $b } @{$data_point}{qw(angle angle_new)};
							my $r = $data_point->{radius} + $label_min_height;
							my $linkset = Set::IntSpan->new(sprintf( "%d-%d",$label_min_height,
																											 $label_min_height + $data_point->{rpadding} ));
							my $tol = 0;
							if (seek_parameter("snuggle_link_overlap_tolerance",@param_path)) {
								$tol = unit_convert(from => unit_validate(seek_parameter("snuggle_link_overlap_tolerance",@param_path),
																													"plots/plot/snuggle_link_overlap_tolerance",
																													qw(r p n)),
																		to      => "p",
																		factors => { rp => $data_point->{dimr} }
																	 );
							}
							my $j = 0;
							for my $i (int( ( $angle_from + $array_deg_offset - $CONF{image}{angle_offset} ) * $angular_resolution )
												 ...
												 int( ( $angle_to   + $array_deg_offset -	$CONF{image}{angle_offset} ) * $angular_resolution )
												) {
								# $ss - snuggle_sampling converted to absolute units
								next if seek_parameter( "snuggle_sampling", @param_path )	and	$j++ % round($ss);
								my $collision = $stackheight[$i]->intersect($linkset)->cardinality - 1;
								if ( $collision > $tol ) {
									delete $data_point->{angle_new};
									$data_point->{skip} = 1;
									next TEXTDATUM;
								}
							}
							stop_timer("track_text_snuggle_overlap");
						}										# snuggle overlap test

						my $a_padding = unit_convert(from    => unit_validate( seek_parameter( "padding", $datum, @param_path ),
																																	 "plots/plot/padding",
																																	 qw(r p) ),
																				 to      => "p",
																				 factors => { rp => $data_point->{dima} }
																				);
						my $padding = $angular_resolution * $RAD2DEG * $a_padding / ( $label_min_height + $data_point->{radius} );
						my $aset_padded = $aset_inner_best->trim( -$padding );
						$data_point->{radius_shift} = $label_min_height;
						printdebug_group("test",
														 "label",
														 "layer", $layer, $PLUS_SIGN,
														 $data_point->{value},
														 "mh",
														 $label_min_height,
														 "a",
														 sprintf( "%.3f", $data_point->{angle} ),
														 "an",
														 sprintf( "%.3f", $data_point->{angle_new} ),
														 "as",
														 sprintf( "%.3f",
																			$data_point->{angle_new} -
																			$data_point->{angle} ),
														 "rs",
														 $data_point->{radius_shift}
														);

						$data_point->{layer} = $layer;
						$label_placed++;
						$all_label_placed++;

						my $ah_outer =
							$RAD2DEG * $data_point->{dima} /
								( $data_point->{radius} +
									$data_point->{radius_shift} +
									$data_point->{dimr} );

						my $ah_set_outer = span_from_pair(
																							map { angle_to_span( $_, $angular_resolution ) } (
																																																$data_point->{angle_new} - $ah_outer / 2,
																																																$data_point->{angle_new} + $ah_outer / 2
																																															 )
																						 );

						$ah_set_outer = $ah_set_outer->trim( -$padding );

						printdebug_group("text",
														 "label",
														 "positioned",
														 $data_point->{value},
														 $data_point->{radius} + $data_point->{radius_shift},
														 $data_point->{radius} + $data_point->{radius_shift} + $data_point->{dimr} + $data_point->{rpadding}
														);

						for my $a ( $ah_set_outer->elements ) {
							my $height =
								$data_point->{radius_shift} +
									$data_point->{dimr} +
										$data_point->{rpadding};

							my $i = $a + $array_deg_offset * $angular_resolution;

							my $stack_low  = $data_point->{radius_shift} + $data_point->{rpadding};
							my $stack_high = $data_point->{radius_shift} + $data_point->{rpadding} + $data_point->{dimr};		      
							if ($CONF{text_snuggle_method} eq "array") {
								$stackheight2[$i] = scalar max($stackheight2[$i],$stack_low,$stack_high);
							} else {
								$stackheight[$i]->U( Set::IntSpan->new( sprintf( "%d-%d", $stack_low,$stack_high)));
							}
						}
					}											# TEXTDATUM

					stop_timer("track_text_preashift");

					printdebug_group("text",
													 "label",   "iterationsummary", 
													 "seekmin", $seek_min_height,   
													 "global_min_height", $global_min_height, 
													 "positioned",  $label_placed,      
													 "all",     $all_label_placed
													);

					# refine angular position within this layer for adjacent labels
					start_timer("track_text_refine");
	      REFINE:
					my $data_point_prev;
					my $refined = 0;
					for my $datum (@label_data) {
						last unless seek_parameter( "snuggle_refine", @param_path );
						next if is_hidden($datum, @param_path );
						my $data_point = $datum->{data}[0];
						next unless defined $data_point->{layer} && $data_point->{layer} == $layer;
						if ($data_point_prev) {
							if ($data_point->{angle_new} < $data_point_prev->{angle_new}
									&& 
									abs($data_point->{radius_shift} - $data_point_prev->{radius_shift}) < 15
								 ) {
								$refined = 1;
								($data_point->{angle_new},$data_point_prev->{angle_new}) = ($data_point_prev->{angle_new},$data_point->{angle_new});
								printdebug_group("text",
																 "label",
																 "refined",
																 $data_point->{value},
																 $data_point->{angle_new},
																 $data_point_prev->{value},
																 $data_point_prev->{angle_new}
																);
			    
								for my $dp ( $data_point, $data_point_prev ) {
									my $ah_outer     = $RAD2DEG *	$dp->{dima} / ( $dp->{radius} +	$dp->{radius_shift} +	$data_point->{dimr} );
									my $ah_set_outer = span_from_pair( map {	angle_to_span( $_, $angular_resolution ) } 
																										 ($dp->{angle_new} - $ah_outer / 2,
																											$dp->{angle_new} + $ah_outer / 2)
																									 );
									my $a_padding = unit_convert( from => unit_validate( seek_parameter( "padding", $datum, @param_path ),
																																			 "plots/plot/padding",
																																			 qw(r p)),
																								to      => "p",
																								factors => { rp => $dp->{dima} }
																							);
									my $padding   = $angular_resolution *	$RAD2DEG * $a_padding /	( $dp->{radius} +	$dp->{radius_shift} );
									$ah_set_outer = $ah_set_outer->trim( -$padding );
									for my $a ( $ah_set_outer->elements ) {
										my $height = $dp->{radius_shift} + $dp->{dimr} + $dp->{rpadding};
										my $i = $a + $array_deg_offset * $angular_resolution;
										$stackheight[$i]->U(Set::IntSpan->new(sprintf( "%d-%d",
																																	 $dp->{radius_shift} + $dp->{rpadding},
																																	 $dp->{radius_shift} + $dp->{dimr} + $dp->{rpadding} )
																												 ));
									}
								}
								last;
							}
						}
						$data_point_prev = $data_point;
					}
					# keep refining this layer, until no refinements are left to make
					goto REFINE if $refined;
					stop_timer("track_text_refine");

					if ($seek_min_height) {
						$seek_min_height = 0;
						printdebug_group("text", "label", "toggle seek_min_height", $seek_min_height,0 );
					} else {
						$seek_min_height = 1;
						if ( !$label_placed ) {
							printdebug_group("text", "label", "toggle seek_min_height", $seek_min_height,1 );
							$label_not_placed++;
							$layer++;
							$global_min_height = undef;
						} else {
							printdebug_group("text", "label", "toggle seek_min_height", $seek_min_height,2 );
							$label_not_placed = 0;
						}
						if ( seek_parameter( "layers", @param_path )
								 && $layer >=
								 seek_parameter( "layers", @param_path ) ) {
							printdebug_group("text", "label", "toggle seek_min_height", $seek_min_height,3 );
							$label_placed     = 0;
							$label_not_placed = 2;
						}
		    
						if ( $all_label_placed_iters{$all_label_placed}++ > 20 ) {
							printdebug_group("text", "label", "toggle seek_min_height", $seek_min_height,4 );
							$label_placed     = 0;
							$label_not_placed = 2;
						}
					}
					printdebug_group("text",
													 "label",  
													 "loopsummary",      
													 "seekmin",              $seek_min_height,   
													 "global_min_height",    $global_min_height, 
													 "label_positioned",     $label_placed,      
													 "label_not_positioned", $label_not_placed,  
													 "all",                  $all_label_placed );
				} while ( $label_placed || $label_not_placed < 2 ); # TEXT LOOP
				stop_timer("track_text_place");
			}

			# last point plotted, by chr
			my $prevpoint;

			printsvg(qq{<g id="plot$plotid-axis">}) if $SVG_MAKE;

			my $axis_defaults = {type=>"axis"};
			Circos::Track::assign_defaults([$axis_defaults],{});

			for my $ideogram (@IDEOGRAMS) { # @ideograms_with_data) {

				$r0 = unit_parse( seek_parameter( "r0", @param_path ), $ideogram );
				$r1 = unit_parse( seek_parameter( "r1", @param_path ), $ideogram );

				my ( $start, $end ) = ( $ideogram->{set}->min, $ideogram->{set}->max );
			
				# added at cupcake corner in Krakow :)
				if (my $bg = seek_parameter("backgrounds",@param_path)) {
				
					my @bg_param_path = ($bg);
				
					if (match_string(seek_parameter("show",@bg_param_path),"data")) {
						next unless defined $track->{ideogram}{ $ideogram->{idx} };
					}
				
					my ($bound_min,$bound_max) = defined $plot_min && defined $plot_max ? ($plot_min,$plot_max) : ($r0,$r1);
					my $divisions   = Circos::Division::make_ranges($bg->{background},
																													\@bg_param_path,
																													$bound_min,
																													$bound_max);
					#$plot_min,
					#$plot_max);
				
					for my $division (@$divisions) {
						my $stroke_color     = seek_parameter( "stroke_color",     $division->{block},@bg_param_path );
						my $stroke_thickness = seek_parameter( "stroke_thickness", $division->{block},@bg_param_path );
						my $color            = seek_parameter( "color",            $division->{block},@bg_param_path );
					
						my ($radius1,$radius2);					
						if (defined $division->{y0} && defined $division->{y1}) {
							my $radius1f   = $bound_max - $bound_min ? ($division->{y0}-$bound_min)/($bound_max-$bound_min) : $bound_min;
							my $radius2f   = $bound_max - $bound_min ? ($division->{y1}-$bound_min)/($bound_max-$bound_min) : $bound_min;
							if ($orientation_direction == 1) {
								$radius1    = $r0 + ($r1-$r0)*$radius1f;
								$radius2    = $r0 + ($r1-$r0)*$radius2f;
							} else {
								$radius1    = $r1 - ($r1-$r0)*$radius1f;
								$radius2    = $r1 - ($r1-$r0)*$radius2f;
							}
						} else {
							$radius1 = $r0;
							$radius2 = $r1;
						}
						printdebug_group("background",$ideogram->{chr},$radius1,$radius2,$color);
						slice(
									image       => $IM,
									start       => $ideogram->{set}->min,
									end         => $ideogram->{set}->max,
									chr         => $ideogram->{chr},
									radius_from => $radius1,
									radius_to   => $radius2,
									fillcolor   => $color,
									edgecolor   => $stroke_color,
									edgestroke  => $stroke_thickness,
									mapoptions  => {
																	object_type   => "trackbg",
																	object_label  => $track_type,
																	object_parent => $ideogram->{chr},
																	object_data   => {
																										start => $ideogram->{set}->min,
																										end   => $ideogram->{set}->max,
																									 },
																 },
								 );
					}
				}
			
				# added on flight to Warsaw :)
				if (my $axes = seek_parameter("axes",@param_path)) {
				
					my @axis_param_path = ($axes,$axis_defaults);
				
					if (match_string(seek_parameter("show",@axis_param_path),"data")) {
						next unless defined $track->{ideogram}{ $ideogram->{idx} };
					}

					push @axis_param_path, $axis_defaults;

					my $divisions       = Circos::Division::make_divisions($axes->{axis},
																																 \@axis_param_path,
																																 $plot_min,
																																 $plot_max,
																																 $r0,
																																 $r1,
																																);
					for my $division (@$divisions) {
						my $color     = seek_parameter( "color",     $division->{block},@axis_param_path );
						my $thickness = seek_parameter( "thickness", $division->{block},@axis_param_path );

						my $radiusf;
						if (defined $plot_min && defined $plot_max) {
							$radiusf   = $plot_max-$plot_min ? ($division->{pos}-$plot_min)/($plot_max-$plot_min) : $plot_min;
						} else {
							$radiusf   = $r1-$r0 ? ($division->{pos}-$r0)/abs($r1-$r0) : $r0;
						}

						my $radius;
						if ($orientation_direction == 1) {
							$radius    = $r0 + ($r1-$r0)*$radiusf;
						} else {
							$radius    = $r1 - ($r1-$r0)*$radiusf;
						}
						printdebug_group("axis",$ideogram->{chr},$division->{spacing},$division->{pos},$radius,$color,$thickness);
						slice(
									image       => $IM,
									start       => $ideogram->{set}->min,
									end         => $ideogram->{set}->max,
									chr         => $ideogram->{chr},
									radius_from => $radius,
									radius_to   => $radius,
									edgecolor   => $color,
									edgestroke  => $thickness,
									mapoptions  => {
																	object_type   => "trackaxis",
																	object_label  => $track_type,
																	object_parent => $ideogram->{chr},
																	object_data   => {
																										start => $ideogram->{set}->min,
																										end   => $ideogram->{set}->max,
																									 },
																 },
								 );
					}
				}
			}
			printsvg(qq{</g>}) if $SVG_MAKE;

			my ( $data_point_prev, $datum_prev, $data_point_next, $datum_next );
			my $sort_funcs = {
												text => sub { ($b->{data}[0]{w}||0) <=> ($a->{data}[0]{w}||0) },
												default => sub {
													( ($a->{param}{z}||0) <=> ($b->{param}{z}||0) )
														|| ( $a->{data}[0]{chr} cmp $b->{data}[0]{chr}
																 || $a->{data}[0]{start} <=> $b->{data}[0]{start} );
												},
												value_asc => sub {
													( ($a->{param}{z}||0) <=> ($b->{param}{z}||0) )
														|| ( $a->{data}[0]{value} <=> $b->{data}[0]{value})
													},
												value_desc => sub {
													( ($a->{param}{z}||0) <=> ($b->{param}{z}||0) )
														|| ( $b->{data}[0]{value} <=> $a->{data}[0]{value})
													},
												size_asc => sub {
													( ($a->{param}{z}||0) <=> ($b->{param}{z}||0) )
														|| ( $a->{data}[0]{end}-$a->{data}[0]{start} <=> $b->{data}[0]{end}-$b->{data}[0]{start})
													},
												size_desc => sub {
													( ($a->{param}{z}||0) <=> ($b->{param}{z}||0) )
														|| ( $b->{data}[0]{end}-$b->{data}[0]{start} <=> $a->{data}[0]{end}-$a->{data}[0]{start})
													},
												heatmap => sub {
													( ($a->{param}{z}||0) <=> ($b->{param}{z}||0) ) ||
														$b->{data}[0]{end} - $b->{data}[0]{start} <=> $a->{data}[0]{end} - $a->{data}[0]{start};
												},
											 };

			my $f = $sort_funcs->{default};
			if (my $sort = seek_parameter("sort",@param_path)) {
				my $dir = seek_parameter("sort_direction",@param_path) || "asc";
				$dir = $dir =~ /asc/ ? "asc" : "desc";
				my $fname = sprintf("%s_%s",$sort,$dir);
				$f    = $sort_funcs->{$fname};
			} else {
				$f = $sort_funcs->{$track_type} if defined $sort_funcs->{$track_type};
			}

			my @sorted_track_data = sort $f @$track_data if $track_data;

		DATAPOINT:
			for my $datum_idx ( 0..@sorted_track_data-1 ) {
				my $datum = $sorted_track_data[$datum_idx];
				$datum->{param}{drawn}++;
				my $data_point = $datum->{data}[0];
				my $data_point_set;
				if ( $track_type eq "connector" ) {
					# nothing to be done for connectors
				} else {
					# adjust this data point so that its start/end is trimmed to the chromosome
					$data_point_set      = make_set($data_point->{start}, $data_point->{end});
					my $chr = $data_point->{chr};
					my $set_checked = check_data_range($data_point_set,$track_type,$chr);
					next DATAPOINT if ! defined $set_checked;
					$data_point_set = $set_checked;
					$data_point->{start} = $data_point_set->min;
					$data_point->{end} = $data_point_set->max;
					#$data_point_set      = $data_point_set->intersect( $KARYOTYPE->{ $data_point->{chr} }{chr}{display_region}{accept} );
					#$data_point->{start} = $data_point_set->min;
					#$data_point->{end}   = $data_point_set->max;
				}

				# the span of the data point must fall on the same ideogram
				my ( $i_start, $i_end ) = ( get_ideogram_idx( $data_point->{start}, $data_point->{chr} ),
																		get_ideogram_idx( $data_point->{end},   $data_point->{chr} ) );
				next DATAPOINT unless defined $i_start && defined $i_end && $i_start == $i_end;

				my $ideogram_idx            = $i_start;
				my $ideogram                = get_ideogram_by_idx($ideogram_idx);

				$data_point->{ideogram_idx} = $i_start;
				$data_point->{ideogram}     = $ideogram;

				if ( $track_type ne "connector" ) {
					next DATAPOINT unless $ideogram->{set}->intersect($data_point_set)->cardinality;
				} else {
					next DATAPOINT unless $ideogram->{set}->member( $data_point->{start} ) && $ideogram->{set}->member( $data_point->{end} );
				}

				# define the next data point, if on the same ideogram possible
				if ( $datum_idx < @sorted_track_data - 1) {
					$datum_next      = $sorted_track_data[ $datum_idx + 1 ];
					$data_point_next = $datum_next->{data}[0];
					$data_point_next->{ideogram_idx} = get_ideogram_idx( $data_point_next->{start}, $data_point_next->{chr} );
				} else {
					$data_point_next = undef;
				}

				################################################################
				# connector track
				if ( $track_type eq "connector" ) {
					start_timer("track_connector");
					$r0 = unit_parse( seek_parameter( "r0", $datum, @param_path ), get_ideogram_by_idx($i_start) );
					$r1 = unit_parse( seek_parameter( "r1", $datum, @param_path ), get_ideogram_by_idx($i_start) );
					my $rd     = abs( $r0 - $r1 );
					my $angle0 = getanglepos( $data_point->{start}, $data_point->{chr} );
					my $angle1 = getanglepos( $data_point->{end},   $data_point->{chr} );
					my $svg    = { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum,@param_path) };
					# In read_data_file, coordinates with start>end have the positions reversed and 'rev' key set
					($angle0,$angle1) = ($angle1,$angle0) if $data_point->{rev};
					my @dims = split( $COMMA,	seek_parameter( "connector_dims", $datum, @param_path ) );

					my $thickness = seek_parameter( "thickness", $datum, @param_path );
					my $color     = seek_parameter( "color",     $datum, @param_path );

					draw_line( [ getxypos( $angle0, $r0 + $dims[0] * $rd ), 
											 getxypos( $angle0, $r0 + ( $dims[0] + $dims[1] ) * $rd ) ],
										 $thickness, $color,
										 $svg );
					if ( $angle1 > $angle0 ) {
						my $adiff  = $angle1 - $angle0;
						my $ainit  = $angle0;
						my $acurr  = $ainit;
						my $rinit  = $r0 + ( $dims[0] + $dims[1] ) * $rd;
						my $rfinal = $r0 + ( $dims[0] + $dims[1] + $dims[2] ) * $rd;
						my $rdiff    = abs( $rfinal - $rinit );
						my $progress = 0;
						while ( $acurr + $CONF{anglestep} <= $angle1 ) {
							draw_line( [ getxypos( $acurr,$rinit + $rdiff * ( $acurr - $ainit ) / $adiff ),
													 getxypos( $acurr+$CONF{anglestep}, $rinit + $rdiff*( $acurr + $CONF{anglestep} - $ainit )/$adiff)],
												 $thickness, $color,
												 $svg );
							$acurr += $CONF{anglestep};
						}
						if ( $acurr < $angle1 ) {
							draw_line( [ getxypos( $acurr, $rinit + $rdiff * ( $acurr - $ainit ) / $adiff),
													 getxypos( $angle1, $rfinal ) ],
												 $thickness, $color, 
												 $svg );
						}
					} elsif ( $angle1 < $angle0 ) {
						my $adiff    = $angle1 - $angle0;
						my $ainit    = $angle0;
						my $acurr    = $ainit;
						my $rinit    = $r0 + ( $dims[0] + $dims[1] ) * $rd;
						my $rfinal   = $r0 + ( $dims[0] + $dims[1] + $dims[2] ) * $rd;
						my $rdiff    = abs( $rfinal - $rinit );
						my $progress = 0;
						while ( $acurr - $CONF{anglestep} >= $angle1 ) {
							draw_line( [ getxypos( $acurr, $rinit + $rdiff*( $acurr - $ainit )/$adiff),
													 getxypos( $acurr - $CONF{anglestep}, $rinit + $rdiff*($acurr - $CONF{anglestep} - $ainit)/$adiff) ],
												 $thickness, $color, 
												 $svg );
							$acurr -= $CONF{anglestep};
						}
						if ( $acurr > $angle1 ) {
							draw_line([getxypos($acurr, $rinit + $rdiff*( $acurr - $ainit )/$adiff),
												 getxypos($angle1, $rfinal ) ],
												$thickness, $color,
												$svg );
						}
					} else {
						my $rinit  = $r0 + ( $dims[0] + $dims[1] ) * $rd;
						my $rfinal = $r0 + ( $dims[0] + $dims[1] + $dims[2] ) * $rd;
						draw_line([getxypos( $angle0, $rinit ),
											 getxypos( $angle1, $rfinal )],
											$thickness, $color, 
											$svg );
					}
					draw_line([getxypos($angle1,$r0 + ( $dims[0] + $dims[1] + $dims[2] ) * $rd),
										 getxypos($angle1,$r0 + ( $dims[0] + $dims[1] + $dims[2] + $dims[3] ) * $rd ) ],
										$thickness, $color, 
										$svg );
					stop_timer("track_connector");
				}

				################################################################
				# Highlight
				if ( $track_type eq "highlight" ) {
					start_timer("track_highlight");
					$r0 = unit_parse( seek_parameter( "r0", $datum, @param_path ), get_ideogram_by_idx($i_start) );
					$r1 = unit_parse( seek_parameter( "r1", $datum, @param_path ), get_ideogram_by_idx($i_start) );
					my $url = seek_parameter("url",$data_point,$datum,@param_path);
					$url = format_url(url=>$url,param_path=>[$data_point,$datum,@param_path]);
					slice(
								image       => $IM,
								start       => $data_point->{start},
								end         => $data_point->{end},
								chr         => $data_point->{chr},
								radius_from => $r0,
								radius_to   => $r1,
								edgecolor   => seek_parameter( "stroke_color|color", $datum, @param_path ),
								edgestroke  => seek_parameter( "stroke_thickness", $datum, @param_path),
								fillcolor   => seek_parameter( "fill_color", $datum, @param_path ),
								svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
								mapoptions  => {url=>$url},
							 );
					stop_timer("track_highlight");
				}

				my $angle = getanglepos( ( $data_point->{start} + $data_point->{end} ) / 2, $data_point->{chr} );

				$r0 = unit_parse( seek_parameter( "r0", @param_path ), get_ideogram_by_idx($i_start) );
				$r1 = unit_parse( seek_parameter( "r1", @param_path ), get_ideogram_by_idx($i_start) );

				$data_point->{value_orig} = $data_point->{value};
				my $value                 = $data_point->{value};

				my ($radius,$radius0)     = ($r1,$r1);
				my $value_outofbounds;

				($radius0,$radius,$value_outofbounds) = check_value_limit(-value=>$value,
																																	-r0=>$r0,
																																	-r1=>$r1,
																																	-orientation=>$orientation,
																																	-plot_min=>$plot_min,
																																	-plot_max=>$plot_max,
																																	-track_type=>$track_type,
																																	-data_point=>$data_point);
				# -value
				# -plot_min
				# -plot_max
				# -track_type
				# -data_point
				#
				# return
				# value_outofbounds
				# radius
				# radius0
				sub check_value_limit {
					my %args = @_;
					my $value = $args{-value};
					my $r0 = $args{-r0};
					my $r1 = $args{-r1};
					my $plot_min = $args{-plot_min};
					my $plot_max = $args{-plot_max};
					my $orientation = $args{-orientation};
					my $track_type = $args{-track_type};
					my $data_point = $args{-data_point};
					my ($value_outofbounds,$radius,$radius0);
					if (defined $value && (defined $plot_min || defined $plot_max) && $track_type ne "text") {
						if ( defined $plot_min && defined $value && $value < $plot_min ) {
							$value             = $plot_min;
							$value_outofbounds = 1;
						}
						if ( defined $plot_max && defined $value && $value > $plot_max ) {
							$value             = $plot_max;
							$value_outofbounds = 1;
						}
						if ($value_outofbounds && defined $data_point) {
							$data_point->{value} = $value;
						}
						# value floor is the axis end closer to zero
						my $valuefloor = abs($plot_min) < abs($plot_max) ? $plot_min : $plot_max;
						$valuefloor    = 0 if $plot_min <= 0 && $plot_max >= 0;

						# orientation refers to the direction of the y-axis 
						#
						# in  - y-axis is oriented towards the center of the circle
						# out - y-axis is oriented towards the outside of the circle
						my $rd = abs( $r1 - $r0 );
						my $dd = ($plot_max||0) - ($plot_min||0);
						if (! $dd) {
							$radius  = $r1;
							$radius0 = $r1;
						} elsif ($dd && defined $value) {
							if ( match_string($orientation,"in") ) {
								# radius of data point
								$radius  = $r1 - $rd * abs( $value - $plot_min ) / $dd;
								# radius of valuefloor
								$radius0 = $r1 - $rd * ( $valuefloor - $plot_min ) / $dd;
							} else {
								# radius of data point
								$radius  = $r0 + $rd * ( $value - $plot_min ) / $dd;
								# radius of valuefloor
								$radius0 = $r0 + $rd * ( $valuefloor - $plot_min ) / $dd;
							}
						}
					}
					return($radius0,$radius,$value_outofbounds);
				}

				if (0 && defined $value && (defined $plot_min || defined $plot_max) && $track_type ne "text") {
					if ( defined $plot_min && defined $value && $value < $plot_min ) {
						$value             = $plot_min;
						$value_outofbounds = 1;
					}
					if ( defined $plot_max && defined $value && $value > $plot_max ) {
						$value             = $plot_max;
						$value_outofbounds = 1;
					}
					if ($value_outofbounds) {
						$data_point->{value}      = $value;
					}

					# value floor is the axis end closer to zero
					my $valuefloor = abs($plot_min) < abs($plot_max) ? $plot_min : $plot_max;
					$valuefloor    = 0 if $plot_min <= 0 && $plot_max >= 0;

					# orientation refers to the direction of the y-axis 
					#
					# in  - y-axis is oriented towards the center of the circle
					# out - y-axis is oriented towards the outside of the circle
					my $rd = abs( $r1 - $r0 );
					my $dd = ($plot_max||0) - ($plot_min||0);
					if (! $dd) {
						$radius  = $r1;
						$radius0 = $r1;
					} elsif ($dd && defined $value) {
						if ( match_string($orientation,"in") ) {
							# radius of data point
							$radius  = $r1 - $rd * abs( $value - $plot_min ) / $dd;
							# radius of valuefloor
							$radius0 = $r1 - $rd * ( $valuefloor - $plot_min ) / $dd;
						} else {
							# radius of data point
							$radius  = $r0 + $rd * ( $value - $plot_min ) / $dd;
							# radius of valuefloor
							$radius0 = $r0 + $rd * ( $valuefloor - $plot_min ) / $dd;
						}
					}
				}

				if ( $track_type ne "text" ) {
					$data_point->{angle}  = $angle;
					$data_point->{radius} = $radius;
				}

				# data is clipped, not skippedv
				if ( $value_outofbounds ) {
					if ($track_type ne "line" && $track_type ne "histogram" && $track_type ne "scatter") {
						#goto SKIPDATUM;
					}
				}

				if ($value_outofbounds) {
					if (my $data_out_of_range = seek_parameter("range",@param_path) || 
							fetch_conf("data_out_of_range")) {
						goto SKIPDATUM if $data_out_of_range eq "hide";
					} else {
						$data_point->{value}  = $value;
					}
				}

				################################################################
				# Text
				if ( $track_type eq "text" ) {
					if (! defined $data_point->{layer} ) {
						if (seek_parameter("overflow", @param_path)) {
							# Catch text that has not been placed, if 'overflow' is set. 
							# For now, place the text at r0 of the track.
							$datum->{param}{color}        = first_defined(seek_parameter("overflow_color",@param_path),
																														seek_parameter("color",$datum,@param_path));
							$datum->{param}{label_size}   = first_defined(seek_parameter("overflow_size",@param_path),
																														seek_parameter("label_size",$datum,@param_path));
							$datum->{param}{label_font}   = first_defined(seek_parameter("overflow_font",@param_path),
																														seek_parameter("label_font",$datum,@param_path));
							$data_point->{layer}  = 0;
							$data_point->{radius} = unit_parse( seek_parameter( "r0", @param_path ), get_ideogram_by_idx($i_start) );
							$data_point->{radius_shift} = 0;
							printdebug_group("textplace","not_placed,overflow",@{$data_point}{qw(chr start end value)});;
						} else {
							printdebug_group("textplace","not_placed",@{$data_point}{qw(chr start end value)});;
							goto SKIPDATUM;
						}
					} else {
						printdebug_group("textplace","placed",@{$data_point}{qw(chr start end value)});
					}

					start_timer("track_text_draw");

					$data_point->{radius_new}       = $data_point->{radius}     + $data_point->{radius_shift};
					$data_point->{radius_new_label} = $data_point->{radius_new} + $data_point->{rpadding};
					$data_point->{angle_new}        = $data_point->{angle} if ! defined $data_point->{angle_new};

					my ( $ao, $ro ) = textoffset(
																			 @{$data_point}{qw(angle_new radius_new_label)},
																			 @{$data_point}{ $data_point->{tangential} ? qw(dimr dima) : qw(dimr dima)},
																			 unit_strip( unit_validate( seek_parameter( "yoffset", 
																																									$datum, 
																																									@param_path ) || "0p",
																																	"plots/plot/yoffset",
																																	"p" )),
																			 $data_point->{tangential},
																			);
	    
					my ( $x, $y ) = getxypos( $data_point->{angle_new} + $ao, $data_point->{radius_new_label} + $ro );
				
					my $fontkey  = seek_parameter( "label_font", $datum, @param_path ) || fetch_conf("default_font") || "default";
					my $fontfile = $CONF{fonts}{ $fontkey };
					die "Non-existent font definition for font [$fontkey] for text track." if ! $fontfile;
					my $labelfontfile = locate_file( file => $fontfile, name=>"label font file");
					die "Could not find file [$fontfile] for font definition [$fontkey] for text track." if ! $labelfontfile;
					my $fontname = get_font_name_from_file($labelfontfile);
	    
					my $text_angle;
					if ( defined_and_zero(seek_parameter( "label_rotate", $datum, @param_path ) )
							 ||
							 seek_parameter( "label_tangential", $datum, @param_path ) ) {
						$text_angle = $DEG2RAD * textangle( $data_point->{angle_new}, 1 );
					} else {
						$text_angle = $DEG2RAD * textangle( $data_point->{angle_new} );
					}

					my $labeldata = {
													 text   => $data_point->{value},
													 font   => $fontkey, #$labelfontfile,
													 size   => unit_strip( unit_validate( seek_parameter( "label_size", $datum, @param_path),
																																"plots/plot/label_size",
																																qw(p n))),
													 color  => seek_parameter( "color", $datum, @param_path ),
													 angle  => $data_point->{angle_new},
													 radius => $data_point->{radius_new_label},

													 is_rotated  => seek_parameter("label_rotate",@param_path),
													 is_parallel => seek_parameter("label_parallel",@param_path),
													 rotation    => seek_parameter("rotation",@param_path),
													 guides      => seek_parameter("guides",@param_path),
													};
	    
					if ( seek_parameter( "show_links", @param_path ) ) {
						my $link_orientation = seek_parameter( "link_orientation", @param_path ) || "in";
						my @link_dims        = split( /[, ]+/, seek_parameter( "link_dims", @param_path ) );
						@link_dims           = map { unit_strip( unit_validate( $_, "plots/plot/link_dims", "p" ) ) } @link_dims;
		
						#
						#      00112223344 (link dims)
						# LABEL  --\
						#           \
						#            \--  LABEL
						#
		
						my $link_thickness = unit_strip( unit_validate( seek_parameter( "link_thickness", $datum, @param_path ),
																														"plots/plot/link_thickness", ("p","n") ));
						my $line_colors = seek_parameter( "link_color", $datum, @param_path )
							|| seek_parameter( "color", $datum, @param_path );
		
						my ($astart,$aend) = @{$data_point}{qw(angle angle_new)};
						if ($link_orientation eq "out") {
							($astart,$aend) = ($aend,$astart);
						}
						draw_line([ getxypos($astart,$data_point->{radius_new} + $link_dims[0]),
												getxypos($astart,$data_point->{radius_new} + sum( @link_dims[ 0, 1 ] )) ],
											$link_thickness,
											$line_colors
										 );
		
						draw_line([ getxypos($astart, $data_point->{radius_new} + sum( @link_dims[ 0, 1 ] ) ),
												getxypos($aend, 	$data_point->{radius_new} + sum( @link_dims[ 0, 1, 2 ] ) ) ],
											$link_thickness,
											$line_colors
										 );
		
						draw_line([ getxypos($aend,	$data_point->{radius_new} + sum( @link_dims[ 0, 1, 2 ] ) ),
												getxypos($aend,	$data_point->{radius_new} + sum( @link_dims[ 0, 1, 2, 3 ] ) ) ],
											$link_thickness,
											$line_colors
										 );
		
					}
					my $url = seek_parameter( "url", $datum, @param_path );
					$url = format_url(url=>$url,param_path=>[$data_point,$datum,@param_path]);
					Circos::Text::draw_text(%$labeldata,
																	svg        => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum,@param_path) },
																	mapoptions => { url  =>$url });
					stop_timer("track_text_draw");
				} 

				################################################################
				# Scatter
				if ( $track_type eq "scatter" ) {
					start_timer("track_scatter");
					#printdumper($datum->{param});
					my $url     = seek_parameter("url",$data_point,$datum,@param_path);
					$url        = format_url(url=>$url,param_path=>[$data_point,$datum,@param_path]);
					my $glyph   = seek_parameter( "glyph", $datum, @param_path );
					my $color   = seek_parameter( "fill_color|color", $datum->{data}[0], $datum);
				
					if (! exists_parameter("fill_color|color",$datum->{data}[0],$datum)) {
						for my $pair ([\$color,"color"]) {
							my ($var,$type) = @$pair;
							if (! defined $$var) {
								for my $item (@{$legend->{$type}}) {
									if ( ! defined $item->{min} && ! defined $item->{max}) {
										$$var = $item->{value};
									} elsif ( ! defined $item->{min} && defined $item->{max} && $value < $item->{max} ) {
										$$var = $item->{value};
									} elsif (! defined $item->{max} && defined $item->{min} && $value >= $item->{min} ) {
										$$var = $item->{value};
									} elsif (defined $item->{min} &&
													 defined $item->{max} &&
													 $value >= $item->{min} && $value < $item->{max}) {
										$$var = $item->{value};
									}
									last if defined $$var;
								}
							}
						}
					}
					if ( $glyph eq "circle" ) {
						my $point = [getxypos( $angle, $radius )];
						if ($SVG_MAKE) {
							my $radius = unit_strip(seek_parameter( "glyph_size", $datum, @param_path ))/2;
							goto SKIPDATUM if ! $radius;
							Circos::SVG::draw_circle(point            => $point,
																			 radius           => $radius,
																			 stroke_color     => seek_parameter( "stroke_color", $datum, @param_path),
																			 stroke_thickness => unit_strip(seek_parameter( "stroke_thickness", $datum, @param_path)),
																			 color            => $color,
																			 attr             => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path));
						}
						if ($PNG_MAKE) {
							my $width = unit_strip(seek_parameter("glyph_size", $datum, @param_path ));
							goto SKIPDATUM if ! $width;
							Circos::PNG::draw_arc(point             => $point,
																		width             => $width,
																		stroke_color      => seek_parameter("stroke_color", $datum, @param_path ),
																		stroke_thickness  => seek_parameter("stroke_thickness", $datum, @param_path ),
																		color             => $color);
							if ($url && $width) {
								my ($x,$y) = @$point;
								my $r      = unit_strip(seek_parameter("glyph_size", $datum,@param_path));
								my $xshift = $CONF{image}{image_map_xshift}||0;
								my $yshift = $CONF{image}{image_map_xshift}||0;
								my $xmult  = $CONF{image}{image_map_xfactor}||1;
								my $ymult  = $CONF{image}{image_map_yfactor}||1;
								my @coords = ($x*$xmult + $xshift , $y*$ymult + $yshift, $r*$xmult);
								report_image_map(shape=>"circle",coords=>\@coords,href=>$url);
							}
						}
					} elsif (grep($glyph eq $_, qw(rectangle square triangle cross)) || $glyph =~ /gon/ ) {
						my ($x,$y)    = getxypos( $angle, $radius );
						my $size      = unit_strip(seek_parameter( "glyph_size", $datum, @param_path ));
						goto SKIPDATUM if ! $size;
						my $size_half = $size/2;
						my $poly = GD::Polygon->new();
						my @pts;
						if ( $glyph eq "rectangle" || $glyph eq "square" ) {
							@pts = (
											[ $x - $size_half, $y - $size_half ],
											[ $x + $size_half, $y - $size_half ],
											[ $x + $size_half, $y + $size_half ],
											[ $x - $size_half, $y + $size_half ]
										 );
						} elsif ( $glyph eq "triangle" ) {
							@pts = (
											[ $x, $y - $size_half * $SQRT3_HALF              ],
											[ $x + $size_half, $y + $size_half * $SQRT3_HALF ],
											[ $x - $size_half, $y + $size_half * $SQRT3_HALF ]
										 );
						} elsif ( $glyph eq "cross" ) {
							@pts = (
											[ $x,              $y - $size_half ],
											[ $x,              $y ],
											[ $x + $size_half, $y ],
											[ $x,              $y ],
											[ $x,              $y + $size_half ],
											[ $x,              $y ],
											[ $x - $size_half, $y ],
											[ $x,              $y ]
										 );
						} elsif ( $glyph =~ /ngon(\d+)?/ || $glyph =~ /(\d+)?gon$/ ) {
							my $sides = $1 || 5;
							for my $side ( 0 .. $sides - 1 ) {
								my $angle = 360 * $side / $sides;
								push @pts, [ $x + $size_half * cos( $angle * $DEG2RAD ),
														 $y + $size_half * sin( $angle * $DEG2RAD ) ];
							}
						}
						my $angle_shift = seek_parameter( "angle_shift|glyph_rotation", $datum, @param_path ) || 0;
						map { $poly->addPt(@$_) } map { [ rotate_xy( @$_, $x, $y, $angle + $angle_shift ) ] } @pts;
						my $url = seek_parameter("url",$datum,@param_path);
						$url    = format_url(url=>$url,param_path=>[$data_point,$datum,@param_path]);
						if ($url) {
							my $xshift = $CONF{image}{image_map_xshift}||0;
							my $yshift = $CONF{image}{image_map_xshift}||0;
							my $xmult  = $CONF{image}{image_map_xfactor}||1;
							my $ymult  = $CONF{image}{image_map_yfactor}||1;
							my @coords = map { ( $_->[0]*$xmult + $xshift , $_->[1]*$ymult + $yshift ) } $poly->vertices;
							report_image_map(shape=>"poly",coords=>\@coords,href=>$url);
						}
						if ($PNG_MAKE) {
							Circos::PNG::draw_polygon(polygon    => $poly,
																				thickness  => unit_strip(seek_parameter("stroke_thickness|thickness", $datum, @param_path ),"p"),
																				fill_color => $glyph eq "cross" ? undef : seek_parameter("fill_color|color", $datum, @param_path ),
																				color      => seek_parameter("stroke_color", $datum, @param_path ));
						}
						if ($SVG_MAKE) {
							Circos::SVG::draw_polygon(polygon    => $poly,
																				thickness  => unit_strip(seek_parameter("stroke_thickness|thickness", $datum, @param_path ),"p"),
																				linecap    => seek_parameter("stroke_linecap|linecap", $datum, @param_path ),
																				fill_color => $glyph eq "cross" ? undef : seek_parameter("fill_color|color", $datum, @param_path ),
																				color      => seek_parameter("stroke_color", $datum, @param_path ),
																				attr       => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path));
						}
					}
					stop_timer("track_scatter");
				}

				################################################################
				# Line or histogram
				if ( $track_type eq "line" || $track_type eq "histogram" ) {

					my $url = seek_parameter("url",$data_point,$datum,@param_path);
					$url = format_url(url=>$url,param_path=>[$data_point,$datum,@param_path]);

					# Check whether adjacent data points should be fused. First, we check
					# whether they pass a gap test, set by max_gap. If max_gap is not defined,
					# then by default this test passes.

					my $gap_pass = 1;
					my $gap_size;

					if ( $data_point_prev && $data_point_prev->{ideogram_idx} == $data_point->{ideogram_idx} ) {
						my $max_gap  = seek_parameter( "max_gap", @param_path );
						$gap_size = $data_point->{start} - $data_point_prev->{end};
						if ( $gap_size > 1 && defined $max_gap) {
							# test gap if the points are further than one unit apart on the scale and if max_gap is defined
							unit_validate( $max_gap, "plots/plot/max_gap", qw(u n p b) );
							my ( $max_gap_value, $max_gap_unit ) = unit_split( $max_gap, "plots/plot/max_gap" );
							if ( $max_gap_unit =~ /[bun]/ ) {
								if ($max_gap_unit eq "u") {
									$max_gap_value = unit_convert(from=>$max_gap,	to=>"b", factors => { ub => $CONF{chromosomes_units} } );
								}
								my $d = $data_point->{start} - $data_point_prev->{end};
								$gap_pass = 0 if $d > $max_gap_value;
							} elsif ($max_gap_unit eq "p") {
								$max_gap_value = unit_strip($max_gap_value);
								my ( $xp, $yp ) = getxypos( @{$data_point_prev}{qw(angle radius)} );
								my ( $x, $y )   = getxypos( @{$data_point}{qw(angle radius)} );
								my $d = sqrt( ( $xp - $x )**2 + ( $yp - $y )**2 );
								$gap_pass = 0 if $d > $max_gap_value;
							} else {
								confess "Bad max_gap unit";
							}
						}
						if ( ! $gap_pass ) {
							goto SKIPDATUM if $track_type eq "line";
						}
					} else {
						$gap_pass = 0;
					}

					my $thickness = seek_parameter( "thickness|stroke_thickness", $datum, @param_path );
					$thickness    = unit_strip($thickness,"p");
					my $color1    = seek_parameter( "color", $datum_prev || $datum, @param_path);
					my $color2    = seek_parameter( "color", $datum, @param_path);

					if ( $track_type eq "line" ) {

				    start_timer("track_line");

						#printinfo(@{$data_point}{qw(chr start end)});

				    goto SKIPDATUM unless $data_point_prev;
				    goto SKIPDATUM if $data_point->{ideogram_idx} != $data_point_prev->{ideogram_idx};

				    my ( $xp, $yp ) = getxypos( @{$data_point_prev}{qw(angle radius)} );
				    my ( $x, $y )   = getxypos( @{$data_point}{qw(angle radius)} );

				    my $fill_color  = seek_parameter("fill_color",  $datum, @param_path);
				    my $fill_color1 = seek_parameter("fill_color",  $datum_prev || $datum, @param_path);
				    my $fill_color2 = seek_parameter("fill_color",  $datum, @param_path);

				    if ($fill_color1 && $fill_color2) {
							if ($fill_color1 ne $fill_color2) {
								my $xxp = $x + $xp;
								my $yyp = $y + $yp;
								draw_line([    $xp,    $yp, $xxp/2, $yyp/2], $thickness,	$color1 );
								draw_line([ $xxp/2, $yyp/2,     $x,     $y], $thickness,	$color2 );
								slice(
											image        => $IM,
											start        => ($data_point_prev->{start}+$data_point_prev->{end})/2,
											end          => (($data_point_prev->{start}+$data_point_prev->{end})/2+($data_point->{start}+$data_point->{end})/2)/2,
											chr          => $data_point->{chr},
											radius_from  => $radius0,
											radius_to_y0 => $data_point_prev->{radius},
											radius_to_y1 => ($data_point->{radius}+$data_point_prev->{radius})/2,
											edgestroke   => 0,
											edgecolor    => $fill_color1,
											fillcolor    => $fill_color1,
											svg          => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions   => {url=>$url},
										 );
								slice(
											image        => $IM,
											start        => (($data_point_prev->{start}+$data_point_prev->{end})/2+($data_point->{start}+$data_point->{end})/2)/2,
											end          => ($data_point->{start}+$data_point->{end})/2,
											chr          => $data_point->{chr},
											radius_from  => $radius0,
											radius_to_y0 => ($data_point->{radius}+$data_point_prev->{radius})/2,
											radius_to_y1 => $data_point->{radius},
											edgestroke   => 0,
											edgecolor    => $fill_color2,
											fillcolor    => $fill_color2,
											svg          => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions   => {url=>$url},
										 );
							} else {
								slice(
											image        => $IM,
											start        => ($data_point_prev->{start}+$data_point_prev->{end})/2,
											end          => ($data_point->{start}+$data_point->{end})/2,
											chr          => $data_point->{chr},
											radius_from  => $radius0,
											radius_to_y0 => $data_point_prev->{radius},
											radius_to_y1 => $data_point->{radius},
											edgestroke   => 0,
											edgecolor    => $fill_color1,
											fillcolor    => $fill_color1,
											svg          => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions   => {url=>$url},
										 );
							}
				    } elsif ($fill_color) {
							slice(
										image        => $IM,
										start        => ($data_point_prev->{start}+$data_point_prev->{end})/2,
										end          => ($data_point->{start}+$data_point->{end})/2,
										chr          => $data_point->{chr},
										radius_from  => $radius0,
										radius_to_y0 => $data_point_prev->{radius},
										radius_to_y1 => $data_point->{radius},
										edgestroke   => 0,
										edgecolor    => $fill_color,
										fillcolor    => $fill_color,
										svg          => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
										mapoptions   => {url=>$url},
									 );
				    }

				    if ( $color1 ne $color2 ) {
							my $xxp = $x + $xp;
							my $yyp = $y + $yp;
							my $svg    = { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum,@param_path) };
							draw_line([    $xp,    $yp, $xxp/2, $yyp/2], $thickness,	$color1, $svg );
							draw_line([ $xxp/2, $yyp/2,     $x,     $y], $thickness,	$color2, $svg );
				    } else {
							draw_line([ $xp, $yp, $x, $y], $thickness,	$color1);
				    }
				    stop_timer("track_line");

					} elsif ( $track_type eq "histogram" ) {

				    start_timer("track_histogram");

				    my ($first_in_series,$last_in_series);

				    if ( ! $data_point_prev || 
								 $data_point_prev->{ideogram_idx} != $data_point->{ideogram_idx} ) {
							$first_in_series = 1;
				    }

				    if ( ! defined $data_point_next->{ideogram_idx} ||
								 ! defined $data_point->{ideogram_idx} ||
								 $data_point->{ideogram_idx} != $data_point_next->{ideogram_idx}) {
							$last_in_series = 1;
				    }

				    my $join_bins;

				    # present bin will be joined to previous one if
				    # - previous bin exists, and
				    #   - bin extension has not been explicitly defined to "no", or
				    #   - previous bin end is within 1 bp of the current bin start

				    my $extend_bin = seek_parameter("extend_bin",$datum,@param_path);

				    if (seek_parameter("stacked",$datum) || seek_parameter("float",$datum,@param_path)) {
							$join_bins = 0;
				    } elsif (defined_and_zero($extend_bin)) {
							if (! defined $gap_size || $gap_size > 1) {
								$join_bins = 0;
							} else {
								$join_bins = 1;
							}
				    } else {
							if ($gap_pass) {
								$join_bins = 1;
							} else {
								$join_bins = 0;
							}
				    }
						# Change the base of the bin to radius associated with 'valuebase'
						if (seek_parameter("float",$datum,@param_path)) {
							my $valuebase = seek_parameter("valuebase",$datum);
							if (defined $valuebase) {
								my ($radius0base,$radiusbase,$value_outofboundsbase) = 
									check_value_limit(-value=>$valuebase,
																		-r0=>$r0,
																		-r1=>$r1,
																		-orientation=>$orientation,
																		-plot_min=>$plot_min,
																		-plot_max=>$plot_max,
																		-track_type=>$track_type,
																		-data_point=>$data_point);
								$radius0 = $radiusbase;
							}
						}

				    0&&printinfo("gappass",$gap_pass,
												 "joinbin",$join_bins,
												 "first",$first_in_series,
												 "last",$last_in_series,
												 "data",
												 $data_point_prev ? $data_point_prev->{start} : undef,
												 $data_point->{start},$data_point->{value},
												 $data_point_next ? $data_point_next->{start} : undef);

				    my $fill_color     = seek_parameter("fill_color",  $datum, @param_path);
				    my $pattern        = seek_parameter("pattern",  $datum, @param_path);
				    my $fill_under     = $fill_color && not_defined_or_one(seek_parameter("fill_under",$datum,@param_path));
				    my $thickness      = seek_parameter("thickness|stroke_thickness",$datum,@param_path);
						$thickness = 0 if ! defined seek_parameter("color",$datum,@param_path);
				    my $stroke_type    = seek_parameter("stroke_type", $datum, @param_path) || "outline";
				    my $bin_stroke     = $stroke_type eq "bin" || $stroke_type eq "both" ? $thickness : 0;
				    my $outline_stroke = $stroke_type eq "outline" || $stroke_type eq "both" ? $thickness : 0;

				    my %params = (image       => $IM,
													fillcolor   => $fill_color,
													edgestroke  => $bin_stroke,
													mapoptions  => {url=>$url},
												 );

				    if ( !$join_bins ) {

							# bins are not joined
							if ($fill_under) {
								# floor of bin is 0 level
								slice(
											image       => $IM,
											start       => $data_point->{start},
											end         => $data_point->{end},
											chr         => $data_point->{chr},
											radius_from => $radius0,
											radius_to   => $data_point->{radius},
											pattern     => $pattern,
											fillcolor   => $fill_color,
											edgecolor   => $color2,
											edgestroke  => $bin_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions  => {url=>$url},
										 );
							} elsif ($bin_stroke) {
						    slice(
											image       => $IM,
											start       => $data_point->{start},
											end         => $data_point->{end},
											chr         => $data_point->{chr},
											radius_from => $radius0,
											radius_to   => $data_point->{radius},
											edgecolor   => $color2,
											edgestroke  => $bin_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions  => {url=>$url},
										 );
							}
							if ($outline_stroke) {
						    # draw drop end of previous bin
						    if ($data_point_prev && ! $first_in_series) {
									slice(
												image       => $IM,
												start       => $data_point_prev->{end},
												end         => $data_point_prev->{end},
												chr         => $data_point_prev->{chr},
												radius_from => $data_point_prev->{radius},
												radius_to   => $radius0,   
												edgecolor   => $color1,
												edgestroke  => $outline_stroke,
												svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											 ); 
								} 
								# draw drop end of current bin, if last on ideogram
								if ($last_in_series) {
									slice(
												image       => $IM,
												start       => $data_point->{end},
												end         => $data_point->{end},
												chr         => $data_point->{chr},
												radius_from => $data_point->{radius},
												radius_to   => $radius0,
												edgecolor   => $color2,
												edgestroke  => $outline_stroke,
												svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											 );
								}
								# draw drop start of current bin
								slice(
											image       => $IM,
											start       => $data_point->{start},
											end         => $data_point->{start},
											chr         => $data_point->{chr},
											radius_from => $data_point->{radius},
											radius_to   => $radius0, #$orientation eq "in" ? $r1 : $r0,
											edgecolor   => $color2,
											edgestroke  => $outline_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
										 );
								# draw roof of current bin
								slice(
											image       => $IM,
											start       => $data_point->{start},
											end         => $data_point->{end},
											chr         => $data_point->{chr},
											radius_from => $data_point->{radius},
											radius_to   => $data_point->{radius},
											edgecolor   => $color2,
											edgestroke  => $outline_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
										 );
							}
						} else {
							# bins are joined
							my ($pos_prev_end,$pos_start,$pos_end);
							$pos_prev_end = $data_point_prev->{end};
							if ($data_point_prev->{end} == $data_point->{start} - 1) {
								$pos_start = $data_point->{start};
							} else {
								$pos_start = ( $data_point_prev->{end} + $data_point->{start} ) / 2;
							}
							$pos_end = $data_point->{end};

							# bins are joined
							if ($fill_under) {
								slice(image       => $IM,
											start       => $pos_prev_end,
											end         => $pos_start,
											chr         => $data_point_prev->{chr},
											radius_from => $radius0,
											radius_to   => $data_point_prev->{radius},
											fillcolor   => $fill_color,
											pattern     => $pattern,
											edgecolor   => $color1,
											edgestroke  => $bin_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions  => {url=>$url},
										 ) if $pos_prev_end != $pos_start - 1;
								slice(
											image       => $IM,
											start       => $pos_start,
											end         => $pos_end,
											chr         => $data_point->{chr},
											radius_from => $radius0,
											radius_to   => $data_point->{radius},
											fillcolor   => $fill_color,
											pattern     => $pattern,
											edgecolor   => $color2,
											edgestroke  => $bin_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions  => {url=>$url},
										 );
							} elsif ($bin_stroke) {
								slice(
											image       => $IM,
											start       => $pos_prev_end,
											end         => $pos_start,
											chr         => $data_point_prev->{chr},
											radius_from => $radius0,
											radius_to   => $data_point_prev->{radius},
											edgecolor   => $color1,
											edgestroke  => $bin_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions  => {url=>$url},
										 ) if $pos_prev_end != $pos_start;
								slice(
											image       => $IM,
											start       => $pos_start,
											end         => $pos_end,
											chr         => $data_point->{chr},
											radius_from => $radius0,
											radius_to   => $data_point->{radius},
											edgecolor   => $color2,
											edgestroke  => $bin_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											mapoptions  => {url=>$url},
										 );
							}
							if ($outline_stroke) {
								slice(
											image       => $IM,
											start       => $pos_prev_end,
											end         => $pos_start,
											chr         => $data_point_prev->{chr},
											radius_from => $data_point_prev->{radius},
											radius_to   => $data_point_prev->{radius},
											edgecolor   => $color1,
											edgestroke  => $outline_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
										 ) if $pos_prev_end != $pos_start;

								if ( ! match_string($color1,$color2) ) {
									my ( $r_min, $r_max, $join_color ) =
										abs( $data_point_prev->{radius} - $radius0 ) <
											abs( $data_point->{radius} - $radius0 )
												? (
													 $data_point_prev->{radius},
													 $data_point->{radius}, $color2
													)
													: (
														 $data_point->{radius},
														 $data_point_prev->{radius}, $color1
														);
			    
									if ( ( $r_min < $radius0 && $r_max > $radius0 )
											 || ( $r_max < $radius0
														&& 
														$r_min > $radius0 )
										 ) {
										slice(
													image => $IM,
													start => $pos_start,
													end   => $pos_start,
													chr   => $data_point_prev->{chr},
													radius_from => $data_point_prev->{radius},
													radius_to   => $radius0,
													edgecolor   => $color1,
													edgestroke  => $outline_stroke,
													svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
												 );

										slice(
													image => $IM,
													start => $pos_start,
													end   => $pos_start,
													chr   => $data_point_prev->{chr},
													radius_from => $radius0,
													radius_to   => $data_point->{radius},
													edgecolor   => $color2,
													edgestroke  => $outline_stroke,
													svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
												 );
									} else {
										slice(
													image       => $IM,
													start       => $pos_start,
													end         => $pos_start,
													chr         => $data_point_prev->{chr},
													radius_from => $r_min,
													radius_to   => $r_max,
													edgecolor   => $join_color,
													edgestroke  => $outline_stroke,
													svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
												 );
									}
								} else {
									slice(
												image       => $IM,
												start       => $pos_start,
												end         => $pos_start,
												chr         => $data_point_prev->{chr},
												radius_from => $data_point_prev->{radius},
												radius_to   => $data_point->{radius},
												edgecolor   => $color2,
												edgestroke  => $outline_stroke,
												svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
											 );
								}
								slice(
											image       => $IM,
											start       => $pos_start,
											end         => $pos_end,
											chr         => $data_point_prev->{chr},
											radius_from => $data_point->{radius},
											radius_to   => $data_point->{radius},
											edgecolor   => $color2,
											edgestroke  => $outline_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
										 );
							}

							# for bins that are first/last on this ideogram, make
							# sure that the drop line from the start/end of the bin
							# is drawn
							if ($first_in_series) {
								slice(
											image       => $IM,
											start       => $data_point->{start},
											end         => $data_point->{start},
											chr         => $data_point->{chr},
											radius_from => $data_point->{radius},
											radius_to   => $radius0,   
											edgecolor   => $color2,
											edgestroke  => $outline_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
										 );
							}
							if ($last_in_series) {
								slice(
											image       => $IM,
											start       => $data_point->{end},
											end         => $data_point->{end},
											chr         => $data_point->{chr},
											radius_from => $data_point->{radius},
											radius_to   => $radius0,   
											edgecolor   => $color2,
											edgestroke  => $outline_stroke,
											svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
										 );
							}
						}
						stop_timer("track_histogram");
					}
				}

				################################################################
				# Tile
				if ( $track_type eq "tile" ) {

					start_timer("track_tile");
					my $set;
					eval { $set = make_set($data_point->{start},$data_point->{end}) };

					if ($@) {
						printinfo( "error - badtileset", $datum->{pos} );
						next;
					}

					my $color   = seek_parameter( "color", $datum->{data}[0], $datum);
					my $pattern = seek_parameter( "pattern", $datum->{data}[0],$datum);
					my $markup  = seek_parameter( "layers_overflow_color", @param_path );

					for my $pair ([\$color,"color"],[\$pattern,"pattern"]) {
						my ($var,$type) = @$pair;
						if (! defined $$var) {
							for my $item (@{$legend->{$type}}) {
								if ( ! defined $item->{min} && ! defined $item->{max}) {
									$$var = $item->{value};
								} elsif ( ! defined $item->{min} && defined $item->{max} && $value < $item->{max} ) {
									$$var = $item->{value};
								} elsif (! defined $item->{max} && defined $item->{min} && $value >= $item->{min} ) {
									$$var = $item->{value};
								} elsif (defined $item->{min} &&
												 defined $item->{max} &&
												 $value >= $item->{min} && $value < $item->{max}) {
									$$var = $item->{value};
								}
								last if defined $$var;
							}
						}
					}

					my $padded_set = Set::IntSpan->new(sprintf( "%d-%d",$set->min-$margin,$set->max+$margin));
					my ($freelayer) = grep( !$_->{set}->intersect($padded_set)->cardinality, @{ $tilelayers[$ideogram_idx] } );

				TILEPLACE:

					if ( !$freelayer ) {
						my $overflow = seek_parameter( "layers_overflow", @param_path ) || $EMPTY_STR;
						if ( $overflow eq "hide" ) {
							# not plotting this data point
							goto SKIPDATUM;
						} elsif ( $overflow eq "collapse" ) {
							$freelayer = $tilelayers[$ideogram_idx][0];
						} else {
							push @{ $tilelayers[$ideogram_idx] },
								{
								 set => Set::IntSpan->new(),
								 idx => int( @{ $tilelayers[$ideogram_idx] } )
								};
							$freelayer = $tilelayers[$ideogram_idx][-1];
						}
						$color = seek_parameter( "layers_overflow_color", $datum->{data}[0], $datum, @param_path ) if $markup;
					}

					if ( $freelayer->{idx} >= seek_parameter( "layers", @param_path ) && $markup ) {
						$color = seek_parameter( "layers_overflow_color", $datum->{data}[0], $datum, @param_path );
					}

					$freelayer->{set} = $freelayer->{set}->union($padded_set);

					my $radius;
					my $t   = seek_parameter( "thickness", $datum->{data}[0], $datum, @param_path );
					my $st  = seek_parameter( "stroke_thickness", $datum->{data}[0], $datum, @param_path );
					my $p   = seek_parameter( "padding", $datum->{data}[0], $datum, @param_path );
					my $off = seek_parameter( "offset", $datum->{data}[0], $datum, @param_path ) || 0;

					$t  = unit_strip($t,"p");
					$st = unit_strip($st,"p");
					$p  = unit_strip($p,"p");

					if ( $orientation eq "out" ) {
						$radius = $r0 + $freelayer->{idx} * ( $t + $p ) + $off;
					} elsif ( $orientation eq "in" ) {
						$radius = $r1 - $freelayer->{idx} * ( $t + $p ) + $off;
					} else {
						my $nlayers = seek_parameter( "layers", @param_path );
						my $midradius = ( $r1 + $r0 ) / 2;
						#  orientation direction
						#      in         -1
						#      out         1
						#      center      1
						if ( not $nlayers % 2 ) {
							# even number of layers
							if ( !$freelayer->{idx} ) {
								# first layer lies below mid-point
								$radius = $midradius - $p / 2 - $t - $off;
							} elsif ( $freelayer->{idx} % 2 ) {
								# 1,3,5,... layer - above mid-point
								my $m = int( $freelayer->{idx} / 2 );
								$radius = $midradius + $p / 2 + $m * ( $t + $p ) + $off;
							} else {
								# 2,4,6,... layer - below mid-point
								my $m   = int( $freelayer->{idx} / 2 );
								$radius = $midradius - $p / 2 - $m * ( $t + $p ) - $t - $off;
							}
						} else {
							# odd number of layers
							if ( !$freelayer->{idx} ) {
								$radius = $midradius - $t / 2 - $off;
							} elsif ( $freelayer->{idx} % 2 ) {
								# 1,3,5,... layer - above mid-point
								my $m   = int( $freelayer->{idx} / 2 );
								$radius = $midradius + $t / 2 + $m * ( $p + $t ) + $p + $off;
							} else {
								# 2,4,6,... layer - below mid-point
								my $m   = int( $freelayer->{idx} / 2 );
								$radius = $midradius - $t / 2 - $m * ( $p + $t ) - $off;
							}
						}
					}

					if ($radius < $r0 || $radius > $r1) {
						my $overflow = seek_parameter( "layers_overflow", @param_path ) || $EMPTY_STR;
						if ( $overflow eq "collapse" ) {
							$freelayer = $tilelayers[$ideogram_idx][0];
						} else {
							# not plotting this data point
							goto SKIPDATUM;
						} 
						$color = $markup = seek_parameter( "layers_overflow_color", $datum, @param_path ) || "red";
						if ($data_point->{seen}++) {
							goto SKIPDATUM;
						} else {
							goto TILEPLACE;
						}
					}

					printdebug_group("tile","tile",$value,"min",$plot_min,"max",$plot_max,"color",$color,"rgb",rgb_color($color),"pattern",$pattern);

					my $url = seek_parameter("url",$data_point,$datum,@param_path);
					$url = format_url(url=>$url,param_path=>[$data_point,$datum,@param_path]);
					slice(
								image       => $IM,
								start       => $set->min,
								end         => $set->max,
								chr         => $data_point->{chr},
								radius_from => $radius,
								radius_to   => $radius + $orientation_direction * $t,
								edgecolor   => seek_parameter("stroke_color", $datum->{data}[0],$datum,@param_path),
								edgestroke  => $st,
								mapoptions  => { url=>$url },
								svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
								fillcolor   => $color,
							 );
					stop_timer("track_tile");
				}

				################################################################
				# Heatmap
				if ( $track_type eq "heatmap" ) {
					start_timer("track_heatmap");
					my $value   = $data_point->{value_orig};
					my $color   = seek_parameter("color", $datum->{data}[0],$datum);
					my $pattern = seek_parameter("pattern", $datum->{data}[0],$datum);
					for my $pair ([\$color,"color"],[\$pattern,"pattern"]) {
						my ($var,$type) = @$pair;
						if (! defined $$var) {
							for my $item (@{$legend->{$type}}) {
								if ( ! defined $item->{min} && ! defined $item->{max}) {
									$$var = $item->{value};
								} elsif ( ! defined $item->{min} && defined $item->{max} && $value < $item->{max} ) {
									$$var = $item->{value};
								} elsif (! defined $item->{max} && defined $item->{min} && $value >= $item->{min} ) {
									$$var = $item->{value};
								} elsif (defined $item->{min} &&
												 defined $item->{max} &&
												 $value >= $item->{min} && $value < $item->{max}) {
									$$var = $item->{value};
								}
								last if defined $$var;
							}
						}
					}
					printdebug_group("heatmap","heatmap",$value,"min",$plot_min,"max",$plot_max,"color",$color,"rgb",rgb_color($color),"pattern",$pattern);
					my $url = seek_parameter("url",$data_point,$datum,@param_path);
					$url = format_url(url=>$url,param_path=>[{color=>$color},$data_point,$datum,@param_path]);
					if (my $min_size = seek_parameter("min_size", $datum->{data}[0],$datum,@param_path)) {
						my $size = $data_point->{end} - $data_point->{start};
						if ($size < $min_size) {
							my $id = $IDEOGRAMS[$data_point->{ideogram_idx}];
							$data_point->{start} -= int(($min_size-$size)/2);
							$data_point->{end}   += int(($min_size-$size)/2);
							$data_point->{start} = max($id->{set}->min,$data_point->{start});
							$data_point->{end}   = min($id->{set}->max,$data_point->{end});
						}
					}
					slice(
								image       => $IM,
								start       => $data_point->{start},
								end         => $data_point->{end},
								chr         => $data_point->{chr},
								radius_from => $r0,
								radius_to   => $r1,
								edgecolor   => seek_parameter("stroke_color", $datum->{data}[0],$datum,@param_path) || $color,
								edgestroke  => seek_parameter("stroke_thickness", $datum->{data}[0],$datum,@param_path),
								svg         => { attr => seek_parameter_glob("^svg.*",qr/^svg/,$datum, @param_path) },
								mapoptions  => { url  => $url},
								fillcolor   => $color,
								pattern     => $pattern,
							 );
					stop_timer("track_heatmap");
				}
			SKIPDATUM:
				$datum_prev      = $datum;
				$data_point_prev = $data_point;
			}
			printsvg(qq{</g>}) if $SVG_MAKE;
			$plotid++;
		}

	OUT:

		printdebug_group("output","generating output");
		if ($MAP_MAKE) {
			printdebug_group("output","compiling image map");
			for my $map_element (reverse @MAP_ELEMENTS) {
				printf MAP $map_element->{string},"\n";
				if ($CONF{image}{image_map_overlay}) {
					# create an overlay of the image map elements
					my $poly = GD::Polygon->new();
					my @coords = map {round($_)} @{$map_element->{coords}};
					if (@coords == 3) {
						if ($CONF{image}{image_map_overlay_fill_color}) {
							$IM->filledArc(
														 @coords,
														 $coords[2],
														 0, 360,
														 aa_color($CONF{image}{image_map_overlay_fill_color},$IM,$COLORS)
														);
						}
						my $color_obj;
						if ($CONF{image}{image_map_overlay_stroke_thickness}) {
							$IM->setThickness($CONF{image}{image_map_overlay_stroke_thickness});
							$color_obj = fetch_color( $CONF{image}{image_map_overlay_stroke_color}, $COLORS);
						} else {
							$color_obj = aa_color($CONF{image}{image_map_overlay_stroke_color},$IM,$COLORS);
						}
						if ($CONF{image}{image_map_overlay_stroke_color}) {
							$IM->arc(
											 @coords,
											 $coords[2],
											 0, 360,
											 $color_obj,
											);
						}
						if ($CONF{image}{image_map_overlay_stroke_thickness}) {
							$IM->setThickness(1);
						}
					} else {
						while (my ($x,$y) = splice(@coords,0,2)) {
							$poly->addPt($x,$y);
						}
						if ($CONF{image}{image_map_overlay_fill_color}) {
							$IM->filledPolygon($poly,
																 aa_color($CONF{image}{image_map_overlay_fill_color},$IM,$COLORS));
						}
						my $color_obj;
						if ($CONF{image}{image_map_overlay_stroke_thickness}) {
							$IM->setThickness($CONF{image}{image_map_overlay_stroke_thickness});
							$color_obj = fetch_color( $CONF{image}{image_map_overlay_stroke_color}, $COLORS );
						} else {
							$color_obj = aa_color($CONF{image}{image_map_overlay_stroke_color},$IM,$COLORS);
						}
						if ($CONF{image}{image_map_overlay_stroke_color}) {
							print $IM->polygon($poly,$color_obj);
						}
						if ($CONF{image}{image_map_overlay_stroke_thickness}) {
							$IM->setThickness(1);
						}
					}
				}
			}
			printf MAP "</map>\n";
			close(MAP);
			my $fsize = round ((-s $outputfile_map) / 1000);
			printdebug_group("output","created HTML image map at $outputfile_map ($fsize kb)");
		}

		if ($PNG_MAKE) {
			open PNG, ">$outputfile_png" || fatal_error("io","cannot_write",$outputfile_png,"PNG file",$!);
			binmode PNG;
			print PNG $IM->png;
			close(PNG);
			my $fsize = round ((-s $outputfile_png) / 1000);
			printdebug_group("output","created PNG image $outputfile_png ($fsize kb)");
		}

		if ($SVG_MAKE) {
			my $patterns = fetch_conf("patterns","svg");
			printsvg("<defs>");
			for my $pattern_name (keys %$patterns) {
				printsvg($patterns->{$pattern_name});
			}
			printsvg("</defs>");
			printsvg(q{</svg>});
			close(SVG);
			my $fsize = -e $outputfile_svg ? round ((-s $outputfile_svg) / 1000) : 0;
			printdebug_group("output","created SVG image $outputfile_svg ($fsize kb)");
		}

		stop_timer("circos");
		report_timer();

		if (my $t = fetch_conf("debug_auto_timer_report")) {
			if (get_timer("circos") > $t) {
				# force timer reporting
				if (! debug_or_group("timer")) {
					debug_group_add("timer");
					report_timer();
					printdebug_group("summary,timer","image took more than $t s to generate. Component timings are shown above. To always show them, use -debug_group timer. To adjust the time cutoff, change debug_auto_timer_report in etc/housekeeping.conf.");
				}
			}
		}
	
		return 1;
	}

# end run()
################################################################

sub check_data_range {
	my ($set,$type,$chr) = @_;
	return undef if !$KARYOTYPE->{$chr}{chr}{display};
	# $int = intersection of ideogram display region with data set
	my $int = $KARYOTYPE->{$chr}{chr}{display_region}{accept}->intersect($set);
	if ($int == $set->cardinality) {
		# data completely within ideogram
		return $set;
	} else {
		my $do_trim = fetch_conf("data_out_of_range") =~ /trim|clip/;
		my $overlap = $int->cardinality;
		if (fetch_conf("data_out_of_range") =~ /warn/) {
			error("warning","data_range_exceeded",
						$type,$set->run_list,
						$chr,$KARYOTYPE->{ $chr }{chr}{display_region}{accept}->run_list,
						$do_trim && $overlap ? "trimmed" : "hidden");
		} elsif (fetch_conf("data_out_of_range") =~ /fatal/) {
			fatal_error("data","data_range_exceeded",
									$type,$set->run_list,
									$chr,$KARYOTYPE->{ $chr }{chr}{display_region}{accept}->run_list);
		}
		if ($do_trim) {
			# trim the link, only if it has a non-zero intersection with the ideogram
			if ($int->cardinality) {
				return $int;
			} else {
				return undef;
			}
		} else {
			return undef;
		}
	}
}

# -------------------------------------------------------------------
sub fetch_brush {
  # given a brush size, try to fetch it from the brush
  # hash, otherwise create and store the brush.
  my ( $w0, $h0, $color ) = @_;
  my ($brush,$brush_colors);
  my $margin = 5;
  fatal_error("graphics","brush_zero_size") unless $w0;

  my ($w,$h) = ($w0 + $margin, $h0 + $margin);

  printdebug_group("brush","asking for brush",$w0,$h0,"with_margin",$w,$h,"color",$color);

  if ( exists $IM_BRUSHES->{size}{$w}{$h}{brush} ) {
    ( $brush, $brush_colors ) = @{ $IM_BRUSHES->{size}{$w}{$h} }{qw(brush colors)};
    printdebug_group("brush","fetching premade brush",$w,$h,$color);
  } else {
    eval {
			if ( $w0 && $h0 ) {
				printdebug_group("brush","creating full brush",$w0,$h0);
				$brush = GD::Image->new( $w, $h, 1 );
			} else {
				printdebug_group("brush","creating empty brush",$w0,$h0);
				$brush = GD::Image->newTrueColor();
			}
    };
    
    if ($@) {
			confess "error - could not create 24-bit brush in fetch_brush"
    }
    
    if ( !$brush ) {
      confess "error - could not create brush of size ($w) x ($h)";
    }

    $brush_colors = allocate_colors($brush);

    @{ $IM_BRUSHES->{size}{$w}{$h} }{qw(brush colors)} = ( $brush, $brush_colors );
  }
  
  if (exists $brush_colors->{transparent}) {
		printdebug_group("brush","using transparent defn for brush",$brush_colors->{transparent});
		$brush->transparent( $brush_colors->{transparent} );
  } else {
		my @rgb = find_transparent();
		printdebug_group("brush","creating transparent color for brush",@rgb);
		allocate_color("transparent",\@rgb,$brush_colors,$brush);
		printdebug_group("brush","using transparent defn for brush",$brush_colors->{transparent});
		$brush->transparent( $brush_colors->{transparent} );
  }
  if ( defined $color && $w && $h ) {
		# the brush will be transparent
		$brush->fill( 0, 0, $brush_colors->{transparent} );
		# with circle
		$brush->arc($w/2, $h/2, $w0, $h0, 0, 360, fetch_color($color,$brush_colors,$brush));
  }
  return ( $brush, $brush_colors );
}

# -------------------------------------------------------------------
sub span_from_pair {
	return Set::IntSpan->new( sprintf( "%d-%d", map { round($_) } @_ ) );
}

# -------------------------------------------------------------------
sub angle_to_span {
  my $angle      = shift;
  my $resolution = shift;
  my $shift      = shift || 0;
  return round ( ( $angle + $shift - $CONF{image}{angle_offset} ) * $resolution );
}

# -------------------------------------------------------------------
sub rotate_xy {
	my ($x,$y,$x0,$y0,$angle) = @_;
	$angle = ( $angle - $CONF{image}{angle_offset} ) * $DEG2RAD;
	my $sa = sin($angle);
	my $ca = cos($angle);
	my $xd = $x-$x0;
	my $yd = $y-$y0;
	my $xr = $xd*$ca - $yd*$sa; # ( $x - $x0 ) * cos($angle) - ( $y - $y0 ) * sin($angle);
	my $yr = $xd*$sa + $yd*$ca; # ( $x - $x0 ) * sin($angle) + ( $y - $y0 ) * cos($angle);
	return ( round( $xr + $x0 ), round( $yr + $y0 ) );
}

# -------------------------------------------------------------------
sub perturb_value {
  #
  # Given a value and string "pmin,pmax", perturb the value
  # within the range value*pmin ... value*pmax, sampling
  # from the range uniformly
  #
  my ( $value, $perturb_parameters ) = @_;

  return $value if !$perturb_parameters || !$value;

  my ( $pmin, $pmax ) = split( /[\s,]+/, $perturb_parameters );
  my $prange          = $pmax - $pmin;
  my $urd             = $pmin + $prange * rand();
  my $new_value       = $value * $urd;

  return $new_value;
}

# -------------------------------------------------------------------
sub draw_guide {
	my ($r0,$r1,$angle,$thickness,$color) = @_;
	my $default_guide_color = "lgrey";
	my $guide_color         = fetch_conf("guides","color","default") || $default_guide_color;
	draw_line([getxypos($angle,$r0),getxypos($angle,$r1)],
						fetch_conf("guides","thickness") || 1,
						$guide_color);
}

sub svg_style {
	my %params = @_;
	my @style;
	for my $param (keys %params) {
		my $value = $params{$param};
		next unless defined $value;
		my $style;
		if ($param eq "stroke-width") {
	    $style = sprintf("stroke-width: %.1f",$value);
		} elsif ($param eq "stroke") {
	    $style = sprintf("stroke: rgb(%d,%d,%d)",rgb_color($value));
		} else {
	    $style = sprintf("%s: %s",$param,$value);
		}
		push @style, $style if $style;
	}
	return join("; ",@style) . ";";
}



################################################################
# First pass at creating a data structure of ideogram order
# groups. Each group is composed of the ideograms that it contains,
# their index within the group, and a few other helper structures
#
# n : number of ideograms in the group
# cumulidx : number of ideograms in all preceeding groups
# idx : group index
# tags : list of ideogram data
#        ideogram_idx - ideogram idx relative to default order
#        tag - tag of the ideogram (ID or user tag)
sub make_chrorder_groups {

  my $chrorder_groups = shift;
  my $chrorder        = shift;

  for my $tag (@$chrorder) {
    if ( $tag eq $CARAT ) {
      # this list has a start anchor
			fatal_error("ideogram","multiple_start_anchors") if grep( $_->{start}, @$chrorder_groups );
			$chrorder_groups->[-1]{start} = 1;
    } elsif ( $tag eq q{$} ) {
      # this list has an end anchor
			fatal_error("ideogram","multiple_end_anchors") if grep( $_->{end}, @$chrorder_groups );
			$chrorder_groups->[-1]{end} = 1;
    } elsif ( $tag eq $PIPE ) {
			# saw a break - create a new group
			push @{$chrorder_groups},
				{
				 idx      => scalar( @{$chrorder_groups} ),
				 cumulidx => $chrorder_groups->[-1]{n} + $chrorder_groups->[-1]{cumulidx}
				};
    } elsif ( $tag eq $DASH ) {
			push @{ $chrorder_groups->[-1]{tags} }, { tag => $tag };
			$chrorder_groups->[-1]{n} = int( @{ $chrorder_groups->[-1]{tags} } );
			$chrorder_groups->[-1]{tags}[-1]{group_idx} = $chrorder_groups->[-1]{n} - 1;
    } else {
			# add this tag and all ideograms that match it (v0.52) to the most recent group 
			#my @tagged_ideograms = grep( ($_->{tag} !~ /__/ && $_->{tag} eq $tag) || ($_->{tag} =~ /__/ && $_->{chr} eq $tag) , @IDEOGRAMS );
			my @tagged_ideograms = grep( $_->{chr} eq $tag || $_->{tag} eq $tag , @IDEOGRAMS );
			for my $tagged_ideogram (@tagged_ideograms) {
				push @{ $chrorder_groups->[-1]{tags} }, { tag => $tag, ideogram_idx => $tagged_ideogram->{idx} };
				$chrorder_groups->[-1]{n} = int( @{ $chrorder_groups->[-1]{tags} } );
				$chrorder_groups->[-1]{tags}[-1]{group_idx} = $chrorder_groups->[-1]{n} - 1;
			}
    }
  }
  #
  # to each tag with corresponding ideogram, add the ideogram_idx
  #
  # check that a group does not have the start and end anchor
  #
  for my $group (@$chrorder_groups) {
		if ( $group->{start} && $group->{end} ) {
			my @tags = map { $_->{tag} } @{ $group->{tags} };
			fatal_error("ideogram","start_and_end_anchors",join($COMMA,@tags));
    }
  }
  return $chrorder_groups;
}

# -------------------------------------------------------------------
sub filter_data {
  my ( $set, $chr ) = @_;
  my $intersection = $set->intersect( $KARYOTYPE->{$chr}{chr}{display_region}{accept} );
  return $intersection;
}

################################################################
#
# Given the initial chromosome order groups (see make_chrorder_groups),
# set the display index of each ideogram.
#
sub set_display_index {
	my $chrorder_groups  = shift;
	my $seen_display_idx = Set::IntSpan->new();
	#
	# keep track of which display_idx values have been used
	# process groups that have start or end flags first
	#
	for my $group (sort { ( $b->{start} || $b->{end} || 0 ) <=> ( $a->{start} || $a->{end} || 0 ) } @$chrorder_groups ) {
		if ( $group->{start} ) {
	    my $display_idx = 0;
	    for my $tag_item ( @{ $group->{tags} } ) {
				$tag_item->{display_idx} = $display_idx;
				$seen_display_idx->insert($display_idx);
				$display_idx++;
	    }
		} elsif ( $group->{end} ) {
	    my $display_idx = @IDEOGRAMS - $group->{n};
	    for my $tag_item ( @{ $group->{tags} } ) {
				$tag_item->{display_idx} = $display_idx;
				$seen_display_idx->insert($display_idx);
				$display_idx++;
	    }
		} else {
	    my $idx;
	    my $minidx;
	    
	    #
	    # ideogram index for first defined idoegram - this is the anchor,
	    # and all other ideograms in this group have their display index
	    # set relative to the anchor
	    #
	    my ($ideogram_anchor) = grep( defined $_->{ideogram_idx},
																		sort { $a->{group_idx} <=> $b->{group_idx} }
																		@{ $group->{tags} } );
	    
	    my $continue;
	    for my $tag_item ( sort { $a->{group_idx} <=> $b->{group_idx} } @{ $group->{tags} } ) {
				$tag_item->{display_idx} = $tag_item->{group_idx} -
					$ideogram_anchor->{group_idx} +
						$ideogram_anchor->{ideogram_idx};
				$seen_display_idx->insert( $tag_item->{display_idx} );
	    }
	    
	    #
	    # find the minimum display index for this group
	    #
	    my $min_display_index =
				min( map { $_->{display_idx} } @{ $group->{tags} } );
	    
	    if ( $min_display_index < 0 ) {
				map { $_->{display_idx} -= $min_display_index }	@{ $group->{tags} };
	    }
		}
	}
	return $chrorder_groups;
}

################################################################
# Create a new span object from start/end positions. 
# Positions are expected to be integers. Floats are truncated.
#
# If start>end the routine aborts with a stack trace via confess
# If start=end or end is not defined, the span is a single value.

# -------------------------------------------------------------------
sub recompute_chrorder_groups {
  my $chrorder_groups = shift;
  my %allocated;
  my $display_idx_set = make_set(0,@IDEOGRAMS-1);

  for my $group (@$chrorder_groups) {
    for my $tag_item ( @{ $group->{tags} } ) {
      my ($ideogram) = grep( ($_->{tag} !~ /__/ && $_->{tag} eq $tag_item->{tag}) || ($_->{tag} =~ /__/ && $_->{chr} eq $tag_item->{tag}), @IDEOGRAMS );
      if ($ideogram) {
				$display_idx_set->remove( $tag_item->{display_idx} ) if defined $tag_item->{display_idx};
				$allocated{ $ideogram->{idx} }++;
      }
    }
  }
  
  for my $group (@$chrorder_groups) {
    for my $tag_item ( @{ $group->{tags} } ) {
      my ($ideogram) = grep( ($_->{tag} !~ /__/ && $_->{tag} eq $tag_item->{tag}) || ($_->{tag} =~ /__/ && $_->{chr} eq $tag_item->{tag}), @IDEOGRAMS );
      #for my $ideogram ( grep( $_->{tag} eq $tag_item->{tag}, @IDEOGRAMS ) ) {
      if ( !$ideogram ) {
				my ($unallocated) = grep( ! exists $allocated{ $_->{idx} }, @IDEOGRAMS );
				$tag_item->{tag}          = $unallocated->{tag};
				$tag_item->{ideogram_idx} = $unallocated->{idx};
				$allocated{ $unallocated->{idx} }++;
				$display_idx_set->remove( $tag_item->{display_idx} );
      }
    }
  }

  for my $group (@$chrorder_groups) {
    for my $tag_item ( @{ $group->{tags} } ) {
      if ( defined $tag_item->{ideogram_idx} ) {
				my $display_idx;
				if ( !defined $tag_item->{display_idx} ) {
					$display_idx = $display_idx_set->first;
					$display_idx_set->remove($display_idx);
					$tag_item->{display_idx} = $display_idx;
				} else {
					$display_idx = $tag_item->{display_idx};
				}
				get_ideogram_by_idx( $tag_item->{ideogram_idx} )->{display_idx} = $display_idx if defined $display_idx;
      } else {
				printwarning("trimming ideogram order - removing entry",$tag_item->{group_idx},"from group", $group->{idx});
				$tag_item->{display_idx} = undef;
      }
    }
  }
  
  for my $ideogram (@IDEOGRAMS) {
    if ( !defined $ideogram->{display_idx} ) {
      my $display_idx = $display_idx_set->first;
      $display_idx_set->remove($display_idx);
      $ideogram->{display_idx} = $display_idx;
    }
  }

  # Adjacent ideograms from the same chromosome which 
  #
  # - are reversed
  # - have same tag as chr name
  #
  # have their order swaped. This is to handle cases like
  #
  # chromosomes_breaks  = -hs1:100-200;-hs1:300-400
  # chromosomes_reverse = hs1
  #
  # so that the segments shown are
  #
  # (--99 + 201--299 + 401--)
  #
  # and NOT
  #
  # 401--) + 201--299 + (--99 

  my $rev_set = Set::IntSpan->new();
  my @IDEOGRAMS_SORT = sort {$a->{display_idx} <=> $b->{display_idx}} @IDEOGRAMS;
  for my $i (0..@IDEOGRAMS_SORT-1) {
		my $id      = $IDEOGRAMS_SORT[$i];
		my $id_next = $IDEOGRAMS_SORT[$i+1];
		last if ! defined $id_next;
		next if ! $id->{reverse};
		next if ! $id_next->{reverse};
		next if $id->{chr} ne $id->{tag};
		next if $id_next->{chr} ne $id_next->{tag};
		if ($id->{chr} eq $id_next->{chr}) {
			$rev_set->insert($i);
			$rev_set->insert($i+1);
		}
  }
  for my $set ($rev_set->sets) {
		my @set    = $set->elements;
		my @setrev = reverse @set;
		for my $i (0..@set-1) {
			$IDEOGRAMS_SORT[ $set[$i] ]{display_idx_new} = $IDEOGRAMS_SORT[ $setrev[$i] ]{display_idx};
		}
  }
  for my $id (@IDEOGRAMS_SORT) {
		if (defined $id->{display_idx_new}) {
			$id->{display_idx} = $id->{display_idx_new};
			delete $id->{display_idx_new};
		}
  }

  # end of display_idx remapping for breaks/reverse
  ################################################################
  
  return $chrorder_groups;
}

# -------------------------------------------------------------------
sub reform_chrorder_groups {
  my $chrorder_groups = shift;
  my $reform_display_idx;
 REFORM:
  do {
    $reform_display_idx = 0;
    my $union = Set::IntSpan->new();

    for my $group (@$chrorder_groups) {
      my $set = Set::IntSpan->new();
      for my $tag_item ( @{ $group->{tags} } ) {
				$set->insert( $tag_item->{display_idx} );
      }

      $group->{display_idx_set} = $set;

      if ( 
					!$union->intersect( $group->{display_idx_set} )->cardinality 
				 ) {
				$union = $union->union( $group->{display_idx_set} );
      } else {

				#printinfo("not adding group to union",$group->{idx});
				$reform_display_idx = 1;
				$group->{reform} = 1;
      }
    }

  GROUP:
    for my $group (@$chrorder_groups) {
      next unless $group->{reform};

      for my $start ( 0 .. @IDEOGRAMS - 1 - $group->{n} ) {
				my $newgroup =
					map_set { $_ - $group->{display_idx_set}->min + $start }
						$group->{display_idx_set};

				printdebug_group("karyotype",
												 "test new set",                      "old",
												 $group->{display_idx_set}->run_list, "start",
												 $start,                              "new",
												 $newgroup->run_list,                 $union->run_list
												);

				if ( !$newgroup->intersect($union)->cardinality ) {
					printdebug_group("karyotype", "found new set", $newgroup->run_list );
					$union = $union->union($newgroup);
					my @elements = $newgroup->elements;

					for my $tag_item ( @{ $group->{tags} } ) {
						$tag_item->{display_idx} = shift @elements;
					}

					$group->{display_idx_set} = $newgroup;
					$group->{reform}          = 0;
					next GROUP;
				}
      }

      if ( $group->{reform} ) {
				my @tags = map { $_->{tag} } @{ $group->{tags} };
				fatal_error("ideograms","cannot_place",join( $COMMA, @tags ));
      }
    }
  } while ($reform_display_idx);

  return $chrorder_groups;
}

# -------------------------------------------------------------------
{
	my $key_ok_table = {};
	sub parse_parameters {

		# Given a configuration file node (e.g. highlights), parse
		# parameter values, filtering for only those parameters that
		# are accepted for this node type
		#
		# parse_parameters( $CONF{highlights}, "highlights" );
		#
		# Parameters keyed by "default" in the list will be added to the
		# list of acceptable parameters for any type.
		#
		# If the $continue flag is set, then fatal errors are not triggered if
		# unsupported parameters are seen.
		#
		# parse_parameters( $CONF{highlights}, "highlights" , 1);
		#
		# Additional acceptable parameters can be added as a list.
		#
		# parse_parameters( $CONF{highlights}, "highlights" , 1, "param1", "param2");
  
		my $node       = shift;
		my $type       = shift;
		my $continue   = shift;
		my @params     = @_;
		my %param_list = (
											default => [qw(
																			init_counter
																			pre_set_counter
																			post_set_counter
																			pre_increment_counter
																			post_increment_counter
																			increment_counter file
																			url
																			id
																			guides
																			record_limit perturb z show hide axes backgrounds background_color 
																			background_stroke_color background_stroke_thickness 
																			label_size label_offset label_font
																	 )],
											highlight => [qw(
																				offset r0 r1 layer_with_data fill_color stroke_color
																				stroke_thickness ideogram minsize padding type
																		 )],
											link => [qw(
																	 offset start end color pattern flat rev reversed inv inverted twist 
																	 thickness stroke_thickness stroke_color ribbon radius radius1 
																	 radius2 bezier_radius crest bezier_radius_purity ribbon 
																	 perturb_crest perturb_bezier_radius perturb_bezier_radius_purity
																	 rules use show hide minsize padding type
																)],
											connector => [qw(
																				connector_dims thickness color r0 r1 inv rev
																		 )],
											plot      => [qw( start end file minsize
																				angle_shift layers_overflow connector_dims extend_bin
																				label_parallel rotation
																				label_rotate label_radial label_tangential value scale_log_base layers_overflow_color
																				offset padding rpadding thickness layers margin max_gap float
																				fill_color pattern pattern_mapping color color_mapping color_mapping_boundaries pattern_mapping_boundaries thickness stroke_color stroke_thickness
																				orientation thickness r0 r1 glyph glyph_size min max
																				stroke_color stroke_thickness fill_under break_line_distance stroke_type
																				type resolution padding resolve_order label_snuggle
																				snuggle_tolerance snuggle_link_overlap_test snuggle_sampling
																				snuggle_refine snuggle_link_overlap_tolerance
																				max_snuggle_distance resolve_tolerance normalize_bin_values sort_bin_values bin_values_num
																				overflow overflow_color overflow_font overflow_size
																				link_thickness link_orientation link_color show_links link_dims skip_run
																				min_value_change yoffset
																				rules range
																		 )],
										 );

		$param_list{scatter}      = $param_list{plot};
		$param_list{line}         = $param_list{plot};
		$param_list{histogram}    = $param_list{plot};
		$param_list{tile}         = $param_list{plot};
		$param_list{heatmap}      = $param_list{plot};
		$param_list{link_twoline} = $param_list{link};
		$param_list{text}         = $param_list{plot};

		fatal_error("configuration","bad_parameter_type",$type) unless $param_list{$type};

		my $params = {};
		my $restrictive = not_defined_or_one(fetch_conf("restrict_parameter_names"));
		my @params_ok   = ( @{ $param_list{$type} }, @{ $param_list{default} }, @params );
		for my $key ( keys %$node ) {
			my ($key_root,$key_number) = $key =~ /(.+?)(\d*)$/;
			my $key_ok;
			if (exists $key_ok_table->{$type}{$key}) {
				$key_ok = $key_ok_table->{$type}{$key};
			} else {
				$key_ok = !$restrictive || 
					grep( $key_root eq $_ || $key eq $_ || $key_root =~ /$_[*]+/ , @params_ok );
				$key_ok_table->{$type}{$key} = 1;
			}
			next if ref $node->{$key} && ! $key_ok;
			if ( $key_ok ) {
				if ( ! defined $params->{$key} ) {
					my $value = $node->{$key};
					#$value =~ s/;\S/,/g;
					if (defined $value) {
						$value = 1 if lc $value eq "yes";
						$value = 0 if lc $value eq "no";
						$params->{$key} = $value;
					}
				} else {
					fatal_error("configuration","defined_twice",$key,$type);
				}
			} elsif ($restrictive && ! $continue) {
				fatal_error("configuration","unsupported_parameter",$key,$type);
			}
		}
		return $params;
	}
}

# -------------------------------------------------------------------
#sub text_size {
#    $CONF{debug_validate} && validate(
# 	@_,
# 	{
#             fontfile => 1,
#             size     => 1,
#             text     => 1,
# 	}
# 	);
    
#     my %params = @_;
#   my @bounds =
#     GD::Image->stringFT( 0, $params{fontfile}, $params{size}, 0, 0, 0,
# 			 $params{text} );
#   my ( $width, $height ) =
#     ( abs( $bounds[2] - $bounds[0] + 1 ),
#       abs( $bounds[5] - $bounds[1] + 1 ) );
#   return ( $width, $height );
# }

# -------------------------------------------------------------------
sub register_z_levels {
  # Examine a data set (e.g. all highlights, all plots) and enumerate
  # all the z values, which can be global, set-specific or data-specific.
  # The list of z values is stored in the {param} tree of the global data
  # structure for highlights or plots
  #
  # DATA
  #   {highlights}{param}{zlist} = [ z1,z2,... ]
  #   {plots}     {param}{zlist} = [ z1,z2,... ]

  my $node = shift;
  my %z;
  $node->{param}{zlist}{0}++;
  $node->{param}{zlist}{ seek_parameter( "z", $node ) } = 1
    if defined seek_parameter( "z", $node );

  for my $dataset ( make_list( $node->{dataset} ) ) {
		#printinfo("dataset");
		if ( defined seek_parameter( "z", $dataset ) ) {
			$node->{param}{zlist}{ seek_parameter( "z", $dataset ) }++;
		}
      
		for my $collection ( make_list( $dataset->{data} ) ) {
			#printinfo("collection",seek_parameter( "z", $collection ));
			if ( defined seek_parameter( "z", $collection ) ) {
	      $node->{param}{zlist}{ seek_parameter( "z", $collection ) }++;
	      #printdumper($node->{param}{zlist});
			}
	  
			for my $collection_point ( make_list( $collection->{data} ) ) {
	      #printinfo("point",seek_parameter( "z", $collection_point ));
	      if ( defined seek_parameter( "z", $collection_point ) ) {
					$node->{param}{zlist}{ seek_parameter( "z", $collection_point ) }++;
	      }
			}
		}
  }
  
  $node->{param}{zlist} = [ 
													 sort { $a <=> $b } keys %{ $node->{param}{zlist} } 
													];
  #printdumper($node->{param}{zlist});
}


# -------------------------------------------------------------------
sub draw_axis_break {
	my $ideogram      = shift;
	my $ideogram_next = $ideogram->{next};
	return unless fetch_conf("ideogram","spacing","axis_break");
	my $style_id   = $CONF{ideogram}{spacing}{axis_break_style};
	my $style_data = $CONF{ideogram}{spacing}{break_style}{$style_id};
	if (! $style_data) {
		fatal_error("ideogram","undefined_axis_break_style",$style_id,$style_id);
	}
	my $radius_change =
		$DIMS->{ideogram}{ $ideogram->{tag} }{radius} !=
			$DIMS->{ideogram}{ $ideogram_next->{tag} }{radius};

	my $thickness = unit_convert(
															 from => unit_validate(
																										 seek_parameter( "thickness", $style_data ),
																										 "ideogram/spacing/break_style/thickness",
																										 qw(r p)
																										),
															 to      => "p",
															 factors => { rp => $ideogram->{thickness} }
															);

	my $break_space = $CONF{ideogram}{spacing}{break};


	#printstructure("ideogram",$ideogram);
	#printstructure("ideogram",$ideogram_next);

	if ( $style_id == 1 ) {
		# slice connecting the IDEOGRAMS
		if ( $ideogram->{break}{start} && $ideogram->{prev}{chr} ne $ideogram->{chr}) {
	    my $start = $ideogram->{reverse} ? $ideogram->{set}->max : $ideogram->{set}->min;
	    draw_break({chr          => $ideogram->{chr},
									ideogram     => $ideogram,
									start_offset => ideogram_spacing_helper( $ideogram->{break}{start} ),
									start        => $start,
									end          => $start,
									fillcolor    => $style_data->{fill_color},
									thickness    => $thickness,
									style_data   => $style_data
								 });
		}
		if ($ideogram->{break}{end} && $ideogram->{next}{chr} ne $ideogram->{chr}) {
	    my $start = $ideogram->{reverse} ? $ideogram->{set}->min : $ideogram->{set}->max;
	    draw_break({chr        => $ideogram->{chr},
									ideogram   => $ideogram,
									end_offset => ideogram_spacing_helper($ideogram->{break}{end}),
									start      => $start,
									end        => $start,
									fillcolor  => $style_data->{fill_color},
									thickness  => $thickness,
									style_data => $style_data
								 });
		}
		if ( $ideogram->{chr} eq $ideogram->{next}{chr} ) {
	    if ($radius_change) {
				draw_break({chr      => $ideogram->{chr},
										ideogram => $ideogram,
										start    => $ideogram->{set}->max,
										end      => $ideogram_next->{set}->min,
										end_offset => -ideogram_spacing_helper($ideogram->{break}{end}),
										fillcolor  => $style_data->{fill_color},
										thickness  => $thickness,
										style_data => $style_data
									 });
				draw_break({chr      => $ideogram->{chr},
										ideogram => $ideogram_next,
										start    => $ideogram->{set}->max,
										end      => $ideogram_next->{set}->min,
										start_offset => -ideogram_spacing_helper( $ideogram->{break}{start}),
										fillcolor  => $style_data->{fill_color},
										thickness  => $thickness,
										style_data => $style_data
									 });
	    } else {
				my $start = $ideogram->{reverse}      ? $ideogram->{set}->min : $ideogram->{set}->max;
				my $end   = $ideogram_next->{reverse} ? $ideogram_next->{set}->max : $ideogram_next->{set}->min;
				draw_break({chr        => $ideogram->{chr},
										ideogram   => $ideogram,
										start      => $start,
										end        => $end,
										fillcolor  => $style_data->{fill_color},
										thickness  => $thickness,
										style_data => $style_data
									 });
	    }
		}
	} elsif ( $style_id == 2 ) {
		# two radial break lines
		if ($ideogram->{break}{start} && $ideogram->{prev}{chr} ne $ideogram->{chr} ) {
	    my $start = $ideogram->{reverse} ? $ideogram->{set}->max : $ideogram->{set}->min;
	    draw_break({chr        => $ideogram->{chr},
									ideogram   => $ideogram,
									start      => $start,
									end        => $start,
									thickness  => $thickness,
									style_data => $style_data
								 });
			if($style_data->{double_line}) {
				draw_break({chr        => $ideogram->{chr},
										ideogram   => $ideogram,
										start_offset => ideogram_spacing_helper( $ideogram->{break}{start} ),
										start      => $start,
										thickness  => $thickness,
										style_data => $style_data
									 });
			}
		}
		if ($ideogram->{break}{end} && $ideogram->{next}{chr} ne $ideogram->{chr}) {
	    my $start = $ideogram->{reverse} ? $ideogram->{set}->min : $ideogram->{set}->max;
	    draw_break({chr        => $ideogram->{chr},
									ideogram   => $ideogram,
									start      => $start,
									end        => $start,
									thickness  => $thickness,
									style_data => $style_data
								 });
			if($style_data->{double_line}) {
				draw_break({chr        => $ideogram->{chr},
										ideogram   => $ideogram,
										end_offset => ideogram_spacing_helper( $ideogram->{break}{end} ),
										end        => $start,
										thickness  => $thickness,
										style_data => $style_data
									 });
			}
		}
		if ( $ideogram->{next}{chr} eq $ideogram->{chr} ) {
	    my $start = $ideogram->{reverse}      ? $ideogram->{set}->min      : $ideogram->{set}->max;
	    my $end   = $ideogram_next->{reverse} ? $ideogram_next->{set}->max : $ideogram_next->{set}->min;
	    draw_break({chr        => $ideogram->{chr},
									ideogram   => $ideogram,
									start      => $start,
									end        => $start,
									thickness  => $thickness,
									style_data => $style_data
								 });
	    draw_break({chr        => $ideogram_next->{chr},
									ideogram   => $ideogram_next,
									start      => $end,
									end        => $end,
									thickness  => $thickness,
									style_data => $style_data
								 });
		}
	}
}

# -------------------------------------------------------------------
sub draw_break {
	my $args          = shift;
	my $ideogram      = $args->{ideogram};
	my $style_data    = $args->{style_data};

	my $id_radius_outer = $DIMS->{ideogram}{ $ideogram->{tag} }{radius_outer};
	my $id_t            = $DIMS->{ideogram}{ $ideogram->{tag} }{thickness};

	my $radius_from = $id_radius_outer - $id_t/2 - $args->{thickness}/2;
	my $radius_to   = $id_radius_outer - $id_t/2 + $args->{thickness}/2;

	slice(image        => $IM,
				chr          => $args->{chr},
				start        => $args->{start},
				end          => $args->{end},
				start_offset => $args->{start_offset},
				end_offset   => $args->{end_offset},
				fillcolor    => $args->{fillcolor},
				radius_from  => $radius_from,
				radius_to    => $radius_to,
				edgecolor    => $style_data->{stroke_color},
				edgestroke   => unit_strip($style_data->{stroke_thickness}),
			 );
}

# -------------------------------------------------------------------
sub init_brush {
  my ( $w, $h, $brush_color ) = @_;
  $h ||= $w;
  my $brush;

  eval { $brush = GD::Image->new( $w, $h, 1) };
  
  if ($@) {
		$brush = GD::Image->new( $w, $h );
  }
  
  my $color = allocate_colors($brush);

  if ( $brush_color && $color->{$brush_color} ) {
    $brush->fill( 0, 0, $color->{$brush_color} );
  }

  return ( $brush, $color );
}

# -------------------------------------------------------------------
sub draw_ticks {
	# draw ticks and associated labels

	$CONF{debug_validate} && validate( @_, { ideogram         => 1 } );

	my %args             = @_;
	my $ideogram         = $args{ideogram};
	my $chr              = $ideogram->{chr};

	my @requested_ticks = make_list( $CONF{ticks}{tick} );
	if (@requested_ticks > fetch_conf("max_ticks")) {
		fatal_error("ticks","too_many",int(@requested_ticks),$chr);
	}

	################################################################
	# Identify ideograms on which ticks should be drawn. By default, ticks
	# are drawn on each ideogram (chromosomes_display_default=yes). To suppress
	# ticks, use
	#
	# chromosomes = -hs1;-hs2 ...
	# 
	# To draw only on specific ideograms, set chromosomes_display_default=no
	# and define
	#
	# chromosomes = hs1;hs5;...
	#
	# Tick blocks can have these parameters defined, which will override
	# their definition in <ticks> for the tick block.
	#
	# To show (or suppress) ticks within a range, 
	#
	# chromosomes = hs1:10-20
	# chromosomes = -hs1:10-20
	#

  for my $tick (@requested_ticks) {
    next if defined $tick->{_ideogram};

    my $show_default    = seek_parameter( "chromosomes_display_default", $tick, $CONF{ticks} )
      || ! defined seek_parameter( "chromosomes_display_default", $tick, $CONF{ticks} );
    my $ideogram_filter = seek_parameter( "chromosomes", $tick, $CONF{ticks} );
    $tick->{_ideogram} = {
													show_default => $show_default,
													filter       => merge_ideogram_filters(parse_ideogram_filter(seek_parameter("chromosomes", $CONF{ticks} )),
																																 parse_ideogram_filter(seek_parameter("chromosomes", $tick )))
												 };
		#printdumper($tick->{_ideogram});
  }

  # parse and fill data structure for each tick level - process
  # units on grids and spacing (do this now rather than later when
  # ticks are drawn)

  for my $tick (@requested_ticks) {
    # do not process this tick if it is not being shown
    next if !show_element($tick);
    $tick = process_tick_structure($tick,$ideogram);
  }

	#printdumper($ideogram->{chr},\@requested_ticks);

  # keep track of whether ticks have been drawn at a given radius
  my %pos_ticked;

	my $max_tick_length = max( grep($_, map { unit_strip($_->{size},"p") } @requested_ticks ) );
	$DIMS->{tick}{max_tick_length} = $max_tick_length;

	my @ticks;
  my $tick_groups;

  # ticks with relative spacing have had their spacing already
  # defined (rspacing*ideogram_size) by process_tick_structure()
	#printdumper(\@requested_ticks);exit;
	for my $tickdata ( sort { (unit_strip($b->{spacing}||0)) <=> (unit_strip($a->{spacing}||0)) } @requested_ticks ) {
		my $filter = $tickdata->{_ideogram};
		next unless show_element($tickdata);
		if($filter->{show_default} &&
			 exists $filter->{filter}{$chr}{hide} && 
			 $filter->{filter}{$chr}{hide}->cardinality < 1 ) {
			printinfo("skipping",$chr,$tickdata->{spacing});
			next;
		}
		if(! $filter->{show_default} &&
			 ! $filter->{filter}{$chr}) {
			printinfo("skipping",$chr,$tickdata->{spacing});
			next;
		}
		my $tick_label_max;
		for my $tick_radius ( @{ $tickdata->{_radius} } ) {
	    printdebug_group(
											 "tick",
											 "drawing ticks",
											 $chr,
											 "radius",
											 $tick_radius,
											 "type",
											 $tickdata->{spacing_type} || "absolute",
											 "spacing",
											 match_string($tickdata->{spacing_type},qr/rel/) ? $tickdata->{rspacing} : $tickdata->{spacing}
											);
			my @mb_pos;
			#
      # the absolute start and end tick positions will be Math::BigFloat;
      #
      my $dims_key;
      if ( seek_parameter( "spacing", $tickdata, $CONF{ticks} ) ) {
				$dims_key = join( $COLON, $tickdata->{spacing}, $tick_radius );
				my ( $mb_pos_start, $mb_pos_end );
				if ( match_string(seek_parameter( "spacing_type", $tickdata, $CONF{ticks} ), "relative" ) ) {
					if ( match_string(seek_parameter("rdivisor|label_rdivisor", $tickdata, $CONF{ticks} ), "ideogram" )) {
						# IDEOGRAM RELATIVE
						# the start/end position will be the start-end range of this ideogram
						# i.e. - relative positions will start at the start of ideogram crop, relative to chr length
						$mb_pos_start = Math::BigFloat->new( $ideogram->{set}->min );
						$mb_pos_end   = $ideogram->{set}->max + 1;
					} else {
						# CHROMOSOME RELATIVE
						# the start/end position will be the 0-chrlen for this ideogram
						# i.e. - relative positions will start at 0 
						$mb_pos_start = Math::BigFloat->new(0);
						$mb_pos_end   = $ideogram->{chrlength} - 1;
					}
				} else {
					$mb_pos_start = nearest( $tickdata->{spacing}, $ideogram->{set}->min );
					$mb_pos_end   = nearest( $tickdata->{spacing}, $ideogram->{set}->max );
				}

				printdebug_group("tick","mbpos","start",$mb_pos_start,"end",$mb_pos_end,"spacing",$tickdata->{spacing});

				#
				# compile a list of position for this tick - this is an important step because we will
				# draw positions from this list and not from the tick data structures
				#
				for ( my $mb_pos = $mb_pos_start ; $mb_pos <= $mb_pos_end ; $mb_pos += $tickdata->{spacing} ) {
					push @mb_pos, $mb_pos;
				}
      } elsif ( seek_parameter( "position", $tickdata, $CONF{ticks} ) ) {
				$dims_key = join( $COLON, join( $EMPTY_STR, @{ $tickdata->{_position} } ), $tick_radius );
				@mb_pos = sort {$a <=> $b} @{ $tickdata->{_position} };
      }

      printdebug_group("tick","spacing",$tickdata->{spacing},"positions",@mb_pos);

      # go through every position and draw the tick

      for my $mb_pos (@mb_pos) {
				# if the tick is outside the ideogram, it isn't shown
				if (!$ideogram->{set}->member($mb_pos)) {
					printdebug_group("tick","tick prep",$mb_pos,"outside ideogram");
					next;
				}

				printdebug_group("tick","tick prep",$mb_pos);
	  
				my $pos = $mb_pos;
				my $do_not_draw;
				if ( ! seek_parameter( "force_display", $tickdata, $CONF{ticks} ) ) {
					#
					# Normally, if a tick at a given radius and position has
					# been drawn, it is not drawn again (e.g. 10 Mb ticks are
					# not drawn on top of 100 Mb ticks)
					#
					# However, you can set force_display=yes to insist that a
					# tick be displayed, even if there is another tick at this
					# position from a different spacing (e.g. force display of
					# 10Mb tick even if 100Mb tick at this angular position has
					# been drawn). This is useful only if the radial distance is
					# different for these ticks, or if a mixture of
					# relative/absolute spacing/labeling is being used.
					#
					# The only exception to this is when a tick is used to define
					# an image map. In this case, the process plays out but the
					# actual tick is not drawn (but the loop is used to generate
					# the image map element).
					my $spacing = seek_parameter( "spacing_type", $tickdata, $CONF{ticks} );
					$do_not_draw = $pos_ticked{$tick_radius}{$pos}{$spacing || "default" }++;
					#next if $do_not_draw && ! $tickdata->{url};
				}

				# determine whether this tick is suppressed by 'chromosomes_display_default'
				# and 'chromosomes' parameters, which were parsed using parse_ideogram_filter()
				my $is_suppressed = 0;
				my $tag = $ideogram->{tag};
				#printdumper($tickdata->{_ideogram});
				if ($tickdata->{_ideogram}{show_default} ) {
					# This tick will be shown on all chromosomes by default. Check
					# check whether this position is explicitly excluded.
					if (defined $tickdata->{_ideogram}{filter}{$tag}{hide}
							&&
							$tickdata->{_ideogram}{filter}{$tag}{hide}->member($pos)) {
						$is_suppressed = 1;
					}
				} else {
					# This tick is not shown by default. Check that its combined
					# filter (show-hide) contains this position
					if (defined $tickdata->{_ideogram}{filter}{$tag}{combined}
							&&
							$tickdata->{_ideogram}{filter}{$tag}{combined}->member($pos)) {
						$is_suppressed = 0;
					} else {
						$is_suppressed = 1;
					}
				}
				next if $is_suppressed;

				printdebug_group("tick","tick draw",$mb_pos);
	  
				# TODO - fix/handle this - is it necessary?
				# this is a bit of a hack, but is required because we
				# use 0-indexed positions on the ideograms, but a
				# relative tick mark at 1.0 won't be shown because it
				# will be +1 past the end of the ideogram
				#
				#if (seek_parameter( "spacing_type", $tickdata, $CONF{ticks} ) eq "relative" ) {
				#$pos-- if $mb_pos > $mb_pos[0];
				#}
	  
				# 
				# Turn $pos into a normal string, from Math::BigFloat
				# 

				$pos = $pos->bstr if ref($pos) eq "Math::BigFloat";

				my $tick_angle = getanglepos( $pos, $chr );
				my $this_tick_radius = $tick_radius +
					unit_parse( ( $tickdata->{offset} || 0 ), $ideogram, undef, $ideogram->{thickness} ) +
						unit_parse( ( $CONF{ticks}{offset} || 0 ), $ideogram, undef, $ideogram->{thickness} );

				# calculate the distance across a neighbourhood of 2*pix_sep_n+1 ticks
				# determine from this the average tick-to-tick distance (use multiple ticks for
				# the calculation to cope with local scale adjustments).
				my $tick_color;
				if (defined seek_parameter("tick_separation", $tickdata, $CONF{ticks})
						&& $tickdata->{spacing}) {
					my $pix_sep_n = 2;
					my @pix_sep   = ();
					for my $i ( -$pix_sep_n .. $pix_sep_n-1 ) {
						next if 
							! $ideogram->{set}->member( $pos + $tickdata->{spacing}*$i )
								||
									! $ideogram->{set}->member( $pos + $tickdata->{spacing}*($i+1) );
						my $d = $this_tick_radius*$DEG2RAD*abs(getanglepos($pos+$tickdata->{spacing}*$i,$chr)
																									 -
																									 getanglepos($pos+$tickdata->{spacing}*($i+1),$chr));
						push @pix_sep, $d;
					}
					my $pix_sep = average(@pix_sep) if @pix_sep;
					$tickdata->{pix_sep} = $pix_sep;
					# determine whether to draw the tick based on requirement of
					# minimum tick separation, if defined
					my $min_sep = 
						unit_strip(unit_validate(seek_parameter("tick_separation", $tickdata, $CONF{ticks}),
																		 "ticks/tick/tick_separation",
																		 "p","n"
																		));
					# don't draw this tick - move to next one
					if (defined $pix_sep && defined $min_sep && $pix_sep < $min_sep) {
						$tick_color = "red";
						next;
					}
				}

				# distance to closest ideogram edge
				my $edge_d_start = $this_tick_radius*$DEG2RAD*abs($tick_angle-getanglepos($ideogram->{set}->min,$chr));
				my $edge_d_end   = $this_tick_radius*$DEG2RAD*abs($tick_angle-getanglepos($ideogram->{set}->max,$chr));
				my $edge_d_min   = int( min( $edge_d_start, $edge_d_end ) );

				if (my $edge_d = seek_parameter( "min_distance_to_edge", $tickdata, $CONF{ticks} ) ) {
					$edge_d = unit_strip(unit_validate($edge_d,
																						 "ticks/tick/min_distance_to_edge",
																						 "p","n"
																						));
					next if $edge_d_min < $edge_d;
				}

				printdebug_group(
												 "tick",
												 $chr,
												 "tick_spacing",
												 $tickdata->{spacing},
												 "tick_radius",
												 $this_tick_radius,
												 "tick_angle",
												 sprintf( "%.1f", $tick_angle ),
												 "textangle",
												 sprintf( "%.1f", textangle($tick_angle) ),
												 "d_tick",
												 sprintf("%.3f",$tickdata->{pix_sep}||0),
												 "d_edge",
												 $edge_d_min,
												 "thickness",
												 $DIMS->{tick}{ $tickdata->{dims_key} }{thickness},
												 "size",
												 $DIMS->{tick}{ $tickdata->{dims_key} }{size},
												);
	
				my $start_a = getanglepos( $pos, $chr );

				#
				# register the tick for drawing
				#

				my ( $r0, $r1 );
				if ( match_string(seek_parameter( "orientation", $tickdata, $CONF{ticks}),"in") ) {
					$r0 = $this_tick_radius - $DIMS->{tick}{$dims_key}{size};
					$r1 = $this_tick_radius;
				} else {
					$r0 = $this_tick_radius;
					$r1 = $this_tick_radius + $DIMS->{tick}{$dims_key}{size};
				}
	  
				my $tick_group_entry = {
																do_not_draw => $do_not_draw,
																skip_first_label => seek_parameter("skip_first_label",$tickdata,$CONF{ticks}),
																skip_last_label => seek_parameter("skip_last_label",$tickdata,$CONF{ticks}),
																tickdata    => $tickdata,
																color       => $tick_color,
																r0          => $r0,
																r1          => $r1,
																a           => $tick_angle,
																pos         => $pos,
																coordinates => [getxypos( $tick_angle, $r0 ),
																								getxypos( $tick_angle, $r1 )],
															 };
	  
				#
				# now check whether we want to draw the label, and if
				# so, add the label data to the tick's registration in
				# @ticks
				#

				if ( $CONF{show_tick_labels}
						 && seek_parameter( "show_label", $tickdata, $CONF{ticks} )
						 && $edge_d_min >= $DIMS->{tick}{$dims_key}{min_label_distance_to_edge} ) {
					my $tick_label;
					my $multiplier  = unit_parse(parse_suffixed_number(seek_parameter("multiplier|label_multiplier", $tickdata, $CONF{ticks} ) ) || 1);
					my $rmultiplier = unit_parse(seek_parameter("rmultiplier|label_rmultiplier", $tickdata, $CONF{ticks})) || 1;

					#
					# position, relative to ideogram size, or chromosome size, as requested by
					#
					my $pos_relative;
					if (match_string(seek_parameter("rdivisor|label_rdivisor", $tickdata, $CONF{ticks}), "ideogram" )) {
						$pos_relative = $mb_pos - $ideogram->{set}->min;
						# v0.55 - -1 to include end point
						$pos_relative /= ( $ideogram->{set}->cardinality - 1 );
					} else {
						# v0.55 - -1 to include end point
						$pos_relative = $mb_pos / ( $ideogram->{chrlength} - 1 );
					}
	      
					# do we want a relative label? (e.g. 0.3 instead of 25?)
					my $label_relative = seek_parameter( "label_relative", $tickdata, $CONF{ticks} );
					my $precision = 0.001;
					if ( defined seek_parameter( "mod", $tickdata, $CONF{ticks} ) ) {
						my $mod = unit_parse(seek_parameter( "mod", $tickdata, $CONF{ticks} ) );
						$pos_relative = ( $mb_pos % $mod ) / $mod;
						if ($label_relative) {
							$tick_label = sprintf(seek_parameter("format", $tickdata, $CONF{ticks}),
																		$pos_relative * $rmultiplier);
						} else {
							$tick_label = sprintf(seek_parameter("format", $tickdata, $CONF{ticks}),
																		( $mb_pos % $mod ) * $multiplier );
						}
					} else {
						if ($label_relative) {
							$tick_label = sprintf(seek_parameter("format", $tickdata, $CONF{ticks}) || "%s",
																		$pos_relative * $rmultiplier);
						} else {
							$tick_label = sprintf(seek_parameter("format", $tickdata, $CONF{ticks}) || "%s",
																		$mb_pos * $multiplier);
						}
					}
	      
					if (defined seek_parameter("thousands_sep|thousands_separator", $tickdata,$CONF{ticks})) {
						$tick_label = add_thousands_separator($tick_label);
					}
					if (defined seek_parameter( "suffix", $tickdata, $CONF{ticks} ) ) {
						$tick_label .= seek_parameter( "suffix", $tickdata, $CONF{ticks} );
					}
					if (defined seek_parameter( "prefix", $tickdata, $CONF{ticks} )) {
						$tick_label = seek_parameter( "prefix", $tickdata, $CONF{ticks} ) . $tick_label;
					}
					$tick_label = seek_parameter( "label", $tickdata ) if defined seek_parameter( "label", $tickdata );
					my $tickfontkey     = seek_parameter( "tick_label_font", $tickdata, $CONF{ticks} ) || seek_parameter( "label_font", $tickdata, $CONF{ticks} ) || fetch_conf("default_font") || "default";
					my $tickfont     = $CONF{fonts}{ $tickfontkey };
					my $tickfontfile = locate_file(file => $tickfont, name=>"tick font file" );
					die "Could not find file for font definition [$tickfont] for tick labels." if ! $tickfontfile;
					my $tickfontname = get_font_name_from_file( $tickfontfile );
					my $label_size   = unit_convert(from => unit_validate(seek_parameter("label_size", $tickdata, $CONF{ticks}),
																																"ticks/tick/label_size",
																																qw(p r n)
																															 ),
																					to      => "p",
																					factors => { rp => $DIMS->{tick}{$dims_key}{size} });
					my ( $label_width, $label_height ) = get_label_size(font_file=>$tickfontfile,
																															size=>$label_size,
																															text=>$tick_label);
	      
					my $label_offset = 0;
					if ( my $offset =  seek_parameter( "label_offset", $CONF{ticks} )) {
						$label_offset += unit_parse( $offset, $ideogram, undef, $DIMS->{tick}{$dims_key}{size} );
					}
					if ( my $offset = seek_parameter( "label_offset", $tickdata )) {
						$label_offset += unit_parse( $offset, $ideogram, undef, $DIMS->{tick}{$dims_key}{size} );
					}
	      
					#
					# label offset is no longer cumulative v0.47 Unless
					# individual offset values are applied, distance of tick
					# label to tick radius is based on the longest tick
					# (max_tick_length).  The label_offset parameter is used
					# to adjust label position.
					#
	      
					my $tick_label_radius;
					if (match_string(seek_parameter( "orientation", $tickdata,$CONF{ticks} ), "in")) {
						$tick_label_radius = $tick_group_entry->{r0} - $label_offset - $label_width; # - $max_tick_length
					} else {
						$tick_label_radius = $tick_group_entry->{r1} + $label_offset; # + $max_tick_length
					}
	      
					my $text_parallel = seek_parameter( "label_parallel", $tickdata,$CONF{ticks});
					my $text_no_rotation = seek_parameter( "label_no_rotation", $tickdata,$CONF{ticks});
	      
					my $height_offset = 0;
	      
					my ( $offset_angle, $offset_radius ) =
						textoffset( getanglepos( $pos, $chr ), 
												$tick_label_radius, $label_width, $label_height, 
												$height_offset,
												$text_parallel,
												$text_no_rotation);
	      
					my $text_angle = $DEG2RAD * textangle($tick_angle,$text_parallel,$text_no_rotation);
	      
					# v0.52-1
					# ticks support label_rotate setting. If set to "no" the labels
					# are horizontal. The exact radius offset was defined heuristically,
					# see ~/work/circos/projects/user.debug/labels.norotate
					if (defined_and_zero(seek_parameter( "label_rotate", $tickdata,$CONF{ticks}))
							||
							seek_parameter( "label_tangential", $tickdata,$CONF{ticks})) {
						$offset_angle  = 0;
						$offset_radius = 0;
						$text_angle    = 0;
						( $offset_angle, $offset_radius ) = textoffset( getanglepos( $pos, $chr ),
																														$tick_label_radius, 2*$label_width / length($tick_label), $label_height );
						if ($tick_angle < 90) {
							# 1 at -90
							# 0 at 90
							my $f          = 1-abs($tick_angle - 90)/180;
							$offset_radius = $label_height * $f;
						} else {
							# 1 at 90
							# 0 at 270
							my $f = abs(270 - $tick_angle)/180;
							#$f = 1 - $f if $f > 0.5;
							$offset_radius = $label_height * $f;
							$f = 1 - abs(180 - $tick_angle)/90;
							$offset_radius += ($label_height + $label_width/length($tick_label)/3) * $f;
						}
						#printinfo("radius",$offset_radius,"angle",$tick_angle);
						#$tick_label = int($offset_radius);
					}
	      
					printdebug_group("tick",
													 "ticklabel",
													 $tick_label,
													 "tickpos",
													 $pos,
													 "angle",
													 $tick_angle + $offset_angle,
													 "radius",
													 $tick_label_radius + $offset_radius,
													 "offseta",
													 $offset_angle,
													 "offsetr",
													 $offset_radius,
													 "params",
													 getanglepos( $pos, $chr ),
													 $tick_label_radius,
													 $label_width,
													 $label_height
													);

					$tick_group_entry->{labeldata} = {
																						label_separation => seek_parameter("label_separation", 
																																							 $tickdata, $CONF{ticks}),
																						fontkey  => $tickfontkey,
																						font     => $tickfontfile,
																						fontname => $tickfontname,
																						is_parallel => seek_parameter( "label_parallel", $tickdata,$CONF{ticks} ),
																						is_rotated  => not_defined_or_one(seek_parameter( "label_rotated", $tickdata,$CONF{ticks} )),
																						color    => seek_parameter("tick_label_color|label_color|color", $tickdata,$CONF{ticks}),
																						size   => $label_size,
																						pangle => $tick_angle, # + $offset_angle,
																						radius => $tick_label_radius, # + $offset_radius,
																						angle  => $text_angle,
																						xy     => [getxypos($tick_angle + $offset_angle,
																																$tick_label_radius + $offset_radius)],
																						svgxy => [getxypos($tick_angle + $offset_angle / $CONF{svg_font_scale}, $tick_label_radius )],
																						svgangle => textanglesvg($tick_angle),
																						text     => $tick_label, #. " tick " . int($tick_angle) . " text " . $RAD2DEG * $text_angle,
																						chr      => $chr,
																						start    => $pos,
																						end      => $pos,
																						start_a  => $tick_radius*$tick_angle*$DEG2RAD - $label_height / 2,
																						end_a    => $tick_radius*$tick_angle*$DEG2RAD + $label_height / 2,
																					 };
				}
	
				if ( $CONF{show_grid} ) {
					if ( seek_parameter("grid",$tickdata,$CONF{ticks}) ) {
						my $grid_r1 = unit_parse(seek_parameter("grid_start", $tickdata, $CONF{ticks}, \%CONF),$ideogram);
						my $grid_r2 = unit_parse(seek_parameter("grid_end",   $tickdata, $CONF{ticks}, \%CONF),$ideogram);
						$tick_group_entry->{griddata}{coordinates} = [getxypos( $start_a, $grid_r1 ),
																													getxypos( $start_a, $grid_r2 )];
						$tick_group_entry->{griddata}{r0} = $grid_r1;
						$tick_group_entry->{griddata}{r1} = $grid_r2;
					}
				}
				push @ticks, $tick_group_entry;
				if (defined $tickdata->{spacing} && defined $tick_radius) {
					push @{$tick_groups->{ $tickdata->{spacing} }{ $tick_radius}}, $tick_group_entry;
				}
      }
    }
  }
  
  my ($first_label_idx) = grep( $ticks[$_]{labeldata}, ( 0 .. @ticks - 1 ) );
  my ($last_label_idx)  = grep( $ticks[$_]{labeldata}, reverse( 0 .. @ticks - 1 ) );
  my @tick_idx = sort { $ticks[$a]{pos} <=> $ticks[$b]{pos} } ( 0 .. @ticks - 1 );

  # Determine whether labels of ticks within a spacing group overlap (label_separation)
  # and if so, set the do_not_draw key to suppress their display.
  #
  # This loop also applies tests to the first and last labels of the ideogram
  # to see whether they should be suppressed (skip_first_label, skip_last_label).

  for my $spacing (keys %$tick_groups) {
    for my $radius (keys %{$tick_groups->{$spacing}}) {
      my @tick_with_label = grep($_->{labeldata}, @{$tick_groups->{$spacing}{$radius}});
      next unless @tick_with_label;
      my $label_color;
      if (seek_parameter("skip_first_label",$tick_with_label[0]{tickdata},$CONF{ticks})) {
				$tick_with_label[0]{labeldata}{do_not_draw} = 1;
      }
      if (seek_parameter("skip_last_label",$tick_with_label[-1]{tickdata},$CONF{ticks})) {
				#printdumper($tick_with_label[-1]{tickdata});
				$tick_with_label[-1]{labeldata}{do_not_draw} = 1;
      }
      if (my $sep = $tick_with_label[0]{labeldata}{label_separation}) {
				$sep = unit_strip(unit_validate($sep, "ticks/label_separation", qw(p n)));
				if ($sep) {
					for my $tick_idx (0..@tick_with_label-1) {
						my $prev_check = $tick_idx ? 
							span_distance(@{$tick_with_label[$tick_idx]{labeldata}}{qw(start_a end_a)},
														@{$tick_with_label[$tick_idx-1]{labeldata}}{qw(start_a end_a)})
								: undef;
						my $next_check = $tick_idx < @tick_with_label-1 ?
							span_distance(@{$tick_with_label[$tick_idx]{labeldata}}{qw(start_a end_a)},
														@{$tick_with_label[$tick_idx+1]{labeldata}}{qw(start_a end_a)})
								: undef;
						if ( ( ! defined $prev_check || $prev_check >= $sep)
								 &&
								 ( ! defined $next_check || $next_check >= $sep) ) {
							# tick label is sufficiently far from neighbours
						} else {
							$tick_with_label[$tick_idx]{labeldata}{do_not_draw} = 1;
							$tick_with_label[$tick_idx]{labeldata}{color}       = "red";
						}
					}
				}
      }
    }
  }

  # group url-ticks by r0

  my $tick_idx_map = {};
  for my $tick_idx (@tick_idx) {
    my $tick = $ticks[$tick_idx];
    if ($tick->{tickdata}{url}) {
      my $r0 = $tick->{r0}; 
      my $spacing = $tick->{tickdata}{spacing};
      push @{$tick_idx_map->{ $r0 }{$spacing}}, $tick_idx;
    }
  }
  
  # create image map regions
  
  for my $tick_r0 (sort {$a <=> $b} keys %$tick_idx_map) {
    for my $tick_spacing (sort {$a <=> $b} keys %{$tick_idx_map->{$tick_r0}}) {
      my @tick_idx_map = @{$tick_idx_map->{$tick_r0}{$tick_spacing}};
      for my $tick_idx ( @tick_idx_map ) {
				my $tick     = $ticks[$tick_idx];
				next unless $tick->{r0} == $tick_r0;
				my $tickdata = $tick->{tickdata};
				#printinfo($tick->{pos});
				if ($tickdata->{url}) {
					my @pos_pairs;
					if ($tick_idx == $tick_idx_map[0]) {
						# this is the first tick - check to extend the
						# map element back to the start of the ideogram if this
						# tick is not at the start of the ideogram
						if ($tick->{pos} > $ideogram->{set}->min) {
							my $pos = $tick->{pos};
							my $prev_pos = $ideogram->{set}->min;
							push @pos_pairs,[$prev_pos,$pos];
						}
					} else {
						my $prev_tick = $ticks[$tick_idx-1];
						my $pos = $tick->{pos};
						my $prev_pos = $prev_tick->{pos};
						push @pos_pairs,[$prev_pos,$pos];
					}
					if ($tick_idx == $tick_idx_map[-1]) {
						if ($tick->{pos} < $ideogram->{set}->max) {
							my $prev_pos = $tick->{pos};
							my $pos = $ideogram->{set}->max;
							push @pos_pairs, [$prev_pos,$pos];
						}
					}
					for my $pos_pair (@pos_pairs) {
						my ($prev_pos,$pos) = @$pos_pair;
						my $url = seek_parameter("url",$tickdata,$CONF{ticks});
						$url = format_url(url=>$url,param_path=>[$ideogram,
																										 $tickdata,
																										 $tick,
																										 {start=>$prev_pos,
																											end=>$pos},
																										]);
						my ($r0,$r1);
						if ($tickdata->{map_radius_inner}) {
							$r0 = unit_parse($tickdata->{map_radius_inner},$ideogram);
						} else {
							$r0 = $tick->{r0};
						}
						if ($tickdata->{map_radius_outer}) {
							$r1 = unit_parse($tickdata->{map_radius_outer},$ideogram);
						} elsif ($tickdata->{map_size}) {
							my $map_size = unit_strip(unit_validate(seek_parameter("map_size", $tickdata, $CONF{ticks}),
																											"ticks/tick/map_size","p"
																										 )
																			 );
							$r1 = $r0 + $map_size;
						} else {
							$r1 = $tick->{r1};
						}
						#printinfo("tickmap",$r0,$r1);
						slice(
									image       => $IM,
									start       => $prev_pos,
									end         => $pos,
									chr         => $chr,
									radius_from => $r0,
									radius_to   => $r1,
									edgecolor   => undef,
									edgestroke  => undef,
									fillcolor   => undef,
									mapoptions => { url=>$url },
								 );
					}
				}
      }
    }
  }
  
  # draw the ticks
  for my $tick_idx ( @tick_idx ) {
    
    my $tick     = $ticks[$tick_idx];
    my $tickdata = $tick->{tickdata};
    next if $tick->{do_not_draw};

    draw_line(
							$tick->{coordinates},
							$DIMS->{tick}{ $tickdata->{dims_key} }{thickness} || 1,
							$tick->{color} || seek_parameter( "color", $tickdata, $CONF{ticks} ),
						 );
    if ( $tick->{griddata} ) {
      draw_line(
                $tick->{griddata}{coordinates},
                seek_parameter("grid_thickness", $tickdata, $CONF{ticks}, \%CONF ),
                seek_parameter( "grid_color", $tickdata, $CONF{ticks}, \%CONF )
								|| seek_parameter( "color", $tickdata, $CONF{ticks} ),
							 );
    }
    if ( $tick->{labeldata} ) {
			if ($tick->{labeldata}{do_not_draw}) {
				#printdumper($tickdata);
				next;
			}
			Circos::Text::draw_text(
															text        => $tick->{labeldata}{text},
															font        => $tick->{labeldata}{fontkey},
															size        => $tick->{labeldata}{size},
															color       => $tick->{labeldata}{color},
															angle       => $tick->{labeldata}{pangle},
															radius      => $tick->{labeldata}{radius},
															is_rotated  => $tick->{labeldata}{is_rotated},
															is_parallel => $tick->{labeldata}{is_parallel},
															guides      => fetch_conf("guides","object","tick_label") || fetch_conf("guides","object","all"),
														 );
    }
  }
}

sub label_bounds {
  # return bounds for a text box
  my ($font,$size,$text) = @_;
  my @bounds = GD::Image->stringFT($COLORS->{black},$font,$size,0,0,0,$text);
  return @bounds;
}
# -------------------------------------------------------------------
sub process_tick_structure {
  # do some up-front munging of the tick data structures
  my ( $tick, $ideogram ) = @_;

	$tick = Clone::clone($tick);

  # handle relatively spaced ticks (e.g. every 0.1), or ticks at
  # specific relative position (e.g. at 0.1)

	my $chr = $ideogram->{chr};
	my $ideogram_idx = $ideogram->{idx};

  if ( match_string(seek_parameter( "spacing_type", $tick, $CONF{ticks} ), "relative" )) {
    if (!defined seek_parameter( "rspacing|rposition", $tick, $CONF{ticks} ) ) {
      confess "error processing tick - this tick's spacing_type is ",
				"set to relative, but no rspacing or rposition parameter is set";
    }
    if ( seek_parameter( "rspacing", $tick, $CONF{ticks} ) ) {
      if ( unit_validate(seek_parameter( "rspacing", $tick, $CONF{ticks} ),"ticks/tick/rspacing", qw(n)) ) {
				my $mb_rspacing = Math::BigFloat->new(seek_parameter( "rspacing", $tick, $CONF{ticks} ) );

				#
				# this is important - if the divisor for relative tick
				# spacing is the chromosome, then the spacing is
				# relative to the length of the chromosome (default)
				# otherwise, if the divisor is ideogram
				# (rdivisor=ideogram), the spacing is relative to the
				# ideogram
				#
				if (match_string(seek_parameter( "rdivisor|label_rdivisor", $tick,$CONF{ticks} )),"ideogram" ) {
					# v0.55 - subtracted 1 to include end point
					$tick->{spacing} = $mb_rspacing * ($ideogram->{set}->cardinality-1);
				} else {
					# v0.55 - subtracted 1 to include end point
					$tick->{spacing} = $mb_rspacing * ($ideogram->{chrlength}-1);
				}
				# at this point, spacing does not have to be an integer
				$tick->{spacing} = $tick->{spacing}->bstr;
      }
      #printinfo("spacingdet",$tick->{spacing});
    } elsif ( seek_parameter( "rposition", $tick, $CONF{ticks} ) ) {
      my @rpos =
				map { unit_validate( $_, "ticks/tick/rposition", qw(n) ) }
					split( /,/, seek_parameter( "rposition", $tick, $CONF{ticks} ) );
      @rpos = map { Math::BigFloat->new($_) } @rpos;
      my $divisor;
      if (match_string(seek_parameter("rdivisor|label_rdivisor", $tick, $CONF{ticks}), "ideogram")) {
				$divisor = $ideogram->{set}->cardinality;
      } else {
				$divisor = $ideogram->{chrlength};
      }

      @rpos = map { $_ * $divisor } @rpos;
      $tick->{_position} = \@rpos;
    }
  } else {
    if ( ! $tick->{_processed}{$ideogram_idx} ) {
      if ( seek_parameter( "spacing", $tick, $CONF{ticks} ) ) {
				$tick->{spacing} = unit_convert(from    => unit_validate(parse_suffixed_number(seek_parameter("spacing",$tick,$CONF{ticks})),
																																 "ticks/tick/spacing", qw(u n b)),
																				to      => "b",
																				factors => { ub => $CONF{chromosomes_units} }
																			 );
      } elsif ( defined seek_parameter("position",$tick,$CONF{ticks})) {
				my @pos;
				for my $pos (split( /,/,seek_parameter("position",$tick,$CONF{ticks}))) {
					if ($pos eq "start") {
						$pos = $ideogram->{set}->min;
					} elsif ($pos eq "end") {
						$pos = $ideogram->{set}->max;
					} 
					push @pos, $pos;
				}
				@pos = map { unit_convert( from    => unit_validate( parse_suffixed_number($_), "ticks/tick/position", qw(u n b) ),
																	 to      => "b",
																	 factors => { ub => $CONF{chromosomes_units} }
																 ) } @pos;
				$tick->{_position} = \@pos;
				#$tick->{spacing} = join(",",@pos).$tick->{radius};
      } else {
				confess "error processing tick - this tick's spacing_type is ",
					"set to absolute, but no spacing or position parameter is set";
      }
    }
  }

  if ( !$tick->{_processed}{$ideogram_idx} ) {
    if ( seek_parameter( "grid", $tick, $CONF{ticks} ) ) {
      $tick->{grid_thickness} = unit_strip(
																					 unit_validate(
																												 (
																													seek_parameter( "grid_thickness", $tick, $CONF{ticks} ),
																													"ticks/*/grid_thickness",
																													qw(p)
																												 )
																												)
																					);
    }
  }

  my $dims_key = $tick->{spacing} || join($EMPTY_STR, @{ $tick->{_position} });
  my @tick_radius;

  if ( $tick->{radius} ) {
    @tick_radius =
      map { unit_parse( $_, $ideogram ) } make_list( $tick->{radius} );
  } else {
    @tick_radius =
      map { unit_parse( $_, $ideogram ) } make_list( $CONF{ticks}{radius} );
  }

  for my $tick_radius (@tick_radius) {
    my $dims_key = join( $COLON, $dims_key, $tick_radius );
    $tick->{dims_key} = $dims_key;
		my $size      = seek_parameter( "size", $tick, $CONF{ticks} );
		my $thickness = seek_parameter( "thickness", $tick, $CONF{ticks} );
		fatal_error("configuration","undefined_parameter","size","ticks") if ! defined $size;
		fatal_error("configuration","undefined_parameter","thickness","ticks") if ! defined $thickness;
    if ( !exists $DIMS->{tick}{$dims_key} ) {
			$DIMS->{tick}{$dims_key}{size} = unit_strip(unit_convert(
																															 from => unit_validate(
																																										 seek_parameter( "size", $tick, $CONF{ticks} ),
																																										 "ticks/tick/size", qw(n r p)
																																										),
																															 to => "p",
																															 factors =>
																															 {
																																rp => $DIMS->{ideogram}{ $ideogram->{tag} }{thickness} }
																															));

			$DIMS->{tick}{$dims_key}{thickness} = unit_strip(unit_convert(
																																		from => unit_validate(
																																													seek_parameter( "thickness", $tick, $CONF{ticks} ),
																																													"ticks/tick/thickness", qw(n r p)
																																												 ),
																																		to      => "p",
																																		factors => { rp => $DIMS->{tick}{ $tick->{spacing} || $tick->{_position} }{size} }
																																	 ));

			$tick->{thickness} = $DIMS->{tick}{$dims_key}{thickness};

			if (seek_parameter("show_label", $tick, $CONF{ticks})) {
				my $label_size = seek_parameter("label_size", $tick, $CONF{ticks});
				fatal_error("configuration","undefined_parameter","label_size","ticks") if ! defined $label_size;
			}

			if (defined seek_parameter("min_label_distance_to_edge", $tick, $CONF{ticks})) {
				$DIMS->{tick}{$dims_key}{min_label_distance_to_edge} 
					= unit_strip(unit_validate(
																		 seek_parameter(
																										"min_label_distance_to_edge", $tick, $CONF{ticks}
																									 ),
																		 "ticks/tick/min_label_distance_to_edge",
																		 "p"
																		)
											);
				$tick->{min_label_distance_to_edge} = $DIMS->{tick}{$dims_key}{min_label_distance_to_edge} 
			} else {
				$DIMS->{tick}{$dims_key}{min_label_distance_to_edge} = 0;
			}
    }
  }

  $tick->{size} = unit_strip(unit_convert(
																					from => unit_validate(
																																seek_parameter( "size", $tick, $CONF{ticks} ),
																																"ticks/tick/size", qw(n r p)
																															 ),
																					to => "p",
																					factors =>
																					{
																					 rp => $DIMS->{ideogram}{ $ideogram->{tag} }{thickness} }
																				 ));

  $tick->{_radius} = \@tick_radius;
  $tick->{_processed}{$ideogram_idx}++;
	return $tick;
}

# -------------------------------------------------------------------
sub ideogram_spacing_helper {
  # given two adjacent ideograms, determine the spacing between them
  # return spacing in bases
  my $value = shift;
  unit_validate( $value, "ideogram/spacing/pairwise", qw(u r) );
  my $spacing;
  if ( unit_fetch( $value, "ideogram/spacing/pairwise" ) eq "u" ) {
    $spacing = unit_strip($value) * $CONF{chromosomes_units};
  } elsif ( unit_fetch( $value, "ideogram/spacing/pairwise" ) eq "r" ) {
    $spacing = unit_strip($value) * $DIMS->{ideogram}{spacing}{default};
  }
  return $spacing;
}

# -------------------------------------------------------------------
sub ideogram_spacing {
  my ( $id1,  $id2, $cache ) = @_;
  my ( $chr1, $chr2 ) = ( $id1->{chr}, $id2->{chr} );
  my ( $tag1, $tag2 ) = ( $id1->{tag}, $id2->{tag} );

  if (exists $DIMS->{ideogram}{spacing}{ sprintf( "%d %d", $id1->{idx}, $id2->{idx} ) } ) {
		return $DIMS->{ideogram}{spacing}{ sprintf( "%d %d", $id1->{idx}, $id2->{idx} ) };
	}

	if (! exists $DIMS->{ideogram}{spacing}{default}) {
		$DIMS->{ideogram}{spacing}{default} = unit_convert(
																											 from    => $CONF{ideogram}{spacing}{default},
																											 to      => "b",
																											 factors => {
																																	 ub => $CONF{chromosomes_units},
																																	 rb => $GSIZE_NOSCALE
																																	}
																											);
		printdebug_group("ideogram","default spacing",$DIMS->{ideogram}{spacing}{default});
	}

  my $spacing = $DIMS->{ideogram}{spacing}{default};
  my @keys    = ( $chr1, $chr2, $tag1, $tag2 );
  my $spacing_found;

	my $leaf = $CONF{ideogram}{spacing};

	# chr1+delim+chr2
 KI1:
  for my $ki (0..@keys-1) {
		for my $kj (0..@keys-1) {
			next if $kj == $ki || $keys[$ki] eq $keys[$kj];
			for my $delim ($SPACE,$SEMICOLON,$COMMA) {
				my $str = join( $delim, @keys[$ki,$kj] );
				if (exists $leaf->{pairwise}{$str}) {
					$spacing       = ideogram_spacing_helper($leaf->{pairwise}{$str}{spacing});
					$spacing_found = 1;
					last KI1;
				} else {
					for my $str (keys %{$leaf->{pairwise}}) {
						my ($str1,$str2) = split($delim,$str);
						my ($rx1,$rx2)   = (parse_as_rx($str1),parse_as_rx($str2));
						if (defined $rx1 && defined $rx2) {
							if ($keys[$ki] =~ $rx1 && $keys[$kj] =~ $rx2) {
								$spacing       = ideogram_spacing_helper($leaf->{pairwise}{$str}{spacing});
								$spacing_found = 1;
								#printinfo($keys[$ki],$keys[$kj],$spacing,"rx");
								last KI1;
							}
						}
					}
				}
			}
		}
	}

	if ( !$spacing_found ) {
	KI2:
		for my $ki ( 0..@keys-1 ) {
      my $str = $keys[$ki];
      if ( exists $leaf->{pairwise}{$str} ) {
				$spacing = ideogram_spacing_helper($leaf->{pairwise}{$str}{spacing});
				$spacing_found = 1;
				last KI2;
			} else {
				for my $str (keys %{$leaf->{pairwise}}) {
					next if $str =~ /\s/;
					my $rx = parse_as_rx($str);
					if (defined $rx) {
						if ($keys[$ki] =~ /$rx/) {
							$spacing       = ideogram_spacing_helper($leaf->{pairwise}{$str}{spacing});
							$spacing_found = 1;
							last KI2;
						}
					}
				}
			}
    }
  }

  if ( !$spacing_found ) {
    if ( $chr1 eq $chr2 ) {
      my $value = $leaf->{break} || $leaf->{default};
      $spacing = ideogram_spacing_helper($value);
    }
  }

  if ( $id1->{break}{end} && $chr1 ne $chr2 ) {
    my $value = $leaf->{break} || $leaf->{default};
    $spacing += ideogram_spacing_helper($value);
    $id1->{break}{end} = $value;
    $DIMS->{ideogram}{break}{ $id1->{chr} }{end} = $value;
  }

  if ( $id2->{break}{start} && $chr1 ne $chr2 ) {
    my $value = $leaf->{break} || $leaf->{default};
    $spacing += ideogram_spacing_helper($value);
    $id2->{break}{start} = $value;
    $DIMS->{ideogram}{break}{ $id2->{chr} }{start} = $value;
  }

	my $scale_type = fetch_conf("relative_scale_spacing") || "min";
	my $scale_multiplier;
	if ($scale_type =~ /$RE{num}{real}/) {
		$scale_multiplier = $scale_type;
		fatal_error("ideogram","bad_spacing_scale",$scale_type) if $scale_type <= 0;
	} else {
		my @ids     = $scale_type =~ /adj/ ? ($id1,$id2) : @IDEOGRAMS;
		my @covers  = map { @{$_->{covers}}} @ids;
		my @scales  = map { $_->{scale} } @covers;
		#printinfo(@scales);
		if ($scale_type =~ /max/) {
			$scale_multiplier = max(@scales);
		} elsif ($scale_type =~ /min/) {
			$scale_multiplier = min(@scales);
		} elsif ($scale_type =~ /mode/) {
			my %count;
			map { $count{$_}++ } @scales;
			my $max_count = max(values %count);
			map { delete $count{$_} if $count{$_} < $max_count } keys %count;
			$scale_multiplier = average( keys %count );
		} elsif ($scale_type =~ /average|avg/) {
			$scale_multiplier = average(@scales);
		} else {
			fatal_error("ideogram","bad_spacing_scale",$scale_type);
		}
	}

	#printinfo($scale_multiplier);
	$spacing *= $scale_multiplier;
	
	if (not_defined_or_one($cache)) {
		$DIMS->{ideogram}{spacing}{ sprintf( "%d %d", $id1->{idx}, $id2->{idx} ) } = $spacing;
		$DIMS->{ideogram}{spacing}{ sprintf( "%d %d", $id2->{idx}, $id1->{idx} ) } = $spacing;
	}
  return $spacing;
}

################################################################
# parse ideogram order from parameter or file
sub read_chromosomes_order {
	my @chrorder;
	# construct a list of ordered chromosomes, from one of
	# - 'chromosomes_order' parameter
	# - 'chromosomes_order_file' input file
	# - native order from karyotype
	if ( $CONF{chromosomes_order} ) {
		@chrorder = @ { Circos::Configuration::make_parameter_list_array( $CONF{chromosomes_order} ) };
	} elsif ( $CONF{chromosomes_order_file} ) {
		$CONF{chromosomes_order_file} = locate_file( $CONF{chromosomes_order_file}, name=>"chromosome order file" );
		open(CHRORDER, $CONF{chromosomes_order_file}) 
	    || fatal_error("io","cannot_read",$CONF{chromosomes_order_file},"chromosome order",$!);
		while (<CHRORDER>) {
	    chomp;
	    my ($tag) = split;
	    push( @chrorder, $tag );
		}
		close(CHRORDER);
	} else {
		@chrorder = ($CARAT, 
								 sort { $KARYOTYPE->{$a}{chr}{display_order} <=> $KARYOTYPE->{$b}{chr}{display_order} } 
								 keys %$KARYOTYPE
								);
	}

	my %seen_tag;
	my @tags = map { $_->{tag} =~ /__/ ? $_->{chr} : $_->{tag} } @IDEOGRAMS;
	my $n = 0;
	for my $tag (@chrorder) {
		my $tag_found = grep( $_ eq $tag, @tags );
		if ($tag_found) {
	    if ( $seen_tag{$tag}++ ) {
				fatal_error("ideogram","multiple_tag",$tag);
	    }
		} elsif ( $tag ne $PIPE && $tag ne $DOLLAR && $tag ne $CARAT && $tag ne $DASH
							&& ! grep($_->{tag} eq $tag, @IDEOGRAMS)
							&& ! grep($_ eq $tag, keys %$KARYOTYPE) ) {
	    fatal_error("ideogram","orphan_tag",$tag);
		}
		$n++ if $tag_found || $tag eq $DASH;
	}
	if ( $n > @IDEOGRAMS ) {
		my $ni = @IDEOGRAMS;
		printwarning("You have more tags [$n] in the chromosomes_order field than ideograms [$ni]. Circos may not be able to correctly order the display");
	}
	return @chrorder;
}

################################################################
# chromosomes and regions can have a scale multiplier to adjust
# the size of the ideogram in the image
#
# scale is keyed by the chromosome/region tag and applied
# in the order of appearance in the scale string
#
sub register_chromosomes_scale {
	my $scale_str = fetch_conf("chromosomes_scale") || fetch_conf("chromosome_scale");
	return unless $scale_str;
	my $scale_table = Circos::Configuration::make_parameter_list_hash($scale_str);
	for my $is_rx (1,0) {
		for my $chr_tag (keys %$scale_table) {
	    my $rx = parse_as_rx($chr_tag);
	    if ($is_rx) {
				# must be a regular expression
				next unless $rx;
	    } else {
				# cannot be a regular expression
				next if $rx;
	    }
	    my $chr_scale = $scale_table->{$chr_tag};
			my @ids_matching = grep(match_string($_->{tag}, $rx || $chr_tag), @IDEOGRAMS);
			for my $ideogram (@ids_matching) {
				my $scale;
				if ($chr_scale =~ /(.+)r$/) {
					$scale = $1;
					$ideogram->{scale_relative} = $scale;
				} elsif ($chr_scale =~ /(.+)rn$/) {
					# relative scale, normalized by number of matching ideograms
					$scale                      = $1 / @ids_matching;
					$ideogram->{scale_relative} = $scale;
				} else {
					$scale = $chr_scale;
					$ideogram->{scale} = $chr_scale;
				}
				printdebug_group("scale",$chr_tag,"rx",$is_rx,"tag",$ideogram->{tag},"scale",$scale);
	    }
		}
	}
}

################################################################
# chromosomes and regions may be reversed
#
sub register_chromosomes_direction {
	#my $chrs = Circos::Configuration::make_parameter_list_array($CONF{chromosomes_reverse});
	#for my $pair (@$chrs) {
	#my ( $tag, $scale ) = split( /:/, $pair );
	#for my $ideogram (@IDEOGRAMS) {
	#$ideogram->{reverse} = 1 if $ideogram->{tag} eq $tag;
	#}
	#    }
	my $direction_str   = fetch_conf("chromosomes_reverse") || fetch_conf("chromosome_reverse");
	return unless $direction_str;
	my $direction_table = Circos::Configuration::make_parameter_list_hash($direction_str);
	for my $is_rx (1,0) {
		for my $chr_tag (keys %$direction_table) {
	    my $rx = parse_as_rx($chr_tag);
	    if ($is_rx) {
				# must be a regular expression
				next unless $rx;
	    } else {
				# cannot be a regular expression
				next if $rx;
	    }
	    for my $ideogram (@IDEOGRAMS) {
				my $match = match_string($ideogram->{tag},$rx || $chr_tag);
				if ($chr_tag =~ /^-/) {
					$ideogram->{reverse} = 0 if $match;
					printdebug_group("ideogram",$rx,"normal orientation",$ideogram->{tag}) if $match;
				} else {
					$ideogram->{reverse} = 1 if $match;
					printdebug_group("ideogram",$rx,"reverse orientation",$ideogram->{tag}) if $match;
				}

	    }
		}
	}
}

# -------------------------------------------------------------------
sub register_chromosomes_radius {
	my $chromosomes_radius = shift;
  my @chrs = split( /[;,]/, $chromosomes_radius );
	
  # Each ideogram can be at a different radius, but for now register the
  # default position for ideograms.
	
  $DIMS->{ideogram}{default}{radius} = unit_parse(unit_convert(
																															 from =>
																															 unit_validate( $CONF{ideogram}{radius}, "ideogram/radius", qw(r p) ),
																															 to      => "p",
																															 factors => { rp => $DIMS->{image}{radius} }
																															));
	
  $DIMS->{ideogram}{default}{thickness} = unit_convert(
																											 from => 
																											 unit_validate($CONF{ideogram}{thickness},"ideogram/thickness", qw(r p) ),
																											 to      => "p",
																											 factors => { rp => $DIMS->{image}{radius} }
																											);
	
  $DIMS->{ideogram}{default}{radius_inner}  = $DIMS->{ideogram}{default}{radius} - $DIMS->{ideogram}{default}{thickness};
  $DIMS->{ideogram}{default}{radius_middle} = $DIMS->{ideogram}{default}{radius} - $DIMS->{ideogram}{default}{thickness}/2;
  $DIMS->{ideogram}{default}{radius_outer}  = $DIMS->{ideogram}{default}{radius};
  $DIMS->{ideogram}{default}{label}{radius} = unit_parse( $CONF{ideogram}{label_radius} );

  # legacy
  $DIMS->{ideogram}{thickness} = $DIMS->{ideogram}{default}{thickness};
  # end legacy

	# support for rx in chromosomes_radius
	my $radius_conf_str = fetch_conf("chromosomes_radius") || fetch_conf("chromosome_radius");
	if ($radius_conf_str) {
		my @radius_list = @{Circos::Configuration::make_parameter_list_array($radius_conf_str)};
		for my $is_rx (1,0) {
			for my $radius_pair (@radius_list) {
				my ($key,$value) = Circos::Configuration::parse_var_value($radius_pair);
				my $radius = unit_convert(from => unit_validate( $value, "ideogram/radius", qw(r p) ),
																	to   => "p",
																	factors => { rp => $DIMS->{ideogram}{default}{radius} }
																 );
				my $rx           = parse_as_rx($key);
				if ($is_rx) {
					next unless $rx;
				} else {
					next if $rx;
				}
				for my $ideogram (@IDEOGRAMS) {
					my $tag = $ideogram->{tag};
					my $chr = $ideogram->{chr};
					my $match = match_string( $tag,$rx||$key ) || match_string( $chr,$rx||$key );
					if ($match) {
						$DIMS->{ideogram}{$tag}{radius} = $radius;
						$ideogram->{radius}        = $DIMS->{ideogram}{$tag}{radius};
						$ideogram->{radius_outer}  = $DIMS->{ideogram}{$tag}{radius};
						$ideogram->{radius_middle} = $DIMS->{ideogram}{$tag}{radius} - $DIMS->{ideogram}{default}{thickness}/2;
						$ideogram->{radius_inner}  = $DIMS->{ideogram}{$tag}{radius} - $DIMS->{ideogram}{default}{thickness};
					}
				}
			}
		}
	}

	# PAIR:
	#  for my $pair (@chrs) {
	#    my ( $tag, $radius ) = Circos::Configuration::parse_var_value($pair);
	#    $DIMS->{ideogram}{$tag}{radius} = unit_convert(
	#																									 from => unit_validate( $radius, "ideogram/radius", qw(r p) ),
	#																									 to   => "p",
	#																									 factors => { rp => $DIMS->{ideogram}{default}{radius} }
	#																									);
	#  for my $ideogram (@IDEOGRAMS) {
	#      if ( $ideogram->{tag} eq $tag || $ideogram->{chr} eq $tag ) {
	#				$ideogram->{radius}        = $DIMS->{ideogram}{$tag}{radius};
	#				$ideogram->{radius_outer}  = $DIMS->{ideogram}{$tag}{radius};
	#				$ideogram->{radius_middle} = $DIMS->{ideogram}{$tag}{radius} - $DIMS->{ideogram}{default}{thickness}/2;
	#				$ideogram->{radius_inner}  = $DIMS->{ideogram}{$tag}{radius} - $DIMS->{ideogram}{default}{thickness};
	#    }
	#   }
	# }

  #
  # By default, each ideogram's radial position is the default one,
  # set within the <ideogram> block by radius and thickness. Apply
  # this default setting if a custom radius has not been defined.
  #
  for my $ideogram (@IDEOGRAMS) {
		#printinfo( "registering tag", $ideogram->{tag} );

    $ideogram->{radius}        ||= $DIMS->{ideogram}{default}{radius};
    $ideogram->{radius_outer}  ||= $DIMS->{ideogram}{default}{radius_outer};
    $ideogram->{radius_inner}  ||= $DIMS->{ideogram}{default}{radius_inner};
    $ideogram->{radius_middle} ||= $DIMS->{ideogram}{default}{radius_middle};
    $ideogram->{thickness}     ||= $DIMS->{ideogram}{default}{thickness};

    $DIMS->{ideogram}{ $ideogram->{tag} }{radius}        ||= $ideogram->{radius};
    $DIMS->{ideogram}{ $ideogram->{tag} }{radius_inner}  ||= $ideogram->{radius_inner};
    $DIMS->{ideogram}{ $ideogram->{tag} }{radius_middle} ||= $ideogram->{radius_middle};
    $DIMS->{ideogram}{ $ideogram->{tag} }{radius_outer}  ||= $ideogram->{radius_outer};
    $DIMS->{ideogram}{ $ideogram->{tag} }{thickness}     ||= $ideogram->{thickness};
    $DIMS->{ideogram}{ $ideogram->{tag} }{label}{radius} ||= unit_parse( $CONF{ideogram}{label_radius}, $ideogram );
  }
}

# -------------------------------------------------------------------
sub get_ideogram_radius {
  my $ideogram = shift;
	my $r;
  if ( defined $DIMS->{ideogram}{ $ideogram->{tag} } ) {
    $r = $DIMS->{ideogram}{ $ideogram->{tag} }{radius};
  } else {
    $r = $DIMS->{ideogram}{default}{radius};
  }
	$r = unit_parse( $r, $ideogram );
	return $r;
}

################################################################
#
sub create_ideogram_set {
  my @chrs = @_;
  my $tag_count;
  for my $chr (@chrs) {
		next unless $chr->{accept};
		my $chrname = $chr->{chr};
		my $region_candidate =  $chr->{set}->intersect($KARYOTYPE->{$chrname}{chr}{display_region}{accept} );
		next unless $region_candidate->cardinality;
		$KARYOTYPE->{ $chrname }{chr}{ideogram} = 1;
		for my $set ( $region_candidate->sets ) {
			if ( $chr->{tag} eq "default" ) {
	      fatal_error("ideogram","reserved_tag","default");
			}
			################################################################
			# v0.52
			# chromosomes that don't have an explicit tag, receive an automatically
			# generated tag if autotag=yes. 
			
			my $autotag = sprintf("%s__%d",$chr->{chr},$tag_count->{ $chr->{chr} }++);
			my $idtag;
			if ($chr->{tag} eq $chr->{chr} && $CONF{autotag}) {
	      $idtag = $autotag;
			} else {
	      $idtag = $chr->{tag};
			}

			my $ideogram = {
											chr       => $chr->{chr},
											chrlength => $KARYOTYPE->{ $chrname }{chr}{size},
											label     => $KARYOTYPE->{ $chrname }{chr}{label},
											param     => $KARYOTYPE->{ $chrname }{chr}{options},
											scale     => 1,
											reverse   => 0,
											tag       => $idtag,
											idx       => int(@IDEOGRAMS),
											set       => $set,
											start     => $set->min,
											end       => $set->max,
											size      => $set->cardinality,
										 };
			if ($ideogram->{tag} eq $ideogram->{chr}) {
	      $ideogram->{chr_with_tag} = $ideogram->{label};
			} else {
	      $ideogram->{chr_with_tag} = $ideogram->{label}.$ideogram->{tag};
			}

			my $color_conf_str = fetch_conf("chromosomes_color") || fetch_conf("chromosome_color");
	    if ($color_conf_str) {
				my @color_list = @{Circos::Configuration::make_parameter_list_array($color_conf_str)};
				for my $is_rx (1,0) {
					for my $color_pair (@color_list) {
						my ($key,$value) = Circos::Configuration::parse_var_value($color_pair);
						my $rx           = parse_as_rx($key);
						if ($is_rx) {
							next unless $rx;
						} else {
							next if $rx;
						}
						my $match = match_string($idtag,$rx||$key);
						if ($match) {
						    my $color_name;
						    if ($value =~ /[()]/) {
							$color_name = lc Circos::Expression::eval_expression({data=>[$ideogram]},
													     $value,
													     undef,
													     -noquote=>1);
						    } else {
							$color_name = lc $value;
						    }
						    $ideogram->{color} = strip_quotes($color_name);
						}
					}
				}
	    }
			push @IDEOGRAMS, $ideogram;
		}
  }
  
  ################################################################
  # v0.52 This section is deprecated (I think). 
  # RUN TESTS TO ENSURE THAT THIS LOOP IS NOT REQUIRED.
  #
  # Scan for chromosome entries that have accept regions but have not been
  # added to @IDEOGRAMS. 
  for my $chrname ( sort keys %$KARYOTYPE ) {
    my $chr = $KARYOTYPE->{$chrname}{chr};
    next if defined $chr->{ideogram};
    next unless $chr->{display_region}{accept}->cardinality;
    $chr->{ideogram} = 1;
    my $autotag = sprintf("%s__%d",$chr->{chr},$tag_count->{ $chrname }++);
    my $idtag;
    if ($chr->{tag} eq $chr->{chr} && $CONF{autotag}) {
      $idtag = $autotag;
    } else {
      $idtag = $chr->{tag};
    }
    for my $set ($chr->{display_region}{accept}->sets) {
      if ( $chr eq "default" ) {
				fatal_error("ideogram","reserved_chr","default");
      }
      push @IDEOGRAMS, {
												chr       => $chrname,
												label     => $chr->{label},
												chrlength => $chr->{size},
												label     => $chr->{label},
												param     => $chr->{options},
												scale     => 1,
												reverse   => 0,
												tag   => $idtag,
												idx   => int(@IDEOGRAMS),
												set   => $set,
											 };
    }
  }
  return sort { $a->{idx} <=> $b->{idx} } @IDEOGRAMS;
}

################################################################
# Ensure that each chromosome in the karyotype has a display_region
# field.
#
# Any reject/accept regions defined in parse_chromosomes() are checked
# against the size of the chromosome and intersected with the extent
# of the chromosome.
#
# This function modifies the {CHR}{chr}{display_region} hash by 
# adjusting 'accept' and 'reject' keys.
#
sub refine_display_regions {
  for my $chr ( sort {$KARYOTYPE->{$a}{chr}{display_order} <=> $KARYOTYPE->{$b}{chr}{display_order}} keys %$KARYOTYPE ) {
    $KARYOTYPE->{$chr}{chr}{display_region} ||= {};

    my $region = $KARYOTYPE->{$chr}{chr}{display_region};

    if ( $region->{reject} && $region->{accept} ) {
      $region->{reject} = $region->{reject}->intersect( $KARYOTYPE->{$chr}{chr}{set} );
      $region->{accept} = $region->{accept}->intersect( $KARYOTYPE->{$chr}{chr}{set} )->diff( $region->{reject} );
    } elsif ( $region->{reject} ) {
      $region->{reject} = $region->{reject}->intersect( $KARYOTYPE->{$chr}{chr}{set} );
      $region->{accept} = $KARYOTYPE->{$chr}{chr}{set}->diff( $region->{reject} );
    } elsif ( $region->{accept} ) {
      $region->{accept} = $region->{accept}->intersect( $KARYOTYPE->{$chr}{chr}{set} );
      $region->{reject} = Set::IntSpan->new();
    } else {
      if ( $CONF{chromosomes_display_default} ) {
				$region->{accept} = $KARYOTYPE->{$chr}{chr}{set};
				$region->{reject} = Set::IntSpan->new();
      } else {
				$region->{reject} = Set::IntSpan->new();
				$region->{accept} = Set::IntSpan->new();
      }
    }
    
    $KARYOTYPE->{$chr}{chr}{display} = $region->{accept}->cardinality ? 1 : 0;
		
    printdebug_group("karyotype",
										 "chromosome ranges",      $chr,
										 "display",                $KARYOTYPE->{$chr}{chr}{display},
										 "region_display",         $region->{accept}->run_list,
										 "region_explicit_reject", $region->{reject}->run_list
										);
  }
}

sub merge_ideogram_filters {
  # Merges multiple ideogram filters into a single filter by taking
  # the union of all sets for a given type (show, hide) and
  # ideogram. This function also creates a new type (combined) which 
  # is show->diff(hide)
  my @filters = @_;
  my $merged_filter;
  my %chrs;
  for my $filter (@filters) {
    for my $chr (keys %$filter) {
      for my $type (keys %{$filter->{$chr}}) {
				if ($merged_filter->{$chr}{$type}) {
					$merged_filter->{$chr}{$type}->U( $filter->{$chr}{$type} );
				} else {
					$merged_filter->{$chr}{$type} = $filter->{$chr}{$type};
				}
      }
    }
  }
  for my $chr (keys %$merged_filter) {
    if (exists $merged_filter->{$chr}{show}) {
      if (exists $merged_filter->{$chr}{hide}) {
				$merged_filter->{$chr}{combined} = $merged_filter->{$chr}{show}->diff($merged_filter->{$chr}{hide});
      } else {
				$merged_filter->{$chr}{combined} = $merged_filter->{$chr}{show};
      }
    } else {
      if (exists $merged_filter->{$chr}{hide}) {
				$merged_filter->{$chr}{combined} = Set::IntSpan->new("(-)")->diff($merged_filter->{$chr}{hide});
      } else {
				$merged_filter->{$chr}{combined} = Set::IntSpan->new("(-)");
      }
    }
  }
  return $merged_filter;
}

sub parse_ideogram_filter {
  # Parse a tick's ideogram filter. The format of this filter string is the same
  # as for the chromosomes parameter. The filter data structure defines
  # an ideogram (and its range) as either shown or hidden
  #
  # $filter->{CHR}{hide} = RANGE
  # $filter->{CHR}{show} = RANGE
  #
  # TODO There is some duplication between this function and parse_chromosomes(). 
  # Common functionality should be centralized.

  my $filter_string = shift;
  my $filter = {};
  return $filter if ! defined $filter_string;

  for my $chr (split(/;/,$filter_string)) {
    my ($suppress,$tag,$runlist) = $chr =~ /(-)?([^:]+):?(.*)/;
    if ( $CONF{chromosomes_units} ) {
      $runlist =~ s/([\.\d]+)/$1*$CONF{chromosomes_units}/eg;
    }
    my $is_suppressed = $suppress ? 1 : 0;
    my $set = Set::IntSpan->new( $runlist || "(-)" );
    if ($is_suppressed) {
      $filter->{$tag}{hide} = $set;
    } else {
      $filter->{$tag}{show} = $set;
    }
  }
  return $filter;
}

# -------------------------------------------------------------------
sub relradius {
  my $radius = shift;
  if ( $radius < 2 ) {
    return $radius * $DIMS->{image}{radius};
  } else {
    return $radius;
  }
}


# -------------------------------------------------------------------
sub arc_points {
	$CONF{debug_validate} && validate(
																		@_,
																		{
																		 start  => 1,
																		 end    => 1,
																		 chr    => 1,
																		 radius => 1,
																		}
																	 );

  my %params = @_;
  my ( $start_a, $end_a ) = (
														 getanglepos( $params{start}, $params{chr} ),
														 getanglepos( $params{end},   $params{chr} )
														);
  my $step_a = $start_a < $end_a ? $CONF{anglestep} : -$CONF{anglestep};

  my ( $x_prev, $y_prev, @points, @angles );
  if ( $start_a < $end_a ) {
    for ( my $angle = $start_a ; $angle <= $end_a ; $angle += $step_a ) {
      push @angles, $angle;
    }
  } else {
    for ( my $angle = $start_a ; $angle >= $end_a ; $angle += $step_a ) {
      push @angles, $angle;
    }
  }

  for my $angle (@angles) {
    my ( $x, $y ) = getxypos( $angle, $params{radius} );

    my $dx = $x - defined $x_prev ? $x_prev : 0;
    my $dy = $y - defined $y_prev ? $y_prev : 0;
    my $d = sqrt( ($dx||0)**2 + ($dy||0)**2 );

    next if defined $x_prev && $d < $CONF{minslicestep};

    ( $x_prev, $y_prev ) = ( $x, $y );

    push @points, [ $x, $y ];

    last if ( $start_a == $end_a );
  }

  push @points, [ getxypos( $end_a, $params{radius} ) ];

  return @points;
}

# -------------------------------------------------------------------
sub bezier_middle {
  my @control_points = @_;
  my $bezier         = Math::Bezier->new(@control_points);
  return $bezier->point(0.5);
}

# -------------------------------------------------------------------
sub bezier_points {
  #
  # given a list of control points for a bezier curve, return
  # $CONF{beziersamples}
  # points on the curve as a list
  #
  # ( [x1,y1], [x2,y2], ... )
  #
  my @control_points = @_;
  my $bezier         = Math::Bezier->new(@control_points);
  my @points         = $bezier->curve( $CONF{beziersamples} );
  my @bezier_points;
  while (@points) {
    push @bezier_points, [ splice( @points, 0, 2 ) ];
  }
  return @bezier_points;
}

# -------------------------------------------------------------------
sub bezier_control_points {
	$CONF{debug_validate} && validate(
																		@_,
																		{
																		 pos1                  => 1,
																		 chr1                  => 1,
																		 radius1               => 1,
																		 pos2                  => 1,
																		 chr2                  => 1,
																		 radius2               => 1,
																		 bezier_radius         => 1,
																		 perturb_bezier_radius => 0,

																		 bezier_radius_purity         => 0,
																		 perturb_bezier_radius_purity => 0,

																		 perturb       => 0,
																		 crest         => 0,
																		 perturb_crest => 0,
																		}
																	 );
  my %params = @_;

  my $perturb = $params{perturb};
  $params{bezier_radius} = unit_parse( $params{bezier_radius} );

	confess if ! defined $params{bezier_radius};

  my ( $a1, $a2 ) = (
										 getanglepos( $params{pos1}, $params{chr1} ),
										 getanglepos( $params{pos2}, $params{chr2} )
										);
  my ( $x1, $y1 ) = getxypos( $a1, $params{radius1} );
  my ( $x2, $y2 ) = getxypos( $a2, $params{radius2} );
  my $bisecting_radius =
    sqrt( ( ( $x1 + $x2 ) / 2 - $DIMS->{image}{width} / 2 )**2 +
          ( ( $y1 + $y2 ) / 2 - $DIMS->{image}{height} / 2 )**2 );

  my $middleangle = abs( $a2 - $a1 ) > 180
    ? ( $a1 + $a2 + 360 ) / 2 - 360
      : ( $a2 + $a1 ) / 2;

  if ( defined $params{bezier_radius_purity} ) {
    my $k = $params{bezier_radius_purity};
    $k = $perturb ? perturb_value( $k, $params{perturb_bezier_radius_purity} ) : $k;
    my $x = abs( 1 - $k ) * abs( $params{bezier_radius} - $bisecting_radius );

    if ( $params{bezier_radius} > $bisecting_radius ) {
      if ( $k > 1 ) {
				$params{bezier_radius} = $params{bezier_radius} + $x;
      } else {
				$params{bezier_radius} = $params{bezier_radius} - $x;
      }
    } else {
      if ( $k > 1 ) {
				$params{bezier_radius} = $params{bezier_radius} - $x;
      } else {
				$params{bezier_radius} = $params{bezier_radius} + $x;
      }
    }
  }

  $params{bezier_radius} = $perturb ? perturb_value( $params{bezier_radius}, $params{perturb_bezier_radius} ) : $params{bezier_radius};

  my ( $x3, $y3 ) = getxypos( $middleangle, $params{bezier_radius} );

  # add intermediate points if crests are requested
  my @controlpoints = ( $x1, $y1, $x3, $y3, $x2, $y2 );

  if ( defined $params{crest} ) {
		$params{crest} = $perturb ? perturb_value( $params{crest}, $params{perturb_crest} ) : $params{crest};
    my $crest_radius;

    if ( $params{radius1} > $params{bezier_radius} ) {
      $crest_radius =
				$params{radius1} -
					abs( $params{radius1} - $params{bezier_radius} ) * $params{crest};
    } else {
      $crest_radius =
				$params{radius1} +
					abs( $params{radius1} - $params{bezier_radius} ) * $params{crest};
    }

    splice( @controlpoints, 2, 0, getxypos( $a1, $crest_radius ) );

    if ( $params{radius2} > $params{bezier_radius} ) {
      $crest_radius =
				$params{radius2} -
					abs( $params{radius2} - $params{bezier_radius} ) * $params{crest};
    } else {
      $crest_radius =
				$params{radius2} +
					abs( $params{radius2} - $params{bezier_radius} ) * $params{crest};
    }
    splice( @controlpoints, 6, 0, getxypos( $a2, $crest_radius ) );
  }

  return @controlpoints;
}

# -------------------------------------------------------------------
sub ribbon {
	$CONF{debug_validate} && validate(
																		@_,
																		{
																		 image                        => { isa => 'GD::Image' },
																		 start1                       => 1,
																		 end1                         => 1,
																		 chr1                         => 1,
																		 start2                       => 1,
																		 end2                         => 1,
																		 chr2                         => 1,
																		 radius1                      => 1,
																		 radius2                      => 1,
																		 edgecolor                    => 1,
																		 edgestroke                   => 1,
																		 fillcolor                    => 0,
																		 pattern                      => 0,
																		 bezier_radius                => 0,
																		 perturb_bezier_radius        => 0,
																		 perturb                      => 0,
																		 bezier_radius_purity         => 0,
																		 perturb_bezier_radius_purity => 0,
																		 crest                        => 0,
																		 perturb_crest                => 0,
																		 svg                          => { type => HASHREF, optional => 1 },
																		 mapoptions                   => { type => HASHREF, optional => 1 },
																		}
																	 );
	my %params = @_;

	my $perturb = $params{perturb};
	if ($SVG_MAKE) {
		my @path;
		my $angle1_start = getanglepos( $params{start1}, $params{chr1} );
		my $angle1_end   = getanglepos( $params{end1},   $params{chr1} );
		my $angle2_start = getanglepos( $params{start2}, $params{chr2} );
		my $angle2_end   = getanglepos( $params{end2},   $params{chr2} );

		my @bezier_control_points1 = (
																	bezier_control_points(
																												pos1                  => $params{end1},
																												chr1                  => $params{chr1},
																												pos2                  => $params{end2},
																												chr2                  => $params{chr2},
																												radius1               => $params{radius1},
																												radius2               => $params{radius2},
																												bezier_radius         => $params{bezier_radius},
																												perturb_bezier_radius => $params{perturb_bezier_radius},
																												bezier_radius_purity  => $params{bezier_radius_purity},
																												perturb_bezier_radius_purity =>
																												$params{perturb_bezier_radius_purity},
																												crest         => $params{crest},
																												perturb => $perturb,
																												perturb_crest => $params{perturb_crest},
																											 )
																 );

		my @bezier_control_points2 = (
																	bezier_control_points(
																												pos1                  => $params{start2},
																												chr1                  => $params{chr2},
																												pos2                  => $params{start1},
																												chr2                  => $params{chr1},
																												radius1               => $params{radius2},
																												radius2               => $params{radius1},
																												bezier_radius         => $params{bezier_radius},
																												perturb_bezier_radius => $params{perturb_bezier_radius},
																												bezier_radius_purity  => $params{bezier_radius_purity},
																												perturb => $perturb,
																												perturb_bezier_radius_purity =>
																												$params{perturb_bezier_radius_purity},
																												crest         => $params{crest},
																												perturb_crest => $params{perturb_crest},
																											 )
																 );

		push @path,
			sprintf( "M %.3f,%.3f", getxypos( $angle1_start, $params{radius1} ) );

		push @path, sprintf(
												"A %.3f,%.3f %.2f %d,%d %.1f,%.1f",
												$params{radius1},
												$params{radius1},
												0,
												abs( $angle1_start - $angle1_end ) > 180,
												$angle1_start < $angle1_end,
												getxypos( $angle1_end, $params{radius1} )
											 );

		if ( @bezier_control_points1 == 10 ) {
			my @bezier_points = bezier_points(@bezier_control_points1);
			my $point_string  = "%.1f,%.1f " x @bezier_points;
			push @path,
				sprintf( "L $point_string",
								 ( map { @$_ } @bezier_points[ 0 .. @bezier_points - 1 ] ) );
		} elsif ( @bezier_control_points1 == 8 ) {
			my $point_string = join( $SPACE,
															 map { sprintf( "%.1f", $_ ) }
															 @bezier_control_points1[ 2 .. @bezier_control_points1 - 1 ] );
			push @path, sprintf( "C %s", $point_string );
		} elsif ( @bezier_control_points1 == 6 ) {
			push @path,
				sprintf( "Q %.1f,%.1f %.1f,%.1f",
								 @bezier_control_points1[ 2 .. @bezier_control_points1 - 1 ] );
		}

		push @path, sprintf(
												"A %.3f,%.3f %.2f %d,%d %.1f,%.1f",
												$params{radius2},
												$params{radius2},
												0,
												abs( $angle2_start - $angle2_end ) > 180,
												$angle2_start > $angle2_end,
												getxypos( $angle2_start, $params{radius2} )
											 );

		if ( @bezier_control_points2 == 10 ) {
			my @bezier_points = bezier_points(@bezier_control_points2);
			my $point_string  = "%.1f,%.1f " x @bezier_points;
			push @path,
				sprintf( "L $point_string",
								 ( map { @$_ } @bezier_points[ 0 .. @bezier_points - 1 ] ) );
		} elsif ( @bezier_control_points2 == 8 ) {
			my $point_string = join( $SPACE,
															 map { sprintf( "%.1f", $_ ) }
															 @bezier_control_points2[ 2 .. @bezier_control_points2 - 1 ] );
			push @path, sprintf( "C %s", $point_string );
		} elsif ( @bezier_control_points2 == 6 ) {
			push @path,
				sprintf( "Q %.1f,%.1f %.1f,%.1f",
								 @bezier_control_points2[ 2 .. @bezier_control_points2 - 1 ] );
		}
		push @path, "Z";

		my $svg_colors = $EMPTY_STR;
		if ( $params{edgecolor} ) {
			$svg_colors .= sprintf( qq{ stroke: rgb(%d,%d,%d);}, rgb_color( $params{edgecolor} ) );
			if ( rgb_color_opacity( $params{edgecolor} ) < 1 ) {
				$svg_colors .= sprintf( qq{ stroke-opacity: %.3f;},
																rgb_color_opacity( $params{edgecolor} ) );
			}
		}

		if ( $params{fillcolor} ) {
			my $svg_color;
			if (defined $params{pattern}) {
				if ($params{fillcolor} =~ /,/) {
					my @colors = split(",",$params{fillcolor});
					(undef,$svg_color) = split(":",$colors[0]);
				} else {
					$svg_color = $params{fillcolor};
				}
			} else {
				$svg_color = $params{fillcolor};
			}
			$svg_colors .= sprintf( qq{ fill: rgb(%d,%d,%d);}, rgb_color($svg_color) );
			if ( rgb_color_opacity( $params{fillcolor} ) < 1 ) {
				$svg_colors .= sprintf( qq{ opacity: %.3f;},
																rgb_color_opacity( $params{fillcolor} ) );
			}
		}
		
		my $svg = sprintf( qq{<path d="%s" style="stroke-width: %.1f; %s" %s/>},
											 join( $SPACE, @path ),
											 $params{edgestroke}||0, 
											 $svg_colors,
											 attr_string($params{svg}{attr}),
										 );
		printsvg($svg);
	}

	if ($PNG_MAKE) {
		my $poly = GD::Polygon->new;

		# arc along span 1
		my @points = arc_points(
														start  => $params{start1},
														end    => $params{end1},
														chr    => $params{chr1},
														radius => $params{radius1}
													 );
		
		# bezier from span1 to span2
		push @points, bezier_points(
																bezier_control_points(
																											pos1                  => $params{end1},
																											chr1                  => $params{chr1},
																											pos2                  => $params{end2},
																											chr2                  => $params{chr2},
																											radius1               => $params{radius1},
																											radius2               => $params{radius2},
																											bezier_radius         => $params{bezier_radius},
																											perturb => $perturb,
																											perturb_bezier_radius => $params{perturb_bezier_radius},
																											bezier_radius_purity  => $params{bezier_radius_purity},
																											perturb_bezier_radius_purity => $params{perturb_bezier_radius_purity},
																											crest         => $params{crest},
																											perturb_crest => $params{perturb_crest},
																										 )
															 );
			
		# arc along span 2
		push @points, arc_points(
														 start  => $params{end2},
														 end    => $params{start2},
														 chr    => $params{chr2},
														 radius => $params{radius2}
														);
			
		push @points, bezier_points(
																bezier_control_points(
																											pos1                  => $params{start2},
																											chr1                  => $params{chr2},
																											pos2                  => $params{start1},
																											chr2                  => $params{chr1},
																											radius1               => $params{radius2},
																											radius2               => $params{radius1},
																											bezier_radius         => $params{bezier_radius},
																											perturb_bezier_radius => $params{perturb_bezier_radius},
																											perturb               => $perturb,
																											bezier_radius_purity  => $params{bezier_radius_purity},
																											perturb_bezier_radius_purity => $params{perturb_bezier_radius_purity},
																											crest                 => $params{crest},
																											perturb_crest         => $params{perturb_crest},
																										 )
															 );
		
		for my $point (@points) {
			$poly->addPt(@$point);
		}

		Circos::PNG::draw_polygon(polygon    => $poly,
															thickness  => unit_strip($params{edgestroke},"p"),
															fill_color => $params{fillcolor},
															pattern    => $params{pattern},
															color      => $params{edgecolor});

		# contribute to image map
		if (defined $params{mapoptions}{url}) {
			my $xshift = $CONF{image}{image_map_xshift}||0;
			my $yshift = $CONF{image}{image_map_xshift}||0;
			my $xmult  = $CONF{image}{image_map_xfactor}||1;
			my $ymult  = $CONF{image}{image_map_yfactor}||1;
			my @coords = map { ( $_->[0]*$xmult + $xshift , $_->[1]*$ymult + $yshift ) } $poly->vertices;
			report_image_map(shape=>"poly",
											 coords=>\@coords,
											 href=>$params{mapoptions}{url});
		}
	}
}

# Fetch a fill pattern from a file, or if previously fetched, from lookup table.
sub fetch_fill_pattern {
	my $tile_name = shift;
	if (! exists $IM_TILES->{$tile_name}) {
		my $tile_file = $CONF{patterns}{$tile_name};
		if (! $tile_file) {
	    fatal_error("pattern","no_file_def",$tile_name);
		}
		$tile_file = locate_file(file=>$tile_file, name=>"tile pattern");
		if (! -e $tile_file) {
	    fatal_error("pattern","no_file",$tile_name,$tile_file);
		}
		my $tile = GD::Image->new($tile_file);
		if (! $tile) {
	    fatal_error("pattern","cannot_create",$tile_name,$tile_file);
		}
		printdebug_group("tile","created tile from file",$tile_file);
		$IM_TILES->{$tile_name} = $tile;
	} 
	return $IM_TILES->{$tile_name};
}

# Fetch a colored fill pattern. Colored patterns are based on 
# patterns read by fetch_fill_pattern, superimposed with a color.
# Colored patterns are stored in a separate lookup table, by
# pattern name and color.
sub fetch_colored_fill_pattern {
	my ($tile_name,$color) = @_;
	# create the old->new color map;
	my $colormap;
	for my $pair (split(/\s*,\s*/,$color)) {
		my ($old,$new) = split(/\s*:\s*/,$pair);
		#confess "Color maps for ribbon patterns must have the format oldcolor:newcolor[,oldcolor:newcolor,...]";
		next unless $new;
		$colormap->{join(",",$IM->rgb(fetch_color($old)))} = $new;
	}
	if (! $IM_TILES_COLORED->{$tile_name}{$color}) {
		my $tile  = fetch_fill_pattern($tile_name)->clone();
		for my $x ( 0.. $tile->width ) {
	    for my $y ( 0.. $tile->height ) {
				my $old_color = $tile->getPixel($x,$y);
				my @old_rgb   = $tile->rgb($old_color);
				my $new_color = $colormap->{join(",",@old_rgb)};
				if (! defined $new_color) {
					my @imbg_rgb = $IM->rgb(fetch_color($CONF{image}{background}));
					if ($old_rgb[0] == $imbg_rgb[0] &&
							$old_rgb[1] == $imbg_rgb[1] &&
							$old_rgb[2] == $imbg_rgb[2]) {
						next;
					} else {
						$new_color = $color;
					}
				}
				my @new_rgb   = $IM->rgb( fetch_color($new_color) );
				my $new_color_idx = $tile->colorExact(@new_rgb);
				$new_color_idx = $tile->colorAllocate(@new_rgb) if $new_color_idx < 0;
				$tile->setPixel($x,$y, $new_color_idx);
				#printinfo($x,$y,@old_rgb,@new_rgb);
	    }
		}
		$IM_TILES_COLORED->{$tile_name}{$color} = $tile;
	}
	return $IM_TILES_COLORED->{$tile_name}{$color};
}



################################################################
# Draw a slice

sub slice {
	$CONF{debug_validate} && validate(
																		@_,
																		{
																		 image        => { isa => 'GD::Image' },
																		 start        => 1,
																		 start_offset => 0,
																		 end_offset   => 0,
																		 end          => 1,
																		 chr          => 1,
																		 radius_from  => 1,
																		 radius_to    => 0,
																		 radius_to_y0 => 0,
																		 radius_to_y1 => 0,
																		 edgecolor    => 1,
																		 edgestroke   => 1,
																		 fillcolor    => 0,
																		 pattern      => 0,
																		 ideogram     => 0,
																		 svg          => { type => HASHREF, optional => 1 },
																		 mapoptions   => { type => HASHREF, optional => 1 },
																		 guides       => 0,
																		}
																	 );
	my %params = @_;
	
	$params{edgestroke} = unit_strip($params{edgestroke});

	start_timer("graphic_slice");
	
	start_timer("graphic_slice_preprocess");
	# determine whether to draw this slice, or whether it is only being
	# used to define an image map element. A slice that appears in the image
	# must have one of edge color, edge stroke or fill color defined.
	my $draw_slice = list_has_defined( @params{qw(edgecolor edgestroke fillcolor)} );

	my $start_a = getanglepos( $params{start}, $params{chr} ) if defined $params{start};
	my $end_a   = getanglepos( $params{end},   $params{chr} ) if defined $params{end};

	if(defined $params{start} && defined $params{end}) {
		if ( $end_a < $start_a ) {
			( $start_a, $end_a ) = ( $end_a, $start_a );
		}
	}

	# The offsets are used to accomodate scales for very short ideograms
	# where individual base positions need to be identified. It allows
	# elements with start=end to be drawn without collapsing into a very
	# thin slice, where start/end angles are the same.
	my @offsets;
	if ($CONF{offsets}) {
		@offsets = split(",",$CONF{offsets});
	} elsif ( abs($start_a - $end_a) < 1 ) {
		@offsets = (0,0);
	}
	if (@offsets) {
		$params{start_offset} = $offsets[0] if ! defined $params{start_offset};
		$params{end_offset}   = $offsets[1] if ! defined $params{end_offset};
		if(defined $params{start}) {
			$start_a -= $GCIRCUM360 * $params{start_offset};
		}
		if(defined $params{end}) {
			$end_a   += $GCIRCUM360 * $params{end_offset};
		}
		$start_a = $end_a   if ! defined $params{start};
		$end_a   = $start_a if ! defined $params{end};
	}

	my $angle_orientation = $CONF{image}{angle_orientation} || $EMPTY_STR;
	if ( $angle_orientation eq 'counterclockwise' ) {
		( $start_a, $end_a ) = ( $end_a, $start_a ) if $end_a < $start_a;
	} else {
		$start_a -= 360 if $start_a > $end_a;
	}
	stop_timer("graphic_slice_preprocess");
	
	start_timer("graphic_slice_polygon_coord");
	my $poly;
	if ( (defined $params{radius_to_y0} && defined $params{radius_to_y1})
			 ||
			 $params{radius_from} != $params{radius_to} ) {
		$poly = GD::Polygon->new;
	} else {
		$poly = GD::Polyline->new;
	}
	my ( $x, $y, $xp, $yp ) = (0,0,0,0);
	for ( my $angle = $start_a;  $angle <= $end_a; $angle += $CONF{anglestep} ) {
		( $x, $y ) = getxypos( $angle, $params{radius_from} );
		my $d = sqrt( ($x-$xp)**2 + ($y-$yp)**2 );
		next if $xp && $yp && $d < $CONF{minslicestep};
		$poly->addPt( $x, $y );
		( $xp, $yp ) = ( $x, $y );
	}
	if ( $end_a != $start_a ) {
		$poly->addPt(getxypos( $end_a, $params{radius_from}));
	}
	if ( (defined $params{radius_to_y0} && defined $params{radius_to_y1})
			 ||
			 $params{radius_from} != $params{radius_to}) {
		( $xp, $yp ) = ( 0,0 );
		if (defined $params{radius_to_y0} && defined $params{radius_to_y1}) {
			my ($ry0,$ry1) = @params{qw(radius_to_y0 radius_to_y1)};
			if ($angle_orientation =~ /counter/) {
				($ry0,$ry1) = ($ry1,$ry0);
			}
			$poly->addPt(getxypos( $end_a,   $ry1));
			$poly->addPt(getxypos( $start_a, $ry0));
		} else {
			for ( my $angle = $end_a; $angle > $start_a; $angle -= $CONF{anglestep} ) {
				( $x, $y ) = getxypos( $angle, $params{radius_to} );
				my $d = sqrt( ( $x - $xp )**2 + ( $y - $yp )**2 );
				next if $xp && $yp && $d < $CONF{minslicestep};
				$poly->addPt( getxypos( $angle, $params{radius_to} ) );
				( $xp, $yp ) = ( $x, $y );
			}
			$poly->addPt( getxypos( $start_a, $params{radius_to} ) );
		}
	}
	stop_timer("graphic_slice_polygon_coord");

	if ($draw_slice) {
		if ($SVG_MAKE) {
			start_timer("graphic_slice_polygon_svg");
			Circos::SVG::draw_slice(%params,
															start_a           => $start_a,
															end_a             => $end_a,
															pattern           => $params{pattern},
															angle_orientation => $angle_orientation,
															attr              => $params{svg}{attr},
														 );
			stop_timer("graphic_slice_polygon_svg");
		}
		if ($PNG_MAKE) {
			start_timer("graphic_png_polygon");
			Circos::PNG::draw_polygon(polygon    => $poly,
																thickness  => unit_strip($params{edgestroke},"p"),
																fill_color => $params{fillcolor},
																pattern    => $params{pattern},
																color      => $params{edgecolor});
			stop_timer("graphic_png_polygon");	    
		}
		if ($params{guides}) {
	    start_timer("graphic_slice_guide");
	    draw_guide(0,2*$params{radius_to},$start_a,2);
	    draw_guide(0,2*$params{radius_to},$end_a,2);
	    draw_guide(0,2*$params{radius_to},($start_a+$end_a)/2,1);
	    stop_timer("graphic_slice_guide");
		}
	}
	if (defined $params{mapoptions}{url}) {
		my $xshift = $CONF{image}{image_map_xshift}||0;
		my $yshift = $CONF{image}{image_map_xshift}||0;
		my $xmult  = $CONF{image}{image_map_xfactor}||1;
		my $ymult  = $CONF{image}{image_map_yfactor}||1;
		my @coords = map { ( $_->[0]*$xmult + $xshift , $_->[1]*$ymult + $yshift ) } $poly->vertices;
		report_image_map(shape=>"poly",
										 coords=>\@coords,
										 href=>$params{mapoptions}{url});
	}
	stop_timer("graphic_slice");
}

sub report_image_map {
  # given a shape, coordinates (as a list) and an href string, report
  # an element of the image map
  my %args = @_;
  my $href = $args{href};
  if ($href =~ /^[^\/]+\/\//) {
    # protocol found
  } elsif (defined $CONF{image}{image_map_protocol}) {
    # prefix the url with the protocol, if defined
    $href = sprintf("%s://%s",$CONF{image}{image_map_protocol},$href);
  }
  my $map_string = sprintf ("<area shape='%s' coords='%s' href='%s' alt='%s' title='%s'>\n",
														$args{shape},
														join(",",map {round($_)} @{$args{coords}}),
														$href,
														$href,
														$href);
  push @MAP_ELEMENTS, {string=>$map_string,
											 type=>$args{shape},
											 coords=>$args{coords}};
}

# -------------------------------------------------------------------
sub myarc {
  my ( $im, $c, $radius, $a1, $a2, $color ) = @_;
	my $astep = 0.1 / $radius * 180 / $PI;
  $astep    = max( 0.01, $astep );
  for ( my $a = $a1 ; $a <= $a2 ; $a += $astep ) {
    $im->setPixel( getxypos( $a, $radius ), $color ) if $PNG_MAKE;
  }
}

# -------------------------------------------------------------------
sub getrdistance {
  my ( $pos, $chr, $r ) = @_;
  my $d;

  if ( $CONF{image}{angle_orientation} eq "counterclockwise" ) {
    $d = $r * $DEG2RAD * 360 * ( 1 - getrelpos_scaled( $pos, $chr ) / $GCIRCUM );
  } else {
    # GCIRCUM360 = 360 / GCIRCUM
    $d = $r * $DEG2RAD * $GCIRCUM360 * getrelpos_scaled( $pos, $chr );
  }

  return $d;
}

sub is_counterclockwise {
	return defined $CONF{image}{angle_orientation} && $CONF{image}{angle_orientation} eq "counterclockwise";
}

# Get the angle for a given sequence position within the genome,
# with appropriate padding built in
#
#   269.99  -90  -89
#
# 181                -1
# 180                 0
# 179                 1 
#
#        91  90   89
#
# Return in degrees.

sub getanglepos {
  my ( $pos, $chr ) = @_;
  my $angle;
  if ( is_counterclockwise() ) {
		$angle = 360 * ( 1 - getrelpos_scaled( $pos, $chr ) / $GCIRCUM );
  } else {
		$angle = $GCIRCUM360 * getrelpos_scaled( $pos, $chr );
  }
  
  if ( $CONF{image}{angle_offset} ) {
		$angle += $CONF{image}{angle_offset};
  }
  $angle %= 360 if $angle > 360 || $angle < -360;
  printdebug_group("angle",$chr,$pos,$angle);
  return $angle;
}

sub get_angle_pos {
	return getanglepos(@_);
}

# -------------------------------------------------------------------
sub get_ideogram_idx {
	# given a chromosome and base pair position, return the index
	# of the ideogram where the position is found
	my ( $pos, $chr ) = @_;
	return if ! defined $pos || ! defined $chr;
	for my $ideogram (@IDEOGRAMS) {
		if ( $ideogram->{chr} eq $chr && $ideogram->{set}->member($pos) ) {
	    return $ideogram->{idx};
		}
	}
	return undef;
}

# -------------------------------------------------------------------
sub get_ideogram_by_idx {
  my $idx = shift;
  return unless defined $idx;
	if (my $ideogram = $IDEOGRAMS_LOOKUP{idx}{$idx}) {
		return $ideogram;
	}
  my ($ideogram) = grep( defined $_->{idx} && $_->{idx} == $idx, @IDEOGRAMS );
  if ($ideogram) {
		return $IDEOGRAMS_LOOKUP{idx}{$idx} = $ideogram;
  } else {
		fatal_error("ideogram","no_such_idx",$idx);
  }
}

# -------------------------------------------------------------------
sub get_ideograms_by_name {
  my $name = shift;
  return unless defined $name;
	if (exists $IDEOGRAMS_LOOKUP{name}{$name}) {
		return $IDEOGRAMS_LOOKUP{name}{$name};
	}
  my @ideograms = grep( defined $_->{chr} && $_->{chr} eq $name, @IDEOGRAMS );
	if (@ideograms) {
		return $IDEOGRAMS_LOOKUP{name}{$name} = \@ideograms;
	} else {
		# return an error if this ideogram is not part of the karyotype
		if (! $KARYOTYPE->{$name} ) {
			fatal_error("ideogram","no_such_name",$name);
		}
		return;
  }
}

# -------------------------------------------------------------------
sub getrelpos_scaled_ideogram_start {
  my $ideogram_idx = shift;
  my $pos          = 0;
  for my $ideogram (@IDEOGRAMS) {
		my $idx = $ideogram->{idx};
		if (defined $ideogram_idx && $idx == $ideogram_idx ) {
			if ( $ideogram->{reverse} ) {
	      $pos += $ideogram->{length}{scale};
			}
			last;
		}
		$pos += $ideogram->{length}{scale};
		if ( $ideogram->{next} ) {
			my $x = ideogram_spacing($ideogram,$ideogram->{next});
			$pos += $x;
		}
  }
  return $pos;
}

# -------------------------------------------------------------------
sub getrelpos_scaled {
  #
  # relative position around the circle [0,1] for a given base
  # position and chromosome.
  #
  my ( $pos, $chr ) = @_;
  my $ideogram_idx = get_ideogram_idx($pos,$chr);
  my $relpos       = getrelpos_scaled_ideogram_start($ideogram_idx);
  my $ideogram     = get_ideogram_by_idx($ideogram_idx);
  if ( match_string($ideogram->{chr},$chr) && $ideogram->{set}->member($pos) ) {
		my $direction = $ideogram->{reverse} ? -1 : 1;
		for my $cover ( @{ $ideogram->{covers} } ) {
      if ( $cover->{set}->member($pos) ) {
				# found the cover that has the position we seek
				$relpos += $direction * ( $pos - $cover->{set}->min ) * $cover->{scale};
				#printinfo($pos,$chr,$relpos);
				return $relpos;
      } else {
				$relpos += $direction * $cover->{set}->cardinality * $cover->{scale};
      }
    }
		fatal_error("ideogram","bad_scaled_position",$chr,$pos);
  }
  #printinfo($pos,$chr,$relpos);
  return $relpos;
}

# -------------------------------------------------------------------
sub get_set_middle {
  my $set = shift;
  return ( $set->min + $set->max ) / 2;
}

# -------------------------------------------------------------------
#sub text_label_size {
#
# return the width and height of a label, based on
# bounds reported by GD's stringFT
#
# bugfix v0.40 - added this wrapper function
#
#  my @bounds = @_;
#  my ( $w, $h );
#  if ( $bounds[1] == $bounds[3] ) {
#    $w = abs( $bounds[2] - $bounds[0] ) - 1;
#    $h = abs( $bounds[5] - $bounds[1] ) - 1;
#  } else {
#    $w =
#      sqrt( ( abs( $bounds[2] - $bounds[0] ) - 1 )**2 +
#	    ( abs( $bounds[3] - $bounds[1] ) - 1 )**2 );
#    $h =
#      sqrt( ( abs( $bounds[6] - $bounds[0] ) - 1 )**2 +
#	    ( abs( $bounds[7] - $bounds[1] ) - 1 )**2 );
#  }
#  return ( $w, $h );
#}

# -------------------------------------------------------------------
sub inittracks {
  my $num = shift;
  my $tracks = [ map { Set::IntSpan->new() } ( 0 .. $num - 1 ) ];
  return $tracks;
}

# -------------------------------------------------------------------
sub gettack {
  # Given an interval set ($set) and a list of existing tracks
  # ($tracks), return the track which can accomodate the $set when
  # padded by $padding
  my $set     = shift;
  my $padding = shift;
  my $chr     = shift;
  my $tracks  = shift;
  my $scale   = shift;

  my $chr_offset = 0;
  $scale ||= 1e3;
  $chr_offset = $KARYOTYPE->{$chr}{chr}{length_cumul} if $chr;
  my $padded_set = Set::IntSpan->new(
																		 sprintf( "%d-%d",
																							( $chr_offset + $set->min - $padding ) / $scale,
																							( $chr_offset + $set->max + $padding ) / $scale )
																		);

  for my $idx ( 0 .. @$tracks - 1 ) {
    my $thistrack = $tracks->[$idx];

    if ( !$thistrack->intersect($padded_set)->cardinality ) {
      $tracks->[$idx] = $thistrack->union($padded_set);
      return $idx;
    }
  }

  return undef;
}

# -------------------------------------------------------------------
sub show_element {
	# returns true only if
	#  show parameter is not defined
	#  show parameter is defined and true
	#  hide parameter is not defined
	#  hide parameter is defined by false
    
	my $param = shift;
	confess "input parameter is not a hash reference" unless ref($param) eq "HASH";
	# the presence of "hide" overrides any value of "show"
	return 0 if $param->{hide};
	return 1 if !exists $param->{show} || $param->{show};
	return 0;
}

# -------------------------------------------------------------------
sub printsvg {
  print SVG @_, "\n" if $SVG_MAKE;
}

# -------------------------------------------------------------------
sub printmap {
  print MAP @_, "\n" if $MAP_MAKE;
}

# -------------------------------------------------------------------

=pod

=head1 AUTHOR

Martin Krzywinski E<lt>martink@bcgsc.caE<gt> L<http://mkweb.bcgsc.ca>

=head1 RESOURCES

L<http://mkweb.bcgsc.ca/circos>

If you are using Circos in a publication, please cite as

Krzywinski, M., J. Schein, I. Birol, J. Connors, R. Gascoyne,
D. Horsman, S. Jones, and M. Marra. 2009. Circos: an Information
Aesthetic for Comparative Genomics. Genome Res 19:1639-1645.

=head1 CONTRIBUTORS

Ken Youens-Clark E<lt>kyclark@gmail.comE<gt>

=head1 BUGS

Please report any bugs or feature requests to 

L<http://groups.google.com/group/circos-data-visualization>

=head1 SUPPORT

Circos documentation is available at

L<http://www.circos.ca/documentation/tutorials>

in the form of tutorials. For a more pedagogical approach, see the Circos course materials at

L<http://www.circos.ca/documentation/course>

=head1 ACKNOWLEDGEMENTS

=head1 SEE ALSO

=over

item * Hive plots 

L<http://www.hiveplot.com>

=item * online Circos table viewer

http://mkweb.bcgsc.ca/tableviewer

Uses Circos to generate visualizations of tabular data.

=item * chromowheel

  Ekdahl, S. and E.L. Sonnhammer, ChromoWheel: a new spin on eukaryotic 
    chromosome visualization. Bioinformatics, 2004. 20(4): p. 576-7.

The ChromeWheel is a processing method for generating interactive
illustrations of genome data. With the process chromosomes, genes and
relations between these genes is displayed. The chromosomes are placed
in a circle to avoid lines representing relations crossing genes and
chromosomes.

http://chromowheel.cgb.ki.se/

=item * genopix

GenomePixelizer was designed to help in visualizing the relationships
between duplicated genes in genome(s) and to follow relationships
between members of gene clusters. GenomePixelizer may be useful in the
detection of duplication events in genomes, tracking the "footprints"
of evolution, as well as displaying the genetic maps and other aspects
of comparative genetics.

http://genopix.sourceforget.net

=back

=head1 COPYRIGHT & LICENSE

Copyright 2004-2014 Martin Krzywinski, all rights reserved.

This file is part of the Genome Sciences Centre Perl code base.

This script is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This script is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this script; if not, write to the Free Software Foundation,
Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut

1;
