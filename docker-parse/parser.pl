#!/usr/bin/env perl

## this script queries a docker daemon to compute the json we need to allow
## download of docker images from mac client. Must talk to machine where
## images were built
##

use Cpanel::JSON::XS qw(decode_json encode_json);
use File::Slurp;
use Data::Dumper;
use LWP::Simple;

my $baseUrl = "http://10.0.1.9:2375";
#my $text = read_file('images.json');
my $text = get("$baseUrl/images/json");
my $ilist = decode_json $text;

my %layerMap = ();
my %images = ();
foreach my $anImage (@$ilist) {
	my $tag = $$anImage{'RepoTags'}[0];
	if ($tag =~ m#^rc2server/(\w+):latest#) {
		my $name = $1;
		my $id = $$anImage{'Id'};
		my $size = $$anImage{'Size'};
		my %obj = (
			'name' => $name,
			'id' => $id,
			'size' => $size,
			'layers' => getLayers("rc2/$name"),
		);
#		$obj{'total'} = addSizes(\%obj);
		$images{$name} = \%obj;
	}
}
my $dbserver = $images{'dbserver'};
my $appserver = $images{'appserver'};
my $compute = $images{'compute'};

my %layers = ();
my $appskip = 0;
my $compskip = 0;
my $layerArray = $$dbserver{'layers'};
for my $dblayer (@$layerArray) {
	my $id = $$dblayer{'id'};
	$layers{$id} = 1;
}
$layerArray = $$appserver{'layers'};
for my $applayer (@$layerArray) {
	my $id = $$applayer{'id'};
	my $val = $layers{$id};
	if ($val > 0) {
		$appskip += $$applayer{'size'};
	}
}
my $appremain = $$appserver{'size'} - $appskip;
print "skipping app: $appskip (remain $appremain)\n";
$$appserver{'dupsize'} = $appskip;

$layerArray = $$compute{'layers'};
for my $applayer (@$layerArray) {
	my $id = $$applayer{'id'};
	my $val = $layers{$id};
	if ($val > 0) {
		$compskip += $$applayer{'size'};
	}
}
$$compute{'dupsize'} = $compskip;
my $compremain = $$compute{'size'} - $compskip;
print "skipping compute $compskip (remain: $compremain)\n";

delete $$appserver{'layers'};
delete $$dbserver{'layers'};
delete $$compute{'layers'};

my %wrapper = ( 'version' => 1, 'images' => \%images );
print encode_json(\%wrapper) . "\n";


sub addSizes {
	my ($array) = @_;
	my $total = 0;
	for my $sz ($array) {
		$total += $$sz{'size'};
	}
	return $total;
}

sub getLayers {
	my ($name) = @_;
	my $url = "$baseUrl/images/$name/history";
	my $text = get($url);
	my $json = decode_json $text;
	my @layers;
	foreach my $entry (@$json) {
		my $id = $$entry{'Id'};
		my %hash = (
			'id' => $id,
			'size' => $$entry{'Size'},
		);
		if ($hash{'size'} > 0) {
			push(@layers, \%hash);
			$layerMap{$id} = 1 + $layerMap{$id};
		}
	}
	return \@layers;
}
