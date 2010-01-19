# Nexuiz rcon2irc plugin by Merlijn Hofstra & Spaceman licensed under GPL - mutes.pl
# Place this file inside the same directory as rcon2irc.pl and add the full filename to the plugins.

sub out($$@);

# :mute:player_id:mute_type:mute_time
[ dp => q{:mute:(\d+):(\d+):([\.\d]+)} => sub {
	my ($id, $mute_type, $mute_time) = @_;

	# find the players name
	my $nick = $store{"playernick_byid_$id"} || '(console)';

	# define the mute types
	my %mute_types = (
		0 => ' (just joined)', # should never happen
		1 => ' (not muted)', # should never happen
		2 => " for $mute_time seconds or the start of the next map", 
		3 => ', life is good', # mute until player leaves the server
		4 => ' until the start of the next map'
	);

	out irc => 0, "PRIVMSG $config{irc_channel} :\00311* mute\017: $nick\017 has been muted" . $mute_types{$mute_type};
	return 0;
} ],

# :unmute:player_id:mute_type
[ dp => q{:unmute:(\d+):(\d+)} => sub {
	my ($id, $mute_type) = @_;

	# find the players name
	my $nick = $store{"playernick_byid_$id"} || '(console)';

	out irc => 0, "PRIVMSG $config{irc_channel} :\00311* unmute\017: $nick\017 has been unmuted";
	return 0;
} ],
