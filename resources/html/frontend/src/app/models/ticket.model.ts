export interface Ticket {
  ticket_id?: number;
  model_used?: string;
  requesting_entity?: string;
  queue?: string;
  status?: string;
  title: string;
  summary?: string;
  summary_long?: string;
  contextual_details?: string;
  contextual_technical_details?: string;
  keywords?: Array<string | { word: string }>;
  ticket_as_question?: string;
  category?: string;
  key_points_discussed?: Array<string | { point: string }>;
  data_patterns_or_trends?: string;
  customer_sentiment?: string;
  customer_sentiment_score?: number;
  created?: string;
  last_updated?: string;
}
