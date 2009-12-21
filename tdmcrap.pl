# Nexuiz rcon2irc plugin by Merlijn Hofstra licensed under GPL - tdmcrap.pl
# Place this file inside the same directory as rcon2irc.pl and add the full filename to the plugins.

sub out($$@);

{ my %tc = (
	nummaps => 5,
); $store{plugin_tdmcrap} = \%tc; }

[ dp => q{:end} => sub {
	my $tc = $store{plugin_tdmcrap};
	$tc->{ctr}++;
	if ($tc->{ctr} % $tc->{nummaps} == 0) {
		#do tdm stuff
		out dp => 0, "doTDM";
	} else {
		#do ctf stuff
		out dp => 0, "doCTF";
	}
} ],
