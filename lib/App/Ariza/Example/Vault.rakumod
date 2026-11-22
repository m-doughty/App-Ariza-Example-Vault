=begin pod

=head1 NAME

App::Ariza::Example::Vault - a tiny encrypted key/value vault, and a worked example of bundling an app with ariza

=head1 SYNOPSIS

From the command line:

=begin code :lang<console>

$ export ARIZA_EXAMPLE_VAULT_DB="$HOME/vault.db"
$ export ARIZA_EXAMPLE_VAULT_PASSPHRASE='correct horse battery staple'

$ ariza-example-vault set api-token 3f9a-77c1
stored 'api-token'
$ printf 'line one\nline two\n' | ariza-example-vault set notes
stored 'notes'
$ ariza-example-vault get api-token
3f9a-77c1
$ ariza-example-vault list
api-token
notes
$ ariza-example-vault show          # a coloured table, drawn with notcurses
$ ariza-example-vault delete notes
deleted 'notes'

=end code

From Raku:

=begin code :lang<raku>

use App::Ariza::Example::Vault;

my $vault = App::Ariza::Example::Vault.open(
    'vault.db', 'correct horse battery staple', :create);

$vault.set('greeting', 'שלום');
say $vault.get('greeting');         # שלום
say $vault.get('missing').defined;  # False
say $vault.keys;                    # (greeting)
say $vault.delete('greeting');      # True
$vault.close;

# A wrong passphrase is an exception of its own type.
try App::Ariza::Example::Vault.open('vault.db', 'not it');
say $!.^name;   # App::Ariza::Example::Vault::WrongPassphrase

=end code

=head1 DESCRIPTION

This distribution exists to show how an application with native
dependencies is packaged with
L<ariza|https://raku.land/zef:apogee/App::Ariza>. It is small enough to
read in one sitting, but it is a real app: it stores keys and values in
an SQLCipher database, which encrypts the whole file, and it draws its
C<show> view with L<Notcurses::Native|https://raku.land/zef:apogee/Notcurses::Native>.
Those are the two native libraries a bundle has to carry, and the
C<ariza.toml> beside this file says how.

=head2 The command line

Every command needs a database path and a passphrase. Neither is ever
prompted for, so the tool behaves the same in a script as at a
keyboard.

=item1 C<--db=FILE>, or C<ARIZA_EXAMPLE_VAULT_DB>, names the database.
The option wins over the variable.

=item1 C<--passphrase-file=FILE>, or C<ARIZA_EXAMPLE_VAULT_PASSPHRASE>,
supplies the passphrase. A file is read whole, and one trailing line
ending is removed. There is deliberately no C<--passphrase=> option:
anything on a command line can be read by other users of the machine.

=item1 C<set KEY [VALUE]> stores a value, replacing any value the key
already had. With no VALUE the value is read from standard input, which
keeps it off the command line too; one trailing line ending is removed.
C<set> is the only command that creates a database.

=item1 C<get KEY> prints the value. C<list> prints every key, one per
line, in code-point order. C<delete KEY> removes one entry; nothing is
ever deleted implicitly.

=item1 C<show> draws every key and value as a table with notcurses
direct mode, measured with notcurses' own idea of how wide each
character is. It needs a terminal, and says so rather than guessing
when standard output is a pipe or a file.

Exit status 0 means success, 1 means the key does not exist (C<get> and
C<delete>), and 2 means anything else went wrong, with the reason on
standard error.

=head2 Rules the vault enforces

=item1 A passphrase must not be empty. SQLCipher treats an empty key as
"do not encrypt", and a vault that quietly writes plain text is worse
than one that refuses.

=item1 Keys are non-empty and contain no control characters, so C<list>
can print one per line. Values may be anything, including empty and
multi-line.

=item1 A wrong passphrase is detected when the database is opened, not
at the first query, and raises C<App::Ariza::Example::Vault::WrongPassphrase>.
SQLCipher cannot tell a wrong passphrase from a file that is not a
vault at all, so the message names both.

=head2 Finding SQLCipher

DBIish loads SQLCipher by name. An ariza bundle carries its own copy
and its launcher makes sure that copy is the one found, so a user of a
bundle installs nothing. Outside a bundle:

=item1 B<macOS>: C<brew install sqlcipher>. Homebrew's library directory
is not on the loader's search path, so the command line links it next
to your Rakudo with L<MacOS::NativeLib|https://raku.land/zef:lizmat/MacOS::NativeLib>
the first time it runs (see L<App::Ariza::Example::Vault::NativeLib>).

=item1 B<Debian and Ubuntu>: C<apt install libsqlcipher-dev>. Releases
that ship C<libsqlcipher.so.1> also need C<DBIISH_SQLCIPHER_LIB> set to
that file's full path, because DBIish looks for C<.so.0> by default.

=item1 B<Fedora>: C<dnf install sqlcipher>, plus C<DBIISH_SQLCIPHER_LIB>
for the same reason.

=item1 B<Windows>: build it with C<vcpkg install sqlcipher:x64-windows>,
copy C<sqlcipher.dll> and the OpenSSL DLLs beside it into one
directory, put that directory on C<PATH>, and point
C<DBIISH_SQLCIPHER_LIB> at the DLL.

When the library cannot be found, opening a vault raises
C<App::Ariza::Example::Vault::LibraryMissing> with the instructions
above.

=head2 The bundle

C<ariza.toml> declares the two natives and three smoke checks:
C<--version> through the launcher, an encrypted create, write and
reopen round trip through this module, and a check that a wrong
passphrase is rejected. ariza adds its own notcurses loader probe to
every bundle that declares notcurses. Build and check a bundle with:

=begin code :lang<console>

$ ariza bundle --app=. --out-dir=dist
$ ariza smoke --archive=dist/ariza-example-vault-0.0.1-macos-arm64.tar.gz

=end code

=head1 METHODS

=head2 open(IO() $path, Str:D $passphrase, Bool :$create --> App::Ariza::Example::Vault)

Opens the vault at C<$path>. Without C<:create> the file must already
be a vault; with it, a missing file becomes a new, empty one. Raises
C<NoVault>, C<WrongPassphrase>, C<LibraryMissing> or plain C<Error>,
all under C<App::Ariza::Example::Vault::>, and all with a C<message>
meant for a person.

=head2 set(Str:D $key, Str:D $value --> Bool)

Stores C<$value> under C<$key>. Returns C<True> when it replaced an
existing value and C<False> when the key is new.

=head2 get(Str:D $key --> Str)

The value, or the C<Str> type object when the key does not exist, so
an empty value and a missing key are different answers.

=head2 keys(--> List) / entries(--> List)

Every key, or every key and value as Pairs, in code-point order.

=head2 delete(Str:D $key --> Bool)

Removes one entry. C<False> means there was nothing to remove.

=head2 close(--> Nil)

Closes the database. Safe to call twice.

=head2 check-key(Str:D $key --> Nil)

Raises C<App::Ariza::Example::Vault::Error> for a key C<set> would
refuse: an empty one, or one containing a control character. Callable
on the class, so a front end can check a key before it creates a file.

=head1 SEE ALSO

L<App::Ariza::Example::Vault::Show> for the notcurses view,
L<App::Ariza::Example::Vault::NativeLib> for finding SQLCipher on macOS,
L<App::Ariza::Example::Vault::CLI> for the command line.

=head1 AUTHOR

Matt Doughty

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it
under the Artistic License 2.0.

=end pod

unit class App::Ariza::Example::Vault;

use DBIish;

# Every failure a caller can act on has a type and a sentence.
class Error is Exception {
	has Str $.reason is required;
	method message(--> Str) { $!reason }
}
class NoVault is Error { }
class WrongPassphrase is Error { }
class LibraryMissing is Error { }

# Bumped only if the table below ever changes shape.
my constant SCHEMA-VERSION = 1;

my constant FIND-SQLCIPHER = q:to/HELP/.chomp;
    Install SQLCipher, or tell DBIish where it is:
      macOS:          brew install sqlcipher
      Debian/Ubuntu:  apt install libsqlcipher-dev
      Fedora:         dnf install sqlcipher
      Windows:        vcpkg install sqlcipher:x64-windows, then put the
                      directory holding sqlcipher.dll on PATH
    If it is installed under another name (libsqlcipher.so.1, say), set
    DBIISH_SQLCIPHER_LIB to the library's full path.
    HELP

has IO::Path $.path is required;
has $!dbh is built;

method open(IO() $path, Str:D $passphrase, Bool :$create = False --> App::Ariza::Example::Vault:D) {
	die Error.new(reason => 'the passphrase is empty; SQLCipher would store the vault unencrypted')
		unless $passphrase.chars;
	die Error.new(reason => "$path is a directory, not a vault") if $path.d;
	die NoVault.new(reason => "there is no vault at $path; `set` creates one")
		unless $create || $path.e;

	my $dbh = connect($path);
	$dbh.key($passphrase);

	# A wrong key only shows on the first read, so read now. Drain it, or
	# the open statement holds a transaction the DDL below trips over.
	my $rows = try {
		$dbh.execute('SELECT count(*), (SELECT user_version FROM pragma_user_version)'
			~ ' FROM sqlite_master').allrows.eager.List;
	};
	without $rows {
		$dbh.dispose;
		die WrongPassphrase.new(reason => "wrong passphrase for $path, or it is not an encrypted vault");
	}
	my ($tables, $version) = $rows[0].map(*.Int);

	if $create && $tables == 0 && $version == 0 {
		run-sql($dbh, 'CREATE TABLE vault_entries (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)');
		run-sql($dbh, "PRAGMA user_version = {SCHEMA-VERSION}");
	}
	elsif $version != SCHEMA-VERSION {
		$dbh.dispose;
		die Error.new(reason => "$path is an encrypted database, but not a vault"
			~ " (schema version $version, expected {SCHEMA-VERSION})");
	}

	self.bless(:$path, :$dbh);
}

method set(Str:D $key, Str:D $value --> Bool:D) {
	self.check-key($key);
	my $existed = self.get($key).defined;
	run-sql(self!dbh, 'INSERT INTO vault_entries (key, value) VALUES (?, ?)'
		~ ' ON CONFLICT(key) DO UPDATE SET value = excluded.value', $key, $value);
	$existed;
}

method get(Str:D $key --> Str) {
	my @rows = self!rows('SELECT value FROM vault_entries WHERE key = ?', $key);
	@rows ?? (@rows[0][0] // '').Str !! Str;
}

method keys(--> List:D) {
	self!rows('SELECT key FROM vault_entries ORDER BY key').map({ .[0].Str }).List;
}

method entries(--> List:D) {
	self!rows('SELECT key, value FROM vault_entries ORDER BY key')
		.map({ .[0].Str => (.[1] // '').Str }).List;
}

method delete(Str:D $key --> Bool:D) {
	return False without self.get($key);
	run-sql(self!dbh, 'DELETE FROM vault_entries WHERE key = ?', $key);
	True;
}

method close(--> Nil) {
	.dispose with $!dbh;
	$!dbh = Nil;
}

method !dbh() {
	$!dbh // die Error.new(reason => "the vault at $!path is closed");
}

# Every row, read to the end so no statement is left open.
method !rows(Str:D $sql, *@bind --> List:D) {
	self!dbh.execute($sql, |plain(@bind)).allrows.eager.List;
}

# DBIish hands a missing library back as an unthrown Failure.
my sub connect(IO::Path:D $path) {
	my $dbh = do {
		CATCH { default { die Error.new(reason => "could not open $path: {.message}") } }
		DBIish.connect('SQLCipher', database => $path.absolute);
	};
	if $dbh ~~ Failure {
		my $ex = $dbh.exception;
		$dbh.so;
		die LibraryMissing.new(reason => "SQLCipher could not be loaded.\n{FIND-SQLCIPHER}\n"
			~ "  ({$ex.message.lines.head})")
			if $ex ~~ X::DBIish::LibraryMissing;
		die Error.new(reason => "could not open $path: {$ex.message}");
	}
	$dbh;
}

# DBIish returns statement errors as unthrown Failures; throw them here.
my sub run-sql($dbh, Str:D $sql, *@bind --> Nil) {
	my $result = $dbh.do($sql, |plain(@bind));
	if $result ~~ Failure {
		my $ex = $result.exception;
		$result.so;
		die Error.new(reason => "the vault could not be written: {$ex.message}");
	}
}

# A command-line "42" is an IntStr, which DBIish cannot choose a binding for.
my sub plain(@bind --> List:D) {
	@bind.map(*.Str).List;
}

# Keys go one per line in `list`, so they may not break a line.
method check-key(Str:D $key --> Nil) {
	die Error.new(reason => 'a key cannot be empty') unless $key.chars;
	die Error.new(reason => "a key cannot contain control characters: {$key.raku}")
		if $key ~~ / <:Cc> /;
}
