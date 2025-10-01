package AIFactory;
use strict;
use warnings FATAL => 'all';

use lib qw(./);
use AI::Gemini;
use AI::4o_mini;
use AI::NomicEmbeddingModel;

sub createGemini2FlashAI
{return AI::Gemini->new($main::conf->{gemini_ai_key}, $main::conf->{gemini_ai_url}, $main::conf->{gemini_ai_model}, $main::conf->{prompt_file});}

sub create4o_miniAI
{return AI::4o_mini->new($main::conf->{openai_key}, $main::conf->{openai_url}, $main::conf->{openai_model}, $main::conf->{prompt_file});}

sub createNomicEmbeddingModel
{return AI::NomicEmbeddingModel->new($main::conf->{nomic_ai_key}, $main::conf->{nomic_ai_url}, $main::conf->{nomic_ai_model}, $main::conf->{prompt_file});}

1;