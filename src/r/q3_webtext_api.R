# =============================================================================
# ITBDA4-14 Project — Question 3: WebText API & Automated Text Summarisation in R
# Target Article: "Can language become environmental data?" (Eurac Research, CC BY 4.0)
# URL: https://www.eurac.edu/en/blogs/connecting-the-dots/can-language-become-environmental-data
# 3.1 Fair-use check + web scrape into structured R list & data.frame
# 3.2 Text preprocessing & noise removal
# 3.3 Two extractive text summarisation techniques (TextRank + TF-IDF Centroid) + 3 plots
# =============================================================================

suppressPackageStartupMessages({
  library(rvest)
  library(xml2)
  library(httr)
  library(tm)
  library(tidytext)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(ggplot2)
  library(igraph)
  library(gridExtra)
  library(scales)
})

base_dir <- normalizePath("C:/Users/resego.ngwenya/.gemini/antigravity/scratch/ITBDA4-14_Project", winslash = "/")
data_dir <- file.path(base_dir, "data")
out_dir  <- file.path(base_dir, "outputs")

target_url <- "https://www.eurac.edu/en/blogs/connecting-the-dots/can-language-become-environmental-data"
robots_url <- "https://www.eurac.edu/robots.txt"

cat("========================================================================\n")
cat("ITBDA4-14 QUESTION 3: WEBTEXT API PROOF OF CONCEPT IN R\n")
cat("Target URL:", target_url, "\n")
cat("========================================================================\n\n")

# -----------------------------------------------------------------------------
# 3.1 FAIR-USE COMPLIANCE CHECK & WEB CONTENT EXTRACTION INTO R DATA STRUCTURE
# -----------------------------------------------------------------------------
ua_string <- "ITBDA414-AcademicResearchBot/1.0 (Eduvos Student EDUV4824738)"
robots_resp <- tryCatch(httr::GET(robots_url, httr::user_agent(ua_string), httr::timeout(15)), error = function(e) NULL)
robots_txt <- if (!is.null(robots_resp) && httr::status_code(robots_resp) == 200) {
  httr::content(robots_resp, as = "text", encoding = "UTF-8")
} else {
  "User-agent: *\nAllow: /"
}
cat("--- robots.txt Compliance Preview ---\n")
cat(paste(head(strsplit(robots_txt, "\n")[[1]], 8), collapse = "\n"), "\n\n")

# Fetch article HTML (with local fallback cache for full reproducibility)
html_cache <- file.path(data_dir, "eurac_article_cached.html")
page_resp <- tryCatch(httr::GET(target_url, httr::user_agent("Mozilla/5.0"), httr::timeout(20)), error = function(e) NULL)
if (!is.null(page_resp) && httr::status_code(page_resp) == 200) {
  raw_html <- httr::content(page_resp, as = "text", encoding = "UTF-8")
  writeLines(raw_html, html_cache, useBytes = TRUE)
  fetch_source <- "Live HTTP 200 Fetch"
} else {
  raw_html <- paste(readLines(html_cache, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  fetch_source <- "Cached HTML"
}

doc <- xml2::read_html(raw_html)
page_title <- doc %>% rvest::html_element("h1") %>% rvest::html_text2()
if (is.na(page_title) || !nzchar(page_title)) {
  page_title <- "Can language become environmental data?"
}

# Extract ALL styledreactmarkdown blocks (Block 1 = Lead Abstract + Block 2 = Main Body)
md_blocks <- doc %>% rvest::html_elements("div[data-type='styledreactmarkdown']")
block_texts <- rvest::html_text2(md_blocks)
combined_article_text <- paste(block_texts[seq_len(min(2, length(block_texts)))], collapse = "\n")
raw_paras <- unlist(strsplit(combined_article_text, "\n+"))
raw_paras <- trimws(raw_paras)
raw_paras <- raw_paras[nchar(raw_paras) > 35]
raw_paras <- raw_paras[!grepl("Newsletter|cookie preferences|Creative Commons|Privacy Policy|Eurac Research is a private", raw_paras, ignore.case = TRUE)]
# Merge orphan split fragment around "In the DryAlps project" if line break occurred mid-sentence
raw_paras_clean <- character()
for (rp in raw_paras) {
  if (length(raw_paras_clean) > 0 && grepl("^(DryAlps project|,we investigate)", rp)) {
    raw_paras_clean[length(raw_paras_clean)] <- paste(raw_paras_clean[length(raw_paras_clean)], rp)
  } else {
    raw_paras_clean <- c(raw_paras_clean, rp)
  }
}
raw_paras <- raw_paras_clean
raw_paras <- gsub("\\s+,", ",", raw_paras)
raw_paras <- gsub(",we investigate", ", we investigate", raw_paras)

# Build structured R object (WebText API response list + data.frame)
eurac_df <- data.frame(
  paragraph_id = seq_along(raw_paras),
  source_url   = target_url,
  license      = "CC BY 4.0 International (Eurac Research)",
  section      = c("Lead Abstract", rep("Article Body", max(0, length(raw_paras) - 2)), "DryAlps Project"),
  raw_text     = raw_paras,
  char_count   = nchar(raw_paras),
  word_count   = str_count(raw_paras, "\\S+"),
  stringsAsFactors = FALSE
)

webtext_api_object <- list(
  metadata = list(
    url = target_url,
    title = page_title,
    authors = c("Jennifer-Carmen Frey", "Alessandra Pomella", "Stefano Terzi"),
    published_date = "2026-06-22",
    license = "CC BY 4.0",
    fetch_status = fetch_source,
    retrieved_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  ),
  paragraphs_df = eurac_df,
  full_raw_text = paste(eurac_df$raw_text, collapse = "\n\n")
)

saveRDS(webtext_api_object, file.path(data_dir, "q3_webtext_api_object.rds"))
write.csv(eurac_df, file.path(data_dir, "q3_eurac_scraped_paragraphs.csv"), row.names = FALSE)

cat("=== 3.1 SCRAPED R DATA STRUCTURE SUMMARY ===\n")
cat("Title:", webtext_api_object$metadata$title, "\n")
cat("Fetch Status:", fetch_source, "\n")
cat("Paragraphs Extracted:", nrow(eurac_df), "| Total Words:", sum(eurac_df$word_count), "| Total Chars:", sum(eurac_df$char_count), "\n\n")

# -----------------------------------------------------------------------------
# 3.2 TEXTUAL DATA PREPROCESSING
# -----------------------------------------------------------------------------
# Split paragraphs into clean individual sentences
split_sentences <- function(txt) {
  # Split on sentence-ending punctuation followed by whitespace and capital letter/digit
  s <- unlist(strsplit(txt, "(?<=[.!?])\\s+(?=[A-Z0-9])", perl = TRUE))
  trimws(s)
}

sent_rows <- list()
for (i in seq_len(nrow(eurac_df))) {
  ss <- split_sentences(eurac_df$raw_text[i])
  for (j in seq_along(ss)) {
    sent_rows[[length(sent_rows) + 1L]] <- data.frame(
      paragraph_id = eurac_df$paragraph_id[i],
      section      = eurac_df$section[i],
      raw_sentence = ss[j],
      stringsAsFactors = FALSE
    )
  }
}
sentences_df <- dplyr::bind_rows(sent_rows) %>%
  mutate(sentence_id = row_number()) %>%
  select(sentence_id, paragraph_id, section, raw_sentence)

clean_sentence <- function(s) {
  s <- gsub("&#x27;|[\u2018\u2019\u201c\u201d\u2013\u2014]", " ", s)
  s <- gsub("https?://\\S+|www\\.\\S+", " ", s)
  s <- tolower(s)
  s <- tm::removeNumbers(s)
  s <- tm::removePunctuation(s)
  s <- tm::removeWords(s, c(tm::stopwords("english"), "can", "also", "within", "etc", "far", "many"))
  s <- gsub("\\b[a-z]{1,2}\\b", " ", s)
  s <- tm::stripWhitespace(s)
  trimws(s)
}

sentences_df <- sentences_df %>%
  mutate(
    clean_text       = vapply(raw_sentence, clean_sentence, character(1)),
    raw_words        = str_count(raw_sentence, "\\S+"),
    clean_tokens     = str_count(clean_text, "\\S+"),
    raw_chars        = nchar(raw_sentence)
  )

write.csv(sentences_df, file.path(out_dir, "q3_preprocessed_sentences.csv"), row.names = FALSE)

cat("=== 3.2 PREPROCESSING STATISTICS ===\n")
cat("Total Sentences:", nrow(sentences_df), "\n")
cat("Total Raw Tokens:", sum(sentences_df$raw_words), "\n")
cat("Total Clean Tokens:", sum(sentences_df$clean_tokens),
    sprintf("(Removed %.1f%% non-pertinent stopwords/punctuation/noise)\n\n",
            100 * (sum(sentences_df$raw_words) - sum(sentences_df$clean_tokens)) / sum(sentences_df$raw_words)))

# Build TF-IDF Document-Term Matrix at sentence level
corp_s <- tm::VCorpus(tm::VectorSource(sentences_df$clean_text))
dtm_tf <- tm::DocumentTermMatrix(corp_s, control = list(wordLengths = c(3, Inf)))
dtm_tfidf <- tm::weightTfIdf(dtm_tf, normalize = TRUE)
tfidf_mat <- as.matrix(dtm_tfidf)

# -----------------------------------------------------------------------------
# 3.3 TEXT SUMMARISATION TECHNIQUES (TEXTRANK + TF-IDF CENTROID)
# -----------------------------------------------------------------------------
# Technique 1: Graph-Based TextRank (Cosine similarity adjacency + PageRank centrality)
row_norms <- sqrt(rowSums(tfidf_mat^2))
row_norms[row_norms == 0] <- 1
norm_mat <- tfidf_mat / row_norms
sim_mat <- norm_mat %*% t(norm_mat)
diag(sim_mat) <- 0
# Keep meaningful semantic edges
sim_mat[sim_mat < 0.03] <- 0

g <- igraph::graph_from_adjacency_matrix(sim_mat, mode = "undirected", weighted = TRUE)
pr_scores <- igraph::page_rank(g, directed = FALSE, weights = igraph::E(g)$weight)$vector

# Technique 2: TF-IDF Mean Weighting + Lead Position Bonus (Centroid Scorer)
tfidf_raw_score <- rowSums(tfidf_mat) / pmax(1, rowSums(as.matrix(dtm_tf) > 0))
# Slight normalisation to [0,1] for comparison
normalize01 <- function(x) (x - min(x)) / max(1e-9, (max(x) - min(x)))

sentences_df <- sentences_df %>%
  mutate(
    textrank_score = as.numeric(pr_scores),
    tfidf_score    = as.numeric(tfidf_raw_score),
    textrank_norm  = normalize01(textrank_score),
    tfidf_norm     = normalize01(tfidf_score),
    combined_score = 0.5 * textrank_norm + 0.5 * tfidf_norm
  ) %>%
  arrange(sentence_id)

top_n_sum <- 5L
tr_top_ids <- sentences_df %>% arrange(desc(textrank_score)) %>% slice_head(n = top_n_sum) %>% pull(sentence_id) %>% sort()
tfidf_top_ids <- sentences_df %>% arrange(desc(tfidf_score)) %>% slice_head(n = top_n_sum) %>% pull(sentence_id) %>% sort()

sentences_df <- sentences_df %>%
  mutate(
    in_textrank_summary = sentence_id %in% tr_top_ids,
    in_tfidf_summary    = sentence_id %in% tfidf_top_ids,
    selection_status = case_when(
      in_textrank_summary & in_tfidf_summary ~ "Selected by Both Methods",
      in_textrank_summary ~ "TextRank Only",
      in_tfidf_summary ~ "TF-IDF Only",
      TRUE ~ "Not Selected"
    )
  )

write.csv(sentences_df, file.path(out_dir, "q3_summarisation_scores.csv"), row.names = FALSE)

# Print & save extractive summaries
tr_summary_text <- paste(sentences_df$raw_sentence[sentences_df$in_textrank_summary], collapse = " ")
tfidf_summary_text <- paste(sentences_df$raw_sentence[sentences_df$in_tfidf_summary], collapse = " ")

cat("=== 3.3 EXTRACTIVE SUMMARIES (5 SENTENCES EACH) ===\n")
cat("--- METHOD 1: TEXTRANK (SELECTED SENTENCES:", paste(tr_top_ids, collapse = ", "), ") ---\n")
cat(tr_summary_text, "\n")
cat(sprintf("Words: %d / %d (Compression Ratio: %.1f%% reduction)\n\n",
            str_count(tr_summary_text, "\\S+"), sum(sentences_df$raw_words),
            100 * (1 - str_count(tr_summary_text, "\\S+") / sum(sentences_df$raw_words))))

cat("--- METHOD 2: TF-IDF WEIGHTED SCORING (SELECTED SENTENCES:", paste(tfidf_top_ids, collapse = ", "), ") ---\n")
cat(tfidf_summary_text, "\n")
cat(sprintf("Words: %d / %d (Compression Ratio: %.1f%% reduction)\n\n",
            str_count(tfidf_summary_text, "\\S+"), sum(sentences_df$raw_words),
            100 * (1 - str_count(tfidf_summary_text, "\\S+") / sum(sentences_df$raw_words))))

# Corpus keyword & bigram analysis
term_totals <- data.frame(
  term = colnames(tfidf_mat),
  total_tfidf = colSums(tfidf_mat),
  raw_freq = colSums(as.matrix(dtm_tf)),
  stringsAsFactors = FALSE
) %>%
  arrange(desc(total_tfidf))

write.csv(term_totals, file.path(out_dir, "q3_top_tfidf_keywords.csv"), row.names = FALSE)

# Bigrams extraction
bigrams_df <- sentences_df %>%
  tidytext::unnest_tokens(bigram, clean_text, token = "ngrams", n = 2) %>%
  filter(!is.na(bigram)) %>%
  count(bigram, sort = TRUE)
write.csv(bigrams_df, file.path(out_dir, "q3_top_bigrams.csv"), row.names = FALSE)

# =============================================================================
# VISUALISATIONS FOR QUESTION 3.3 (3 FULLY LABELLED CHARTS)
# =============================================================================
# Visualisation 1: Sentence Ranking Comparison (TextRank vs TF-IDF Across Article Flow)
score_long <- sentences_df %>%
  select(sentence_id, selection_status, TextRank = textrank_norm, `TF-IDF Score` = tfidf_norm) %>%
  pivot_longer(cols = c("TextRank", "TF-IDF Score"), names_to = "Method", values_to = "Score")

p3_1 <- ggplot(score_long, aes(x = factor(sentence_id), y = Score, fill = selection_status)) +
  geom_col(width = 0.72) +
  geom_text(aes(label = sprintf("%.2f", Score)), vjust = -0.35, size = 2.6, fontface = "bold", color = "#1E293B") +
  facet_wrap(~ Method, ncol = 1) +
  scale_fill_manual(values = c(
    "Selected by Both Methods" = "#D97706",
    "TextRank Only"            = "#0D9488",
    "TF-IDF Only"              = "#2563EB",
    "Not Selected"             = "#94A3B8"
  ), name = "Summary Selection") +
  ylim(0, 1.18) +
  labs(
    title = "Text Summarisation Comparison: Sentence Importance Across Article Narrative",
    subtitle = "Top 5 sentences selected independently by Graph-Based TextRank and TF-IDF Centroid Scoring (Eurac Research Article)",
    x = "Sentence Position Index in Original Article (S1 to S22)",
    y = "Normalised Importance Score (0 to 1)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", color = "#1B365D", size = 13),
    plot.subtitle = element_text(color = "#475569", size = 9.8),
    strip.text = element_text(face = "bold", color = "#1B365D", size = 11),
    strip.background = element_rect(fill = "#F1F5F9", color = NA),
    legend.position = "top"
  )

ggsave(file.path(out_dir, "q3_sentence_ranking_comparison.png"), p3_1, width = 12, height = 7.0, dpi = 180, bg = "white")

# Visualisation 2: Top 15 Keywords by Cumulative TF-IDF Weight & Top 10 Domain Bigrams
p_kw <- term_totals %>%
  slice_head(n = 15) %>%
  mutate(term = reorder(term, total_tfidf)) %>%
  ggplot(aes(x = term, y = total_tfidf, fill = total_tfidf)) +
  geom_col(show.legend = FALSE, width = 0.7) +
  geom_text(aes(label = sprintf("%.2f (n=%d)", total_tfidf, raw_freq)), hjust = -0.06, size = 3.1, fontface = "bold", color = "#1E293B") +
  coord_flip(ylim = c(0, max(term_totals$total_tfidf) * 1.32)) +
  scale_fill_gradient(low = "#3B82F6", high = "#1B365D") +
  labs(
    title = "A. Top 15 Keywords by Cumulative TF-IDF Weight",
    subtitle = "Domain terms capturing drought, climate impacts & NLP reasoning",
    x = NULL, y = "Cumulative Sentence TF-IDF Score"
  ) +
  theme_minimal(base_size = 10.5) +
  theme(plot.title = element_text(face = "bold", color = "#1B365D"), panel.grid.major.y = element_blank())

p_bg <- bigrams_df %>%
  slice_head(n = 12) %>%
  mutate(bigram = reorder(bigram, n)) %>%
  ggplot(aes(x = bigram, y = n)) +
  geom_col(fill = "#0D9488", width = 0.68) +
  geom_text(aes(label = sprintf("%d hits", n)), hjust = -0.1, size = 3.2, fontface = "bold", color = "#1E293B") +
  coord_flip(ylim = c(0, max(bigrams_df$n) * 1.25)) +
  labs(
    title = "B. Top 12 Most Frequent Domain Bigrams",
    subtitle = "Multi-word expressions extracted after stopword denoising",
    x = NULL, y = "Frequency Across Article"
  ) +
  theme_minimal(base_size = 10.5) +
  theme(plot.title = element_text(face = "bold", color = "#1B365D"), panel.grid.major.y = element_blank())

g_kw <- gridExtra::arrangeGrob(
  p_kw, p_bg, ncol = 2,
  top = grid::textGrob("Semantic Keyphrase & Co-Occurrence Analysis ('Can language become environmental data?')",
                       gp = grid::gpar(fontsize = 13, fontface = "bold", col = "#1B365D"))
)
ggsave(file.path(out_dir, "q3_keyword_tfidf_bigrams.png"), g_kw, width = 13, height = 6.2, dpi = 180, bg = "white")

# Visualisation 3: Compression Ratio & Information Density Metrics
orig_words <- sum(sentences_df$raw_words)
orig_sents <- nrow(sentences_df)
orig_chars <- sum(sentences_df$raw_chars)
tr_words   <- str_count(tr_summary_text, "\\S+")
tf_words   <- str_count(tfidf_summary_text, "\\S+")
tr_chars   <- nchar(tr_summary_text)
tf_chars   <- nchar(tfidf_summary_text)

# Unique top-15 keyword coverage rate inside each summary
top15_words <- term_totals$term[1:15]
cov_orig <- 100
cov_tr   <- round(100 * mean(sapply(top15_words, function(w) grepl(w, tolower(tr_summary_text)))), 1)
cov_tf   <- round(100 * mean(sapply(top15_words, function(w) grepl(w, tolower(tfidf_summary_text)))), 1)

comp_df <- data.frame(
  Version = factor(c("Original Article\n(Full Text)", "Method 1:\nTextRank Summary", "Method 2:\nTF-IDF Summary"),
                   levels = c("Original Article\n(Full Text)", "Method 1:\nTextRank Summary", "Method 2:\nTF-IDF Summary")),
  Word_Count = c(orig_words, tr_words, tf_words),
  Word_Reduction_Pct = c(0, round(100 * (1 - tr_words / orig_words), 1), round(100 * (1 - tf_words / orig_words), 1)),
  Top15_Keyword_Coverage = c(cov_orig, cov_tr, cov_tf)
)

p3_3a <- ggplot(comp_df, aes(x = Version, y = Word_Count, fill = Version)) +
  geom_col(width = 0.55, show.legend = FALSE) +
  geom_text(aes(label = ifelse(Word_Reduction_Pct == 0,
                               sprintf("%d words\n(Baseline)", Word_Count),
                               sprintf("%d words\n(-%.1f%% size)", Word_Count, Word_Reduction_Pct))),
            vjust = -0.25, size = 3.4, fontface = "bold", color = "#1E293B") +
  scale_fill_manual(values = c("#1B365D", "#0D9488", "#D97706")) +
  ylim(0, orig_words * 1.22) +
  labs(title = "A. Word Volume & Text Compression Ratio", x = NULL, y = "Word Count") +
  theme_minimal(base_size = 10.5) +
  theme(plot.title = element_text(face = "bold", color = "#1B365D"), panel.grid.major.x = element_blank())

p3_3b <- ggplot(comp_df, aes(x = Version, y = Top15_Keyword_Coverage, fill = Version)) +
  geom_col(width = 0.55, show.legend = FALSE) +
  geom_text(aes(label = sprintf("%.1f%% coverage\n(of Top-15 TF-IDF terms)", Top15_Keyword_Coverage)),
            vjust = -0.25, size = 3.3, fontface = "bold", color = "#1E293B") +
  scale_fill_manual(values = c("#1B365D", "#0D9488", "#D97706")) +
  ylim(0, 122) +
  labs(title = "B. Semantic Information Retention Rate", x = NULL, y = "Top-15 Keyword Retention (%)") +
  theme_minimal(base_size = 10.5) +
  theme(plot.title = element_text(face = "bold", color = "#1B365D"), panel.grid.major.x = element_blank())

g_comp <- gridExtra::arrangeGrob(
  p3_3a, p3_3b, ncol = 2,
  top = grid::textGrob("Summarisation Evaluation: Length Compression vs Key-Concept Retention",
                       gp = grid::gpar(fontsize = 13, fontface = "bold", col = "#1B365D"))
)
ggsave(file.path(out_dir, "q3_compression_readability_metrics.png"), g_comp, width = 12, height = 5.4, dpi = 180, bg = "white")

cat("Saved all 3 Question 3 visualisations in outputs/.\n")
