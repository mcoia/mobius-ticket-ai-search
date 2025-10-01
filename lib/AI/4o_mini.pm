package AI::4o_mini;
use strict;
use warnings FATAL => 'all';

use lib qw(./);
use parent 'AI';

sub executeAPIRequest
{
    my $self = shift;
    my $prompt = shift;

    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'POST',
        $self->{url},
        [ 'Content-Type'    => 'application/json',
            'Authorization' => "Bearer " . $self->{key} ]
    );

    my $data = {
        'model'       => $self->{model},
        'messages'    => [
            {
                'role'    => 'user',
                'content' => $prompt
            }
        ],
        'temperature' => 0.7
    };

    $request->content(encode_json($data));
    my $response = $ua->request($request);

    if ($response->is_success)
    {
        my $result = decode_json($response->content);
        return $result->{choices}[0]{message}{content};
    }

    die "API request failed: " . $response->status_line;
}

sub rateLimit
{

    my $self = shift;
    my $lastRequestTime = shift; # Time of the last request in seconds (epoch time)

    # We're allowed 3 requests per minute
    my $requestsPerMinute = 3;
    my $minTimeBetweenRequests = 60 / $requestsPerMinute; # 20 seconds between requests

    my $currentTime = time();
    my $timeSinceLastRequest = $currentTime - $lastRequestTime;

    # If less than 20 seconds have passed since last request, sleep for the remaining time
    if ($timeSinceLastRequest < $minTimeBetweenRequests)
    {
        my $sleepTime = $minTimeBetweenRequests - $timeSinceLastRequest;
        sleep($sleepTime);
    }

    return time(); # Return current time after potential sleep
}

1;