=begin pod

=head1 NAME

App::Ariza::Example::Vault::CLI - the commands behind C<ariza-example-vault>

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Ariza::Example::Vault::CLI;

say version-line();     # App::Ariza::Example::Vault 0.0.1

my %env = ARIZA_EXAMPLE_VAULT_DB         => 'vault.db',
          ARIZA_EXAMPLE_VAULT_PASSPHRASE => 'correct horse battery staple';

run-command('set', 'api-token', '3f9a-77c1', :%env);   # 0, prints: stored 'api-token'
run-command('get', 'api-token', :%env);                # 0, prints: 3f9a-77c1
run-command('get', 'nope', :%env);                     # 1, says so on stderr
run-command('list', :db('other.db'), :%env);           # --db wins over the variable

=end code

=head1 DESCRIPTION

The executable is a thin layer of C<MAIN> candidates over
C<run-command>, which keeps every command callable, and testable,
from Raku. Output goes to C<$*OUT> and errors to C<$*ERR>, so a caller
can capture either by rebinding the dynamic variable.

Where the database and passphrase come from, in order:

=item1 C<:db>, which is C<--db=FILE>, then C<ARIZA_EXAMPLE_VAULT_DB>.

=item1 C<:passphrase-file>, which is C<--passphrase-file=FILE>, then
C<ARIZA_EXAMPLE_VAULT_PASSPHRASE>. One trailing line ending is removed
from a file, so C<echo secret E<gt> file> works.

Nothing is ever prompted for. C<set> with no value reads standard input,
but refuses when standard input is a terminal, because waiting there
for a value nobody was asked for would look like a hang.

C<set> is the only command that creates a database, and it says so on
standard error when it does.

=head1 FUNCTIONS

=head2 run-command(Str:D $command, *@words, Str :$db, Str :$passphrase-file, :%env --> Int:D)

Runs one of C<set>, C<get>, C<list>, C<delete> or C<show> and returns
the exit status: 0 for success, 1 when the key does not exist, 2 for
everything else, with the reason on C<$*ERR>. C<%env> defaults to
C<%*ENV>.

=head2 version-line(--> Str:D)

C<App::Ariza::Example::Vault> and the installed version. From a
checkout run with C<-Ilib> there is no installed version, and the
answer is C<dev>, the same answer ariza itself gives.

=head1 AUTHOR

Matt Doughty

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it
under the Artistic License 2.0.

=end pod

unit module App::Ariza::Example::Vault::CLI;

use App::Ariza::Example::Vault;
use App::Ariza::Example::Vault::NativeLib;
use App::Ariza::Example::Vault::Show;

my constant DB-ENV = 'ARIZA_EXAMPLE_VAULT_DB';
my constant PASSPHRASE-ENV = 'ARIZA_EXAMPLE_VAULT_PASSPHRASE';
my constant %ARITY = set => (1, 2), get => (1, 1), list => (0, 0), delete => (1, 1), show => (0, 0);

sub version-line(--> Str:D) is export {
	my $version = try $?DISTRIBUTION.meta<version>;
	"App::Ariza::Example::Vault {$version.defined && $version.Str.chars ?? $version.Str !! 'dev'}";
}

sub run-command(Str:D $command, *@words, Str :$db, Str :$passphrase-file, :%env = %*ENV --> Int:D) is export {
	CATCH {
		when App::Ariza::Example::Vault::Error {
			$*ERR.say: "ariza-example-vault: {.message}";
			return 2;
		}
	}

	my ($least, $most) = |(%ARITY{$command} // fail-with("unknown command '$command'"));
	fail-with("$command takes {$least == $most ?? $least !! "$least or $most"} argument(s), not {+@words}")
		unless $least <= @words <= $most;

	my $path = (($db // %env{DB-ENV} // '') || fail-with("no database: pass --db=FILE or set {DB-ENV}")).IO;
	my $passphrase = passphrase($passphrase-file, %env);
	$*ERR.say("ariza-example-vault: $_") with link-sqlcipher();

	given $command {
		when 'set' {
			App::Ariza::Example::Vault.check-key(@words[0]);
			my $value = @words[1] // value-from-stdin();
			my $new = !$path.e;
			my $vault = App::Ariza::Example::Vault.open($path, $passphrase, :create);
			LEAVE { .close with $vault }
			$*ERR.say("ariza-example-vault: created a new vault at $path") if $new;
			my $replaced = $vault.set(@words[0], $value);
			$*OUT.say: "{$replaced ?? 'replaced' !! 'stored'} '{visible(@words[0])}'";
			0;
		}
		when 'get' {
			my $vault = App::Ariza::Example::Vault.open($path, $passphrase);
			LEAVE { .close with $vault }
			with $vault.get(@words[0]) { $*OUT.say: $_; 0 } else { no-such-key(@words[0]) }
		}
		when 'list' {
			my $vault = App::Ariza::Example::Vault.open($path, $passphrase);
			LEAVE { .close with $vault }
			$*OUT.say($_) for $vault.keys;
			0;
		}
		when 'delete' {
			my $vault = App::Ariza::Example::Vault.open($path, $passphrase);
			LEAVE { .close with $vault }
			return no-such-key(@words[0]) unless $vault.delete(@words[0]);
			$*OUT.say: "deleted '{visible(@words[0])}'";
			0;
		}
		when 'show' {
			my $vault = App::Ariza::Example::Vault.open($path, $passphrase);
			my @entries = $vault.entries;
			$vault.close;
			show(@entries, :title("{+@entries} {@entries == 1 ?? 'entry' !! 'entries'} in {$path.basename}"));
			0;
		}
	}
}

my sub fail-with(Str:D $reason) {
	die App::Ariza::Example::Vault::Error.new(:$reason);
}

my sub no-such-key(Str:D $key --> 1) {
	$*ERR.say: "ariza-example-vault: no such key '{visible($key)}'";
}

my sub passphrase(Str $file, %env --> Str:D) {
	with $file {
		fail-with("cannot read the passphrase file $file") unless .IO.f;
		return chomp-one(.IO.open.slurp(:close));
	}
	%env{PASSPHRASE-ENV} // fail-with("no passphrase: pass --passphrase-file=FILE or set {PASSPHRASE-ENV}");
}

my sub value-from-stdin(--> Str:D) {
	fail-with('no value given: pass it after the key, or pipe it on standard input')
		if $*IN.t;
	chomp-one($*IN.slurp);
}

# One trailing line ending, so `echo secret > file` means "secret".
my sub chomp-one(Str:D $text --> Str:D) {
	$text.subst(/ \n $ /, '');
}
