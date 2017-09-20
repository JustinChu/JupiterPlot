#!/usr/bin/env perl

#Written by Justin Chu 2017
#generate generic karyotype from fasta file
#Adds bands on chromosomes based on content of Ns (gaps) in the file
#Other features, like centromeres or other cytogentic bands must be added manually (i.e. by altering file and running again)

my $line = <>;

my $hueNum = 3;
my $maxHue = 30;

while ($line) {
	my $header = $line;
	$line = <>;
	my $currentStr = "";
	while ( $line && $line !~ /^>/ ) {
		chomp $line;
		$currentStr .= $line;
		$line = <>;
	}
	my ($chrName) = $header =~ /^>([^\s]+)\s/;
	
	#TODO assign colours in meaningful way
	print "chr - " . $chrName . " " . $chrName. " 0 " . length($currentStr) . " hue-$hueNum\n";
	if($maxHue == $hueNum)
	{
		$hueNum = 3;
	}
	else
	{
		++$hueNum;
	}
	#TODO process gaps 
	while ( $currentStr =~ /([^ATCGatcg]+)/g ) {
		print "band $chrName N N $-[0] $+[0] black\n";
	}
}
