#!/usr/bin/env perl

#Written by Justin Chu 2017
#generate generic karyotype from fasta file
#Adds bands on chromosomes based on content of Ns (gaps) in the file
#Other features, like centromeres or other cytogentic bands must be added manually (i.e. by altering file and running again)

my $line = <>;

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
	print "chr - " . $chrName . " " . $chrName. " 0 " . length($currentStr) . " grey\n"
	
	#TODO process gaps 
#	while ( $currentStr =~ /([^ATCGatcg]+)/g ) {
#		print $chrName . "\t" . $-[0] . "\t" . $+[0] . "\n";
#	}
}
