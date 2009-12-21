# Nexuiz rcon2irc plugin by Merlijn Hofstra licensed under GPL - nadzmute.pl
# Place this file inside the same directory as rcon2irc.pl and add the full filename to the plugins.

sub out($$@);

[ dp => q{:join:(\d+):(\d+):([^:]*):(.*)} => sub {
	my ($id, $slot, $ip, $nick) = @_;
	$nick = color_dp2none $nick;
	if ($nick =~ m/^nadz/i) {
		out dp => 0, "mute $slot -1";
	}
	return 0;
} ],
