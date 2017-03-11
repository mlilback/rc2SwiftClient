#!/usr/bin/env perl

use autodie;
use Switch;
use Data::Dumper;
use strict;
use Storable 'dclone';

print "opening $ARGV[0]\n";
my $src;
open($src, '<:raw', $ARGV[0]);
my $bytes_read = read $src, my $bytes, 4;
die "failed to read header" unless $bytes_read == 4;
my ($code,$space) = unpack("A2S", $bytes);
$space == 1 && $code eq "CS" || die "only supports RGB colors\n"; 
my $defaultColor = &readColor($src);
seek($src, -1, 1);

my $blockCount = &readShort($src);
my ($curGroupName, %groups, %curGroup);
for (my $i=0; $i < $blockCount; $i++) {
	my $blockType = &readShort($src);
	switch ($blockType) {
		case 1 { 
			my %color = &readColor($src);
			$curGroup{$color{name}} = $color{hex};
		}
		case 2 { 
			$curGroupName = &startGroup($src); 
			undef %curGroup;
		}
		case 3 { 
			my $working = dclone \%curGroup;
			$groups{$curGroupName} = $working;
			undef %curGroup;
		}
		else { die "bad block type" }
	}
}
my $groupCount = keys %groups;
print "got $groupCount groups\n";
#print Dumper(\%groups);

for my $aName (keys %groups) {
	my $hashRef = dclone $groups{$aName};	
	print "group $aName\n";
#	print Dumper($groups{$aName});
	for my $colorName (keys %$hashRef) {
		my %chash = $$hashRef{$colorName};
		print "     $colorName = $$hashRef{$colorName}\n";
	}
}

sub startGroup() {
	my ($fh) = @_;
	my $name = &readString($fh);
	my $foo;
	read($fh, $foo, 1);
	return $name;
}

sub readColor() {
	my ($fh) = @_;
	my %color;
	$color{name} = &readString($fh) || "unknown";
	my ($r,$g,$b) = readRGB($fh);
	$color{red} = $r;
	$color{green} = $g;
	$color{blue} = $b;
	my $hex = sprintf("%0.2x%0.2x%0.2x", int($r * 255.0), int($g * 255.0), int($b * 255.0));
	$color{hex} = $hex;
	return %color;
}

sub readRGB() {
	my ($fh) = @_;
	my $data;
	my $type = &readShort($fh);
	$type == 1 || die "CMYK not suported";
	my $br = read($fh, $data, 13);
	$br == 13 || die "bad color $br";
	my ($r, $g, $b, $e) = unpack("fffA", $data);
	return ($r, $g, $b);
}

sub readString() {
	my ($fh) = @_;
	my $bytes;
	my $len = readShort($fh);
	my $br = read($fh, $bytes, $len);
	$br == $len || die "read $br, looking for bad str len $len";
	my ($name) = unpack("A$len", $bytes);
	return $name;
}

sub readShort() {
	my $bytes;
	my $br = read($src, $bytes, 2);
	$br == 2 || return die "EOF";
	my ($val) = unpack("S", $bytes);
	return $val;
}
