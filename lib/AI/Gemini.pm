package AI::Gemini;
use strict;
use warnings FATAL => 'all';
use LWP::UserAgent;
use JSON;
use lib qw(./);
use parent 'AI';

sub executeAPIRequest
{
    my $self = shift;
    my $prompt = shift;

    # print "url: " . $self->{url} . "\n";
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'POST',
        $self->{url} . "?key=" . $self->{key},
        [ 'Content-Type' => 'application/json' ]
    );

    my $data = {
        'contents' => [
            {
                'parts' => [
                    {
                        'text' => $prompt
                    }
                ]
            }
        ]
    };

    $request->content(encode_json($data));
    
    # I should put this in the conf
    my $max_retries = 3;
    my $retry_delay = 5; # seconds
    my $retries = 0;
    my $response;
    
    while ($retries <= $max_retries) {
        $response = $ua->request($request);
        
        if ($response->is_success) {
            my $result = decode_json($response->content);
            return $result->{candidates}[0]{content}{parts}[0]{text};
        }
        else {
            $retries++;
            if ($retries > $max_retries) {
                die "API request failed after $max_retries retries: " . $response->status_line;
            }
            
            print "API request failed (attempt $retries/$max_retries): " . 
                  $response->status_line . ". Retrying in $retry_delay seconds...\n";
            sleep($retry_delay);
        }
    }
}

1;