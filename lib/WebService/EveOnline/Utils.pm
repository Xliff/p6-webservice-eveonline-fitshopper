use v6.c;

use DateTime::Parse;
use HTTP::UserAgent;
use HTTP::Cookie;

sub urlEncode($s) is export {
	$s.subst(/<-alnum>/, *.ord.fmt("%%%02X"), :g); 
}

sub prepParams($l) is export {
	$l.map({ $_[1] = urlEncode($_[1]); $_.join('='); }).join('&');
}

sub cookieExtra($c, $f) is export {
	for $c<extras> -> $e {
		return $e{$f} if $e{$f}.defined;
	}
	Nil;
}

sub cookieExtraVal($c, $f) is export {
	 my $k = cookieExtra($c, $f);
	 $k.defined ?? $k<value> !! Nil;
}

sub getCookies($r) is export {
	my @cookies;
	my $broken_cookies = 
		$r.header.field('Set-Cookie').values.
		join(' ');
	$broken_cookies ~~ s:g/( 'path=/' || 'secure' ) \s/$0; /;
	my $g = Cookie_Grammar.parse($broken_cookies);

	for @( $g<cookie> ) -> $c {
		my $dts = (cookieExtraVal($c, 'expires') // '').Str;
		if $dts.chars {
			my $dt = DateTime::Parse.new($dts);
			if $dt.defined {
				next unless $dt > DateTime.now;
			}
		}
		
		@cookies.push(HTTP::Cookie.new(
			name 		=> $c<name>.Str,
			value 		=> ($c<value> // '').Str,
			expires 	=> ($dts // ''),
			path		=> (cookieExtraVal($c, 'path')  // '').Str,
			secure  	=> (cookieExtra($c, 'secure')   // '').Str.lc eq 'secure',
			httponly 	=> (cookieExtra($c, 'httponly') // '').Str.lc eq 'httponly'
		));
	}

	@cookies;
}

sub getRequest($ua, $url) {

}