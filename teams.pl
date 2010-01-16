# Nexuiz rcon2irc plugin by Merlijn Hofstra licensed under GPL - teams.pl
# Place this file inside the same directory as rcon2irc.pl and add the full filename to the plugins.

 use POSIX qw(ceil);
 use List::Util 'shuffle'; # this needs perl 5.8+ or Scalar-List-Utils 1.03+

{ my %tp = (
	autobalance => 0, # allow this script to balance players directly when they are playing. TODO
	balance_vote => 0, # performs a vcall and lets users decide if the balance should take place. TODO
	# if the server has set g_start_delay, players can join teams before it actually starts, when the
	# game starts the teams can be checked for equal strength based on the players results in the last
	# match.
	balance_onstart => 1,
	balance_join => 1, # balance players to the weaker team when they join.
	# by how many players may teamsizes differ when balancing joins.
	# A 0 value disables this check, otherwise this is a percentage of players.
	# the highest tolerable difference would be ceil((slot count - 1) * this value).
	balance_join_maxdiff => 0.15,
	# if balance is off more than this threshold, the script will push clients to the weaker team.
	# maxdiff is always obeyed here, and in case the balance is within the threshold, the script
	# prefers to keep the teams of equal size.
	balance_join_threshold => 0.36,
	# when average lifetimes are balanced, it may be hard to determine the right team for the script.
	# if the average lifetimes are within this range, the players choise is respected.
	balance_join_min_threshold => 0.13,
	# amount of seconds after mapstart where people are not balanced forcefully.
	# this value should be higher or equal than g_start_delay if used together with balance_onstart.
	balance_join_mapstart => 15,
	# how long after a match has started should we use stats from the lastround to balance the teams.
	# this value is mostly used to overcome the first bit of a game where we don't have enough data
	# to accurately balance teams. The value is a number of seconds after the start delay has ended.
	balance_lastround_time => 60,
	# when people leave the teamsizes may become hugely unbalanced, this value holds a threshold to
	# prevent extreme unbalance. the maxdiff can be computed as ceil(num_players * this value).
	# setting this to a value of 1 disables this check entirely.
	balance_part_maxdiff => 0.2,
	# if the game is unbalanced,  people may leave the weak time as losing is no fun.
	# this makes the game even less balanced, so when the average lifetime drops below this threshold
	# players will be balanced to the weaker team. a zero value disables this check.
	balance_part_threshold => 0.55,
	# on public servers the players in a team constantly change, which has a large impact on balance.
	# spawns_clear discards any information older than this amount of seconds. High values may result
	# in inaccurate data to be used, while low values may not provide enough data to use.
	spawns_clear => 300,
	# how often should the server check if the balance is ok?
	# this value is a multiplication of 30 seconds, so a value of 2 indicates a check every minute.
	# 0 disables checking the balance mid-game at all.
	balance_check => 2,
	# when a balance action has been taken (or suggested), how long should we wait for a balance check
	# again? When a player is balanced, his stats are reset and it will take a while for the teamstats
	# to stabilise. This is also used at the start of matches. Again a multiple of 30 seconds.
	balance_tryout => 6,
	# number of players minimally needed to evaluate the balance. Notice that accuracy goes up with
	# playercount, so setting this value too low may be counterproductive.
	balance_minplayers => 5,
	# if there is still bots on the server, rebalance them to make teamsizes equal.
	# when using this, make sure that the minplayers cvar is a multiple of the amount of teams.
	balance_bots => 1,
	# in certain situations the teams can be locked, for example when maxdiff does not allow a 
	# stronger player to join the weaker team. this value allows players with a good score to overrule
	# this behaviour and change teams anyway. A value of zero disables overruling altogether.
	balance_overrule_score => 0,
	# percentage of difference between average lifetime, the lower this value - the sooner it will
	# be triggered to attempt to fix the balance.
	balance_threshold => 0.4, 
	# people who attempt to join the winning team will be pushed back to the weaker team, however at
	# some point the conditions may be so to allow him to move to the stronger team. Setting this
	# value to 1 notifies IRC on successful manual joins too, if they have been refused before.
	track_wtj => 1,
	sdev_base => 0.1, # base for standard deviation to use, 0.25 performs p25-p75, 0.1 does p40-p60
);

$store{plugin_teams} = \%tp; }

sub out($$@);
sub schedule($$);

if (defined %config) {
	schedule sub {
		my ($timer) = @_;
		out dp => 0, "minplayers";
		out dp => 0, "g_respawn_delay";
		schedule $timer => 600;;
	} => 1;
	
	print "Loaded teams.pl by merlijn\n";
}

my %team_code2name = (-1 => 'spec', 5 => 'red', 14 => 'blue', 13 => 'yellow', 10 => 'pink');
my %jointypes = (1 => 'connect', 2 => 'auto', 3 => 'manual', 4 => 'spec', 5 => 'switch', 6 => 'adminmove');

sub round { return int($_[0]+0.5); }

sub teamsize {
	return scalar(players_in_team(@_));
}

sub is_largest_team { # TODO remove, not being called
	my $team = shift;
	my $size = teamsize($team);
	foreach (teams_active()) {
		next if ($_ == $team);
		return 0 if (teamsize($_) >= $size);
	}
	return 1;
}

sub is_smallest_team { # TODO remove, not being called
	return ($_[0] == get_smallest_team());
}

sub get_smallest_team { # TODO remove, not being called
	my $smallest;
	my $ctr = $store{slots_max};
	foreach (teams_active()) {
		my $t = teamsize($_);
		$smallest = $_ if ($t && $t < $ctr);
		$ctr = $t if $t;
	}
	return $smallest;
}

sub players_in_team {
	my $team = shift;
	my @r;
	foreach my $id (0 .. @{ $store{teams} }-1) { # TODO skip bots?
		push @r, $id if ($store{teams}->[$id] && $store{teams}->[$id] == $team);
	}
	return @r;
}

sub sdev_lifetime {
	my @ids = @_;
	my @times = sorted_lifetimes(@ids);
	return 0 unless @times;
	
	my $base = $store{plugin_teams}->{sdev_base};
	my $l = $times[round(scalar(@times)*(0.5 - $base))];
	my $h = $times[round(scalar(@times)*(0.5 + $base))];
	
	my $med = median_lifetime(@ids);
	my $lh = $med - $l;
	my $uh = $h - $med;
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
	my $timeout = $store{plugin_teams}->{spawns_clear};
	my $respawn_delay = $store{plugin_teams}->{respawn_delay};
	
	foreach my $id (@ids) {
		next unless $store{spawns}->[$id];
		
		my $prev;
		foreach my $spawn (@{ $store{spawns}->[$id] }) {
			push @times, ($spawn - $prev) if ($prev && $spawn >= time() - $timeout);
			$prev = $spawn + $respawn_delay;
		}
		push @times, (time() - $prev) if $prev; #add current lifetime
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

sub indexof {     # pass in value, array reference
   my ( $value, $arrayref ) = ( shift, shift );
   foreach my $i ( 0 .. @$arrayref-1 )  {
      return $i if $$arrayref[$i] == $value;
   }
}

sub stats_irc {
	my @ts;
	my @caps;
	my @lifetime;
	foreach (sort {$a <=> $b} teams_active()) {
		my $size = teamsize($_);
		next unless ($size); #skip teams without players
		
		push(@ts, sprintf("\003%02d%d\017", $color_team2irc_table{$_}, $size)); #add teamsize
		
		if ($store{map} =~ m/^ctf/) { #add captures for ctf
			my $numcaps = scalar(@{ $store{caps}->{$_} });
			push(@caps, sprintf("\003%02d%d\017", $color_team2irc_table{$_}, $numcaps));
		}
		
		my @team = players_in_team($_);
		push(@lifetime, sprintf("\003%02d%d/%.1f/%.1f\017", $color_team2irc_table{$_}, average_lifetime(@team), 
			median_lifetime(@team), sdev_lifetime(@team))); #add lifetime
	}
	
	my $str;
	if (@ts) {
		$str = "Players: " . join(':', @ts) .
			(scalar(@caps) ? " Caps: " . join(':', @caps) : '') .
			" Lifetime (avg/med/sdev): " . join(':', @lifetime);
	} else {
		$str = "Nobody is playing!";
	}
	
	return $str;
}

# This function evaluates if balance should run this round or skip until it is called again.
sub balance_round {
	my $tp = $store{plugin_teams};
	
	# are we in the tryout stage?
	if ($tp->{balance_tryout_bool} && $tp->{balance_tryout} > 1) {
		if (!$tp->{balance_tryout_ctr}) {
			$tp->{balance_tryout_ctr} = 1;
			return 0;
		} elsif ($tp->{balance_tryout_ctr} % $tp->{balance_tryout} > 0) {
			$tp->{balance_tryout_ctr}++;
			return 0;
		} else {
			#running this time
			$tp->{balance_tryout_ctr} = 0;
			$tp->{balance_tryout_bool} = 0;
			$tp->{balance_check_ctr} = 1;
			return 1;
		}
	}
	
	# should we wait or run?
	if ($tp->{balance_check} > 1) {
		if (!$tp->{balance_check_ctr}) {
			$tp->{balance_check_ctr} = 1;
			return 0;
		} elsif ($tp->{balance_check_ctr} % $tp->{balance_check} > 0) {
			$tp->{balance_check_ctr}++;
			return 0;
		} else {
			#running this time
			$tp->{balance_check_ctr} = 1;
		}
	}
	return 1;
}

# Generate a strong and weak team, returns 0 if data is no good or a hash ref with team data.
sub balance_teaminfo {
	my %r = (
		highlt => 0,
		lowlt => 1200,
	);
	
	foreach (teams_active()) {
		my $t = average_lifetime(players_in_team($_));
		next unless ($t);
		if ($t > $r{highlt}) {
			$r{highlt} = $t;
			$r{highteam} = $_;
		}
		if ($t < $r{lowlt}) {
			$r{lowlt} = $t;
			$r{lowteam} = $_;
		}
	}
	
	#check if data is ok
	return 0 unless (defined $r{highteam} && defined $r{lowteam});
	return 0 if ($r{highteam} == $r{lowteam});
	
	#add teamsizes
	$r{highsize} = teamsize($r{highteam});
	$r{lowsize} = teamsize($r{lowteam});
	
	return \%r; #ref to %r
}

sub movetoteam { # showmsg enables output to the user/irc
	my ($id, $team, $showmsg) = @_;
	$team = $team_code2name{$team} if ($team =~ m/^\d+$/);
	out dp => 0, "settemp g_balance_kill_delay 0"; #don't make the player wait
	out dp => 0, "sv_cmd movetoteam " . $store{"playerslot_byid_$id"} . " $team " . ($showmsg ? '0' : '3');
	out dp => 0, "settemp_restore g_balance_kill_delay";

	return 0 unless ($showmsg);
	
	my $nick = $store{"playernick_byid_$id"} || '(console)';
	out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: forcing $nick\017 to $team team " . stats_irc();
	
	return 0;
}

sub switch {
	my ($id1,$id2,$showmsg) = @_;
	my $team1 = $store{teams}->[$id1];
	my $team2 = $store{teams}->[$id2];
	return unless ($team1 > 0 && $team2 > 1);
	movetoteam($id1, $team2, $showmsg);
	movetoteam($id2, $team1, $showmsg);
	
	return 0;
}

sub is_carrier {
	my $id = shift;
	return 1 if $store{fc}->[$id];
	# TODO check keyhunt here
	return 0;
}

sub players_active {
	my $r = 0;
	foreach my $team (teams_active()) {
		foreach (players_in_team($team)) {
			$r++ if ($store{"playerip_byid_$_"} ne 'bot');
		}
	}
	return $r;
}

sub teams_active {
	my @r;
	for (1 .. $store{slots_max}) {
		my $id = $store{"playerid_byslot_$_"};
		next unless $id;
		my $team = $store{teams}->[$id];
		push @r, $team if (defined $team && $team > 0); # ignore spectator team
	}
	my %t = undef;
	return shuffle grep !$t{$_}++, @r; # unique values of @r, in random order.
}

sub playername_to_slot { # TODO not needed?
	my $name = shift;
	for (1 .. $store{slots_max}) {
		my $id = $store{"playerid_byslot_$_"};
		next unless $id;
		return $_ if ($name eq $store{"playernickraw_byid_$id"});
	}
	return undef;
}

# Generates known averages from player stats from last round
sub lastround_stats {
	my @ids = @_;
	my $count = 0;
	my %t;
	foreach my $label (@{ $store{plugin_teams}->{labels} }) {
		foreach my $id (@ids) {
			my $slot = $store{"playerslot_byid_$id"};
			next unless ($store{plugin_teams}->{lastround}->[$slot]); # no data known
			$count++ if ($label eq 'score');
			
			$t{$label} += $store{plugin_teams}->{lastround}->[$slot]->{$label};
		}
	}
	return 0 unless ($count);
	my %r;
	$r{$_} = $t{$_} / $count foreach ( keys %t ); # generate averages
	return \%r;
}

# Determines player strength based on kill to death ratio in last round.
sub get_strength { # TODO not used?
	my $stats = lastround_stats(@_);
	return undef unless ($stats);
	return undef unless ($stats->{deaths});
	my %ratios = ( # TODO create sane values here
		0.667 => 'weak',
		1.3   => 'average',
		1.7   => 'strong',
	);
	
	foreach (keys %ratios) {
		return $ratios{$_} if (($stats->{kills} / $stats->{deaths}) < $_);
	}
	return 'strong';
}

sub killdeathratio {
	my $teams = shift; # arrayref to teams
	my $low;
	my $high;
	foreach my $team (shuffle @{ $teams }) {
		next unless ($team);
		my @teamids;
		push @teamids, $store{"playerid_byslot_$_"} foreach (@{ $team});
		
		my $lr = lastround_stats(@teamids);
		next unless ($lr && $lr->{deaths}); # should never happen, but let's be safe
		my $ratio = $lr->{kills} / $lr->{deaths};
		$low = $ratio if (!defined $low || $ratio < $low);
		$high = $ratio if (!defined $high || $ratio > $high);
	}
	return abs $high - $low;
}

[ dp => q{:team:(\d+):(-?\d+):(\d+)} => sub { # : team : player_id : team_code : join_type
	my ($id, $team, $join) = @_;
	my $tp = $store{plugin_teams};

	my $nick = $store{"playernick_byid_$id"} || 'console';

	my $jointype = $jointypes{$join};
	my $teamname = $team_code2name{$team};
	
	unless ($jointype && $teamname) { # TODO remove when stable
		out irc => 0, "PRIVMSG $config{irc_channel} :\00304* error\017 $nick\017 has joined with unknown jointype/team $join/$team";
		return 0;
	}
	
	$store{teams}->[$id] = undef; # reset teaminfo
	$store{spawns}->[$id] = undef; # reset spawns
	
	return 0 if ($jointype eq 'connect' && !($store{"playerip_byid_$id"} eq 'bot')); # bots only do :team: messages on connect
	return 0 if ($teamname eq 'spec' || $jointype eq 'spec'); # nothing left to do for spectators TODO do balance check here?
	
	my $tbl = balance_teaminfo();
	
	if ($tbl && $jointype eq 'manual' && $team != $tbl->{lowteam} && !$tp->{balance_join}) {
		out irc => 0, sprintf("PRIVMSG $config{irc_channel} :\00308* warning\017 $nick\017 has manually joined the stronger team: \003%02d", 
			$color_team2irc_table{$team}) . uc($teamname) . "\017 " . stats_irc();
	}
	
	# if there are still bots, we must keep teamsizes equal.
	if ($tbl && $store{map} && $tp->{balance_bots} && players_active() < $tp->{minbots} && $jointype eq 'manual' &&
		abs($tbl->{highsize} - $tbl->{lowsize}) > 0) {
		
		my $big = ($tbl->{highsize} > $tbl->{lowsize}) ? $tbl->{highteam} : $tbl->{lowteam};
		my $small = ($tbl->{highsize} < $tbl->{lowsize}) ? $tbl->{highteam} : $tbl->{lowteam};
		if ($team != $small) { # must move a bot to balance sizes
			my $kicked = 0;
			foreach (shuffle players_in_team($big)) { 
				if ($store{"playerip_byid_$_"} eq 'bot') {
					out dp => 0, "kick # " . $store{"playerslot_byid_$_"};
					$kicked = 1;
					last;
				}
			}
			if (!$kicked) {
				$tp->{wtjtrack}->[$id] = 1;
				return movetoteam($id, $small, 1); # player joined the larger team, but there are no bots - move him to the other team.
			}
		}
	}
	
	# TODO does this code work properly for > 2 teams?
	if ($tbl && $store{map} && $tp->{balance_join} && ($jointype eq 'auto' || $jointype eq 'manual') && !$tp->{game_ended} &&
		!($store{"playerip_byid_$id"} eq 'bot') && players_active() >= $tp->{minbots} && # this code works poorly when bots will disconnect.
		$tp->{balance_join_mapstart} < (time() - $store{map_starttime}) && (!$store{startdelay} || !$tp->{balance_onstart}) &&
		players_active() >= $tp->{balance_minplayers} && 
		(!$tp->{balance_overrule_score} || $tp->{currentscore}->[$id] < $tp->{balance_overrule_score})) { # strong players may overrule our balancing
		
		# detect smallest team and prefer weaker team if sizes equal
		my $smallest = ($tbl->{lowsize} <= $tbl->{highsize} ? $tbl->{lowteam} : $tbl->{highteam});
		
		# consider maxdiff
		my $diff = abs($tbl->{highsize} - $tbl->{lowsize});
		if ($tp->{balance_join_maxdiff} > 0 && $diff >= ceil(players_active() * $tp->{balance_join_maxdiff})) {
			# player must join smallest team
			unless ($smallest == $team) {
				$tp->{wtjtrack}->[$id] = 1 if ($jointype ne 'auto');
				return movetoteam($id, $smallest, ($jointype eq 'auto'? 0 : 1));
			}
			
			
		# should we use lastround stats for balance?
		} elsif ((time() - $store{map_starttime}) < $tp->{balance_lastround_time} && 0) { # TODO remove 0
			# TODO write algorithm to determine team strength and pick best team
			
		# evaluate balance based on lifetimes
		} elsif ($tbl->{highlt} - ($tbl->{highlt} * $tp->{balance_join_threshold}) < $tbl->{lowlt}) { # balance is ok
			
			unless ($smallest == $team || $tbl->{lowteam} == $team || # allow changes to larger team when it aids balance
				$tbl->{highlt} - ($tbl->{highlt} * $tp->{balance_join_min_threshold}) < $tbl->{lowlt}) {  # check min threshold
				
				$tp->{wtjtrack}->[$id] = 1 if ($jointype ne 'auto');
				return movetoteam($id, $smallest, ($jointype eq 'auto'? 0 : 1));
			}
			
		} elsif ($team != $tbl->{lowteam}) { # balance is off, join weakest team
			$tp->{wtjtrack}->[$id] = 1 if ($jointype ne 'auto');
			return movetoteam($id, $tbl->{lowteam}, ($jointype eq 'auto'? 0 : 1));
		}
	}
	
	if ($tp->{track_wtj} && $tp->{wtjtrack}->[$id] && $jointype eq 'manual') { # echo tracked players
		out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017 allowing tracked player " . $store{"playernick_byid_$id"} .
			"\017 to join $teamname team " . stats_irc();
	}
	
	$store{teams}->[$id] = $team;
	push @{ $store{spawns}->[$id] }, (time() - $tp->{respawn_delay});

	return 0;
} ],

# TODO rewrite this as schedule sub
[ dp => q{timing:   [0-9.]*% CPU, [0-9.]*% lost, offset avg [0-9.]*ms, max [0-9.]*ms, sdev [0-9.]*ms} => sub {
	# this function will be executed every 30 seconds, so we use it to balance teams.
	my $tp = $store{plugin_teams};
	
	# skip if we don't have full data (rcon2irc started during a match)
	return 0 unless (defined $store{map});
	
	# should we evaluate balance at all?
	return 0 unless ($tp->{balance_check});
	
	# should we run this round?
	return 0 unless (balance_round());
	
	# are there enough real players to evaluate the balance?
	return 0 if (players_active() < $tp->{balance_minplayers} || players_active() < $tp->{minbots});
	
	# balance based on lifetimes
	my $tbl = balance_teaminfo();
	return 0 unless ($tbl);
	return 0 if ($tbl->{highlt} - ($tbl->{highlt} * $tp->{balance_threshold}) < $tbl->{lowlt}); # balance within threshold
	
	my $highteam = $tbl->{highteam};
	my $lowteam = $tbl->{lowteam};
	
	out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: something is wrong - " . stats_irc();
	
	# decide type of action
	my @htp = players_in_team($highteam);
	my @ltp = players_in_team($lowteam);
	if (scalar(@htp) > scalar(@ltp)) { #move a player
		my $candidate;
		foreach my $player (@htp) {
			next if is_carrier($player); #player carries a flag or key
			my @ltpnew = (@ltp, $player);
			my @htpnew = @htp;
			splice @htpnew, indexof($player), 1;
			#will this player improve the lifetime?
			next unless (average_lifetime(@ltpnew) <= average_lifetime(@ltp));
			#don't overbalance
			next if (average_lifetime(@ltpnew) > average_lifetime(@htpnew));
			#since we're moving a person, (s)he should be in the lower half in lifetimes.
			next unless (average_lifetime($player) <= average_lifetime(@htpnew));
			#find best match
			unless ($candidate) {
				$candidate = $player;
				next;
			}
			$candidate = $player unless (average_lifetime($player) < average_lifetime($candidate));
		} # FIXME - doesn't find suitable candidates enough, weaken conditions
		if ($candidate) {
			$tp->{balance_tryout_bool} = 1;
			out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: " . $store{"playernick_byid_$candidate"} . "\017" . 
				sprintf(" would get moved from \003%02d", $color_team2irc_table{$highteam}) . uc($team_code2name{$highteam}) . "\017 to " .
				sprintf("\003%02d", $color_team2irc_table{$lowteam}) . uc($team_code2name{$lowteam});
		} else {
			out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: would like to balance from " .
				sprintf("\003%02d", $color_team2irc_table{$highteam}) . uc($team_code2name{$highteam}) . "\017 to " .
				sprintf("\003%02d", $color_team2irc_table{$lowteam}) . uc($team_code2name{$lowteam}) . "\017 " .
				"but can't find a suitable player";
		}
	} else { #swap players
		my @candidates;
		foreach my $hplr (@htp) {
			foreach my $lplr (@ltp) {
				next if (is_carrier($hplr) || is_carrier($lplr)); # carriers should not be moved
				next unless (average_lifetime($hplr) && average_lifetime($lplr));
				my @ltpnew = (@ltp, $hplr);
				my @htpnew = (@htp, $lplr);
				splice @ltpnew, indexof($lplr), 1;
				splice @htpnew, indexof($hplr), 1;
				
				#will this improve the balance?
				my $oldratio = average_lifetime(@htp) / average_lifetime(@ltp);
				my $newratio = average_lifetime(@htpnew) / average_lifetime(@ltpnew);
				next if ($oldratio < $newratio);
				#don't overbalance
				next if (average_lifetime(@ltpnew) > average_lifetime(@htpnew));
				#add candidates
				my $ratio = average_lifetime($hplr) / average_lifetime($lplr);
				push @candidates, "$hplr:$lplr:$ratio" if ($ratio > 1);			
			}
		}
		unless (@candidates) {
			out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: would like to swap stronger player from " .
				sprintf("\003%02d", $color_team2irc_table{$highteam}) . uc($team_code2name{$highteam}) . "\017 with weaker from " .
				sprintf("\003%02d", $color_team2irc_table{$lowteam}) . uc($team_code2name{$lowteam}) . "\017 " .
				"but can't find suitable candidates";
				
				return 0;
		}
		@candidates = sort { @a = split(':', $a); @b = split(':', $b); $a[2] <=> $b[2] } @candidates;
		#pick one in the middle TODO make a sane algorithm
		my $cand = $candidates[round((scalar(@candidates) - 1) * 0.7)];
		my ($strong,$weak,$ratio) = split ':', $cand;
		$tp->{balance_tryout_bool} = 1;
		out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: would swap " . sprintf("\003%02d", $color_team2irc_table{$highteam}) .
			color_dp2none($store{"playernickraw_byid_$strong"}) . "\017 with " . sprintf("\003%02d", $color_team2irc_table{$lowteam}) .
			color_dp2none($store{"playernickraw_byid_$weak"}) . sprintf("\017 ratio=%.2f", $ratio);
	}
	
	return 0;
} ],

# status 1 output to parse the playerscore for current strength
[ dp => q{\^\d(\S+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(-?\d+)\s+\#(\d+)\s+\^\d(.*)} => sub {
	return 0 unless $store{status_waiting} > 0;
	my ($ip, $pl, $ping, $time, $score, $slot, $name) = ($1, $2, $3, $4, $5, $6, $7);
	my $id = $store{"playerid_byslot_$slot"};
	$store{plugin_teams}->{currentscore}->[$id] = $score unless ($score == -666);
	
	return 0;
} ],

[ dp => q{:labels:player:(.*)} => sub {
	my ($line) = @_;
	my @labels = split '[!<,]+', $line;
	$store{plugin_teams}->{labels} = \@labels;
	
	# discard last results, but only if this map has been played for at least 3 minutes.
	$store{plugin_teams}->{lastround} = undef if ((time() - $store{map_starttime}) > 180); 
	return 0;
} ],

[ dp => q{:player:see-labels:([-,\d]*):(\d+):(\d+):(\d+):.*} => sub {
	my ($line,$time,$team,$id) = @_;
	return 0 if ($store{"playerip_byid_$id"} eq 'bot');
	return 0 if ($time < 60); # one minute of playing does not give accurate results.
	return 0 unless ((time() - $store{map_starttime}) > 180); # map must be played for at least 3 minutes
	
	my $slot = $store{"playerslot_byid_$id"};
	my @results = split ',', $line;
	for ( 0 .. @results-1 ) {
		my $type = $store{plugin_teams}->{labels}->[$_]; # fetch type of result
		$store{plugin_teams}->{lastround}->[$slot]->{$type} = $results[$_];
	}
	return 0;
} ],

[ dp => q{:startdelay_ended} => sub {
	$store{startdelay} = 0;
	$store{map_starttime} = time();
	my $tp = $store{plugin_teams};
	
	# reset spawns to 0
	for ( 0 .. @{ $store{spawns} }-1 ) {
		if (defined $store{teams}->[$_] && $store{teams}->[$id] > 0) {
			$store{spawns}->[$_] = undef;
			push @{ $store{spawns}->[$_] }, (time() - $tp->{respawn_delay}); # this workaround is needed for accuracy
		}
	}
	
	return 0 unless ($tp->{balance_onstart});
	return 0 unless ($tp->{lastround});
	return 0 if (players_active() < $tp->{balance_minplayers} || players_active() < $tp->{minbots});
	
	# Here's the explanation of how this algorithm works:
	# First we generate an array with all players that have joined up to now and then sort this array in such a way
	# that the next and previous values match up to players of equal strength and playing type. For CTF all the
	# flagrunners are matched up and the defenders are matched up based on the results of the last played map.
	# A visualization of the array would be [][][][][][][][] for eight players now.
	
	my @plrs = ();
	@plrs = (@plrs, players_in_team($_)) foreach (teams_active());
	
	my @splrs;
	for ( 0 .. @plrs-1) { # translate ids to slots
		if ($plrs[$_] && $tp->{id2slot}->[$plrs[$_]]) {
			push @splrs, $tp->{id2slot}->[$plrs[$_]];
		}
	}
	@plrs = @splrs;
	
	if ($store{map} =~ m/^ctf/i && 0) { # CTF optimized code TODO
		@plrs = sort {
			return 0 unless ($a && $tp->{lastround}->[$a] && $b && $tp->{lastround}->[$b]);
			return -1 unless ($b && $tp->{lastround}->[$b]);
			return 1 unless ($a && $tp->{lastround}->[$a]);
			
			# TODO add more sufficient data checks (returns)
			return -1 unless ($tp->{lastround}->[$b]->{deaths});
			return 1 unless ($tp->{lastround}->[$a]->{deaths});
			
			my $playtypea;
			if ($tp->{lastround}->[$b]->{fckills} + $tp->{lastround}->[$b]->{returns} > 0) {
				$playtypea = ($tp->{lastround}->[$a]->{caps} + $tp->{lastround}->[$a]->{pickups}) /
							($tp->{lastround}->[$a]->{fckills} + $tp->{lastround}->[$a]->{returns});
			} else {
				$playtypea = ($tp->{lastround}->[$a]->{caps} + $tp->{lastround}->[$a]->{pickups});
			}
			
			my $playtypeb;
			if ($tp->{lastround}->[$b]->{fckills} + $tp->{lastround}->[$b]->{returns} > 0) {
				$playtypeb = ($tp->{lastround}->[$b]->{caps} + $tp->{lastround}->[$b]->{pickups}) /
							($tp->{lastround}->[$b]->{fckills} + $tp->{lastround}->[$b]->{returns});
			} else {
				$playtypeb = ($tp->{lastround}->[$b]->{caps} + $tp->{lastround}->[$b]->{pickups});
			}
			
			
			if ($playtypea > 1 && $playtypeb > 1) { # both are attackers
				return ($tp->{lastround}->[$a]->{caps} / $tp->{lastround}->[$a]->{pickups}) <=>
					   ($tp->{lastround}->[$b]->{caps} / $tp->{lastround}->[$b]->{pickups}); # sort by successrate
			}
			
			return -1 if ($playtypea > 1);
			return 1 if ($playtypeb > 1);
			
			if ($playtypea <= 1 && $playtypeb <= 1) { # both are defenders
				return ($tp->{lastround}->[$a]->{kills} / $tp->{lastround}->[$a]->{deaths}) <=>
					   ($tp->{lastround}->[$b]->{kills} / $tp->{lastround}->[$b]->{deaths}); # sort by k-d ratio
			}
			
			return 1 if ($playtypea <= 1);
			return -1 if ($playtypeb <= 1);
			
			return 0;
		} @plrs;
	}
	
	elsif ($store{map} =~ m/^tdm/i) { # TDM optimized code
		@plrs = sort { 
			return 0 unless ($a && $tp->{lastround}->[$a] && $b && $tp->{lastround}->[$b]);
			return -1 unless ($b && $tp->{lastround}->[$b]);
			return 1 unless ($a && $tp->{lastround}->[$a]);
			
			return -1 unless ($tp->{lastround}->[$b]->{deaths});
			return 1 unless ($tp->{lastround}->[$a]->{deaths});
			
			my $ratioa = $tp->{lastround}->[$a]->{kills} / $tp->{lastround}->[$a]->{deaths};
			my $ratiob = $tp->{lastround}->[$b]->{kills} / $tp->{lastround}->[$b]->{deaths};
			return $ratioa <=> $ratiob;
		} @plrs;
	}
	
	else {
		@plrs = sort { # sort players by score, should be safe for any unsupported gametypes
			return 0 unless ($a && $tp->{lastround}->[$a] && $b && $tp->{lastround}->[$b]);
			return -1 unless ($b && $tp->{lastround}->[$b]);
			return 1 unless ($a && $tp->{lastround}->[$a]);
			
			return ($tp->{lastround}->[$b]->{score} <=> $tp->{lastround}->[$a]->{score});
		} @plrs;
	}
	
	# Now that we have an array with matched up players, we start dividing them in teams. The rule here is that 
	# players of 'equal' strength cannot be in the same team. If there are 2 teams the array would look like this:
	# ([][])([][])([][])([][]) where the round brackets indicate a match of players that cannot be in the same team.
	# If there would be three teams, the array would look like this: ([][][])([][][])([][]).
	
	my $bestteams;
	my @teams = teams_active();
	for (0 .. @plrs-1) { # assign players to a team
		push @{ $bestteams->[($teams[($_ % scalar(@teams))])] }, $plrs[$_];
	}
	
	# The score used to generate these teams may not line up with the lifetime statistics, so we try to make the
	# teams more fair by optimizing the kill to death ratio. The players that are matched against eachother are 
	# switched of team and the best possible kill to death balance is used as the final teams we want to make.
	# 
	# The initial array might look like this: ([r][b])([r][b])([r][b])([r][b]), but after this shuffle round
	# it may look like this: ([r][b])([b][r])([r][b])([b][r]).
	
	my $diff = killdeathratio($bestteams);
	for ( 0 .. int(scalar(@plrs)/scalar(@teams))-1 ) { # try to even the teams by making kill to death ratio difference as small as possible
		foreach my $i (1 .. @teams-1) {
			($bestteams->[$teams[$i]]->[$_], $bestteams->[$teams[$i-1]]->[$_]) = ($bestteams->[$teams[$i-1]]->[$_], $bestteams->[$teams[$i]]->[$_]);
			my $newdiff = killdeathratio($bestteams);
			if ($newdiff > $diff) { # restore as this doesn't improve
				($bestteams->[$teams[$i]]->[$_], $bestteams->[$teams[$i-1]]->[$_]) = ($bestteams->[$teams[$i-1]]->[$_], $bestteams->[$teams[$i]]->[$_]);
			} else {
				$diff = $newdiff;
			}
		}
	}
	
	foreach my $teamnum (@teams) { # shuffle teams to optimize amount of moves needed
		my $mic;
		my $teammic; #most in common
		foreach my $plrs (@{ $bestteams }) {
			next unless ($plrs);
			my $ic = 0;
			foreach my $slot (@{ $plrs }) {
				$ic++ if ($tp->{teams}->[$store{"playerid_byslot_$slot"}] == $teamnum);
			}
			if (!$teammic || $ic > $mic) {
				$mic = $ic;
				$teammic = $plrs;
			}
		}
		$bestteams->[indexof($plrs)] = $bestteams->[$teamnum];
		$bestteams->[$teamnum] = $plrs;
	}
	
	out dp => 0, "settemp g_balance_kill_delay 0"; # don't make the player wait
	for ( 0 .. @{ $bestteams }-1 ) {
		next unless $bestteams->[$_];
		my $team = $team_code2name{$_};
		foreach my $plrslot ( @{ $bestteams->[$_] } ) {
			unless ($_ == $tp->{teams}->[$store{"playerid_byslot_$plrslot"}]) { # TODO uncomment
				#out dp => 0, "movetoteam_$team " . $plrslot . " 1";
			}
		}
	}
	out dp => 0, "settemp_restore g_balance_kill_delay";
	
	return 0;
} ],

[ dp => q{:kill:(frag|tk|suicide|accident):(\d+):(\d+):.*} => sub {
	my ($type, $killerid, $victimid) = @_;
	push @{ $store{spawns}->[$victimid] }, time();
	return 0;
} ],

[ dp => q{:ctf:(steal|dropped|pickup|capture|return):(\d+):(\d+)} => sub {
	my ($action,$flag, $id) = @_;
	my $team = $store{teams}->[$id];
	if ($action eq 'steal' || $action eq 'pickup') {
		$store{fc}->[$id] = 1;
	} elsif ($action eq 'capture') {
		push @{ $store{caps}->{$team} }, $id;
		$store{fc}->[$id] = undef;
	} elsif ($action eq 'dropped') {
		$store{fc}->[$id] = undef;
	}
	return 0;
} ],

[ dp => q{:part:(\d+)} => sub {
	my ($id) = @_;
	$store{spawns}->[$id] = undef;
	$store{fc}->[$id] = undef;
	
	my $slot = $store{plugin_teams}->{id2slot}->[$id];
	$store{plugin_teams}->{id2slot}->[$id] = undef;
	$store{plugin_teams}->{lastround}->[$slot] = undef;
	$store{plugin_teams}->{currentscore}->[$id] = undef;
	$store{plugin_teams}->{wtjtrack}->[$id] = undef;
	
	my $team = $store{teams}->[$id];
	$store{teams}->[$id] = undef;
	return 0 if ($slot eq 'bot'); # detect if player is a bot
	return 0 unless (defined $team || $team == -1); # if a spectator leaves, the balance isn't affected
	
	my $tp = $store{plugin_teams};
	return 0 unless ($tp->{balance_part_threshold});
	return 0 unless ($store{playing});
	return 0 if ((time() - $store{map_starttime}) < 120); # after 2 minutes we don't have enough useful data
	
	my $tbl = balance_teaminfo();
	if ($tbl && $store{map} && players_active() >= $tp->{balance_minplayers} && players_active() >= $tp->{minbots}) {
		my $diff = abs($tbl->{highsize} - $tbl->{lowsize});
		if (ceil(players_active() * $tp->{balance_part_maxdiff}) < $diff) { # too much difference in teamsizes
			out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: something is wrong (part teamsizes) - " . stats_irc();
		
			# TODO add code to balance teams
		
		} elsif (($tbl->{highlt} - ($tbl->{highlt} * $tp->{balance_part_threshold}) >= $tbl->{lowlt})) {
			out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: something is wrong (part lifetimes) - " . stats_irc();
		
			# TODO add code to balance teams
		}
	}
	
	return 0;
} ],

# we need our own store for id->slot mappings, as they may conflict with other plugins
[ dp => q{:join:(\d+):(\d+):([^:]*):(.*)} => sub {
	my ($id, $slot, $ip, $nick) = @_;
	if ($ip eq 'bot') {
		$store{plugin_teams}->{id2slot}->[$id] = $ip; #dirty workaround for bot detection
	} else {
		$store{plugin_teams}->{id2slot}->[$id] = $slot;
	}
	
	$store{plugin_teams}->{currentscore}->[$id] = 0;
	
	return 0;
} ],

[ dp => q{:gamestart:.*:[0-9\.]*} => sub {
	$store{teams} = undef;
	$store{caps} = undef;
	$store{spawns} = undef;
	$store{fc} = undef;
	$store{plugin_teams}->{id2slot} = undef;
	$store{plugin_teams}->{currentscore} = undef;
	
	$store{plugin_teams}->{balance_tryout_ctr} = 0;
	$store{plugin_teams}->{balance_check_ctr} = 0;
	
	$store{startdelay} = 1;
	$store{plugin_teams}->{game_ended} = 0;
	return 0;
} ],

[ dp => q{:end} => sub {
	#don't attempt to balance the game if it already finished.
	$store{plugin_teams}->{balance_tryout_ctr} = 0;
	$store{plugin_teams}->{balance_tryout_bool} = 1;
	
	$store{plugin_teams}->{game_ended} = 1;
	$store{plugin_teams}->{wtjtrack} = undef;
	return 0;
} ],

[ dp => q{"minplayers" is "([^"]*)" \["[^"]*"\]} => sub {
	my ($minp) = @_;
	$store{plugin_teams}->{minbots} = $minp;
	return 0;
} ],

[ dp => q{"g_respawn_delay" is "([^"]*)" \["[^"]*"\]} => sub {
	my ($respawn_delay) = @_;
	$store{plugin_teams}->{respawn_delay} = $respawn_delay;
	return 0;
} ],

[ dp => q{\001(.*?)\^7: (.*)} => sub {
	my ($nickraw, $message) = @_;
	$message = color_dp2none $message;
	if ($message =~ m/^!?(teams|unbalanced|unfair)[!\.,;]?$/gi) {
		my $nick = color_dp2irc $nickraw;
		my $str = stats_irc();
		out irc => 0, "PRIVMSG $config{irc_channel} :\00307* balance\017: $nick\017 thinks the teams are unfair: $str";
		return -1; # do not have it echoed again
	}
	
	return 0;
} ],

[ irc => q{:[^ ]* (?i:PRIVMSG) (?i:(??{$config{irc_channel}})) :!teams} => sub {
	#outputs team stats to irc
	my $str = stats_irc();
	out irc => 0, "PRIVMSG $config{irc_channel} :$str";
	return 0;
} ],

# allow tuning of the variables directly, so bot doesn't need a restart - these values are NOT saved
[ irc => q{:(([^! ]*)![^ ]*) (?i:PRIVMSG) [^&#%]\S* :(.*)} => sub {
	my ($hostmask, $nick, $command) = @_;
	
	return 0 if (($store{logins}{$hostmask} || 0) < time());
	
	if ($command =~ m/^teams (.+)$/i) {
		my ($var,$value) = split ' ', $1;
		if (!defined $store{plugin_teams}->{$var}) {
			out irc => 0, "PRIVMSG $nick :undefined key $var";
		} elsif (!defined $value) { #echo variable
			out irc => 0, "PRIVMSG $nick :$var " . $store{plugin_teams}->{$var};
		} else { #assign value
			$store{plugin_teams}->{$var} = $value;
			out irc => 0, "PRIVMSG $nick :assigned $var to $value";
		}
		return -1;
	}
	
	return 0;
} ],
