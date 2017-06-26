#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use IO::File;

my $genomeIndexFile = "";
my $scaffoldFiles   = "";
my $scafftigsBED    = "";
my $agpFile         = "";
my $numScaff        = 90;
my $rawConf = "rawConf.conf";
my $prefix = "circos";
my $result          = GetOptions(
	's=s' => \$scaffoldFiles,
	'g=s' => \$genomeIndexFile,
	'n=i' => \$numScaff,
	'b=s' => \$scafftigsBED,
	'a=s' => \$agpFile,
	'r=s' => \$rawConf,
	'p=s' => \$prefix
);

$numScaff = $numScaff / 100;

if ( $genomeIndexFile eq "" || $scaffoldFiles eq "" ) {
	die "-s -b and -g parameters needed";
}

my %scaffolds;
my %scaffoldsSize;
my @chrOrder = (
	"hs1",  "hs2",  "hs3",  "hs4",  "hs5",  "hs6",  "hs7",  "hs8",
	"hs9",  "hs10", "hs11", "hs12", "hs13", "hs14", "hs15", "hs16",
	"hs17", "hs18", "hs19", "hs20", "hs21", "hs22", "hsX"
);

#convert labels
my %chrNames = (
	"CM000663.2" => "chr1",
	"CM000664.2" => "chr2",
	"CM000665.2" => "chr3",
	"CM000666.2" => "chr4",
	"CM000667.2" => "chr5",
	"CM000668.2" => "chr6",
	"CM000669.2" => "chr7",
	"CM000670.2" => "chr8",
	"CM000671.2" => "chr9",
	"CM000672.2" => "chr10",
	"CM000673.2" => "chr11",
	"CM000674.2" => "chr12",
	"CM000675.2" => "chr13",
	"CM000676.2" => "chr14",
	"CM000677.2" => "chr15",
	"CM000678.2" => "chr16",
	"CM000679.2" => "chr17",
	"CM000680.2" => "chr18",
	"CM000681.2" => "chr19",
	"CM000682.2" => "chr20",
	"CM000683.2" => "chr21",
	"CM000684.2" => "chr22",
	"CM000685.2" => "chrx",
	"CM000686.2" => "chry"
);

#convert labels
my %labelNames = (
	"CM000663.2" => "hs1",
	"CM000664.2" => "hs2",
	"CM000665.2" => "hs3",
	"CM000666.2" => "hs4",
	"CM000667.2" => "hs5",
	"CM000668.2" => "hs6",
	"CM000669.2" => "hs7",
	"CM000670.2" => "hs8",
	"CM000671.2" => "hs9",
	"CM000672.2" => "hs10",
	"CM000673.2" => "hs11",
	"CM000674.2" => "hs12",
	"CM000675.2" => "hs13",
	"CM000676.2" => "hs14",
	"CM000677.2" => "hs15",
	"CM000678.2" => "hs16",
	"CM000679.2" => "hs17",
	"CM000680.2" => "hs18",
	"CM000681.2" => "hs19",
	"CM000682.2" => "hs20",
	"CM000683.2" => "hs21",
	"CM000684.2" => "hs22",
	"CM000685.2" => "hsX",
	"CM000686.2" => "hsY"
);

#convert labels
my %values = (
	"CM000663.2" => "1",
	"CM000664.2" => "2",
	"CM000665.2" => "3",
	"CM000666.2" => "4",
	"CM000667.2" => "5",
	"CM000668.2" => "6",
	"CM000669.2" => "7",
	"CM000670.2" => "8",
	"CM000671.2" => "9",
	"CM000672.2" => "10",
	"CM000673.2" => "11",
	"CM000674.2" => "12",
	"CM000675.2" => "13",
	"CM000676.2" => "14",
	"CM000677.2" => "15",
	"CM000678.2" => "16",
	"CM000679.2" => "17",
	"CM000680.2" => "18",
	"CM000681.2" => "19",
	"CM000682.2" => "20",
	"CM000683.2" => "21",
	"CM000684.2" => "22",
	"CM000685.2" => "X",
	"CM000686.2" => "Y"
);

#centromeres
my $centromere = <<EOT;
hs1 121700000 125100000 O
hs10 38000000 41600000 O
hs11 51000000 55800000 O
hs12 33200000 37800000 O
hs13 16500000 18900000 O
hs14 16100000 18200000 O
hs15 17500000 20500000 O
hs16 35300000 38400000 O
hs17 22700000 27400000 O
hs18 15400000 21500000 O
hs19 24200000 28100000 O
hs2 91800000 96000000 O
hs20 25700000 30400000 O
hs21 10900000 13000000 O
hs22 13700000 17400000 O
hs3 87800000 94000000 O
hs4 48200000 51800000 O
hs5 46100000 51400000 O
hs6 58500000 62600000 O
hs7 58100000 62100000 O
hs8 43200000 47200000 O
hs9 42200000 45500000 O
hsX 58100000 63800000 O
hsY 10300000 10600000 O
EOT

#cytogenetic bands
my $cytoBand = <<EOT;
band hs1 N N 125184587 143184587 black
band hs1 N N 228558364 228608364 black
band hs1 N N 12954384 13004384 black
band hs1 N N 223558935 223608935 black
band hs1 N N 0 10000 black
band hs1 N N 207666 257666 black
band hs1 N N 297968 347968 black
band hs1 N N 535988 585988 black
band hs1 N N 2702781 2746290 black
band hs1 N N 16799163 16849163 black
band hs1 N N 29552233 29553835 black
band hs1 N N 121976459 122026459 black
band hs1 N N 122224535 122224635 black
band hs1 N N 122503147 122503247 black
band hs1 N N 124785432 124785532 black
band hs1 N N 124849129 124849229 black
band hs1 N N 124932724 124932824 black
band hs1 N N 124977944 124978326 black
band hs1 N N 125013060 125013223 black
band hs1 N N 125026048 125026071 black
band hs1 N N 125029104 125029169 black
band hs1 N N 125103213 125103233 black
band hs1 N N 125130246 125131847 black
band hs1 N N 125171347 125173583 black
band hs1 N N 248946422 248956422 black
band hs2 N N 0 10000 black
band hs2 N N 16145119 16146119 black
band hs2 N N 89330679 89530679 black
band hs2 N N 89685992 89753992 black
band hs2 N N 90402511 91402511 black
band hs2 N N 92138145 92188145 black
band hs2 N N 94090557 94140557 black
band hs2 N N 94293015 94496015 black
band hs2 N N 97439618 97489618 black
band hs2 N N 238903659 238904047 black
band hs2 N N 242183529 242193529 black
band hs3 N N 0 10000 black
band hs3 N N 90550102 90550202 black
band hs3 N N 90565295 90568828 black
band hs3 N N 90699772 90699792 black
band hs3 N N 90722458 90772458 black
band hs3 N N 91233586 91233686 black
band hs3 N N 91247622 91247722 black
band hs3 N N 91249905 91256421 black
band hs3 N N 91257890 91260180 black
band hs3 N N 91265381 91276994 black
band hs3 N N 91282175 91282734 black
band hs3 N N 91291069 91291218 black
band hs3 N N 91345078 91345173 black
band hs3 N N 91364131 91364151 black
band hs3 N N 91438798 91438818 black
band hs3 N N 91553319 91553419 black
band hs3 N N 93655574 93705574 black
band hs3 N N 198235559 198285559 black
band hs3 N N 198285559 198295559 black
band hs4 N N 0 10000 black
band hs4 N N 1429358 1434206 black
band hs4 N N 1435794 1441552 black
band hs4 N N 8797477 8816477 black
band hs4 N N 9272916 9322916 black
band hs4 N N 31819295 31832569 black
band hs4 N N 31835775 31835795 black
band hs4 N N 32833016 32839016 black
band hs4 N N 49336924 49486924 black
band hs4 N N 49658100 49708100 black
band hs4 N N 49711961 49712061 black
band hs4 N N 51743951 51793951 black
band hs4 N N 58878793 58921381 black
band hs4 N N 190123121 190173121 black
band hs4 N N 190204555 190214555 black
band hs5 N N 17530548 17580548 black
band hs5 N N 50059807 50109807 black
band hs5 N N 181528259 181538259 black
band hs5 N N 0 10000 black
band hs5 N N 46435900 46485900 black
band hs5 N N 46569062 46569162 black
band hs5 N N 46796725 46796825 black
band hs5 N N 47061288 47061388 black
band hs5 N N 47069162 47073730 black
band hs5 N N 47078603 47078720 black
band hs5 N N 47079733 47082080 black
band hs5 N N 47106894 47106994 black
band hs5 N N 47153339 47153439 black
band hs5 N N 47296069 47296169 black
band hs5 N N 47300585 47306086 black
band hs5 N N 47309084 47309184 black
band hs5 N N 49591369 49591469 black
band hs5 N N 49592920 49599323 black
band hs5 N N 49600986 49601086 black
band hs5 N N 49603131 49609714 black
band hs5 N N 49611721 49612096 black
band hs5 N N 49618994 49621605 black
band hs5 N N 49628165 49630729 black
band hs5 N N 49633793 49641815 black
band hs5 N N 49646823 49646923 black
band hs5 N N 49650573 49656261 black
band hs5 N N 49661871 49666173 black
band hs5 N N 49667431 49667531 black
band hs5 N N 49721203 49721303 black
band hs5 N N 139452659 139453659 black
band hs5 N N 155760324 155761324 black
band hs5 N N 181478259 181528259 black
band hs6 N N 58453888 58553888 black
band hs6 N N 59829934 60229934 black
band hs6 N N 95020790 95070790 black
band hs6 N N 167591393 167641393 black
band hs6 N N 170745979 170795979 black
band hs6 N N 0 10000 black
band hs6 N N 10000 60000 black
band hs6 N N 61357029 61363066 black
band hs6 N N 61370554 61371372 black
band hs6 N N 61378482 61378582 black
band hs6 N N 61381502 61381602 black
band hs6 N N 61393846 61393946 black
band hs6 N N 61398161 61398261 black
band hs6 N N 170795979 170805979 black
band hs7 N N 0 10000 black
band hs7 N N 237846 240242 black
band hs7 N N 58119653 58169653 black
band hs7 N N 60828234 60878234 black
band hs7 N N 61063378 61063426 black
band hs7 N N 61327788 61377788 black
band hs7 N N 61528020 61578020 black
band hs7 N N 61964169 61967063 black
band hs7 N N 61976104 62026104 black
band hs7 N N 62456779 62506779 black
band hs7 N N 143650804 143700804 black
band hs7 N N 159335973 159345973 black
band hs8 N N 0 10000 black
band hs8 N N 10000 60000 black
band hs8 N N 7617127 7667127 black
band hs8 N N 12234345 12284345 black
band hs8 N N 43983744 44033744 black
band hs8 N N 45877265 45927265 black
band hs8 N N 85664222 85714222 black
band hs8 N N 145078636 145128636 black
band hs8 N N 145128636 145138636 black
band hs9 N N 45518558 60518558 black
band hs9 N N 60779521 60829521 black
band hs9 N N 63918447 63968447 black
band hs9 N N 64998124 65048124 black
band hs9 N N 67920552 68220552 black
band hs9 N N 61468808 61518808 black
band hs9 N N 62748832 62798832 black
band hs9 N N 64215162 64315162 black
band hs9 N N 66391387 66591387 black
band hs9 N N 0 10000 black
band hs9 N N 40529470 40529480 black
band hs9 N N 40537052 40537134 black
band hs9 N N 40547487 40547497 black
band hs9 N N 40561938 40561948 black
band hs9 N N 41225986 41229378 black
band hs9 N N 41237752 41238504 black
band hs9 N N 43222167 43236167 black
band hs9 N N 43240559 43240579 black
band hs9 N N 43254332 43254352 black
band hs9 N N 43263290 43263820 black
band hs9 N N 43268730 43268750 black
band hs9 N N 43270944 43274935 black
band hs9 N N 43276248 43276457 black
band hs9 N N 43281323 43282956 black
band hs9 N N 43332174 43333269 black
band hs9 N N 43370405 43371325 black
band hs9 N N 43377453 43382279 black
band hs9 N N 43389535 43389635 black
band hs9 N N 60688432 60738432 black
band hs9 N N 61003887 61053887 black
band hs9 N N 61231966 61281966 black
band hs9 N N 61735368 61785368 black
band hs9 N N 62149738 62249738 black
band hs9 N N 62958371 63008371 black
band hs9 N N 63202862 63252862 black
band hs9 N N 63492264 63542264 black
band hs9 N N 64135013 64185013 black
band hs9 N N 65080082 65130082 black
band hs9 N N 65325123 65375123 black
band hs9 N N 65595191 65645191 black
band hs9 N N 134183092 134185536 black
band hs9 N N 138334717 138384717 black
band hs9 N N 138384717 138394717 black
band hsX N N 1949345 2132994 black
band hsX N N 114281198 114331198 black
band hsX N N 37099262 37285837 black
band hsX N N 49348394 49528394 black
band hsX N N 58555579 58605579 black
band hsX N N 144425606 144475606 black
band hsX N N 0 10000 black
band hsX N N 44821 94821 black
band hsX N N 133871 222346 black
band hsX N N 226276 226351 black
band hsX N N 2137388 2137488 black
band hsX N N 50228964 50278964 black
band hsX N N 62412542 62462542 black
band hsX N N 115738949 115838949 black
band hsX N N 116557779 116595566 black
band hsX N N 120879381 120929381 black
band hsX N N 156030895 156040895 black
band hs10 N N 41916265 42066265 black
band hs10 N N 38529907 38573338 black
band hs10 N N 41593521 41693521 black
band hs10 N N 47780368 47870368 black
band hs10 N N 133690466 133740466 black
band hs10 N N 0 10000 black
band hs10 N N 38906036 38911580 black
band hs10 N N 38913438 38918269 black
band hs10 N N 39229918 39230136 black
band hs10 N N 39238955 39239118 black
band hs10 N N 39254773 39254793 black
band hs10 N N 39338430 39338450 black
band hs10 N N 39341685 39341705 black
band hs10 N N 39409792 39410237 black
band hs10 N N 39479351 39479371 black
band hs10 N N 39497198 39497296 black
band hs10 N N 39570652 39570672 black
band hs10 N N 39585287 39590435 black
band hs10 N N 39593013 39597435 black
band hs10 N N 39598812 39598832 black
band hs10 N N 39602699 39606089 black
band hs10 N N 39607431 39607451 black
band hs10 N N 39613189 39615618 black
band hs10 N N 39617141 39617255 black
band hs10 N N 39622353 39625274 black
band hs10 N N 39635037 39635057 black
band hs10 N N 39636682 39686682 black
band hs10 N N 39935900 39936000 black
band hs10 N N 41497440 41497540 black
band hs10 N N 41545720 41545820 black
band hs10 N N 124121200 124121502 black
band hs10 N N 131597030 131597130 black
band hs10 N N 133787422 133797422 black
band hs11 N N 0 10000 black
band hs11 N N 10000 60000 black
band hs11 N N 50821348 50871348 black
band hs11 N N 50871348 51078348 black
band hs11 N N 51090317 51090417 black
band hs11 N N 54342399 54342499 black
band hs11 N N 54425074 54525074 black
band hs11 N N 70955696 71055696 black
band hs11 N N 87978202 88002896 black
band hs11 N N 96566178 96566364 black
band hs11 N N 135076622 135086622 black
band hs12 N N 34719407 34769407 black
band hs12 N N 37185252 37235252 black
band hs12 N N 0 10000 black
band hs12 N N 7083650 7084650 black
band hs12 N N 34816611 34816711 black
band hs12 N N 34820185 34820285 black
band hs12 N N 34822289 34829237 black
band hs12 N N 34832088 34832188 black
band hs12 N N 34835195 34835295 black
band hs12 N N 37240944 37245716 black
band hs12 N N 37255332 37257055 black
band hs12 N N 37333222 37333242 black
band hs12 N N 37334747 37334767 black
band hs12 N N 37379851 37380460 black
band hs12 N N 37460032 37460128 black
band hs12 N N 132223362 132224362 black
band hs12 N N 133265309 133275309 black
band hs13 N N 10000 16000000 black
band hs13 N N 18071248 18171248 black
band hs13 N N 86202979 86252979 black
band hs13 N N 111793441 111843441 black
band hs13 N N 0 10000 black
band hs13 N N 16022537 16022637 black
band hs13 N N 16110659 16110759 black
band hs13 N N 16164892 16164992 black
band hs13 N N 16228527 16228627 black
band hs13 N N 16249297 16249397 black
band hs13 N N 16256067 16256167 black
band hs13 N N 16259412 16259512 black
band hs13 N N 16282073 16282173 black
band hs13 N N 17416384 17416484 black
band hs13 N N 17416824 17416924 black
band hs13 N N 17417264 17417364 black
band hs13 N N 17418562 17418662 black
band hs13 N N 18051248 18071248 black
band hs13 N N 18358106 18408106 black
band hs13 N N 111703855 111753855 black
band hs13 N N 113673020 113723020 black
band hs13 N N 114354328 114364328 black
band hs14 N N 10000 16000000 black
band hs14 N N 106883718 107033718 black
band hs14 N N 18173523 18223523 black
band hs14 N N 18712644 18862644 black
band hs14 N N 19511713 19611713 black
band hs14 N N 0 10000 black
band hs14 N N 16022537 16022637 black
band hs14 N N 16053976 16054459 black
band hs14 N N 16061677 16061993 black
band hs14 N N 16086625 16089562 black
band hs14 N N 16096530 16096630 black
band hs14 N N 16105376 16113232 black
band hs14 N N 16130858 16133335 black
band hs14 N N 16140527 16140627 black
band hs14 N N 16228649 16228749 black
band hs14 N N 16282882 16282982 black
band hs14 N N 16346517 16346617 black
band hs14 N N 16367287 16367387 black
band hs14 N N 16374057 16374157 black
band hs14 N N 16377402 16377502 black
band hs14 N N 16400063 16400163 black
band hs14 N N 16404348 16404448 black
band hs14 N N 17538659 17538759 black
band hs14 N N 17539099 17539199 black
band hs14 N N 17539539 17539639 black
band hs14 N N 17540837 17540937 black
band hs14 N N 107033718 107043718 black
band hs15 N N 10000 17000000 black
band hs15 N N 20689304 20729746 black
band hs15 N N 21193490 21242090 black
band hs15 N N 84270066 84320066 black
band hs15 N N 0 10000 black
band hs15 N N 17049135 17049334 black
band hs15 N N 17076577 17076597 black
band hs15 N N 17083573 17083673 black
band hs15 N N 17498951 17499051 black
band hs15 N N 18355008 18355108 black
band hs15 N N 19725254 19775254 black
band hs15 N N 21778502 21828502 black
band hs15 N N 22308242 22358242 black
band hs15 N N 23226874 23276874 black
band hs15 N N 101981189 101991189 black
band hs16 N N 0 10000 black
band hs16 N N 18436486 18486486 black
band hs16 N N 33214595 33264595 black
band hs16 N N 33392411 33442411 black
band hs16 N N 34289329 34339329 black
band hs16 N N 34521510 34571510 black
band hs16 N N 34576805 34580965 black
band hs16 N N 34584085 34584622 black
band hs16 N N 36260386 36260628 black
band hs16 N N 36261158 36311158 black
band hs16 N N 36334460 36334560 black
band hs16 N N 36337566 36337666 black
band hs16 N N 38265669 38265769 black
band hs16 N N 38269096 38275758 black
band hs16 N N 38280682 46280682 black
band hs16 N N 46280682 46380682 black
band hs16 N N 90228345 90328345 black
band hs16 N N 90328345 90338345 black
band hs17 N N 0 10000 black
band hs17 N N 10000 60000 black
band hs17 N N 448188 488987 black
band hs17 N N 490395 491111 black
band hs17 N N 21795850 21814103 black
band hs17 N N 21860937 21860957 black
band hs17 N N 21976511 21976531 black
band hs17 N N 21983452 21983554 black
band hs17 N N 21984549 21985100 black
band hs17 N N 21992061 22042061 black
band hs17 N N 22089188 22089410 black
band hs17 N N 22763679 22813679 black
band hs17 N N 23194918 23195018 black
band hs17 N N 26566633 26566733 black
band hs17 N N 26616164 26616264 black
band hs17 N N 26627010 26627349 black
band hs17 N N 26638554 26638627 black
band hs17 N N 26640334 26640620 black
band hs17 N N 26643468 26643843 black
band hs17 N N 26698590 26698998 black
band hs17 N N 26720420 26721376 black
band hs17 N N 26735204 26735774 black
band hs17 N N 26805755 26805775 black
band hs17 N N 26820065 26820266 black
band hs17 N N 26859724 26860166 black
band hs17 N N 26876740 26876850 black
band hs17 N N 26880254 26880354 black
band hs17 N N 26885980 26935980 black
band hs17 N N 81742542 81792542 black
band hs17 N N 81796281 81797727 black
band hs17 N N 81798717 81799133 black
band hs17 N N 83247441 83257441 black
band hs18 N N 0 10000 black
band hs18 N N 15410899 15460899 black
band hs18 N N 15780377 15780477 black
band hs18 N N 15788380 15791047 black
band hs18 N N 15797755 15797855 black
band hs18 N N 20561439 20561539 black
band hs18 N N 20564714 20571466 black
band hs18 N N 20582635 20582735 black
band hs18 N N 20603147 20603247 black
band hs18 N N 20696289 20696389 black
band hs18 N N 20736025 20736125 black
band hs18 N N 20813083 20813183 black
band hs18 N N 20830724 20831341 black
band hs18 N N 20835547 20835592 black
band hs18 N N 20839697 20839797 black
band hs18 N N 20861206 20911206 black
band hs18 N N 46969912 47019912 black
band hs18 N N 54536574 54537528 black
band hs18 N N 80263285 80363285 black
band hs18 N N 80363285 80373285 black
band hs19 N N 0 10000 black
band hs19 N N 10000 60000 black
band hs19 N N 24448980 24498980 black
band hs19 N N 24552652 24552752 black
band hs19 N N 24891256 24891356 black
band hs19 N N 24895790 24895890 black
band hs19 N N 24898313 24904771 black
band hs19 N N 24908589 24908689 black
band hs19 N N 27190874 27240874 black
band hs19 N N 58607616 58617616 black
band hs20 N N 30761898 30811898 black
band hs20 N N 64334167 64434167 black
band hs20 N N 0 10000 black
band hs20 N N 10000 60000 black
band hs20 N N 63215 63840 black
band hs20 N N 66235 66335 black
band hs20 N N 26348365 26348390 black
band hs20 N N 26364240 26365414 black
band hs20 N N 26382164 26382616 black
band hs20 N N 26386232 26436232 black
band hs20 N N 26586955 26587055 black
band hs20 N N 26590875 26596363 black
band hs20 N N 26608045 26608145 black
band hs20 N N 28494539 28494639 black
band hs20 N N 28499358 28504764 black
band hs20 N N 28508897 28508997 black
band hs20 N N 28556953 28557053 black
band hs20 N N 28646195 28646295 black
band hs20 N N 28648008 28648108 black
band hs20 N N 28728874 28728974 black
band hs20 N N 28751119 28752590 black
band hs20 N N 28754750 28754770 black
band hs20 N N 28757831 28757851 black
band hs20 N N 28790010 28790158 black
band hs20 N N 28820603 28820663 black
band hs20 N N 28843401 28859997 black
band hs20 N N 28861347 28861367 black
band hs20 N N 28867524 28868452 black
band hs20 N N 28875884 28875904 black
band hs20 N N 28889198 28889218 black
band hs20 N N 28890335 28896362 black
band hs20 N N 29125693 29125793 black
band hs20 N N 29204668 29204768 black
band hs20 N N 29271546 29271826 black
band hs20 N N 29307456 29307476 black
band hs20 N N 29315342 29315821 black
band hs20 N N 29362154 29362183 black
band hs20 N N 29412507 29413577 black
band hs20 N N 29447838 29447883 black
band hs20 N N 29452158 29452178 black
band hs20 N N 29538733 29538783 black
band hs20 N N 29540234 29540284 black
band hs20 N N 29556103 29556141 black
band hs20 N N 29562970 29563363 black
band hs20 N N 29564411 29565353 black
band hs20 N N 29592644 29592737 black
band hs20 N N 29651590 29651610 black
band hs20 N N 29697363 29697630 black
band hs20 N N 29884750 29884850 black
band hs20 N N 29917304 29917404 black
band hs20 N N 30038348 30088348 black
band hs20 N N 30425128 30456077 black
band hs20 N N 31001508 31051508 black
band hs20 N N 31107036 31157036 black
band hs20 N N 31159119 31161625 black
band hs20 N N 64434167 64444167 black
band hs21 N N 10000 5010000 black
band hs21 N N 7327865 7377865 black
band hs21 N N 9377143 9527143 black
band hs21 N N 5627596 5677596 black
band hs21 N N 6377258 6427258 black
band hs21 N N 6934219 6984219 black
band hs21 N N 7693700 7743700 black
band hs21 N N 8472360 8522360 black
band hs21 N N 8886604 8986604 black
band hs21 N N 10169868 10269868 black
band hs21 N N 43212462 43262462 black
band hs21 N N 0 10000 black
band hs21 N N 5166246 5216246 black
band hs21 N N 5393558 5443558 black
band hs21 N N 5449012 5499012 black
band hs21 N N 5796009 5846009 black
band hs21 N N 5916593 5966593 black
band hs21 N N 6161371 6211371 black
band hs21 N N 6580181 6630181 black
band hs21 N N 6739085 6789085 black
band hs21 N N 7149527 7199527 black
band hs21 N N 7500890 7550890 black
band hs21 N N 7865746 7915746 black
band hs21 N N 8049839 8099839 black
band hs21 N N 8260971 8310971 black
band hs21 N N 8706715 8756715 black
band hs21 N N 9196087 9246087 black
band hs21 N N 10274327 10324327 black
band hs21 N N 10814560 10864560 black
band hs21 N N 10887097 10887197 black
band hs21 N N 10975219 10975319 black
band hs21 N N 11029452 11029552 black
band hs21 N N 11093087 11093187 black
band hs21 N N 11113857 11113957 black
band hs21 N N 11120627 11120727 black
band hs21 N N 11123972 11124072 black
band hs21 N N 11146633 11146733 black
band hs21 N N 12280944 12281044 black
band hs21 N N 12281384 12281484 black
band hs21 N N 12281824 12281924 black
band hs21 N N 12283122 12283222 black
band hs21 N N 12915808 12965808 black
band hs21 N N 41584292 41584392 black
band hs21 N N 46699983 46709983 black
band hs22 N N 10000 10510000 black
band hs22 N N 11497337 11547337 black
band hs22 N N 10874572 10924572 black
band hs22 N N 10966724 11016724 black
band hs22 N N 11378056 11428056 black
band hs22 N N 11631288 11681288 black
band hs22 N N 12438690 12488690 black
band hs22 N N 12818137 12868137 black
band hs22 N N 15054318 15154318 black
band hs22 N N 18433513 18483513 black
band hs22 N N 0 10000 black
band hs22 N N 10784643 10834643 black
band hs22 N N 11068987 11118987 black
band hs22 N N 11160921 11210921 black
band hs22 N N 11724629 11774629 black
band hs22 N N 11977555 12027555 black
band hs22 N N 12225588 12275588 black
band hs22 N N 12641730 12691730 black
band hs22 N N 12726204 12776204 black
band hs22 N N 12904788 12954788 black
band hs22 N N 12977325 12977425 black
band hs22 N N 12986171 12994027 black
band hs22 N N 13011653 13014130 black
band hs22 N N 13021322 13021422 black
band hs22 N N 13109444 13109544 black
band hs22 N N 13163677 13163777 black
band hs22 N N 13227312 13227412 black
band hs22 N N 13248082 13248182 black
band hs22 N N 13254852 13254952 black
band hs22 N N 13258197 13258297 black
band hs22 N N 13280858 13280958 black
band hs22 N N 13285143 13285243 black
band hs22 N N 14419454 14419554 black
band hs22 N N 14419894 14419994 black
band hs22 N N 14420334 14420434 black
band hs22 N N 14421632 14421732 black
band hs22 N N 16279672 16302843 black
band hs22 N N 16304296 16305427 black
band hs22 N N 16307048 16307605 black
band hs22 N N 16310302 16310402 black
band hs22 N N 16313516 16314010 black
band hs22 N N 18239129 18339129 black
band hs22 N N 18659564 18709564 black
band hs22 N N 49973865 49975365 black
band hs22 N N 50808468 50818468 black
EOT

my %direction;

system("cp " . $rawConf . " circos.conf -f");
open(my $fd, ">>circos.conf");
	

#create karyotype file
outputKaryotype();
outputLinks();

sub outputKaryotype {

	#load in genome file
	my $karyotype    = new IO::File(">data/karyotype.txt");
	my $genomeFileFH = new IO::File($genomeIndexFile);
	my $line         = $genomeFileFH->getline();
	my $genomeSize   = 0;

	while ($line) {
		chomp($line);

		#chr - hs1 1 0 248956422 chr1
		#CM000663.2	248956422	73	248956422	248956423
		my @tempArray = split( "\t", $line );
		unless ( $labelNames{ $tempArray[0] } eq "hsY" ) {
			$karyotype->write( "chr - "
				  . $labelNames{ $tempArray[0] } . " "
				  . $values{ $tempArray[0] } . " 0 "
				  . $tempArray[1] . " "
				  . $chrNames{ $tempArray[0] }
				  . "\n" );
		}
		$genomeSize += $tempArray[1];
		$line = $genomeFileFH->getline();
	}
	$genomeFileFH->close();

	my $scaffFH = new IO::File($scaffoldFiles);
	$line = $scaffFH->getline();
	
	my %scaffoldLengths;
	
	#load in fai file
	while ( $line ){
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[0];
		chomp($line);
		$scaffoldLengths{$scaffoldID} = $tempArray[1];
		$line = $scaffFH->getline();		
	}
	$scaffFH->close();
	
	#sort by length
	my @lengthOrder = sort { $scaffoldLengths{$a} <=> $scaffoldLengths{$b} } keys %scaffoldLengths;

	my $count       = 1;
	my $scaffoldSum = 0;

	foreach my $scaffoldID ( reverse @lengthOrder ) {
		
		if(( $genomeSize * $numScaff ) <= $scaffoldSum){
			last;
		}

		#remove underscores
		$scaffolds{$scaffoldID} = "scaffold" . $count;
		$direction{$scaffoldID} = 0;
		$karyotype->write( "chr - "
			  . $scaffolds{$scaffoldID}
			  . " $scaffolds{$scaffoldID} 0 "
			  . $scaffoldLengths{$scaffoldID} . " vvlgrey"
			  . "\n" );
		$scaffoldSum += $scaffoldLengths{$scaffoldID};
		$scaffoldsSize{$scaffoldID} = $scaffoldLengths{$scaffoldID};
		$count++;
	}
	
	#print out spacing information:
	my $defaultSpacing = 0.002;
	print $fd "<ideogram>\n<spacing>\ndefault = " . $defaultSpacing . "r\n";
	my $spacingSize = (scalar(@chrOrder) + (($genomeSize - $scaffoldSum)) / (2*$genomeSize*$defaultSpacing)) / ($count - 1);

	foreach ( keys(%scaffolds) ) {
		print $fd "<pairwise "
		  . $scaffolds{$_}
		  . ">\nspacing = "
		  . $spacingSize
		  . "r\n</pairwise>\n";
	}
	print $fd "</spacing>\n</ideogram>\n";
	print $fd "<image>\nfile  = $prefix.png\n</image>\n";
	
	my $plot = new IO::File(">data/plot.txt");
	$plot->write($centromere);
	$plot->close();

	$karyotype->write($cytoBand);
	$karyotype->close();
}

#create links file
sub outputLinks {

	my $agpFH = new IO::File($agpFile);
	my $line  = $agpFH->getline();
	my %scafftigLocationsFW;
	my %scafftigLocationsRV;
	my %scafftigSize;

	while ($line) {
		chomp($line);
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[0];
		$scaffoldID =~ s/^scaffold//;

		if ( exists( $scaffolds{$scaffoldID} ) && $tempArray[4] eq "W" ) {
			my $contigID = $tempArray[5];

			#special removal for LINKS created scaffolds
			if ( $contigID =~ /_[rf]/ ) {
				$contigID =~ s/_([rf])/$1/g;
			}
			if ( exists( $scafftigSize{$contigID} ) ) {
				print STDERR "$tempArray[5] exists!\n";
				print STDERR $scafftigLocationsFW{$contigID} . "\n";
				exit(1);
			}

			#correct for 0th position? (index starts at 1)
			$scafftigLocationsFW{$contigID} = $tempArray[1];
			$scafftigLocationsRV{$contigID} =
			  ( $scaffoldsSize{$scaffoldID} - $tempArray[2] );
			$scafftigSize{$contigID} = $tempArray[2] - $tempArray[1];
		}
		$line = $agpFH->getline();
	}
	$agpFH->close();

	my %bestScaffToChrCount;
	my %bestScaffToChrStart;

	my $bedFH = new IO::File($scafftigsBED);
	$line = $bedFH->getline();
	my $count2 = 0;

	while ($line) {
		chomp($line);

#hs1 100 200 hs2 250 300
#CM000667.2	165524114	165541850	contigscaffold7,63778938,f2072554Z57691322k42a0m10r2072561z3380221k43a0m10f2072570z2707395_3247	60	+
		my @tempArray = split( /\t/, $line );
		my $scaffoldID = $tempArray[3];
		$count2++;
		unless(defined $tempArray[3]){
			print $line . " $count2" . "\n";
			exit(1);
		}
		$scaffoldID =~ s/^contig//;
		$scaffoldID =~ s/_\d+$//;
		my $linkSize = $tempArray[2] - $tempArray[1];
		if ( exists $scaffolds{$scaffoldID} ) {
			my $contigID = $tempArray[3];
			if (
				!exists(
					$bestScaffToChrCount{$scaffoldID}->{ $labelNames{ $tempArray[0] } }
				)
			  )
			{
				$bestScaffToChrStart{$scaffoldID}->{ $labelNames{ $tempArray[0] } } = $tempArray[1];
				$bestScaffToChrCount{$scaffoldID}->{ $labelNames{ $tempArray[0] } } =
				  0;
			}
			else {
				$bestScaffToChrCount{$scaffoldID}->{ $labelNames{ $tempArray[0] } }++;
			}

			if ( $tempArray[5] eq "+" ) {
				$direction{$scaffoldID}++;
			}
			else {
				$direction{$scaffoldID}--;
				my $contigID = $tempArray[3];
			}
		}
		$line = $bedFH->getline();
	}
	$bedFH->close();

	my $links = new IO::File(">data/links.txt");
	$bedFH = new IO::File($scafftigsBED);
	$line  = $bedFH->getline();

	while ($line) {
		chomp($line);

#hs1 100 200 hs2 250 300
#CM000667.2	165524114	165541850	contigscaffold7,63778938,f2072554Z57691322k42a0m10r2072561z3380221k43a0m10f2072570z2707395_3247	60	+
		my @tempArray = split( /\t/, $line );
#		print $line . "\n";
		my $scaffoldID = $tempArray[3];
		$scaffoldID =~ s/^contig//;
		$scaffoldID =~ s/_\d+$//;
		my $linkSize = $tempArray[2] - $tempArray[1];
		if ( exists $scaffolds{$scaffoldID} ) {

			if ( $direction{$scaffoldID} >= 0 ) {
				my $contigID = $tempArray[3];
				if ( !exists( $scafftigSize{$contigID} ) ) {
					print $scaffoldID . " " . $contigID . "\n";
					exit(1);
				}
				$linkSize =
				    $linkSize < $scafftigSize{$contigID}
				  ? $linkSize
				  : $scafftigSize{$contigID};
				$links->write( $labelNames{ $tempArray[0] } . " "
					  . $tempArray[1] . " "
					  . $tempArray[2] . " "
					  . $scaffolds{$scaffoldID} . " "
					  . $scafftigLocationsRV{$contigID} . " "
					  . ( $scafftigLocationsRV{$contigID} + $linkSize )
					  . " color="
					  . $chrNames{ $tempArray[0] }
					  . "_a1\n" );
			}
			else {
				my $contigID = $tempArray[3];
				$linkSize =
				    $linkSize < $scafftigSize{$contigID}
				  ? $linkSize
				  : $scafftigSize{$contigID};
				$links->write( $labelNames{ $tempArray[0] } . " "
					  . $tempArray[1] . " "
					  . $tempArray[2] . " "
					  . $scaffolds{$scaffoldID} . " "
					  . $scafftigLocationsFW{$contigID} . " "
					  . ( $scafftigLocationsFW{$contigID} + $linkSize )
					  . " color="
					  . $chrNames{ $tempArray[0] }
					  . "_a1\n" );
			}
		}
		$line = $bedFH->getline();
	}
	
	my %scaffoldOrder;
	my %scaffoldStart;

	foreach my $key ( keys(%bestScaffToChrCount) ) {
		my $countsRef = $bestScaffToChrCount{$key};
		my $startsRef = $bestScaffToChrStart{$key};
		my $bestChr = 0;
		my $bestNum = 0;
		my $start = 0;
		foreach my $i ( keys(%{$countsRef})){
			if($countsRef->{$i} > $bestNum){
				$bestNum = $countsRef->{$i};
				$start = $startsRef->{$i};
				$bestChr = $i;
			}	
		}
		push(@{$scaffoldOrder{$bestChr}}, $scaffolds{$key});
		$scaffoldStart{$scaffolds{$key}} = $start;
	}
	
	print $fd "chromosomes_order = ";
	
	foreach ( reverse(@chrOrder) ) { 
		my @tempArray = sort { $scaffoldStart{$b} <=> $scaffoldStart{$a} } @{$scaffoldOrder{$_}};
		print $fd join(",", @tempArray) . ",";
	}
	
	for(my $i = 0; $i < scalar(@chrOrder) - 1; ++$i ) {
		print $fd $chrOrder[$i] . ",";
	}
	print $fd $chrOrder[scalar(@chrOrder) - 1] ."\n";

	$bedFH->close();
	$links->close();
}
