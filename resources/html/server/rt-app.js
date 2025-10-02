const express = require('express');
const cors = require('cors');
const path = require('path');
const axios = require('axios');
const fs = require('fs');

const app = express();
const port = 10000;

/*
   So the elastic search needs to connect to the cloud vm instance whereas the ollama server is local.

   We do have the ollama server on the cloud vm, but it's not open for external connections.
   We have to have a local ollama instance for embedding the tickets so we just use that one for development.

   Don't forget to set the apiUrl in the angular search.service.ts file.
   private apiUrl = ''; <== Production

*/

// ===== SECURITY CONFIGURATION =====
const ALLOWED_WIKI_DOMAIN = 'https://wiki.mobiusconsortium.org';

// Elasticsearch configuration
const esConfig = {
    // url: 'http://34.172.8.54:9200', // <== Development
    url: 'http://localhost:9200', // <== Production
    username: 'elastic',
    password: 'zm75yUEzjKVVTxczj0BU',
    indexes: {
        summary: 'ticket_summary',
        embeddings: 'ticket_embeddings'
    }
};

// Ollama configuration
const ollamaConfig = {
    // url: 'http://192.168.11.164:11434', // <== Development
    url: 'http://localhost:11434', // <== Production
    model: 'nomic-embed-text:latest'
};

// ===== SECURITY MIDDLEWARE - Must come before other middleware =====
// Set security headers to restrict iframe embedding to only your wiki
app.use((req, res, next) => {
    // CSP frame-ancestors is the modern standard for controlling iframe embedding
    res.setHeader('Content-Security-Policy', `frame-ancestors 'self' ${ALLOWED_WIKI_DOMAIN}`);

    // X-Frame-Options as fallback for older browsers
    res.setHeader('X-Frame-Options', `ALLOW-FROM ${ALLOWED_WIKI_DOMAIN}`);

    next();
});

// ===== EXISTING MIDDLEWARE =====
app.use(cors({
    origin: 'https://wiki.mobiusconsortium.org',
    credentials: true
}));
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

// Referer check ONLY for the root route (not static assets)
app.get('/', (req, res) => {
    const referer = req.get('Referer') || req.get('Referrer') || '';

    // Only allow if referer is from wiki
    if (referer && referer.startsWith(ALLOWED_WIKI_DOMAIN)) {
        return res.sendFile(path.join(__dirname, 'public', 'index.html'));
    }

    // Block direct access
    console.log(`⛔ Blocked direct access from: ${referer || 'no referer'}`);
    return res.status(403).send('Access denied: This application can only be accessed through the authorized wiki');
});

// Elasticsearch test endpoint
app.get('/api/test', async (req, res) => {
    try {
        const response = await axios.get(esConfig.url, {
            auth: {
                username: esConfig.username,
                password: esConfig.password
            }
        });

        res.json({
            status: 'success',
            message: 'Successfully connected to Elasticsearch',
            version: response.data.version,
            cluster_name: response.data.cluster_name
        });
    } catch (error) {
        res.status(500).json({
            status: 'error',
            message: 'Failed to connect to Elasticsearch',
            error: error.message
        });
    }
});

app.get('/health', async (req, res) => {
    try {
        // Check Elasticsearch connection
        await axios.get(esConfig.url, {
            auth: {
                username: esConfig.username,
                password: esConfig.password
            },
            timeout: 5000 // 5 second timeout
        });

        // Check Ollama connection
        await axios.get(`${ollamaConfig.url}/api/tags`, {timeout: 5000});

        res.json({status: 'healthy'});
    } catch (error) {
        res.status(500).json({
            status: 'unhealthy',
            error: error.message
        });
    }
});

// Get ticket by ID endpoint
app.get('/api/ticket/:id', async (req, res) => {
    try {
        const ticketId = req.params.id;

        if (!ticketId) {
            return res.status(400).json({
                status: 'error',
                message: 'Ticket ID is required'
            });
        }

        const query = {
            query: {
                term: {
                    ticket_id: ticketId
                }
            }
        };

        const response = await axios.post(
            `${esConfig.url}/${esConfig.indexes.summary}/_search`,
            query,
            {
                auth: {
                    username: esConfig.username,
                    password: esConfig.password
                },
                headers: {
                    'Content-Type': 'application/json'
                }
            }
        );

        if (response.data.hits.hits.length === 0) {
            return res.status(404).json({
                status: 'error',
                message: `Ticket with ID ${ticketId} not found`
            });
        }

        // Return the first matching ticket
        res.json(response.data.hits.hits[0]._source);

    } catch (error) {
        console.error(`Error fetching ticket #${req.params.id}:`, error);

        if (error.response) {
            console.error('Error response data:', JSON.stringify(error.response.data, null, 2));
        }

        res.status(500).json({
            status: 'error',
            message: 'Failed to fetch ticket details',
            error: error.message
        });
    }
});

// Helper function to build filter clauses based on filter parameters
function buildFilterClauses(filters) {
    const filterClauses = [];

    if (!filters) {
        return filterClauses;
    }

    // Queue filters
    if (filters.queue && filters.queue.length > 0) {
        filterClauses.push({
            terms: {
                queue: filters.queue
            }
        });
    }

    // Status filters
    if (filters.status && filters.status.length > 0) {
        filterClauses.push({
            terms: {
                status: filters.status
            }
        });
    }

    // Date range filters for created dates
    if (filters.created) {
        const createdRange = {};
        if (filters.created.from) {
            createdRange.gte = filters.created.from;
        }
        if (filters.created.to) {
            createdRange.lte = filters.created.to;
        }

        if (Object.keys(createdRange).length > 0) {
            filterClauses.push({
                range: {
                    created: createdRange
                }
            });
        }
    }

    // Date range filters for updated dates
    if (filters.updated) {
        const updatedRange = {};
        if (filters.updated.from) {
            updatedRange.gte = filters.updated.from;
        }
        if (filters.updated.to) {
            updatedRange.lte = filters.updated.to;
        }

        if (Object.keys(updatedRange).length > 0) {
            filterClauses.push({
                range: {
                    last_updated: updatedRange
                }
            });
        }
    }

    return filterClauses;
}

// Extract the text search functionality to a separate function for reuse
async function performTextSearch(searchTerm, hasTicketId, ticketIdValue, filters, res, SEARCH_CONFIG, FALLBACK_TEXT_SEARCH_FIELDS) {
    // Build filter clauses
    const filterClauses = buildFilterClauses(filters);

    let textOnlyQuery;

    if (hasTicketId) {
        // If it looks like a ticket ID, use a combined query
        textOnlyQuery = {
            query: {
                bool: {
                    should: [
                        // Exact match on ticket_id (no fuzzy)
                        {
                            term: {
                                ticket_id: {
                                    value: ticketIdValue,
                                    boost: SEARCH_CONFIG.ticketIdBoost
                                }
                            }
                        },
                        // Text search on other fields
                        {
                            multi_match: {
                                query: searchTerm,
                                fields: FALLBACK_TEXT_SEARCH_FIELDS,
                                fuzziness: "AUTO"
                            }
                        }
                    ],
                    // Add filter conditions if they exist
                    ...(filterClauses.length > 0 && {filter: filterClauses})
                }
            },
            size: SEARCH_CONFIG.maxFinalResults
        };
    } else {
        // Standard text search without ticket_id for non-numeric queries
        textOnlyQuery = {
            query: {
                bool: {
                    must: [
                        {
                            multi_match: {
                                query: searchTerm,
                                fields: FALLBACK_TEXT_SEARCH_FIELDS,
                                fuzziness: "AUTO"
                            }
                        }
                    ],
                    // Add filter conditions if they exist
                    ...(filterClauses.length > 0 && {filter: filterClauses})
                }
            },
            size: SEARCH_CONFIG.maxFinalResults
        };
    }

    try {
        const textOnlyResponse = await axios.post(
            `${esConfig.url}/${esConfig.indexes.summary}/_search`,
            textOnlyQuery,
            {
                auth: {
                    username: esConfig.username,
                    password: esConfig.password
                },
                headers: {
                    'Content-Type': 'application/json'
                }
            }
        );

        // Filter out results with low scores
        const significantResults = textOnlyResponse.data.hits.hits.filter(hit =>
            hit._score > SEARCH_CONFIG.minSignificantScore
        );

        // Log the number of results returned and the scores
        console.log(`Found ${textOnlyResponse.data.hits.hits.length} total matching documents (text search)`);
        console.log(`Returning ${significantResults.length} significant results after filtering`);

        if (textOnlyResponse.data.hits.hits.length > 0) {
            console.log(`Top score: ${textOnlyResponse.data.hits.hits[0]._score}`);
            console.log(`Bottom score before filtering: ${textOnlyResponse.data.hits.hits[textOnlyResponse.data.hits.hits.length - 1]._score}`);
            if (significantResults.length > 0) {
                console.log(`Bottom score after filtering [text]: ${significantResults[significantResults.length - 1]._score}`);
            }
        }

        return res.json({
            hits: significantResults.map(hit => hit._source)
        });
    } catch (error) {
        console.error('Text search error:', error.message);
        return res.status(500).json({
            status: 'error',
            message: 'Failed to perform text search',
            error: error.message
        });
    }
}

// Generate embeddings using Ollama's nomic-embed-text model
async function generateEmbedding(text) {
    try {
        const response = await axios.post(
            `${ollamaConfig.url}/api/embeddings`,
            {
                model: ollamaConfig.model,
                prompt: text
            }
        );
        return response.data.embedding;
    } catch (error) {
        console.error('Error generating embedding:', error.message);
        throw error;
    }
}

// Search endpoint with dedicated ticket ID search path
app.post('/api/search', async (req, res) => {
    try {

        // Search settings
        const SEARCH_CONFIG = {
            // Result limits
            maxEmbeddingResults: 300,        // Max results to fetch from embedding search
            maxCombinedResults: 500,         // Max results after combining and scoring
            maxFinalResults: 500,            // Max results to return

            // Scoring weights
            originalEmbeddingWeight: 0.3,   // Weight for original ticket embeddings
            summaryEmbeddingWeight: 0.7,    // Weight for summary embeddings
            semanticSearchWeight: 0.6,      // Weight for semantic search in rescoring
            textSearchWeight: 0.4,          // Weight for text search in rescoring

            // Thresholds
            minEmbeddingScore: 1.0,         // Minimum cosine similarity score (+1.0)
            minFinalScore: 1.0,             // Minimum final score for results
            minSignificantScore: 1.0,       // Minimum score for results to be included in final output

            // Boosting factors
            ticketIdBoost: 5.0,             // Boost for exact ticket ID matches
            titleBoost: 3.0,                // Boost for title matches
            summaryBoost: 2.0,              // Boost for summary matches
            summaryLongBoost: 2.0,          // Boost for long summary matches
            requestingEntityBoost: 5.0,     // Boost for requesting entity matches
            queueBoost: 5.0,                // Boost for queue matches
            statusBoost: 5.0,               // Boost for status matches
            keywordBoost: 2.0               // Boost for keyword matches
        };

        // Field configurations
        const TEXT_SEARCH_FIELDS = [
            `title^${SEARCH_CONFIG.titleBoost}`,
            `summary^${SEARCH_CONFIG.summaryBoost}`,
            `summary_long^${SEARCH_CONFIG.summaryLongBoost}`,
            "contextual_details",
            "contextual_technical_details",
            "category",
            `requesting_entity^${SEARCH_CONFIG.requestingEntityBoost}`,
            "data_patterns_or_trends",
            `queue^${SEARCH_CONFIG.queueBoost}`,
            "ticket_as_question",
            `status^${SEARCH_CONFIG.statusBoost}`
        ];

        const FALLBACK_TEXT_SEARCH_FIELDS = [
            `title^${SEARCH_CONFIG.titleBoost}`,
            "summary",
            "summary_long",
            "contextual_details",
            "contextual_technical_details",
            "keywords.word",
            "key_points_discussed.point",
            "category",
            "requesting_entity",
            "data_patterns_or_trends",
            "customer_sentiment"
        ];

        // ===== MAIN SEARCH LOGIC =====
        const {searchTerm, filters} = req.body;

        // Log the received filters for debugging
        if (filters) {
            console.log('Received filters:', JSON.stringify(filters, null, 2));
        }

        if (!searchTerm) {
            return res.json({hits: []});
        }

        // ===== WILDCARD SEARCH HANDLING =====
        // Check if the search term is just a wildcard (*) to return all results
        if (searchTerm.trim() === '*') {
            console.log('Wildcard search detected, returning all results');

            // Build filter clauses for Elasticsearch (reuse existing function)
            const filterClauses = buildFilterClauses(filters);

            // Create a match_all query that respects any filters
            const wildCardQuery = {
                query: {
                    bool: {
                        must: [
                            {match_all: {}}
                        ],
                        // Add filter conditions if they exist
                        ...(filterClauses.length > 0 && {filter: filterClauses})
                    }
                },
                // Exclude the embeddings to reduce response size
                _source: {
                    excludes: ["embedding"]
                },
                // Return all results (up to ES max, typically 10000)
                size: 10000
            };

            try {
                const wildCardResponse = await axios.post(
                    `${esConfig.url}/${esConfig.indexes.summary}/_search`,
                    wildCardQuery,
                    {
                        auth: {
                            username: esConfig.username,
                            password: esConfig.password
                        },
                        headers: {
                            'Content-Type': 'application/json'
                        }
                    }
                );

                console.log(`Found ${wildCardResponse.data.hits.hits.length} total documents for wildcard search`);

                return res.json({
                    hits: wildCardResponse.data.hits.hits.map(hit => hit._source)
                });
            } catch (wildCardError) {
                console.error('Wildcard search error:', wildCardError.message);
                return res.status(500).json({
                    status: 'error',
                    message: 'Failed to perform wildcard search',
                    error: wildCardError.message
                });
            }
        }

        // ===== NORMAL SEARCH LOGIC (UNCHANGED) =====
        // Check if the search term looks like a ticket ID
        const ticketIdMatch = searchTerm.trim().match(/^#?(\d+)$/);

        // If the search term is ONLY a ticket ID (nothing else), try direct ticket lookup first
        if (ticketIdMatch !== null) {
            const ticketIdValue = parseInt(ticketIdMatch[1]);
            console.log(`Search term appears to be a ticket ID: ${ticketIdValue}, attempting direct lookup`);

            try {
                // Direct ticket ID lookup query
                const directTicketQuery = {
                    query: {
                        term: {
                            ticket_id: ticketIdValue
                        }
                    }
                };

                const directTicketResponse = await axios.post(
                    `${esConfig.url}/${esConfig.indexes.summary}/_search`,
                    directTicketQuery,
                    {
                        auth: {
                            username: esConfig.username,
                            password: esConfig.password
                        },
                        headers: {
                            'Content-Type': 'application/json'
                        }
                    }
                );

                // If we found an exact ticket ID match, return it immediately
                if (directTicketResponse.data.hits.hits.length > 0) {
                    console.log(`Found exact match for ticket ID ${ticketIdValue}`);
                    return res.json({
                        hits: directTicketResponse.data.hits.hits.map(hit => hit._source)
                    });
                }

                console.log(`No exact match found for ticket ID ${ticketIdValue}, continuing with regular search`);
            } catch (directLookupError) {
                console.error('Error during direct ticket lookup:', directLookupError.message);
                // Continue with regular search if direct lookup fails
            }
        }

        // If we get here, either:
        // 1. The search wasn't a ticket ID
        // 2. Or it was a ticket ID but no exact match was found
        // So we proceed with the regular semantic + text search

        // Generate embedding for the search term
        const embedding = await generateEmbedding(searchTerm);
        console.log('Embedding generated successfully, length:', embedding.length);

        // Log the search term for debugging
        saveSearchLog(searchTerm);
        console.log(`Search term: [${searchTerm}]`);

        // Check if the search term contains a ticket ID pattern (for rescoring)
        const partialTicketIdMatch = searchTerm.trim().match(/#?(\d+)/);
        const hasTicketId = partialTicketIdMatch !== null;
        const ticketIdValue = hasTicketId ? parseInt(partialTicketIdMatch[1]) : null;

        try {
            // 1. Search in the dedicated embeddings index (original tickets)
            const originalEmbeddingQuery = {
                query: {
                    script_score: {
                        query: {
                            exists: {
                                field: "embedding"
                            }
                        },
                        script: {
                            source: "cosineSimilarity(params.query_vector, doc['embedding']) + 1.0",
                            params: {query_vector: embedding}
                        }
                    }
                },
                min_score: SEARCH_CONFIG.minEmbeddingScore,
                size: SEARCH_CONFIG.maxEmbeddingResults,
                _source: ["ticket_id"]
            };

            // 2. Search in the summary index using summary embeddings
            const summaryEmbeddingQuery = {
                query: {
                    script_score: {
                        query: {
                            exists: {
                                field: "embedding"
                            }
                        },
                        script: {
                            source: "cosineSimilarity(params.query_vector, doc['embedding']) + 1.0",
                            params: {query_vector: embedding}
                        }
                    }
                },
                min_score: SEARCH_CONFIG.minEmbeddingScore,
                size: SEARCH_CONFIG.maxEmbeddingResults,
                _source: ["ticket_id"] // Only return the ticket_id field
            };

            // Execute both queries in parallel
            const [originalEmbeddingResponse, summaryEmbeddingResponse] = await Promise.all([
                axios.post(
                    `${esConfig.url}/${esConfig.indexes.embeddings}/_search`,
                    originalEmbeddingQuery,
                    {
                        auth: {
                            username: esConfig.username,
                            password: esConfig.password
                        },
                        headers: {
                            'Content-Type': 'application/json'
                        }
                    }
                ),
                axios.post(
                    `${esConfig.url}/${esConfig.indexes.summary}/_search`,
                    summaryEmbeddingQuery,
                    {
                        auth: {
                            username: esConfig.username,
                            password: esConfig.password
                        },
                        headers: {
                            'Content-Type': 'application/json'
                        }
                    }
                )
            ]);

            // Extract ticket IDs and scores from both responses
            const originalResults = originalEmbeddingResponse.data.hits.hits.map(hit => ({
                ticket_id: hit._source.ticket_id,
                score: hit._score,
                source: 'original'
            }));

            const summaryResults = summaryEmbeddingResponse.data.hits.hits.map(hit => ({
                ticket_id: hit._source.ticket_id,
                score: hit._score,
                source: 'summary'
            }));

            console.log(`Found ${originalResults.length} tickets via original embeddings`);
            console.log(`Found ${summaryResults.length} tickets via summary embeddings`);

            // Combine and merge results
            const combinedResults = [...originalResults, ...summaryResults];

            // Group by ticket_id and combine scores
            const ticketScores = {};
            combinedResults.forEach(result => {
                const id = result.ticket_id;
                if (!ticketScores[id]) {
                    ticketScores[id] = {
                        ticket_id: id,
                        originalScore: 0,
                        summaryScore: 0
                    };
                }

                if (result.source === 'original') {
                    ticketScores[id].originalScore = result.score;
                } else {
                    ticketScores[id].summaryScore = result.score;
                }
            });

            // Calculate combined score with weighting
            const scoredTickets = Object.values(ticketScores).map(ticket => {
                // Normalize scores (they're already shifted by +1.0 from cosineSimilarity)
                const originalNorm = ticket.originalScore > 0 ? ticket.originalScore : 1.0;
                const summaryNorm = ticket.summaryScore > 0 ? ticket.summaryScore : 1.0;

                // Apply weights
                const combinedScore =
                    (originalNorm * SEARCH_CONFIG.originalEmbeddingWeight) +
                    (summaryNorm * SEARCH_CONFIG.summaryEmbeddingWeight);

                return {
                    ticket_id: ticket.ticket_id,
                    score: combinedScore
                };
            });

            // Sort by combined score and take top results
            const topTickets = scoredTickets
                .sort((a, b) => b.score - a.score)
                .slice(0, SEARCH_CONFIG.maxCombinedResults);

            const relevantTicketIds = topTickets.map(t => t.ticket_id);
            console.log(`Combined top ${relevantTicketIds.length} ticket IDs after scoring`);

            // If no relevant ticket_ids found, fall back to text search only
            if (relevantTicketIds.length === 0) {
                console.log('No relevant tickets found via embeddings, falling back to text search');
                return performTextSearch(searchTerm, hasTicketId, ticketIdValue, filters, res, SEARCH_CONFIG, FALLBACK_TEXT_SEARCH_FIELDS);
            }

            // Build filter conditions for Elasticsearch
            const filterClauses = buildFilterClauses(filters);

            // Get summaries using ticket_ids and rescore with keyword search
            const summaryQuery = {
                query: {
                    bool: {
                        must: [
                            {
                                terms: {
                                    ticket_id: relevantTicketIds
                                }
                            }
                        ],
                        // Add filter conditions if they exist
                        ...(filterClauses.length > 0 && {filter: filterClauses})
                    }
                },
                // Use rescore to adjust ranking based on text matches
                rescore: {
                    window_size: SEARCH_CONFIG.maxFinalResults, // Rescore all our results
                    query: {
                        rescore_query: {
                            bool: {
                                should: [
                                    // Check for ticket_id match if searchTerm is numeric
                                    ...(hasTicketId ? [{
                                        term: {
                                            ticket_id: {
                                                value: ticketIdValue,
                                                boost: SEARCH_CONFIG.ticketIdBoost
                                            }
                                        }
                                    }] : []),
                                    // Regular fields with multi_match
                                    {
                                        multi_match: {
                                            query: searchTerm,
                                            fields: TEXT_SEARCH_FIELDS,
                                            fuzziness: "AUTO"
                                        }
                                    },
                                    // Nested query for keywords
                                    {
                                        nested: {
                                            path: "keywords",
                                            query: {
                                                match: {
                                                    "keywords.word": {
                                                        query: searchTerm,
                                                        boost: SEARCH_CONFIG.keywordBoost
                                                    }
                                                }
                                            },
                                            score_mode: "avg"
                                        }
                                    },
                                    // Nested query for key_points_discussed
                                    {
                                        nested: {
                                            path: "key_points_discussed",
                                            query: {
                                                match: {
                                                    "key_points_discussed.point": searchTerm
                                                }
                                            },
                                            score_mode: "avg"
                                        }
                                    }
                                ]
                            }
                        },
                        query_weight: SEARCH_CONFIG.semanticSearchWeight,
                        rescore_query_weight: SEARCH_CONFIG.textSearchWeight
                    }
                },
                // we are getting the embeddings in the response bloating the size
                _source: {
                    excludes: ["embedding"]
                },
                min_score: SEARCH_CONFIG.minFinalScore,
                size: SEARCH_CONFIG.maxFinalResults
            };
            const summarySearchResponse = await axios.post(
                `${esConfig.url}/${esConfig.indexes.summary}/_search`,
                summaryQuery,
                {
                    auth: {
                        username: esConfig.username,
                        password: esConfig.password
                    },
                    headers: {
                        'Content-Type': 'application/json'
                    }
                }
            );

            // Filter out results with low scores
            const significantResults = summarySearchResponse.data.hits.hits.filter(hit =>
                hit._score > SEARCH_CONFIG.minSignificantScore
            );

            // Log the number of results returned and the scores
            console.log(`Found ${summarySearchResponse.data.hits.hits.length} total matching documents`);
            console.log(`Returning ${significantResults.length} significant results after filtering`);

            if (summarySearchResponse.data.hits.hits.length > 0) {
                console.log(`Top score: ${summarySearchResponse.data.hits.hits[0]._score}`);
                console.log(`Bottom score before filtering: ${summarySearchResponse.data.hits.hits[summarySearchResponse.data.hits.hits.length - 1]._score}`);
                if (significantResults.length > 0) {
                    console.log(`Bottom score after filtering: ${significantResults[significantResults.length - 1]._score}`);
                }
            }

            res.json({
                hits: significantResults.map(hit => hit._source)
            });
        } catch (searchError) {
            console.error('Embedding search error:', searchError.message);

            // Log the full error response if available
            if (searchError.response) {
                console.error('Error response data:', JSON.stringify(searchError.response.data, null, 2));
            }

            // Fall back to text search if embedding search fails
            console.log('Falling back to text-only search');
            return performTextSearch(searchTerm, hasTicketId, ticketIdValue, filters, res, SEARCH_CONFIG, FALLBACK_TEXT_SEARCH_FIELDS);
        }
    } catch (error) {
        console.error('Search error:', error.message);
        // Log more details about the error
        if (error.response) {
            console.error('Error response data:', JSON.stringify(error.response.data, null, 2));
        }
        res.status(500).json({
            status: 'error',
            message: 'Failed to search Elasticsearch',
            error: error.message
        });
    }
});

function saveSearchLog(searchTerm) {
    const date = new Date().toISOString().split('T')[0]; // Get the current date in YYYY-MM-DD format
    const time = new Date().toISOString().split('T')[1].split('.')[0]; // Get the current time in HH:MM:SS format
    const logMessage = `[${searchTerm}] ${time}\n`;
    const logFilePath = `searches-${date}.log`; // Create a log file for the current date

    fs.access(logFilePath, fs.constants.F_OK, (err) => {
        if (err) {
            // File does not exist, create it
            fs.writeFile(logFilePath, logMessage, (writeErr) => {
                if (writeErr) {
                    console.error('Failed to create log file:', writeErr.message);
                }
            });
        } else {
            // File exists, append to it
            fs.appendFile(logFilePath, logMessage, (appendErr) => {
                if (appendErr) {
                    console.error('Failed to write to log file:', appendErr.message);
                }
            });
        }
    });
}

app.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});