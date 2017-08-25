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
	while ( $currentStr =~ /([^ATCGatcg]+)/g ) {
		my @start = @-;
		my @end   = @+;
		print $chrName . "\t" . $start[0] . "\t" . $end[0] . "\n";
	}
}
