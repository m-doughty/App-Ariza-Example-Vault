=begin pod

=head1 NAME

App::Ariza::Example::Vault::Show - draw a vault's entries as a table with notcurses direct mode

=head1 SYNOPSIS

=begin code :lang<raku>

use App::Ariza::Example::Vault::Show;

# On a terminal: a bold title, keys in blue, values beside them,
# everything cut to the terminal's width.
show(('api-token' => '3f9a-77c1', 'notes' => "line one\nline two"),
     :title('2 entries in vault.db'));

# The pieces, which need no terminal:
say visible("line one\nline two");      # line one␊line two
say cell-width('abc');                  # 3, measured by libnotcurses

.say for layout(('a-long-key' => 'a value that will not fit',),
                :columns(24), :width(*.chars));
# (a-long-key a value tha…)

=end code

=head1 DESCRIPTION

C<show> is the one command in the example that draws with
L<Notcurses::Native|https://raku.land/zef:apogee/Notcurses::Native>,
which is what makes the notcurses pack a real dependency of the bundle
rather than a declared one. It uses notcurses' I<direct mode>: no
full-screen takeover, just styled lines written where the cursor is,
so the table stays in the scrollback like any other command's output.

Widths are notcurses' own. Once direct mode has started (which sets up
the locale), C<ncstrwidth> says how many columns each key and value
occupies, so wide characters, emoji and combining marks line up.

Values are printed with every control character replaced by its
Unicode control picture. A vault can hold anything, and a value
containing an escape sequence must not be able to rewrite the user's
terminal.

=head2 Not a terminal

Direct mode on a pipe or a file would make notcurses go looking for a
controlling terminal to interrogate, which can wait forever. C<show>
checks first and fails with a sentence pointing at C<list> and C<get>,
which are the commands meant for scripts.

=head1 FUNCTIONS

=head2 show(@entries, Str:D :$title --> Nil)

Draws C<@entries> (Pairs of key and value) on standard output.
Raises C<App::Ariza::Example::Vault::Error> when standard output is not
a terminal or notcurses cannot start.

=head2 layout(@entries, Int:D :$columns!, :&width! --> List)

The table without the drawing: one C<(key-cell, value-cell)> list per
entry, with the key column padded to a common width (at most half the
screen) and values cut with C<…> to fit C<$columns>. C<&width> measures
one string in terminal columns.

=head2 visible(Str:D --> Str:D)

The string with C0 controls and DEL shown as their control pictures
(U+2400 to U+2421) and C1 controls as U+FFFD.

=head2 cell-width(Str:D --> Int:D)

Terminal columns according to libnotcurses' C<ncstrwidth>, falling back
to the grapheme count when notcurses cannot measure the string.
Before direct mode has set the locale, only plain ASCII is measured
reliably.

=head1 AUTHOR

Matt Doughty

=head1 COPYRIGHT AND LICENSE

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it
under the Artistic License 2.0.

=end pod

unit module App::Ariza::Example::Vault::Show;

use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Direct;
use Notcurses::Native::Context;

use App::Ariza::Example::Vault;

my constant KEY-RGB   = 0x5FAFFF;
my constant QUIET-RGB = 0x8A8A8A;
my constant GAP       = '  ';
my constant ELLIPSIS  = '…';

sub visible(Str:D $text --> Str:D) is export {
	$text.subst(/ <:Cc> /, -> $c {
		my $code = $c.Str.ord;
		$code < 0x20 ?? chr(0x2400 + $code)
			!! $code == 0x7F ?? chr(0x2421)
			!! chr(0xFFFD)
	}, :g);
}

sub cell-width(Str:D $text --> Int:D) is export {
	my int32 $bytes = 0;
	my int32 $columns = 0;
	my $measured = ncstrwidth($text, $bytes, $columns);
	$measured >= 0 ?? $measured !! $text.chars;
}

sub layout(@entries, Int:D :$columns!, :&width! --> List:D) is export {
	my @pairs = @entries.map({ visible(.key) => visible(.value) });
	my $widest = @pairs.map({ width(.key) }).max max 1;
	my $key-columns = min($widest, max($columns div 2, 1));
	my $value-columns = max($columns - $key-columns - GAP.chars, 1);

	@pairs.map(-> $pair {
		my $key = fit($pair.key, $key-columns, &width);
		($key ~ ' ' x ($key-columns - width($key)), fit($pair.value, $value-columns, &width))
	}).List;
}

sub show(@entries, Str:D :$title! --> Nil) is export {
	die App::Ariza::Example::Vault::Error.new(
		reason => 'show draws on a terminal, and standard output is not one;'
			~ ' use `list` and `get` in scripts')
		unless $*OUT.t;

	# Raku and notcurses buffer stdout separately; empty ours first.
	$*OUT.flush;
	my $nc = ncdirect_init(Str, Pointer, NCDIRECT_OPTION_INHIBIT_CBREAK);
	die App::Ariza::Example::Vault::Error.new(reason => 'notcurses could not start on this terminal')
		without $nc;
	LEAVE { ncdirect_stop($nc) with $nc }

	ncdirect_on_styles($nc, NCSTYLE_BOLD);
	put($nc, 0, "$title\n");
	ncdirect_off_styles($nc, NCSTYLE_BOLD);

	my $columns = max(ncdirect_dim_x($nc), 20);
	for layout(@entries, :$columns, :width(&cell-width)) -> ($key, $value) {
		put($nc, foreground(KEY-RGB), $key);
		put($nc, 0, GAP ~ $value ~ "\n");
	}
	put($nc, foreground(QUIET-RGB), "(empty)\n") unless @entries;
	ncdirect_flush($nc);
}

# A channel pair with only the foreground set; 0 is default colours.
my sub foreground(Int:D $rgb --> Int:D) {
	(NC_BGDEFAULT_MASK +| $rgb) +< 32;
}

my sub put($nc, Int:D $channels, Str:D $text) {
	die App::Ariza::Example::Vault::Error.new(reason => 'notcurses could not write to the terminal')
		if ncdirect_putstr($nc, $channels, $text) < 0;
}

# The longest prefix of whole characters that fits, marked when cut.
my sub fit(Str:D $text, Int:D $columns, &width --> Str:D) {
	return $text if width($text) <= $columns;
	my $room = $columns - width(ELLIPSIS);
	my $kept = '';
	my $used = 0;
	for $text.comb -> $char {
		my $w = width($char);
		last if $used + $w > $room;
		$kept ~= $char;
		$used += $w;
	}
	$room < 0 ?? '' !! $kept ~ ELLIPSIS;
}
