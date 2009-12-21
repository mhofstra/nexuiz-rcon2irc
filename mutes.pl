sub out($$@);

# :mute:player_id:mute_type:mute_time
[ dp => q{:mute:(\d+):(\d+):([\.\d]+)} => sub {
	my ($id, $mute_type, $mute_time) = @_;

	# find the players name
	my $nick = $store{"playernick_byid_$id"} || '(console)';

	# define the mute types
	my %mute_types = (1 => "for $mute_time seconds or the end of this map", 2 => 'life is good', 3 => 'until the end of this map');

	out irc => 0, "PRIVMSG $config{irc_channel} :\00311* mute\017: $nick\017 has been muted, " . $mute_types{$mute_type};
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
