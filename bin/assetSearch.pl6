#!/usr/bin/perl6

use v6.c;

use DBIish;

use WebService::EveOnline::SSO::Web;
use WebService::EveOnline::Utils;
use WebService::EveOnline::Data;
use WebService::EveOnline::Data::Misc;
use WebService::EveOnline::ESI::Assets;
use WebService::EveOnline::ESI::Universe;

my (%inv, %manifest, %assets, $asset-api, $universe, $sso, $search);

my @valid-filters = <
	is_singleton
	item_id
	item_name
	location_flag
	location_id
	location_type
	quantity
	type_id
>;

my @additional-bp-filters = <
	material_efficiency
	time_efficiency
	runs
>;

my @additional-filters = <
  systems
  system-ids
  regions
  region-ids
  station-ids
>;

my @aliases = <item-name name names te me>;

sub compareQuantity($num, $l) {
	do given $l[0] {
		when '=' { $num == $l[1]; }
		when '>' { $num  > $l[1]; }
		when '<' { $num  < $l[1]; }
	}
}

# MAY BE DEPRECATED.
sub checkLocation($t, @list, $i) {
	my @loc = do given $t {
		when 'systems' | 'regions' {
			@list.grep({
				[&&](
					$i<xMin> <= $_<x> <= $i<xMax>,
					$i<yMin> <= $_<y> <= $i<yMax>,
					$i<zMin> <= $_<z> <= $i<zMax>
				)
				||
				[+](
					($_<x> - $i<x>) ** 2,
					($_<y> - $i<y>) ** 2,
					($_<z> - $i<z>) ** 2
				) < $i<radius> ** 2
			});
		}

		when 'stations' {
			@list.grep({
				[&&](
					$_<x> == $i<x>,
					$_<y> == $i<y>,
					$_<z> == $i<z>
				)
			});
		}
	}
	return False unless +@loc;
	$_<location> = $i;
	True;
}

# Resolve what gets passed down, since the item MUST be returned with a
# resolved location.
	my (%privateStructures, %publicStructures);

	sub getResolutionInformation {
		use WebService::EveOnline::ESI::Alliance;
		use WebService::EveOnline::ESI::Corporation;

    # If only using character search, then exclude all non-public station
    # results.
    return unless $search<where> eq <all corp>.any;
    
		# Get private corporation structures.
		my $corp = WebService::EveOnline::ESI::Corporation.new($sso);
		%privateStructures = arrayToHash(
			$corp.getStructures(),
			'structure_id'
		);
		# Get alliance corporation List
		my $alliance = WebService::EveOnline::ESI::Alliance.new($sso);
		my $alliance-corps = $alliance.getCorporations();
		for $alliance-corps -> $ac {
			my $corpStructures = $corp.getStructures($ac);

			%privateStructures.append(
				arrayToHash($corpStructures, 'structure_id')
			) if $corpStructures;

			CATCH {
				# Silent fail all API errors.
				when X::Cro::HTTP::Error::Client {
					if .response.status == (401, 403).any {
						my $i = $corp.getInformation($ac);
						note "Cannot get structures from the '$i<name>' corporation.";
						.resume
					}
				}
			}
		}
	}

	sub resolveLocation(%items, $i, $ip?) {
		my $unr;

		if $ip.defined {
			$unr = $ip;
		} else {
			$unr = $i;
			getResolutionInformation() unless +%privateStructures;
		}

		given $unr<location_id> {
      say "Resolving: $_";
      
			# In known space
			when is-a-system($_) {
				$i<system_id> = $_;
			}
			# In a station
			when is-a-station($_) {
				my $station = $universe.getStation($_);

				$i<station_id> = $_;
				$i<system_id> = $station<system_id>;
			}
			when is-an-abyssal($_) {
				# WAT!? RILLY?
				# (this should never happen)
				note "Item { $p.value<item_id> } is in an abyssal system!";
			}
			# In a public structure (aka citadel)
			when %publicStructures{$_} {
				$i<structure_id system_id> = %publicStructures{$_}<structure_id system_id>;
			}
			# In a private structure
			when %privateStructures{$_} {
				$i<structure_id system_id> = %privateStructures{$_}<structure_id system_id>
			}
			# In the the list of assets.
			when %items<data>{$_} {
				resolveLocation(
					$i,
					%items<data>{ %items<data>{$_}<location_id> }
				);
			}
			# In an unknown place (LIMBO!)
			default {
				note "Item { $i<item_id> } has a location_id that cannot be resolved.";
			}
		}
	}

sub filterLocations(%items, %filters) {
	my @location-based = %filters<ADDITIONAL>.flat;
	%publicStructures = $universe.getStructures()<data>.map({ $_ => 1 }).Hash;

	my %usedItems := %items<filtered>:exists ?? %items<filtered> !! %items;
	for %usedItems.pairs -> $p {
    say "P: { $p.gist }";
    
	  my $item = resolveLocation($p.value);
	  # Retrieve location data. (mandatory)
	  # for <char corp> -> $c {
	  # 	%locations{$c} = do given $c {
	  # 		when 'char' {
	  # 			$asset-api.getCharacterAssetLocations(
	  # 				%found-items{$c}.keys.map( *.Int )
	  # 			);
	  # 	  }
	  # 		when 'corp' {
	  # 			$asset-api.getCorporationAssetLocations(
	  # 				%found-items{$c}.keys.map( *.Int )
	  # 			);
	  # 		}
	  # 	}
	  # 	for %locations{$c}.keys -> $k {
	  # 		if %found-items{$c}{$k}:exists {
	  # 			#%found-items{$c}{$k}<item_id>:delete;
	  # 			%found-items{$c}{$k}.append: %locations{$c}{$k}.pairs;
	  # 		}
	  # 	}
	  #
	  # 	# location data is now with the item. Now need to filter. Turns result back into an array.
	  # 	# Note that location-based searching uses inverse logic than asset-based.
	  # 	if +@location-based {
	  # 		%found-items{$c} = %found-items{$c}.pairs.grep({
	  # 			for @location-based -> $l {
	  # 				return True if $l.value( $_.value );
	  # 			}
	  # 			False;
	  # 		});
	  # 	}
	  # }
	}
}

sub findItems(%filters, $searches) {
	my %empty = (
		char => {
			data     => {},
			filtered => {},
		},
		corp => {
			data     => {},
			filtered => {},
		}
	);

	my %found-items = %empty.clone;
	my @filtered = %filters.keys;
	for $searches<what>.List -> $w {

		my $grepSub = sub (*@a) {
			for @filtered -> $k {
				return False unless %filters{$k}(@a[0]);
			}
			True;
		};

		my $assets;
		given $w {
			when 'asset' {
				@filtered .= grep(* ne @additional-bp-filters.all);

				my $a;
				if $searches<where>.any eq <all char>.any {
					$a = $asset-api.getCharacterAssets( :filter($grepSub) );
					%found-items<char><data>.append: $a<data>.Hash;
					%found-items<char><filtered>.append($a<filtered>.Hash) 
            if $a<filtered>:exists;
				}

				if $searches<where>.any eq <all corp>.any {
					$a = $asset-api.getCorporationAssets( :filter($grepSub) );
					%found-items<corp><data>.append: $a<data>.Hash;
					%found-items<corp><filtered>.append($a<filtered>.Hash) 
            if $a<filtered>:exists;
				}
			}

			when 'bp' {
				my $a;
				if $searches<where>.any eq <all char>.any {
					$a = $asset-api.getCharacterBlueprints( :filter($grepSub) );
					%found-items<char><data>.append: $a<data>;
					%found-items<char><filtered>.append($a<filtered>.Hash) 
            if $a<filtered>:exists;
				}

				if $searches<where>.any eq <all corp>.any {
					$a = $asset-api.getCorporationBlueprints( :filter($grepSub) );
				  %found-items<corp><data>.append($a<data>.Hash);
				  %found-items<corp><filtered>.append($a<filtered>.Hash) 
            if $a<filtered>:exists;
			  }
		  }
		}
	}

	%found-items;
}

sub showResults(%items) {
	%items.gist.say;
}

sub MAIN(
	:$sqlite,
	:$corp,
	:$char,
	:$blueprints,
	:$bp,
	:$bponly,
	*%extras
) {
	my regex c { ',' \s* };

	my @valid-options = (
		|@valid-filters,
		|@additional-bp-filters,
		|@additional-filters,
		|@aliases
	);

  my @scopes = ('esi-assets.read_assets.v1');
	$sso = WebService::EveOnline::SSO::Web.new(
		# :scopes(<
		# 	esi-assets.read_assets.v1
		# 	esi-assets.read_corporation_assets.v1
		# 	esi-corporations.read_blueprints.v1
		# 	esi-characters.read_blueprints.v1
		# 	esi-universe.read_structures.v1
    #   esi-corporations.read_structures.v1
		# >),
    :@scopes,
		:realm<ESI>,
		:section<assetCrawler>
	);
  $sso.await-init;

	# Add in :type, later.
	$universe = WebService::EveOnline::ESI::Universe.new(:$sso);
	$asset-api = WebService::EveOnline::ESI::Assets.new(:$sso);

	$search = {
		where => 'char',
		what  => [ 'asset' ]
	};
	$search<where> = 'corp' with $corp;
	$search<where> = 'char' with $char;
	$search<where> = 'all'  with $corp && $char;

	# cw: Would blueprints without a filter be a useful option?
	#     (Probably for newbies, but....)
	$search<what>.push: 'bp'   if $blueprints || $bp;
	$search<what> = [ 'bp' ]   if $bponly;

	if
		! +%extras
		||
		%extras.keys.all ne @valid-options.any
	{
		USAGE;
		exit;
	}

	my (%filters, @location_flags, @systems, @regions);
	my (@type_ids, @location_types, @names, $ql);

	if %extras<location_flag>.defined {
		@location_flags = %extras<location_flag>.split(/<c>/);
		die "Invalid location flag specified."
			unless @location_flags.all eq @valid-location-flags.any;
	}

	if %extras<location_type>.defined {
		@location_types = %extras<location_type>.split(/<c>/);
		die "Invalid value for --location_type\n"
		 	unless @location_types.all eq @valid-location-types.any;
	}

	openStaticDB($sqlite);

	@type_ids = %extras<type_id>.split(/<c>/) if %extras<type_id>.defined;
	if [||] (
		%extras<item_name>.defined,
		%extras<item-name>.defined,
		%extras<names>.defined,
		%extras<name>.defined;
	) {
		# There is a lot of work being done, here.
		@type_ids.append: resolveItemNames(
			(
				|( %extras<item_name> // '' ).split(/<c>/),
				|( %extras<item-name> // '' ).split(/<c>/),
				|( %extras<names>     // '' ).split(/<c>/),
				|( %extras<name>      // '' ).split(/<c>/)
			).unique.grep( *.chars )
		);
	}

	@systems.append: %extras<system_ids>.split(/<c>/) if %extras<system_id>.defined;
	@systems.append: %extras<system-ids>.split(/<c>/) if %extras<system-id>.defined;
	@systems.append: resolveSystemNames(
		|( %extras<systems>.split(/<c>/) )
	) if %extras<systems>.defined;

	# Even though it is a system-based search, we still need this to be separate
	# for error-checking purposes.
	@regions.append: %extras<region_ids>.split(/<c>/) if %extras<region_ids>.defined;
	@regions.append: %extras<region-ids>.split(/<c>/) if %extras<region-ids>.defined;
	@regions.append: resolveRegionNames(
		%extras<regions>.split(/<c>/),
		@systems
	) if %extras<regions>.defined;

	my @stations;
	@stations.append: %extras<station-ids>.split(/<c>/) if %extras<station-ids>.defined;
	@stations.append: %extras<station_ids>.split(/<c>/) if %extras<station_ids>.defined;

	{
		my $checkQl = sub {
			die "Invalid quantity specification for $^a."
				unless $^b ~~ /^ (<[ > < = ]>?) (\d+) $/;
			[ ($/[0] // '='), $/[1] ];
		}

		if %extras<quantity>.defined {
			my $ql = $checkQl('--quantity', %extras<quantity>);
			%filters.push: {
				quantity => -> $i { compareQuantity($i<quantity>, $ql) }
			};
		}

		if %extras<runs>.defined {
			my $ql = $checkQl('--runs', %extras<runs>);
			%filters.push: {
				runs => -> $i { compareQuantity($i<runs> , $ql); }
			};
		}

		if %extras<te>.defined {
			my $ql = $checkQl('--te', %extras<te>);
			die "Time efficiency must be an integer between 0 and 10.\n"
				unless $ql[1] <= 10;
			%filters.push: {
				time_efficiency => -> $i { compareQuantity($i<te> , $ql); }
			};
		}

		if %extras<time_efficiency>.defined {
			my $ql = $checkQl('--time_efficiency', %extras<time_efficiency>);
			die "Time efficiency must be an integer between 0 and 10.\n"
				unless $ql[1] <= 10;
			%filters.push: -> $i {
				time_efficiency => { compareQuantity($i<time_efficiency> , $ql); }
			};
		}

		if %extras<me>.defined {
			my $ql = $checkQl('--me', %extras<me>);
			die "Material efficiency must be an integer between 0 and 10.\n"
				unless $ql[1] <= 10;
			%filters.push: {
				material_efficiency => -> $i { compareQuantity($i<me> , $ql); }
			};
		}

		if %extras<material_efficiency>.defined {
			my $ql = $checkQl('--material_efficiency', %extras<material_efficiency>);
			die "Material efficiency must be an integer between 0 and 10.\n"
				unless $ql[1] <= 10;
			%filters.push: {
				material_efficiency => -> $i { 
          compareQuantity($i<material_efficiency> , $ql); 
        }
			};
		}
	}

	if %extras<is_singleton>.defined {
		die "Invalid value for --is_singleton.\n"
			unless %extras<is_singleton>.Str.lc eq <1 0 true false>.any;

		%filters.push: {
			is_singleton => {
				$_<is_singleton>.Bool == %extras<is_singleton>.Bool
			}
		}
	}

	if %extras<item_id>.defined {
		die "Invalid value for --item_id.\n"
			unless %extras<item_id> ~~ Int;

		%filters.push: {
			item_id => {
				$_<item_id> == %extras<item_id>.split(/<c>/).map( *.Int ).any
			}
		}
	}

	%filters.push: {
		type_id => -> $i { $i<type_id> == @type_ids.any }
	} if +@type_ids;

	%filters.push: {
		location_type => -> $i { $i<location_type> eq @location_types.any }
	} if +@location_types;

	%filters.push: {
		location_flag => -> $i { $_<location_flag> eq @location_flags.any }
	} if +@location_flags;

	if %extras<is-original>.defined || %extras<is-copy>.defined {
		die "Cannot specify --is-original or --is-copy at the same time."
			if %extras<is-original>.defined && %extras<is-copy>.defined;

		die "Invalid value for --is-original.\n"
			unless
				%extras<is-original>.defined &&
				%extras<is-original>.Str.lc eq <1 0 true false>;

		die "Invalid value for --is-copy.\n"
			unless
				%extras<is-copy>.defined &&
				%extras<is-copy>.Str.lc eq <1 0 true false>;

		%filters.push: {
			is-original => -> $i {
			  (%extras<is-original> // !%extras<is-copy>) ??
					($i<quantity> == -1)
					!!
					($i<quantity> == -2)
			}
		};
	}

	my @loc-search = (+@systems, +@regions, +@stations);
	die q:to/DIE/
Too many location based searches specified. Please choose a single type of
location search.
DIE
		unless @loc-search.one || @loc-search.none;

	# system
	my %location-filters = [];
	%location-filters.push: {
		system-ids => { checkLocation('systems', @systems, $_) }
	} if +@systems;

  # region => list of systems
	%location-filters.push: {
		region-ids => { checkLocation('regions', @regions, $_) }
	} if +@regions;

	# station
	%location-filters.push: {
		stations  => { checkLocation('stations', @stations, $_) }
	} if +@stations;

	#DEBUG#
	%filters.gist.say;
	%location-filters.gist.say;

  my %f = findItems(%filters, $search);
  say "----> F:  { %f.gist }";
  
	resolveLocation(%f, %location-filters);
	
}

use nqp;
sub USAGE {
	  # cw: Don't know why the extra spacings are needed. Editor?
		say nqp::getlexcaller(q|$*USAGE|) ~ qq:to/USAGE/;


REQUIRED
  --sqlite         Location of static data file. Program will attempt to
                   autodetect this file, but if it is not named one of:
                      ./Eve_Static.sqlite3
                      ./data/Eve_Static.sqlite3
                      ../data/Eve_Static.sqlite3
                   Then the file can be specified using this option.

SEARCH TYPES
  --corp           Search corporation assets
  --char           Search character assets [default]

	--bp
  --blueprints     Add blueprints into search results

  --bponly         ONLY search on blueprints

EXTRA OPTIONS

  ASSET FILTERS
    --is_singleton    Only one item in the stack (?)
    --item_id         Comma separated list of item_ids
    --location_flag   Filter by location flag. Please see the following page for
		                  the exhaustive list.
    --location_id     Numeric location ID
    --location_type   Filter by location type: 'solarsystem', 'station' or
                      'other'.
    --type_id         Comma separated list of numeric type_ids
    --quantity        Match the number of items in a stack. Quantity logic can be
                      specified by the following methods:
                        >[num] - At least #num items in stack
                        <[num] - No more than #num items in stack
                        =[num] - Exactly #num items in stack
                        [num]  - Same as above.
                      Where [num] is a numeric value.

    --name(s)
    --item-name
    --item_name       Comma separated list of item names, if any argument includes
                      spaces, surround the entire argument in quotes.

  BLUEPRINT FILTERS
    --is-copy         If blueprint is a copy
    --is-original     If blueprint is original
    --runs            Matches number of runs left on a blueprint. Uses quantity
                      logic matching. See --quantity.
		--te							Matches Time Efficiency. Also uses quantity logic,
                      See --quantity. (Can also be specified as
											--time_efficiency)
		--me              Matches Material Efficiency. Also uses quantity logic,
                      See --quantity. (Can also be specified as
											--material_efficiency)

  LOCATION-BASED SEARCH TYPES [Select only ONE type]:
    --systems         Comma separated list of system names. If any system name
                      has a space, the entire list must be quoted.
    --system_ids
    --system-ids      Comma separated list of system IDs

    -OR-

    --regions         Comma separated list of region names. If any region name
                      has a space, the entire list must be quoted.
    --region_ids
    --region-ids      Comma separated list of region ids

    -OR-

    --station-ids     Comma separated list of station ID
USAGE

}
