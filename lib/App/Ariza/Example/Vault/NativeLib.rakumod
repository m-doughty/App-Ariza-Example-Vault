=begin pod

=head1 NAME

App::Ariza::Example::Vault::NativeLib - make Homebrew's SQLCipher loadable on macOS

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Ariza::Example::Vault::NativeLib;
use App::Ariza::Example::Vault;

# Before the first vault is opened. Does nothing on Linux and Windows,
# and nothing on a Mac where the library is already loadable.
.note with link-sqlcipher();

my $vault = App::Ariza::Example::Vault.open('vault.db', 'passphrase', :create);

=end code

=head1 DESCRIPTION

DBIish asks the dynamic loader for SQLCipher by its leaf name, and on
macOS the loader searches the directory beside the Rakudo executable
but not Homebrew's C<lib/>. L<MacOS::NativeLib|https://raku.land/zef:lizmat/MacOS::NativeLib>
fixes that by linking Homebrew's copies into the Rakudo C<lib/>
directory, once.

Asking Homebrew where it keeps the library costs about a second, so
C<link-sqlcipher> only does it when C<libsqlcipher.dylib> is not already
beside the running Rakudo. Inside an ariza bundle it always is: ariza
puts SQLCipher in the bundle's own C<rakudo/lib>, so a bundle never
runs Homebrew at all.

=head1 FUNCTIONS

=head2 link-sqlcipher(--> Str)

Links SQLCipher next to the running Rakudo when that is needed and
possible. Returns the undefined C<Str> when there is nothing to report,
and a message when Homebrew could not supply the library, which
L<App::Ariza::Example::Vault>'s C<open> will then fail to load with
instructions of its own.

=head1 AUTHOR

Matt Doughty

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it
under the Artistic License 2.0.

=end pod

unit module App::Ariza::Example::Vault::NativeLib;

# Imports only &ensure-symlink-for; linking happens when it is called.
use MacOS::NativeLib;

# Read once: in Rakudo 2026.09 every read of $*DISTRO leaks a descriptor on macOS.
my constant IS-MACOS = $*VM.osname eq 'darwin';

sub link-sqlcipher(--> Str) is export {
	return Str unless IS-MACOS;
	return Str if $*EXECUTABLE.parent.sibling('lib').add('libsqlcipher.dylib').e;
	my $problems = ensure-symlink-for('sqlcipher');
	$problems ?? "SQLCipher could not be linked from Homebrew: $problems" !! Str;
}
