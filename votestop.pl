# Nexuiz rcon2irc plugin by Merlijn Hofstra licensed under GPL - votestop.pl
# Place this file inside the same directory as rcon2irc.pl and add the full filename to the plugins.

# This plugin will stop an ongoing vote when the person who called it leaves.

{ my %vs = (
	mapstart => 60, # can't call mapchange votes for this amount of seconds after mapstart
	connected => 180, # can't call votes when you just joined the server
);

$store{plugin_votestop} = \%vs; }

sub out($$@);

sub time_to_seconds {
	my $in = shift;
	my @ar = split /:/, $in;
	return ($ar[0] * 60 * 60) + ($ar[1] * 60) + $ar[2];
}

[ dp => q{:vote:vcall:(\d+):(.*)} => sub {
	my ($id, $command) = @_;
	$command = color_dp2irc $command;
	$vs = $store{plugin_votestop};
	
	if ($vs->{mapstart} && (time() - $store{map_starttime}) < $vs->{mapstart}) {
		if ($command =~ m/^(endmatch|restart|gotomap|chmap)/gi) {
			out dp => 0, "sv_cmd vote stop";
			out irc => 0, "PRIVMSG $config{irc_channel} :* vote \00304$command\017 by " . $store{"playernick_byid_$id"} .
				"\017 was rejected because the map hasn't been played long enough";
				
			out dp => 0, "tell #$id your vote was rejected because this map only just started.";
			
			$vs->{vstopignore} = 1;
			return -1;
		}
	}
	
	my $slot = $store{"playerslot_byid_$id"};
	my $time = time_to_seconds $store{"playerslot_$slot"}->{'time'};
	if ($vs->{connected} && $time < $vs->{connected}) {
		out dp => 0, "sv_cmd vote stop";
		out irc => 0, "PRIVMSG $config{irc_channel} :* vote \00304$command\017 by " . $store{"playernick_byid_$id"} .
			"\017 was rejected because he isn't connected long enough";
			
		out dp => 0, "tell #$id your vote was rejected because you just joined the server.";
			
		$vs->{vstopignore} = 1;
		return -1;
	}
	
	$vs->{currentvote} = $id;
	return 0;
} ],

[ dp => q{:vote:v(yes|no|timeout|stop):.*} => sub {
	my ($cmd) = @_;
	$store{plugin_votestop}->{currentvote} = undef;
	
	if ($cmd eq 'stop' && $vs->{vstopignore}) {
		$vs->{vstopignore} = undef;
		return -1;
	}
	return 0;
} ],

[ dp => q{:gamestart:(.*):[0-9.]*} => sub {
	if (defined $store{plugin_votestop}->{currentvote}) {
		out dp => 0, "sv_cmd vote stop";
		$store{plugin_votestop}->{currentvote} = undef;
	}
	return 0;
} ],

[ dp => q{:part:(\d+)} => sub {
	my ($id) = @_;
	if (defined $store{plugin_votestop}->{currentvote} && $id == $store{plugin_votestop}->{currentvote}) {
		out dp => 0, "sv_cmd vote stop";
	}
	return 0;
} ],
