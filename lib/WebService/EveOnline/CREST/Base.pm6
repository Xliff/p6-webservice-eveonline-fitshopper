use v6.c;

use WebService::EveOnline::Base;

class WebService::EveOnline::CREST::Base {
	also is WebService::EveOnline::Base;

	has $.sso;

	submethod BUILD(:$sso) {
		$!sso = $sso;
	}

	method checkScope($scope!) {
		die "'$scope' scope not specified for this token!"
			unless $.sso.scopes.grep(* eq $scope);
	}

	method makeRequest($url, :$method, :$headers) {
		$.sso.refreshToken if DateTime.now > $.sso.expires;

		nextwith(
			$url, 
			:$method, 
			:header($.sso.getHeader.append($headers.pairs))
		);
	}
}