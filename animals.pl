#!perl
use v5.20;
use experimental qw(signatures);

use Mojo::JSON qw(encode_json);
use Mojo::Promise;
use Mojo::UserAgent;
use Mojo::Util qw(dumper);

my @grand;
END {
	# Since the results come out of order,
	# sort by animal name then title
	@grand = sort {
		$a->{animal} cmp $b->{animal}
			or
		$a->{title} cmp $b->{title}
		} @grand;

	my $json = encode_json( \@grand );
	say $json;
	}

my $url = 'https://www.oreilly.com/animals.csp';
my( $start, $interval, $total );

my $ua = Mojo::UserAgent->new;

# We need to get the first request to get the total number of
# requests. Note that that number is actually larger than the
# number of results there will be, by about 80.
my $first_page_tx = $ua->get_p( $url )->then(
	sub ( $tx ) {
		push @grand, parse_page( $tx )->@*;
		( $start, $interval, $total ) = get_pagination( $tx );
		},
	sub ( $tx ) { die "Initial fetch failed!" }
	)->wait;

my @requests =
	map {
		my $page = $_;
		$ua->get_p( $url => form => { 'x-o' => $page } )->then(
			sub ( $tx ) { push @grand, parse_page( $tx )->@* },
			sub ( $tx ) { warn "Something is wrong" }
			);
		}
	map {
		$_ * $interval
		}
	1 .. ($total / $interval)
	;

Mojo::Promise->all( @requests )->wait;

sub get_pagination ( $tx ) {
	# 1141 to 1160 of 1244
	my $pagination = $tx
		->result
		->dom
		->at( 'span.cs-prevnext' )
		->text;

	my( $start, $interval, $total ) = $pagination =~ /
		(\d+) \h+ to \h+ (\d+) \h+ of \h+ (\d+) /x;
	}

sub parse_page ( $tx ) {
=pod

<div class="animal-row">
    <a class="book" href="https://shop.oreilly.com/product/9780596007379.do" title="">
      <img class="book-cvr" src="https://covers.oreilly.com/images/9780596007379/cat.gif" />
      <p class="book-title">Perl 6 and Parrot Essentials</p>
    </a>
    <p class="animal-name">Aoudad, aka Barbary sheep</p>
  </div>

=cut

	my $results = eval {
		$tx
			->result
			->dom
			->find( 'div.animal-row' )
			->map( sub {
				my %h;
				$h{link}      = $_->at( 'a.book' )->attr( 'href' );
				$h{cover_src} = $_->at( 'img.book-cvr' )->attr( 'src' );
				$h{title}     = $_->at( 'p.book-title' )->text;
				$h{animal}    = $_->at( 'p.animal-name' )->text;
				\%h;
				} )
			->to_array
		} or do {
			warn "Could not process a request!\n";
			[];
			};
	}
