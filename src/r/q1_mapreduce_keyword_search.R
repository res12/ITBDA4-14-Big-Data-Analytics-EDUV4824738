# =============================================================================
# ITBDA4-14 Project — Question 1: Dynamic MapReduce Keyword Search in R
# Usage: Rscript q1_mapreduce_keyword_search.R africa
# Supports dynamic CLI keyword argument (defaults to prompting/using arg[1])
# =============================================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(stringr)
  library(grid)
})

args <- commandArgs(trailingOnly = TRUE)
search_keyword <- if (length(args) >= 1 && nzchar(trimws(args[1]))) {
  trimws(args[1])
} else {
  Sys.getenv("SEARCH_KEYWORD", unset = "africa")
}

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
base_dir <- if (length(script_arg)) {
  normalizePath(file.path(dirname(sub("^--file=", "", script_arg[1])), "../.."), winslash = "/")
} else normalizePath(".", winslash = "/")
docs_dir <- file.path(base_dir, "data", "map_reduce_test_docs")
out_dir  <- file.path(base_dir, "outputs")

cat("========================================================================\n")
cat("ITBDA4-14 QUESTION 1: DYNAMIC MAPREDUCE KEYWORD SEARCH (R ENGINE)\n")
cat("Target Keyword (case-insensitive):", search_keyword, "\n")
cat("========================================================================\n\n")

# Configuration Settings Object (mirrors Hadoop Configuration & mapred-site.xml)
mr_config <- list(
  `fs.defaultFS` = "hdfs://localhost:9000",
  `mapreduce.framework.name` = "yarn",
  `mapreduce.job.reduces` = 1L,
  `mapreduce.input.fileinputformat.split.maxsize` = 134217728L,
  `search.keyword` = search_keyword,
  `search.case_sensitive` = FALSE
)

# MAPPER FUNCTION: emits <doc_name, list(row, char_col, word_col, token, exact_word)>
keyword_mapper <- function(file_path, config) {
  doc_name <- basename(file_path)
  lines <- readLines(file_path, warn = FALSE, encoding = "UTF-8")
  # Build exact case-insensitive literal regex
  kw_escaped <- stringr::str_replace_all(config$search.keyword, "([\\W])", "\\\\\\1")
  pat <- stringr::regex(kw_escaped, ignore_case = !config$search.case_sensitive)

  records <- list()
  for (row_idx in seq_along(lines)) {
    line_txt <- lines[row_idx]
    locs <- stringr::str_locate_all(line_txt, pat)[[1]]
    if (nrow(locs) > 0) {
      for (m_idx in seq_len(nrow(locs))) {
        char_col <- locs[m_idx, "start"]
        prefix <- if (char_col > 1) substr(line_txt, 1, char_col - 1) else ""
        prior_tokens <- stringr::str_count(prefix, "\\S+(?=\\s)")
        word_col <- prior_tokens + 1L
        # Extract full whitespace-delimited token around match
        tokens <- strsplit(line_txt, "\\s+")[[1]]
        tok_str <- if (word_col <= length(tokens)) tokens[word_col] else config$search.keyword
        tok_clean <- gsub("[[:punct:]\u2018\u2019\u201c\u201d]+$", "", tok_str)
        exact_flag <- tolower(tok_clean) == tolower(config$search.keyword)

        records[[length(records) + 1L]] <- data.frame(
          doc_name   = doc_name,
          row_num    = row_idx,
          char_col   = char_col,
          word_col   = word_col,
          token      = tok_clean,
          exact_word = exact_flag,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(records) == 0) return(NULL)
  dplyr::bind_rows(records)
}

# SHUFFLE & SORT + REDUCER FUNCTION: groups by doc_name, sorts coordinates, aggregates counts
keyword_reducer <- function(mapped_list, all_docs) {
  non_empty <- mapped_list[!sapply(mapped_list, is.null)]
  all_matches <- if (length(non_empty) > 0) dplyr::bind_rows(non_empty) else data.frame(
    doc_name = character(), row_num = integer(), char_col = integer(),
    word_col = integer(), token = character(), exact_word = logical(),
    stringsAsFactors = FALSE
  )

  # Group per document (Shuffle & Sort key = doc_name)
  summary_df <- data.frame(doc_name = all_docs, stringsAsFactors = FALSE) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(
      total_matches = sum(all_matches$doc_name == doc_name),
      exact_word_matches = sum(all_matches$doc_name == doc_name & all_matches$exact_word),
      coordinates = {
        sub <- all_matches[all_matches$doc_name == doc_name, ]
        if (nrow(sub) == 0) {
          "None (0 matches)"
        } else {
          sub <- sub[order(sub$row_num, sub$char_col), ]
          paste(sprintf("(Row %d, CharCol %d, WordCol %d)", sub$row_num, sub$char_col, sub$word_col), collapse = "; ")
        }
      }
    ) %>%
    dplyr::ungroup()

  list(matches = all_matches, summary = summary_df)
}

# Execute MapReduce Job
doc_files <- sort(list.files(docs_dir, pattern = "\\.txt$", full.names = TRUE))
mapped_results <- lapply(doc_files, keyword_mapper, config = mr_config)
reduced_output <- keyword_reducer(mapped_results, basename(doc_files))

write.csv(reduced_output$matches, file.path(out_dir, "q1_r_mapreduce_matches.csv"), row.names = FALSE)
write.csv(reduced_output$summary, file.path(out_dir, "q1_r_mapreduce_summary.csv"), row.names = FALSE)

cat("--- REDUCER SUMMARY PER DOCUMENT ---\n")
print(reduced_output$summary)
cat("\n--- DETAILED ROW & COLUMN LOCATIONS ---\n")
print(reduced_output$matches)

# =============================================================================
# CHART 1: VISUALISATION OF KEYWORD MATCHES PER DOCUMENT & COORDINATE MAP
# =============================================================================
sum_plot_df <- reduced_output$summary %>%
  mutate(
    variant_matches = total_matches - exact_word_matches,
    doc_label = factor(doc_name, levels = rev(sort(doc_name)))
  )

p1 <- ggplot(sum_plot_df, aes(x = doc_label, y = total_matches, fill = total_matches > 0)) +
  geom_col(width = 0.62, show.legend = FALSE) +
  geom_text(
    aes(label = ifelse(total_matches > 0,
                       sprintf("%d matches (%d exact / %d inflected)", total_matches, exact_word_matches, variant_matches),
                       "0 matches")),
    hjust = -0.05, size = 3.6, fontface = "bold", color = "#1B365D"
  ) +
  scale_fill_manual(values = c("TRUE" = "#1F4E78", "FALSE" = "#94A3B8")) +
  coord_flip(ylim = c(0, 14.5)) +
  labs(
    title = sprintf("MapReduce Case-Insensitive Keyword Search: '%s' Occurrences per Document", search_keyword),
    subtitle = sprintf("Corpus: map_reduce_test_docs.zip (7 documents) | Total: %d occurrences across 4 matching documents",
                       sum(sum_plot_df$total_matches)),
    x = "Document Name (Reducer Key)",
    y = "Total Case-Insensitive Occurrences Emitted by Reducer"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", color = "#1B365D", size = 13),
    plot.subtitle = element_text(color = "#475569", size = 10),
    panel.grid.major.y = element_blank(),
    axis.text = element_text(color = "#1E293B", face = "bold")
  )

ggsave(file.path(out_dir, "q1_keyword_matches_chart.png"), p1, width = 10.5, height = 5.2, dpi = 180, bg = "white")
cat("\nSaved Chart -> outputs/q1_keyword_matches_chart.png\n")
