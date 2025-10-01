package AI;
use strict;
use warnings FATAL => 'all';
use LWP::UserAgent;
use JSON;
use HTTP::Request;
use Cwd;

sub new
{
    my $class = shift;
    my $self = {
        'key'        => shift,
        'url'        => shift,
        'model'      => shift,
        'promptfile' => shift,
    };
    bless $self, $class;
    return $self;
}

# Abstract method 
# This method is responsible for making the API request to the AI service 
# and returning the response 
# my $prompt = shift; we need to pass the prompt to the 
sub executeAPIRequest
{die "subclass must implement abstract method executeAPIRequest";}

sub buildPrompt
{
    my $self = shift;
    my $json = shift;
    my $categories = shift;

    my $prompt = "";
    my $promptFilePath = getcwd() . "/" . $self->{promptfile};

    # open the xml prompt file
    open(my $fh, '<', $promptFilePath) or die "Could not open file '$promptFilePath' $!";
    while (my $row = <$fh>)
    {$prompt .= $row;}
    close($fh);

    # We have this line in the $prompt that we need to inject data into <ticket-data type="json"></ticket-data>
    # It should look something like this: <ticket-data type="json">{"ticket_id":196589,"history_id":3727001 ... }</ticket-data>
    $prompt =~ s/<ticket-data type="json"><\/ticket-data>/<ticket-data type="json">$json<\/ticket-data>/g;

    # the same goes for the <category></category> tag

    $prompt =~ s/<category><\/category>/<category>$categories<\/category>/g;

    return $prompt;
}

1;
