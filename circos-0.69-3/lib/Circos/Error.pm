package Circos::Error;

=pod

=head1 NAME

Circos::Error - error handling for Circos

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
error
fatal_error
);

use Cwd;
use Carp qw( carp confess croak );
use Params::Validate;
use Text::Format;

use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/../lib";
use lib "$FindBin::RealBin/lib";

use Circos::Constants;
use Circos::Debug;
use Circos::Utils;

our %GROUPERROR = (configuration => "configuration file error",
color =>"color handling error");
our %ERROR;

$ERROR{color} =
{
    bad_name_in_list => "The color list [%s] included a color definition [%s] that does not match any previously defined color.",
    clear_redefined  => "You defined a color named 'clear' but this name is reserved as synonym for 'transparent'. Plese remove this definition and call your color something else.",
    undefined => "You've asked for color named [%s] but this color has not been defined.\nPlease verify that you've included all the color files you wanted in the <color> block.\nIf you've asked for a transparent color (e.g. blue_a3), make sure that in the <image> block you have auto_alpha_colors=yes and an appropriate value for auto_alpha_steps.",
    multiple_defn => "The color [%s] has multiple distinct definitions - please use only one of these.\n%s",
    malformed_structure => "The color [%s] is not defined correctly. Saw a data structure of type [%s] instead of a simple color assignment.",
    circular_defn => "You have a circular color definition in your <color> block. Color [%s] and [%s] refer to each other.\nYou can define one color in terms of another, such as\n red=255,0,0\n favourite=red\nbut you must avoid loops, such as\n red=favourite\n favourite=red",
    reserved_name_a => "You are trying to allocate color [%s] with definition [%s], but names ending in _aN are reserved for colors with transparency.",
    cannot_allocate => "Could not allocate color [%s] with definition [%s] (error: %s).",
    bad_alpha => "Alpha value of [%s] cannot be used. Please use a range 0-1, where 0 is opaque and 1 is transparent.",
    malformed_hsv => "HSV definition [%s] is not in the correct format. You must use\n h,s,v = 60,1,0.5\nor\n h,s,v,a = 0,1,0.5,100\nwhere a is the alpha channel (0-127), h is the hue (0-360), s is saturation (0-1) and v is the value (0-1).",
    malformed_rgb => "RGB definition [%s] is not in the correct format. You must use\n r,g,b = 60,120,180\nor\n r,g,b,a = 60,120,180,100\nwhere a is the alpha channel (0-127), and r,g,b is in the range 0-255.",
    malformed_lch => "LCH definition [%s] is not in the correct format. You must use\n l,c,h = 60,50,180\nor\n l,c,h,a = 60,50,180,100\nwhere a is the alpha channel (0-127), and l,c is in the range 0 about 100 and h in the range 0 to 360.",
    bad_rgb_lookup => "Could not find a color with RGB value %d,%d,%d.",
 undef_value=>"Tried to apply color function [%s] to an undefined value",
};

$ERROR{ideogram} =
{
    max_number => "You have asked to draw [%d] ideograms, but the maximum is currently set at [%d]. To increase this number change max_ideograms in etc/housekeeping.conf. Keep in mind that drawing that many ideograms may create an image that is too busy and uninterpretable.",
    use_undefined => "Entry in 'chromosomes' parameter [%s] mentions chromosome [%s] which is not defined the karyotype file. Make sure that list_record_delim and list_field_delim are defined (see etc/housekeeping.conf) in order for the 'chromosomes' parameter to be parsed correctly.",
    multiple_start_anchors => "Only one chromosome order group can have a start '^' anchor",
    multiple_end_anchors => "Only one chromosome order group can have an end '\$' anchor",
    multiple_tag => "Incorrectly formatted chromosomes_order field (or content of chromosomes_order_file). Tag [%s] appears multiple times, but must be unique.",
    orphan_tag => "Incorrectly formatted chromosomes_order field (or content of chromosomes_order_file). Tag [%s] is not associated with any chromosome.",
    reserved_tag => "You have an ideogram with the tag [%s] which is not allowed, as this is a reserved keyword",
    reserved_chr => "You have an ideogram with the name [%s] which is not allowed, as this is a reserved keyword",
    start_and_end_anchors => "You have a chromosome order group with both start '^' and end '\$' anchors.\n %s\nThis is not supported.\nIf you want to limit which ideograms are drawn, use '-' in front of their names in the chromosomes field. For example,\n chromosomes = -hs1,-hs2",
    cannot_place => "Chromosomes_order string cannot be processed because group\n %s\ncannot be placed in the figure. This may be due to more tags in the chromosomes_order field than ideograms.",
    unparsable_def => "Chromosome definition\n %s\ncould not be parsed. It must be in the format CHR_NAME or CHR_NAME:RUN_LIST. For example\n hs1\n hs1:10-20\n hs1:10-20,30-50\n hs1:(-20,30-)",
    regex_tag => "You have used a regular expression in the 'chromosomes' parameter in the string\n %s\ntogether with a tag [%s]. This combination is not supported.",
    no_ideograms_to_draw => "No ideograms to draw. Either define some in 'chromosomes' parameter or set\n chromosomes_display_default = yes",
    no_such_idx => "Tried to fetch a chromosome with index [%d], but no such chromosome exists.",
    no_such_name => "You referenced a chromosome with name [%s], but no such chromosome exists. Check the karyotype file to make sure that it is defined.",
    bad_scaled_position => "Could not correctly apply scaling to find pixel position for ideogram [%s] position [%s].",
		bad_spacing_scale => "The relative_scale_spacing parameter had a value that could not be understood [%s]. Options are min|max|average|mode for spacing based on scale statistics of all ideograms and minadj|maxadj|averageadj|modeadj if you wish to consider only ideograms flanking the space.\n\nYou can also specify the scale using a positive floating point value.",
		bad_relative_scale => "Relative scale for a chromosome must be in the range (0,1). The scale value is meant to represent the fraction of the circle occupied by the ideogram. Your value [%s] for ideogram [%s, tag %s] is out of bounds.\nIf you want to make all ideograms the same physical size on the figure, set the same relative scale to each. For example, use\n\n chromosomes_scale = /./=0.1r",
 undefined_axis_break_style => "You asked to use axis break style [%s] but this style is not defined. Please make sure you have an <break_style %s> block in the <ideogram><spacing> block.",
};


$ERROR{rule} = 
	{
	 cannot_undefine => "You tried to set parameter [%s] to 'undef'. You cannot undefine the position of a data point.",
	 no_condition_no_flow => "This rule has neither a 'condition' nor a 'flow' parameter. One or both are required.\nIf you want the rule to trigger for each element, set condition = 1\nIf you want the rule to short circuit all downstream rules, set flow = stop\n\n %s",
	 bad_flow => "Cannot understand the flow [%s] for the rule tagged [%s]",
	 bad_tag => "You tried to goto a rule with tag [%s] but no such rule could be found.",
	 bad_coord => "You asked for variable [%s] of coordinate #%s. However, your data has %s coordinates",
	 
	 wrong_coord_num => "You tried to parse variables from a data point with an unsupported number of coordinates. Expect 1 or 2, but saw [%s] coordinates.",
	 conflicting_coord => "You asked for variable [%s] but your data has [%s] coordinates which have conflicting values of this variable [%s] vs [%s]. Please use %s1 or %s2 to specify which coordinate you wish to use.",
	 need_2_coord => "You asked for variable [%s] for a data point, but the data point only has [%s] coordinates. This variable requires 2 coordinates to compute.",
	 fn_need_2_coord => "You've used the function [%s] in the rule\n\n %s\n\nand applied it to a data value with a single coordinates. This function requires a data value with two coordinates, such as a link. Circos wants to test whether the two coordinates' chromosomes match [%s] and [%s]",
	 fn_wrong_arg => "You've used the function [%s] in the rule\n\n %s\n\nwith the wrong number of arguments. This function requires [%d] arguments.",
};

$ERROR{pattern} = 
{
    no_file_def => "You asked for pattern [%s] but it is not associated with a file definition in the <pattern> block.",
    no_file     => "You asked for pattern [%s] but its associated image file [%s] does not exist.",
    cannot_create => "There was a problem creating the pattern [%s] from image file [%s].",
    
};

$ERROR{configuration} = 
  {
		bad_command_line_options=>"Some of the command-line options you provided [%s] are either unknown or ambiguous.",
	 no_debug_group=>"You asked for debug group [%s] using -debug_group. This group is not defined. Please use one of\n\n[%s]\n\nTo request all groups, use -debug_group _all.",
	 deprecated =>"The configuration syntax [%s] is deprecated and no longer supported. Instead, use [%s].",
	 no_such_conf_item => "You attempted to reference a configuration parameter using %s, but no parameter was found at the configuration file position %s.\n\nTo reference a parameter in another block, provide the full block path, such as conf(ideogram,spacing,default). In general, conf(block1,block2,...,blockn,parameter).\n\nTo reference the first defined parameter above the block in which conf() is called, use conf(.,parameter).",
   no_housekeeping => "You did not include the etc/housekeeping.conf file in your configuration file. This file contains many important system parameters and must be included in each Circos configuration.\n\nTo do so, use\n\n  <<include etc/housekeeping.conf>>\n\nin your main configuration file. For an example, see\n\n  http://www.circos.ca/documentation/tutorials/quick_guide/hello_world/configuration\n\nIf you have made other provisions to include these parameters, make sure you have\n\n  housekeeping = yes\n\ndefined to skip this check.",
   multi_word_key => "Your parameter [%s] contains a white space. This is not allowed. You either forgot a '=' in assignment (e.g. 'red 255,0,0' vs 'red = 255,0,0') or used a multi-word parameter name\n (e.g. 'my red = 255,0,0' vs 'my_red = 255,0,0'",
   missing => "file(error/configuration.missing.txt)",
   bad_parameter_type => "You attempted to reference a configuration parameter group with name [%s], but it is not defined",
   defined_twice => "Parameter [%s] of type [%s] is defined twice. Some parameters can have multiple values, but not this one.",
   multiple_defn_in_list => "Configuration value [%s] defines parameter [%s] more than once. This is not allowed. If you want to override a parameter included from a file, use * suffix (e.g. file* = myfile.png)",
   multivalue => "Configuration parameter [%s] in parent block [%s] has been defined more than once in the block shown above, and has been interpreted as a list. This is not allowed. Did you forget to comment out an old value of the parameter?",
   unsupported_parameter => "Parameter [%s] of type [%s] is not supported.",
   bad_pointer => "Problem with variable lookup in configuration file. You referenced variable [%s] (seen as %s) in another parameter, but this variable is not defined.",
   no_karyotype => "You did not define a karyotype file. Are you sure your configuration file is well formed?",
   no_block => "You did not define an <%s> block in the configuration file.",
	 no_counter => "No such counter [%s]",
	 cannot_find_include => "Error parsing the configuration file. You used an <<include FILE>> directive, but the FILE could not be found. This FILE is interpreted relative to the configuration file in which the <<include>> directive is used. Circos lookd for the file in these directories\n\n%s\n\nThe Config::General module reported the error\n\n%s",
	 cannot_parse_file => "Error parsing the configuration file. The Config::General module reported the error\n\n%s",
	 bad_var_value => "Could not parse variable/value pair [%s] using the delimiter regular expression [%s].",
	 parampath_missing => "You tried to set the parameter [%s] to value [%s] using -param, but the block [%s] does not exist in the configuration file.",
	 parampath_nothash => "You tried to set the parameter [%s] to value [%s] using -param, but the block [%s] is not unique.",
	 undefined_parameter => "The required parameter [%s] for [%s] block was not defined",
	 undefined_string => "Could not parse value for configuration parameter [%s] in block [%s]. The location in the configuration is shown above.",
  };

$ERROR{font} = 
{
    no_def  => "Non-existent font definition for font [%s] requested for [%s].",
    no_file => "Could not find file for font [%s] which has definition [%s] requested for [%s]",
    no_name => "Non-existent font definition for font [%s] requested for [%s].",
    init_error => "Could not initalize font from file [%s] to find out its name for SVG",
    no_name_in_font => "Could not determine font name from font file [%s]",
    no_ttf  => "There was a problem with True Type font support. Circos could not render text from the font file\n  %s\nPlease check that gd (system graphics library) and GD (Perl's interface to gd) are compiled with True Type support.\nOn UNIX systems, try\n  gdlib-config --all\nand look for GD_FREETYPE in the 'features' line and -lfreetype in the 'libs' line. If these are there, it's likely that your Perl GD module needs recompiling.\nFor help in installing libgd and/or GD, see\n  http://www.perlmonks.org/?node_id=621579",
};

$ERROR{svg} =
	{
	 no_such_tag => "No such SVG tag [%s] is defined.",
};

$ERROR{argument} =
{
    list_size => "Function [%s] in package [%s] expected a list of size [%d] but only saw [%d] elements.",
};

$ERROR{geometry} =
{
    angle_out_of_bounds => "The angle [%f] is out of bounds. Expected value in [-90,270].",
    bad_angle_or_radius => "Tried to obtain (x,y) coordinate from angle [%s] and radius [%s], but one of these was not defined.",
};

$ERROR{graphics} =
{
    brush_zero_size => "Cannot create a brush with zero width",
};

$ERROR{rules} =
	{
	 no_such_field => "You set up a rule [%s] that uses the parsable field [%s] but the data point you are testing does not have this field. If you want Circos to skip missing fields, set skip_missing_expression_vars=yes in etc/housekeeping.conf\n\n%s.",
	 no_field_value => "You set up a rule [%s] that uses the parsable field [%s], but this field has no associated value.",
	 wrong_num_elements => "You set up a rule [%s] that uses the parsable field [%s] but the data point you are testing does not have [%d] elements.",
	 parse_error => "There was a problem evaluating the string [%s] as code (error: %s)",
	 no_condition => "This rule does not have a condition field. If you want the rule to trigger for each element, set condition = 1\n\n%s",
	 bad_tag => "You tried to goto a rule with tag [%s] but no such rule could be found.",
	 bad_coord => "You asked for variable [%s] of coordinate #%s. However, your data has %s coordinates",
	 
	 wrong_coord_num => "You tried to parse variables from a data point with an unsupported number of coordinates. Expect 1 or 2, but saw [%s] coordinates.",
	 conflicting_coord => "You asked for variable [%s] but your data has [%s] coordinates which have conflicting values of this variable [%s] vs [%s]. Please use %s1 or %s2 to specify which coordinate you wish to use",
	 need_2_coord => "You asked for variable [%s] for a data point, but the data point only has [%s] coordinates. This variable requires 2 coordinates to compute.",
	 flow_syntax_error => "The flow parameter value [%s] in rule with tag [%s] could not be parsed. Options for this field are\n\n continue\n\n restart\n\n stop {if true|false}\n\n goto RULETAG {if true|false}",
};

$ERROR{io} =
{
    temp_dir_not_created => "Attempted to automatically determine a directory for temporary files, but failed. Please set the %s parameter to define it.",
    cannot_write => "Cannot open file [%s] for writing %s. Make sure that the directory for this file exists (Circos will not create directories) and is writeable. (error %s)",
    cannot_read => "Cannot read file [%s] for reading %s. (error %s)",
    cannot_find => "Cannot guess the location of file [%s]. Tried to look in the following directories\n%s",
    no_directory => "Cannot find the directory [%s] for writing %s.",
};

$ERROR{parsedata} =
	{
	 bad_options => "Error parsing data point options. Saw parameter assignment [%s] but expected it to be in the format x=y. Make sure that you're not using a data file with values for a track that does not require values.",
	 bad_csv     => "Could not parse comma-delimited list [%s] because of unbalanced parentheses [%d]. Correct syntax is x=(1,2),y=3, which is split along the second comma to x=(1,2) and y=3. If you do not use parentheses, the last item in the list will be considered as a parameter, e.g. x=a,b,c=2 is parsed as x=a,b c=2.",
	 bad_field_format => "The field [%s] did not have the expected format. The value [%s] was expected to be a [%s]. This was seen in file [%s] on line\n\n%s",
	 bad_field_count => "The line\n\n%s\n\nfrom file\n\n%s\n\nfor a track of type [%s] did not have the expected number of fields, which for this track type are\n\n%s",
	 no_such_re => "You tried to test the number [%s] with a number regular expression of type [%s] but this type is not defined. Regexp::Common module returned error [%s]",
	 bad_number => "The number [%s] did not match expected type [%s].",
	 bad_number_range => "The number [%s] of type [%s] falls outside of allowable range [ %s-%s ].",
	 no_such_ideogram => "You referenced chromosome [%s] in file [%s], but this chromosome is not defined. Check the karyotype file.\n\n%s",
}; 
 
$ERROR{warning} =
{
 general => "%s",
 data_range_exceeded => "Data point of type [%s] [%s] extended past end of ideogram [%s %s]. This data point will be [%s].",
 track_has_no_file => "Track id [%s] of type [%s] has no file definition. This is alright if you're using the track for side-effects like axes and backgrounds.",
 track_has_no_type => "Track id [%s] has no type definition. This is alright if you're using the track for side-effects like axes and backgrounds.",
 paranoid => "Circos produced a warning and quit because you are running it in paranoid mode. The warning does not nececessarily mean that something is wrong - Circos was likely trying to guess a parameter or massage data to fit the figure.\nTo change this setting, use -noparanoid flag or change the 'paranoid' parameter in etc/housekeeping.conf to 'paranoid=no'.",
};

$ERROR{heatmap} =
{
 rescale_boundary_bad_fmt => "Could not parse the color mapping boundary string [%s]. The format is x1:z1,x2:z2,... where xi is the position desired for color index zi.",
 rescale_boundary_bad_value => "The the color mapping boundary value [%s] is not an integer.",
 rescale_boundary_bad_position => "The the color mapping boundary position [%s] is not a number.",
 rescale_boundary_value_out_of_bounds => "You asked to rescale the color mapping to center color index [%d] on value [%f]. The index is out of range -- you only have [%d] colors to pick from. Set the color index to be in the range [0-%d]",
 rescale_boundary_position_out_of_bounds => "The color mapping boundary [%f] is beyond the range of plot value range [%f,%f]",
 rescale_boundary_value_not_increasing => "Your color mapping boundaries do not specify increasing color index. Saw successive values of [%d] and [%d].",
 rescale_boundary_position_not_increasing => "Your color mapping boundaries do not specify increasing positions. Saw successive positions of [%d] and [%d].",
};

$ERROR{track} =
{
 max_number => "You have asked to draw [%d] data points in a [%s] track from file\n\n %s\n\nbut the maximum is currently set at [%d]. To increase this number change max_points_per_track in etc/housekeeping.conf. Keep in mind that drawing that many data points may create an image that is too busy and uninterpretable.",
 min_larger_than_max => "Plot min value [%f] is larger than max [%f]",
 start_larger_than_end => "Input data line in file [%s] for track type [%s] has start position [%s] greater than end position [%s].",
 bad_type => "Track type [%s] is not a valid type. Choose one of [%s]. The offending track was\n\n %s",
 no_type => "You must specify a type for a track. Choose one of [%s]. The offending track id [%s] was\n\n %s",
 no_file => "You must specify a file for a track. The offending track had type [%s] and id [%s]\n\n %s",
 duplicate_names => "Multiple track blocks with name [%s] are defined. This is not supported.",
 too_many_axes => "You asked for an axis with spacing [%s]. This would result in a very large number [%d] of axes. Is this what you want?",
 division => "Cannot divide 0-sized chromosome region [%d,%d] for ticks [%s].",
};

$ERROR{links} = 
{
    max_number => "You have asked to draw [%d] links from file\n\n %s\n\nbut the maximum is currently set at [%d]. To increase this number change max_links in etc/housekeeping.conf. Keep in mind that drawing that many links may create an image that is too busy and uninterpretable.",
    duplicate_names => "Multiple link data sets with name [%s] are defined. This is not supported.",
    single_entry => "Link [%s] in file [%s] has a single positional entry. A link must have two entries - a start and an end.\n\n %s",
    too_many_entries => "Link [%s] in file [%s] has [%s] coordinates. A link must have two coordinates - a start and an end.\n\n %s",
    too_thick =>"You are attempting to draw a bezier curve of thickness greater than 100 [%d]. This would take a very long time and you don't want to do this.",
    too_thin =>"You are attempting to draw a bezier curve of thickness less than 1 [%d]. This would produce nothing. Is this what you want? If so, hide the link. If not, set the thickness to be at least 1.",

};

$ERROR{module} = 
{
   missing => "You are missing the module [%s]. Use CPAN to install it as described in this tutorial\n\nhttp://www.circos.ca/documentation/tutorials/configuration/perl_and_modules",
};

$ERROR{map} = 
{
    url_param_not_set => "You have tried to use the URL [%s] for an image map, but the parameter in the url [%s] has no value defined for this data point or data set.\nTo make this error go away, either (a) define the parameter, (b) set\n image_map_missing_parameter = blank\nto remove the undefined parameter from the image element, or (c) set\n image_map_missing_parameter = removeurl\nto remove the URL from the image element.",
};

$ERROR{data} =
{
    data_range_exceeded => "Data point of type [%s] [%s] extended past end of ideogram [%s %s]. You've set data_out_of_range=fatal, so Circos is quitting. See etc/housekeeping.conf for other options of this parameter.",
    bad_karyotype_format => "Could not parse line from karyotype file [%s].",
    bad_karyotype_format => "Could not parse line from karyotype file. The line\n\n  %s\n\nis missing fields. The correct format is\n\n  chr - chr_name chr_label start end color options\n\nfor chromosomes and\n\n  band chr_name band_name band_label start end color options\n\nfor cytogenetic bands. Please see data/karyotype in the distribution for examples.",
    malformed_span => "There was a problem initializing a span. Saw start [%s] > end [%s].",
    repeated_chr_in_karyotype => "Chromosome [%s] defined more than once in karyotype file.",
    malformed_karyotype_coordinates => "Start [%s] and/or end [%s] coordinate in karyotype file don't appear to be numbers. Thousands separators , and _ are allowed, but not any other characters.",
    unknown_karyotype_line => "You have a line starting with field [%s] in the karyotype file but currently only 'chr' or 'band' lines are supported.\n\n%s",
    inconsistent_karyotype_coordinates => "Start [%s] must be smaller than end [%s] coordinate in karyotype file.",
    band_on_missing_chr => "Bands for chromosome [%s] are defined but the chromosome itself has no definition.\nIs there a 'chr' line for this chromosome in the karyotype file?",
    band_sticks_out => "Band [%s] on chromosome [%s] has coordinates that extend outside chromosome.",
    band_overlaps => "Band [%s] on chromosome [%s] overlaps with another band by more than [%s].",
};

$ERROR{ticks} =
	{
	 bad_suffix => "You used the suffix [%s] in the string [%s]. This suffix is not defined. Use one of K, G, M, or T (or Kb, Gb, Mb, Tb)",
	 unparsable => "The string [%s] cannot be parsed into a numerical quantity.",
	 too_many   => "You are trying to draw [%s] ticks on ideogram [%s]. This is a lot of ticks and will take a very long time. Make sure that chromosomes_units parameter is set and read this tutorial\n\nhttp://www.circos.ca/documentation/tutorials/ticks_and_labels/basics/\n\nTo change the maximum tick number, adjust 'max_ticks' in etc/housekeeping.conf",
};

$ERROR{function} =
{
    remap_wrong_num_args => "You must pass five parameters to remap(). The syntax is\n remap(value,min,max,remap_min,remap_max)",
    remap_min_max =>        "You must pass five parameters to remap(). The syntax is\n remap(value,min,max,remap_min,remap_max)\nYou have set min [%s] = max [%s], but this only makes sense if remap_min [%s] = remap_max [%s].",
    pairwise => "You have tried to use the %s(a,b,x,y) function but one of the arguments a=[%s] b=[%s] c=[%s] d=[%s] is undefined.",
    sample_list_bad_arg => "Argument to sample_list must be a list but saw [%s] of type [%s].",
};

$ERROR{unit} =
{
    conversion_fail => "Unable to convert a value [%s] from one unit [%s] to another [%s]. The following from->to combinations were expected: %s",
};

$ERROR{system} =
{
 bad_error_name => "What do you know - a fatal error caused by bad error handling.\nThe error category [%s] and name [%s] is invalid.",
 missing_units_ok => "The parameter 'units_ok' is not defined (usually found in etc/housekeeping.conf). This parameter defines allowable units and is required. Set it to\n units_ok = %s",
 missing_units_nounit => "The parameter 'units_nounit' is not defined (usually found in etc/housekeeping.conf). This parameter defines the explicit suffix for unitless quantities. Set it to\n units_nounit = %s",
 wrong_unit => "The parameter [%s] value [%s] does not have the correct unit. Saw [%s] but expected one of [%s].",
 undef_parameter => "The parameter [%s] was not defined. It needs to be defined and have one of these units [%s].",
 unit_format_fail => "The unit [%s] failed format check. The list of allowable units is set by 'units_ok' (usually in etc/housekeeping.conf).",
 bad_dimension => "Dimension [%s] is not defined in expression [%s]",
 hash_leaf_undef => "You tried to access the key [%s] of a hash, but it does not exist.",
};

$ERROR{support} =
{
    googlegroup=>"If you are having trouble debugging this error, first read the best practices tutorial for helpful tips that address many common problems\n http://www.circos.ca/documentation/tutorials/reference/best_practices\nThe debugging facility is helpful to figure out what's happening under the hood\n http://www.circos.ca/documentation/tutorials/configuration/debugging\nIf you're still stumped, get support in the Circos Google Group. Please include this error and all your configuration and data files.\n http://groups.google.com/group/circos-data-visualization",
};

sub error {
    my ($cat,$errorid,@args) = @_;
    my $error_text = $ERROR{$cat}{$errorid};
    if(! defined $error_text) {
			fatal_error("system","bad_error_name",$cat,$errorid);
    }
    if($error_text =~ /file\((.*)\)/) {
			my $file = Circos::Utils::locate_file(file=>$1,name=>"error file",return_undef=>1);
			if($file && open(F,$file)) {
				$error_text = join("",<F>);
				close(F);
			} else {
				$error_text = "...error text from [$1] could not be read...";
			}
    }
    my (@text,$format);
    my $undef_text = Circos::Configuration::fetch_conf("debug_undef_text") || "_undef_";
    @args = map { defined $_ ? $_ : $undef_text } @args;
    if($cat eq "warning") {
			if(Circos::Configuration::fetch_conf("paranoid")) {
				@text = ("WARNING *** "
								 .
								 ($GROUPERROR{$cat} ? uc $GROUPERROR{$cat} : $EMPTY_STR)
								 .
								 sprintf($error_text,@args));
				#$format = 1;
			} else {
				printdebug_group("!circoswarning",uc $GROUPERROR{$cat},sprintf($error_text,@args));
				return;
			}
    } else {
			@text = ("*** CIRCOS ERROR ***",
							 sprintf("     cwd: %s",cwd()),
							 sprintf(" command: %s",join(" ",$0,$main::OPT{"_argv"})),
							 $GROUPERROR{$cat} ? uc $GROUPERROR{$cat} : $EMPTY_STR,
							 sprintf($error_text,@args),
							 $ERROR{support}{googlegroup},
							 "",
							 "Stack trace:",
							);
			$format = 1;
    }
    if($format) {
			my @text_fmt;
			for my $t (@text) {
				for my $line (split(/\n/, $t)) {
					if ($line =~ /^\s/) {
						push @text_fmt, Text::Format->new({leftMargin=>6,columns=>80,firstIndent=>0})->paragraphs($line);
					} else {
						push @text_fmt, Text::Format->new({leftMargin=>2,columns=>80,firstIndent=>0})->paragraphs($line);
					}
				}
			}
			print "\n" . join("\n", @text_fmt);
    } else {
			print join(" ",@text)."\n";
    }
	}

sub fake_error {
	my $error_path = shift;
	# fake an error, if we must
	my ($cat,$name) = split($COMMA,$error_path);
	if(! $cat && ! $name) {
		printinfo("The following error categories and IDs are available.");
		for my $cat (sort keys %ERROR) {
	    printinfo($cat);
	    for my $name (sort keys %{$ERROR{$cat}}) {
				printinfo(" ",$name);
	    }
		}
		exit;
	} elsif (! $name) {
		printinfo("The following errors are available for category [$cat]");
	for my $name (sort keys %{$ERROR{$cat}}) {
	    printinfo(" ",$name);
	}
	exit;	
    } elsif (! $cat) {
	my $found;
	printinfo("The following categories contain the error ID [$name]");
	for my $thiscat (sort keys %ERROR) {
	    for my $thisname (sort keys %{$ERROR{$thiscat}}) {
		if($name eq $thisname) {
		    printinfo($thiscat,$name);
		    $found = 1;
		}
	    }
	}
	printinfo("Could not find error name [$name] in any error category") if ! $found;
	exit;
    } else {
	fatal_error($cat,$name, map { 0 } (1..10) );
    }
}

sub fatal_error {
    error(@_);
    confess;
}

1;
