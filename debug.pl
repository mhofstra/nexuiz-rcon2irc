# Nexuiz rcon2irc plugin by Merlijn Hofstra licensed under GPL - debug.pl
# Place this file inside the same directory as rcon2irc.pl and add the full filename to the plugins.

# Use this plugin with extreme caution, it allows irc-admins to modify ANYTHING on your server.

sub out($$@);

[ irc => q{:(([^! ]*)![^ ]*) (?i:PRIVMSG) [^&#%]\S* :(.*)} => sub {
	my ($hostmask, $nick, $command) = @_;
	
	return 0 if (($store{logins}{$hostmask} || 0) < time());
	
	if ($command =~ m/^debug (.+)$/i) {
		my $str = eval $1;
		
		if ($@) {
			out irc => 0, "PRIVMSG $nick :$@";
		} elsif (!defined $str) {
			out irc => 0, "PRIVMSG $nick :undef"
		} elsif ($str eq '') {
			out irc => 0, "PRIVMSG $nick :''";
		} else {
			out irc => 0, "PRIVMSG $nick :$str";
		}
		
		return -1;
	}
	
	return 0;
} ],
