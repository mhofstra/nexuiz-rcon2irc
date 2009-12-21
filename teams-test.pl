#!/usr/bin/perl
use strict;
use warnings;

my @a = (undef, 5, 14, 5, 5, -1, 14, -1, -1, 5, 14, 14, 5, 5);
my @spawns1 = timefix(1, 2, 4, 7, 11, 15, 18, 20, 21);
my @spawns2 = timefix(2, 7, 12, 17, 22);
my %store;
$store{teams} = \@a;
$store{spawns}->[1] = \@spawns1;
$store{spawns}->[2] = \@spawns2;

my @red = players_in_team(5);
my @lf = sorted_lifetimes(@red);
print "red: @red   times: @lf\n";
print "teamsize 5: " . teamsize(5) . " is_largest_team 5: " . is_largest_team(5) . " lifetime(avg/med/sdev) 5: " . average_lifetime(@red) . 
	"/" . median_lifetime(@red) . "/" . sdev_lifetime(@red) . "\n";
my @blue = players_in_team(14);
print "teamsize 14: " . teamsize(14) . " is_largest_team 14: " . is_largest_team(14) . " lifetime(avg/med/sdev) 14: " . average_lifetime(@blue) .
	"/" . median_lifetime(@blue) . "/" . sdev_lifetime(@blue) . "\n";
print "player 1 lifetime(avg/med/sdev): " . average_lifetime(1) . "/" . median_lifetime(1) . "/" . sdev_lifetime(1) . "\n";

sub sdev_lifetime {
	my @ids = @_;
	my @times = sorted_lifetimes(@ids);
	return 0 unless @times;
	my $p25 = $times[round(scalar(@times)*0.25)];
	my $p75 = $times[round(scalar(@times)*0.75)];
	my $med = median_lifetime(@ids);
	my $lh = $med - $p25;
	my $uh = $p75 - $med;
	return (($lh+$uh)/2);
}

sub median_lifetime {
	my @ids = @_;
	my @times = sorted_lifetimes(@ids);
	return 0 unless @times;
	if (scalar(@times) % 2 == 1) { #single median
		return $times[int(scalar(@times)/2)];
	} else { #composed median
		my $h = $times[int(scalar(@times)/2)];
		my $l = $times[int(scalar(@times)/2)-1];
		return (($h+$l)/2);
	}
}

sub sorted_lifetimes {
	my @ids = @_;
	my @times;
	foreach my $id (@ids) {
		next unless $store{spawns}->[$id];
		
		my $prev;
		foreach my $spawn (@{ $store{spawns}->[$id] }) {			
			push @times, ($spawn - $prev) if $prev;
			$prev = $spawn;
			
			if ( $spawn == $store{spawns}->[$id]->[-1] ) { #last round
				#push @times, (time() - $spawn);
			}
		}
	}
	return sort { $a <=> $b } @times;
}

sub average_lifetime {
	my @ids = @_;
	my @times = sorted_lifetimes(@ids);
	return 0 unless @times;
	my $total;
	$total += $_ foreach (@times);
	return round($total / scalar(@times));
}

sub players_in_team {
	my $team = shift;
	my @r;
	for (my $id=0; $id < @{ $store{teams} }; $id++) {
		next unless ($store{teams}->[$id]);
		push @r, $id if ( $store{teams}->[$id] == $team );
	}
	return @r;
}

sub timefix {
	my @r = @_;
	for (my $i=0; $i < @r;$i++) {
		$r[$i] = time() - ($r[scalar(@r)-1]) + $r[$i];
	}
	return @r;
}

sub teamsize {
	return scalar(players_in_team(@_));
}

sub is_largest_team {
	my $team = shift;
	my $size = teamsize($team) - 1;
	foreach (5, 14, 13, 10) {
		next if ($_ == $team);
		return 0 if (teamsize($_) >= $size);
	}
	return 1;
}

sub round { return int($_[0]+0.5); }
