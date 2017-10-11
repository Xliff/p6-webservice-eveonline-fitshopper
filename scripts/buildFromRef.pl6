#!/usr/bin/env perl6

use v6.c;

use Mojo::DOM:from<Perl5>;
use Data::Dump;

my %Endpoints;
my $ref_html;

die "Could not open file 'ESI.html'"
  unless  "ESI.html".IO.e && $ref_html = "ESI.html".IO.open.slurp-rest;

my $doc = Mojo::DOM.new($ref_html);

for @( $doc.find('span.path a').to_array ) -> $a {
  my $p = $a.parent.parent.parent.parent;

  $a.text ~~ / '/' (\w+?) '/' /;
  my $group = $0;
  $group.chop if $group.substr(*-1) eq 's';

  my %h = (
    prefix   => $a.text,
    'method' => $a.parent.previous.find('a').last.text,
  );

  my @scopes;
  for @( $p.find('div.authorize__btn ul li').to_array ) -> $s {
    @scopes.push: $s.text;
  }
  %h<scopes> = @scopes if @scopes;

  # Endpoint Parameters
  my %params;

  # Retrieving proper data types from Inline::Perl5 is problematic, particularly
  # when dealing with MOJO::Collections.
  for @( $p.find('tbody.operation-params tr').to_array ) -> $r {
    my @c = @( $r.children.to_array );
    my $n = @c[0].find('label').last;
    my $t = @c[3];
    my $dt = @c[4] // '';

    # cw: ATM cannot use 'next' due to Inline::Perl5.
    if $n {
      $n = $n.text;
      $t = $t ?? $t.text !! '';

      if $dt {
        my ($de, @prop-e, @props, @pd);
        my $propCount = 0;
        $dt = $dt.find('span.model-signature').last;
        $de = $dt.find('div.signature-container').last;
        if $de {
          @prop-e = @( $de.find('span.propName, span.propType').to_array );

          for @prop-e -> $p {
            given $p.attr('class') {
              when /propName/ {
                @props[$propCount][0] = $p.text;
                @props[$propCount][2] = 1 if $p.attr('class') ~~ /required/;
              }
              when 'propType' {
                # Let's hope this is properly ordered.
                @props[$propCount++][1] = $p.text ;
              }
            }
          }

        }

        $dt = @props ?? @props !! $dt.text;
      }

      unless $n.lc.trim eq <token x-user-agent user_agent page>.any {
        %params{$t.lc}.push: [ $n, $dt ];
      }
    }
  }

  %h<params> = %params;
  %Endpoints{$group}.push: %h;
}

#say Dump %Endpoints;
#dd %Endpoints.keys;
#exit;

# cw: Autogenerate code for required endpoints.
for <characters corporations> -> $end {
  for @( %Endpoints{$end} ) -> $ep {

      # Determine method from Endpoint prefix
      my ($methodName,$singular);
      my @parts;
      for $ep<prefix>.split('/').grep({ $_ }).map( *.tc ).kv -> $k, $v {
        if $v ~~ / '{' / {
          @parts[*-1] = do given @parts[*-1] {
            when @parts[*-1].substr(*-1) eq 's' {
              @parts[*-1].chop;
            }

            # cw: The above doesn't seem to catch this case for some reason.
            when 'Events' {
              'Event';
            }

            default {
              @parts[*-1];
            }
          }

        } else {
          @parts.push($v);
          # cw: Special casing.
          @parts.push('Events') if $v eq 'Calendar';
        }

      }
      @parts.shift if @parts.elems > 1;
      @parts.unshift: $ep{'method'};
      $methodName = @parts.join;

      $methodName.say;

      # Extract path parameters and replace them for method signature
      # Extract query parameters as named arguments
      # Extract body parameters, IF ANY as named hash argument.
      #   - If body parameters are given, insert gode to sanity check entries.
      #   - Build a hash containing body parameters. Create new hash, NEVER
      #     direcly pass the parameter.
      # Check method for final disposition
      #   - If a GET request, then return self.makeRequest(...)
      #   - If a PUT then return whether request succeeded after self.put
      #   - If a DELETE then return whether request succeeded after self.delete
      #   - If a POST then return whether request succeeded after self.post
  }

  # Write method output.
}
