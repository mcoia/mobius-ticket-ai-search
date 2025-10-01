package AI::NomicEmbeddingModel;
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
    my $model = shift || "nomic-embed-text:latest";

    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'POST',
        $self->{url} . "/api/embeddings",
        [ 'Content-Type' => 'application/json' ]
    );

    my $data = {
        'model'  => $model,
        'prompt' => $prompt
    };

    $request->content(encode_json($data));
    my $response = $ua->request($request);

    if ($response->is_success)
    {
        my $result = decode_json($response->content);
        # return $result; # Return the full embeddings result
        # return $response->content;
        return encode_json($result->{embedding});
    }
    else
    {
        die "API request failed: " . $response->status_line . "\n" . $response->content;
    }
}

sub rateLimit
{
    my $self = shift;
    return $self;
}

1;