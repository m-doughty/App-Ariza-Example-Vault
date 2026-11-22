NAME
====

App::Ariza::Example::Vault - a tiny encrypted key/value vault, and a worked example of bundling an app with ariza

SYNOPSIS
========

From the command line:

```console
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
```

From Raku:

```raku
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
```

DESCRIPTION
===========

This distribution exists to show how an application with native dependencies is packaged with [ariza](https://raku.land/zef:apogee/App::Ariza). It is small enough to read in one sitting, but it is a real app: it stores keys and values in an SQLCipher database, which encrypts the whole file, and it draws its `show` view with [Notcurses::Native](https://raku.land/zef:apogee/Notcurses::Native). Those are the two native libraries a bundle has to carry, and the `ariza.toml` beside this file says how.

The command line
----------------

Every command needs a database path and a passphrase. Neither is ever prompted for, so the tool behaves the same in a script as at a keyboard.

  * `--db=FILE`, or `ARIZA_EXAMPLE_VAULT_DB`, names the database. The option wins over the variable.

  * `--passphrase-file=FILE`, or `ARIZA_EXAMPLE_VAULT_PASSPHRASE`, supplies the passphrase. A file is read whole, and one trailing line ending is removed. There is deliberately no `--passphrase=` option: anything on a command line can be read by other users of the machine.

  * `set KEY [VALUE]` stores a value, replacing any value the key already had. With no VALUE the value is read from standard input, which keeps it off the command line too; one trailing line ending is removed. `set` is the only command that creates a database.

  * `get KEY` prints the value. `list` prints every key, one per line, in code-point order. `delete KEY` removes one entry; nothing is ever deleted implicitly.

  * `show` draws every key and value as a table with notcurses direct mode, measured with notcurses' own idea of how wide each character is. It needs a terminal, and says so rather than guessing when standard output is a pipe or a file.

Exit status 0 means success, 1 means the key does not exist (`get` and `delete`), and 2 means anything else went wrong, with the reason on standard error.

Rules the vault enforces
------------------------

  * A passphrase must not be empty. SQLCipher treats an empty key as "do not encrypt", and a vault that quietly writes plain text is worse than one that refuses.

  * Keys are non-empty and contain no control characters, so `list` can print one per line. Values may be anything, including empty and multi-line.

  * A wrong passphrase is detected when the database is opened, not at the first query, and raises `App::Ariza::Example::Vault::WrongPassphrase`. SQLCipher cannot tell a wrong passphrase from a file that is not a vault at all, so the message names both.

Finding SQLCipher
-----------------

DBIish loads SQLCipher by name. An ariza bundle carries its own copy and its launcher makes sure that copy is the one found, so a user of a bundle installs nothing. Outside a bundle:

  * **macOS**: `brew install sqlcipher`. Homebrew's library directory is not on the loader's search path, so the command line links it next to your Rakudo with [MacOS::NativeLib](https://raku.land/zef:lizmat/MacOS::NativeLib) the first time it runs (see [App::Ariza::Example::Vault::NativeLib](App::Ariza::Example::Vault::NativeLib)).

  * **Debian and Ubuntu**: `apt install libsqlcipher-dev`. Releases that ship `libsqlcipher.so.1` also need `DBIISH_SQLCIPHER_LIB` set to that file's full path, because DBIish looks for `.so.0` by default.

  * **Fedora**: `dnf install sqlcipher`, plus `DBIISH_SQLCIPHER_LIB` for the same reason.

  * **Windows**: build it with `vcpkg install sqlcipher:x64-windows`, copy `sqlcipher.dll` and the OpenSSL DLLs beside it into one directory, put that directory on `PATH`, and point `DBIISH_SQLCIPHER_LIB` at the DLL.

When the library cannot be found, opening a vault raises `App::Ariza::Example::Vault::LibraryMissing` with the instructions above.

The bundle
----------

`ariza.toml` declares the two natives and three smoke checks: `--version` through the launcher, an encrypted create, write and reopen round trip through this module, and a check that a wrong passphrase is rejected. ariza adds its own notcurses loader probe to every bundle that declares notcurses. Build and check a bundle with:

```console
$ ariza bundle --app=. --out-dir=dist
$ ariza smoke --archive=dist/ariza-example-vault-0.0.1-macos-arm64.tar.gz
```

METHODS
=======

open(IO() $path, Str:D $passphrase, Bool :$create --> App::Ariza::Example::Vault)
---------------------------------------------------------------------------------

Opens the vault at `$path`. Without `:create` the file must already be a vault; with it, a missing file becomes a new, empty one. Raises `NoVault`, `WrongPassphrase`, `LibraryMissing` or plain `Error`, all under `App::Ariza::Example::Vault::`, and all with a `message` meant for a person.

set(Str:D $key, Str:D $value --> Bool)
--------------------------------------

Stores `$value` under `$key`. Returns `True` when it replaced an existing value and `False` when the key is new.

get(Str:D $key --> Str)
-----------------------

The value, or the `Str` type object when the key does not exist, so an empty value and a missing key are different answers.

keys(--> List) / entries(--> List)
----------------------------------

Every key, or every key and value as Pairs, in code-point order.

delete(Str:D $key --> Bool)
---------------------------

Removes one entry. `False` means there was nothing to remove.

close(--> Nil)
--------------

Closes the database. Safe to call twice.

check-key(Str:D $key --> Nil)
-----------------------------

Raises `App::Ariza::Example::Vault::Error` for a key `set` would refuse: an empty one, or one containing a control character. Callable on the class, so a front end can check a key before it creates a file.

SEE ALSO
========

[App::Ariza::Example::Vault::Show](App::Ariza::Example::Vault::Show) for the notcurses view, [App::Ariza::Example::Vault::NativeLib](App::Ariza::Example::Vault::NativeLib) for finding SQLCipher on macOS, [App::Ariza::Example::Vault::CLI](App::Ariza::Example::Vault::CLI) for the command line.

AUTHOR
======

Matt Doughty

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

