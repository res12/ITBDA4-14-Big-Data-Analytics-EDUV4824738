# =============================================================================
# ITBDA4-14 Project — Question 2: LDA Topic Modelling on SA News Corpus (news.zip)
# 2.1 Load news.zip into data.frame(file_name, content) & denoise text
# 2.2 Run Latent Dirichlet Allocation (LDA) -> top n topics & top k words/topic
# 2.3 Visualise top keywords and document-topic distributions using 3 methods
# =============================================================================

suppressPackageStartupMessages({
  library(tm)
  library(topicmodels)
  library(tidytext)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(ggplot2)
  library(wordcloud)
  library(RColorBrewer)
  library(scales)
})

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
base_dir <- if (length(script_arg)) {
  normalizePath(file.path(dirname(sub("^--file=", "", script_arg[1])), "../.."), winslash = "/")
} else normalizePath(".", winslash = "/")
news_zip <- file.path(base_dir, "data", "news.zip")
news_dir <- file.path(base_dir, "data", "sa_news")
out_dir  <- file.path(base_dir, "outputs")

# -----------------------------------------------------------------------------
# 2.1 LOAD FILES INTO DATA FRAME (col_1: file_name, col_2: content) & DENOISE
# -----------------------------------------------------------------------------
unzip(news_zip, exdir = file.path(base_dir, "data"))
txt_files <- sort(list.files(news_dir, pattern = "\\.txt$", full.names = TRUE))
# Order numerically (news_1 .. news_10)
ord_idx <- order(as.integer(str_extract(basename(txt_files), "\\d+")))
txt_files <- txt_files[ord_idx]

news_df <- data.frame(
  file_name = basename(txt_files),
  content   = vapply(txt_files, function(f) paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), character(1)),
  stringsAsFactors = FALSE,
  row.names = NULL
)

cat("=== 2.1 RAW NEWS DATAFRAME SUMMARY ===\n")
cat("Dimensions:", nrow(news_df), "rows x", ncol(news_df), "columns\n")
cat("Columns:", paste(names(news_df), collapse = ", "), "\n")

# Custom noise stopwords tuned for South African government news (weekdays, months, boilerplate)
custom_noise <- c(
  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
  "january", "february", "march", "april", "may", "june", "july", "august",
  "september", "october", "november", "december", "sanews", "sanewsgovza",
  "said", "also", "says", "will", "one", "two", "must", "can", "year", "years",
  "including", "across", "well", "among", "made", "first", "new", "make", "take"
)

denoise_text <- function(txt) {
  # Remove curly quotes/dashes and non-ASCII artefacts
  txt <- gsub("[\u2018\u2019\u201c\u201d\u2013\u2014]", " ", txt)
  # Strip URLs and email addresses
  txt <- gsub("https?://\\S+|www\\.\\S+|\\S+@\\S+", " ", txt)
  # Strip publication dateline strings like "Tuesday, July 9, 2024"
  txt <- gsub("(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\\s+[A-Za-z]+\\s+\\d{1,2},\\s+\\d{4}", " ", txt)
  txt <- tolower(txt)
  txt <- tm::removeNumbers(txt)
  txt <- tm::removePunctuation(txt)
  txt <- tm::removeWords(txt, c(tm::stopwords("english"), custom_noise))
  # Remove short 1-2 character noise tokens
  txt <- gsub("\\b[a-z]{1,2}\\b", " ", txt)
  txt <- tm::stripWhitespace(txt)
  trimws(txt)
}

news_df <- news_df %>%
  mutate(
    headline = vapply(strsplit(content, "\n"), function(x) trimws(x[1]), character(1)),
    raw_words = str_count(content, "\\S+"),
    clean_content = vapply(content, denoise_text, character(1)),
    clean_words = str_count(clean_content, "\\S+"),
    noise_removed_pct = round(100 * (raw_words - clean_words) / raw_words, 1)
  )

write.csv(news_df %>% select(file_name, headline, raw_words, clean_words, noise_removed_pct, clean_content),
          file.path(out_dir, "q2_news_denoised_summary.csv"), row.names = FALSE)

cat("\n--- DENOISING REPORT PER DOCUMENT ---\n")
print(news_df %>% select(file_name, raw_words, clean_words, noise_removed_pct, headline))

# -----------------------------------------------------------------------------
# 2.2 LATENT DIRICHLET ALLOCATION (LDA) -> TOP n = 4 TOPICS, TOP k = 10 WORDS
# -----------------------------------------------------------------------------
corpus <- tm::VCorpus(tm::VectorSource(news_df$clean_content))
dtm <- tm::DocumentTermMatrix(corpus, control = list(wordLengths = c(3, Inf)))
rownames(dtm) <- news_df$file_name
# Keep terms appearing in at least 1 doc and valid vocabulary
cat(sprintf("\nDTM Dimensions: %d documents x %d unique denoised terms (Sparsity: %.1f%%)\n",
            nrow(dtm), ncol(dtm), 100 * (1 - length(dtm$v) / (nrow(dtm) * ncol(dtm)))))

# Fit four exploratory topics with a fixed seed for reproducibility.
set.seed(2026)
k_topics <- 4L
top_k_words <- 10L
lda_model <- topicmodels::LDA(
  dtm, k = k_topics, method = "Gibbs",
  control = list(seed = 2026, burnin = 1000, iter = 3000, thin = 100, alpha = 0.25)
)

# Extract beta (word-topic probability) and gamma (document-topic probability)
beta_df <- tidytext::tidy(lda_model, matrix = "beta")
gamma_df <- tidytext::tidy(lda_model, matrix = "gamma")

top_terms <- beta_df %>%
  group_by(topic) %>%
  slice_max(beta, n = top_k_words, with_ties = FALSE) %>%
  ungroup() %>%
  arrange(topic, desc(beta)) %>%
  group_by(topic) %>%
  mutate(rank = row_number()) %>%
  ungroup()

# Assign mutually exclusive domain labels directly from top-5 distinctive keywords
assign_topic_label <- function(terms_vec) {
  top5 <- paste(head(terms_vec, 6), collapse = " ")
  if (grepl("weather|cape|cold|rain", top5)) {
    return("Severe Weather, Crime & Security")
  } else if (grepl("education|school|eskom|court|accounting", top5)) {
    return("Education, Eskom & Accountability")
  } else if (grepl("coalition|trust|ireland|parties", top5)) {
    return("Coalition Politics & Governance")
  } else if (grepl("labour|psc|employment|public|commission|bribes", top5)) {
    return("Labour, Public Service & Integrity")
  } else {
    return("Public Policy & State Operations")
  }
}

topic_labels_df <- top_terms %>%
  group_by(topic) %>%
  summarise(
    top_10_words = paste(term, collapse = ", "),
    top_3_betas  = paste(sprintf("%s (%.4f)", term[1:3], beta[1:3]), collapse = "; "),
    topic_label  = assign_topic_label(term),
    .groups = "drop"
  ) %>%
  mutate(topic_title = sprintf("Topic %d: %s", topic, topic_label))

top_terms <- top_terms %>% left_join(topic_labels_df %>% select(topic, topic_title), by = "topic")
gamma_df <- gamma_df %>%
  rename(file_name = document) %>%
  left_join(topic_labels_df %>% select(topic, topic_title), by = "topic") %>%
  left_join(news_df %>% select(file_name, headline), by = "file_name")

dominant_topics <- gamma_df %>%
  group_by(file_name) %>%
  slice_max(gamma, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  arrange(as.integer(str_extract(file_name, "\\d+")))

write.csv(top_terms, file.path(out_dir, "q2_lda_top_terms.csv"), row.names = FALSE)
write.csv(gamma_df, file.path(out_dir, "q2_lda_doc_topic_gamma.csv"), row.names = FALSE)
write.csv(topic_labels_df, file.path(out_dir, "q2_lda_topic_summary.csv"), row.names = FALSE)
write.csv(dominant_topics, file.path(out_dir, "q2_lda_dominant_topics.csv"), row.names = FALSE)

cat("\n=== 2.2 LDA TOPICS SUMMARY (k = 4 TOPICS, TOP 10 WORDS EACH) ===\n")
print(topic_labels_df)
cat("\n--- DOMINANT TOPIC PER NEWS ARTICLE (GAMMA) ---\n")
print(dominant_topics %>% select(file_name, topic_title, gamma, headline))

# -----------------------------------------------------------------------------
# 2.3 VISUALISATION METHOD 1: FACETED TOP-K TERMS BAR CHART (BETA DISTRIBUTION)
# -----------------------------------------------------------------------------
p_beta <- top_terms %>%
  mutate(term_reordered = tidytext::reorder_within(term, beta, topic_title)) %>%
  ggplot(aes(x = term_reordered, y = beta, fill = factor(topic))) +
  geom_col(show.legend = FALSE, width = 0.72) +
  geom_text(aes(label = sprintf("%.3f", beta)), hjust = -0.1, size = 3.0, fontface = "bold", color = "#1E293B") +
  tidytext::scale_x_reordered() +
  coord_flip(ylim = c(0, max(top_terms$beta) * 1.25)) +
  facet_wrap(~ topic_title, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("1" = "#1B365D", "2" = "#DC2626", "3" = "#0D9488", "4" = "#D97706")) +
  labs(
    title = "LDA Topic Modelling (n = 4 Topics): Top 10 Keywords per Topic (Beta Probabilities)",
    subtitle = "Corpus: 10 denoised South African government news articles (Gibbs Sampling, 3 000 iterations)",
    x = NULL,
    y = "Word-in-Topic Probability (Beta)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", color = "#1B365D", size = 13),
    plot.subtitle = element_text(color = "#475569", size = 9.8),
    strip.text = element_text(face = "bold", color = "#1B365D", size = 10.5),
    strip.background = element_rect(fill = "#F1F5F9", color = NA),
    panel.grid.major.y = element_blank()
  )

ggsave(file.path(out_dir, "q2_lda_top_terms_faceted.png"), p_beta, width = 12, height = 7.8, dpi = 180, bg = "white")

# -----------------------------------------------------------------------------
# VISUALISATION METHOD 2: DOCUMENT-TOPIC DISTRIBUTION (GAMMA) HEATMAP
# -----------------------------------------------------------------------------
gamma_plot <- gamma_df %>%
  mutate(
    short_doc = sprintf("%s: %s...", file_name, str_trunc(headline, 34, ellipsis = "")),
    doc_ord = factor(short_doc, levels = rev(unique(short_doc[order(as.integer(str_extract(file_name, "\\d+")))])))
  )

p_gamma <- ggplot(gamma_plot, aes(x = str_wrap(topic_title, 20), y = doc_ord, fill = gamma)) +
  geom_tile(color = "white", linewidth = 1.1) +
  geom_text(aes(label = sprintf("%.1f%%", gamma * 100),
                color = ifelse(gamma > 0.45, "white", "#1E293B")),
            fontface = "bold", size = 3.5, show.legend = FALSE) +
  scale_color_identity() +
  scale_fill_gradientn(colors = c("#F8FAFC", "#BFDBFE", "#2563EB", "#1B365D"),
                       labels = scales::percent_format(accuracy = 1),
                       name = "Topic Weight (Gamma)") +
  labs(
    title = "Document-to-Topic Probability Distribution (Gamma Matrix Across All 10 Articles)",
    subtitle = "Each cell shows the percentage of words in the article generated by that latent LDA topic",
    x = "Discovered Latent Topic",
    y = "News Document & Headline"
  ) +
  theme_minimal(base_size = 10.5) +
  theme(
    plot.title = element_text(face = "bold", color = "#1B365D", size = 12.5),
    plot.subtitle = element_text(color = "#475569", size = 9.5),
    axis.text.x = element_text(face = "bold", color = "#1B365D"),
    axis.text.y = element_text(color = "#1E293B"),
    panel.grid = element_blank()
  )

ggsave(file.path(out_dir, "q2_lda_doc_topic_heatmap.png"), p_gamma, width = 11.8, height = 6.2, dpi = 180, bg = "white")

# -----------------------------------------------------------------------------
# VISUALISATION METHOD 3: MULTI-TOPIC WORD CLOUDS GRID (4 PANELS)
# -----------------------------------------------------------------------------
png(file.path(out_dir, "q2_lda_topic_wordclouds.png"), width = 1800, height = 1400, res = 180, bg = "white")
par(mfrow = c(2, 2), mar = c(1.6, 1.4, 3.8, 1.4))
pal_list <- list(
  brewer.pal(8, "Blues")[4:8],
  brewer.pal(8, "Reds")[4:8],
  brewer.pal(8, "BuGn")[4:8],
  brewer.pal(8, "Oranges")[4:8]
)
for (t_id in 1:k_topics) {
  sub_w <- beta_df %>% filter(topic == t_id) %>% arrange(desc(beta)) %>% head(28)
  lbl <- topic_labels_df$topic_title[topic_labels_df$topic == t_id]
  set.seed(2026 + t_id)
  wordcloud::wordcloud(
    words = sub_w$term,
    freq = round(sub_w$beta * 10000),
    max.words = 28,
    random.order = FALSE,
    rot.per = 0.12,
    scale = c(2.35, 0.65),
    colors = pal_list[[t_id]]
  )
  title(main = lbl, col.main = "#1B365D", cex.main = 1.2, font.main = 2)
}
dev.off()

cat("\nSaved all 3 Q2 LDA visualisations in outputs/.\n")
