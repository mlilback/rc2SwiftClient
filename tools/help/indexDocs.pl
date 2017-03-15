#!/usr/bin/env perl

# TODO: add the package name

# getting perl setup
# curl -L http://cpanmin.us | perl - --sudo App::cpanminus
# sudo cpanm Statistics::R
# sudo cpanm Cpanel::JSON::XS

use Statistics::R;
use File::Find;
use Cpanel::JSON::XS qw(decode_json encode_json);
#use JSON;

my @docPaths = qw();;

sub check_if_interested {
	if ($File::Find::name =~ /.Rd$/) {
		push(@docPaths, $File::Find::name);
	}
}
find(\&check_if_interested, "/Users/mlilback/working/rc2/doc-generation/R-3.3.1/src/library");

my @json = qw();
my $R = Statistics::R->new();
foreach $path (@docPaths) {
	#exclude platform-specific help files in the utils directory
	if ($path =~ m#/library/utils/man/(windows|unix)/#) { next; }
	$R->run(q`library(tools)`);
	$R->run(qq`rdata <- parse_Rd("$path")`);
	$R->run(q`tags <- tools:::RdTags(rdata)`);
	$R->run(q`rtitle <- paste(unlist(rdata[[which(tags == "\\\\title")]]), collapse='')`);
	$R->run(q`rname <- paste(unlist(rdata[[which(tags == "\\\\name")]]), collapse='')`);
	$R->run(q`rdesc <- paste(unlist(rdata[[which(tags == "\\\\description")]]), collapse='')`);
	$R->run(q`raliases <- paste(unlist(rdata[which(tags == "\\\\alias")]), collapse=' ')`);
	my $rname = $R->get('rname');
	my $rtitle = $R->get('rtitle');
	my $rdesc = $R->get('rdesc');
	my @aliases =  split(/ /, $R->get('raliases'));
	shift(@aliases); #remove the actual name from the list
	my @paths = split(/\//, $path);
	my $rpack = splice @paths, -3, 1;
	$rtitle =~ s#\\n# #g;
	$rtitle =~ s#\s+# #g;
	$rname =~ s#\\n# #g;
	$rname =~ s#\s+# #g;
	$rdesc =~ s#\\n# #g;
	$rdesc =~ s#\s+# #g;
	push(@json, { name => $rname, title => $rtitle, aliases => join(':',@aliases), desc => $rdesc, package => $rpack });
}
#print encode_json(\@json) . "\n";
$R->stop();

my $coder = Cpanel::JSON::XS->new->ascii->pretty->allow_nonref;
my $json = $coder->encode({ help => \@json });
#my $json = JSON::encode_json({ help => \@json });
print "$json\n";
