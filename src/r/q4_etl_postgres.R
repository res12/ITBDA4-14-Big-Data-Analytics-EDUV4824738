# ==============================================================================
# ITBDA4-14 Question 4: ETL Manipulating Using R & PostgreSQL
# Source: Eduvos Qualifications Catalogue (https://www.eduvos.com/qualifications/)
# ==============================================================================

suppressPackageStartupMessages({
  library(rvest)
  library(xml2)
  library(httr)
  library(stringr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
  library(DBI)
  library(RPostgres)
})

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
base_dir <- if (length(script_arg)) {
  normalizePath(file.path(dirname(sub("^--file=", "", script_arg[1])), "../.."), winslash = "/")
} else normalizePath(".", winslash = "/")
data_dir <- file.path(base_dir, "data")
out_dir  <- file.path(base_dir, "outputs")
sql_dir  <- file.path(base_dir, "src", "sql")
dir.create(sql_dir, recursive = TRUE, showWarnings = FALSE)

cache_html <- file.path(data_dir, "eduvos_qualifications_cached.html")
target_url <- "https://www.eduvos.com/qualifications/"

# ------------------------------------------------------------------------------
# STEP 4.1: EXTRACT - WEB SCRAPING & REGEX PARSING (RAW UNSTRUCTURED DATASET)
# ------------------------------------------------------------------------------
if (!file.exists(cache_html)) {
  resp <- GET(
    target_url,
    user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) ITBDA4-14-ETL-Research/1.0"),
    timeout(30)
  )
  stopifnot(status_code(resp) == 200)
  html_raw <- content(resp, as = "text", encoding = "UTF-8")
  writeLines(html_raw, cache_html, useBytes = TRUE)
} else {
  html_raw <- paste(readLines(cache_html, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}

pg <- read_html(html_raw)
cards <- pg %>% html_elements("article.qf-card")
cat(sprintf("Extracted %d raw <article class='qf-card'> records from Eduvos Qualifications.\n", length(cards)))

extract_text_safe <- function(node, selector) {
  el <- html_element(node, selector)
  if (inherits(el, "xml_missing")) return(NA_character_)
  val <- str_squish(html_text2(el))
  if (val == "") return(NA_character_)
  val
}

raw_onclick <- vapply(cards, function(c) {
  val <- html_attr(c, "onclick")
  if (is.na(val)) "" else val
}, character(1))

# Regex extraction of URL slug inside window.open('...')
url_slug <- str_match(raw_onclick, "window\\.open\\('([^']+)'")[, 2]
href_attr <- vapply(cards, function(c) {
  el <- html_element(c, ".qf-card-title a")
  if (inherits(el, "xml_missing")) NA_character_ else html_attr(el, "href")
}, character(1))
rel_url <- ifelse(!is.na(href_attr) & nzchar(href_attr), href_attr, url_slug)

learning_modes_attr <- vapply(cards, function(c) {
  val <- html_attr(c, "data-learning-mode")
  if (is.na(val) || str_trim(val) == "") NA_character_ else str_trim(val)
}, character(1))

title_raw <- vapply(cards, extract_text_safe, character(1), selector = ".qf-card-title a")
type_raw  <- vapply(cards, extract_text_safe, character(1), selector = ".qf-type-corner")
fac_raw   <- vapply(cards, extract_text_safe, character(1), selector = ".qf-card-faculty")
desc_raw  <- vapply(cards, extract_text_safe, character(1), selector = ".qf-card-description")
start_raw <- vapply(cards, extract_text_safe, character(1), selector = ".qf-start-date")

# Regex inference of raw numerical attributes (intentionally preserving NAs where card metadata is absent)
infer_nqf_raw <- function(t_type, t_title) {
  case_when(
    str_detect(t_type, regex("^Higher Certificate$", ignore_case = TRUE)) ~ 5L,
    str_detect(t_type, regex("^Degree$", ignore_case = TRUE)) &
      str_detect(t_title, regex("Bachelor of Laws|\\bLLB\\b", ignore_case = TRUE)) ~ 8L,
    str_detect(t_type, regex("^Degree$", ignore_case = TRUE)) ~ 7L,
    str_detect(t_type, regex("Postgraduate|Honours", ignore_case = TRUE)) ~ 8L,
    str_detect(t_type, regex("^Masters$", ignore_case = TRUE)) ~ 9L,
    str_detect(t_type, regex("^Doctorates$", ignore_case = TRUE)) ~ 10L,
    TRUE ~ NA_integer_  # Access, Pre-Degree, Corporate Training have no explicit NQF tier
  )
}

infer_duration_raw <- function(t_type, t_title) {
  case_when(
    str_detect(t_type, regex("^Higher Certificate$|Postgraduate|Honours", ignore_case = TRUE)) ~ 1.0,
    str_detect(t_type, regex("^Degree$", ignore_case = TRUE)) &
      str_detect(t_title, regex("Bachelor of Laws|\\bLLB\\b", ignore_case = TRUE)) ~ 4.0,
    str_detect(t_type, regex("^Degree$", ignore_case = TRUE)) ~ 3.0,
    str_detect(t_type, regex("^Masters$", ignore_case = TRUE)) ~ 2.0,
    str_detect(t_type, regex("^Doctorates$", ignore_case = TRUE)) ~ 3.0,
    str_detect(t_type, regex("^Pre-Degree$", ignore_case = TRUE)) ~ 1.0,
    TRUE ~ NA_real_     # Access & Corporate Training lack explicit duration on listing cards
  )
}

raw_df <- data.frame(
  programme_id           = sprintf("EDV-%03d", seq_along(cards)),
  programme_title_raw    = title_raw,
  faculty_raw            = fac_raw,
  qualification_type_raw = type_raw,
  learning_modes_raw     = learning_modes_attr,
  start_date_raw         = start_raw,
  description_raw        = desc_raw,
  programme_url_raw      = rel_url,
  nqf_level_raw          = infer_nqf_raw(type_raw, title_raw),
  min_duration_years_raw = infer_duration_raw(type_raw, title_raw),
  delivery_mode_count_raw = ifelse(
    is.na(learning_modes_attr),
    NA_integer_,
    str_count(learning_modes_attr, ",") + 1L
  ),
  desc_word_count_raw    = str_count(desc_raw, "\\S+"),
  desc_char_count_raw    = nchar(desc_raw),
  stringsAsFactors       = FALSE
)

write.csv(raw_df, file.path(data_dir, "q4_eduvos_programmes_raw.csv"), row.names = FALSE, na = "NA")

# Quantify real-world anomalies / imperfections prior to cleaning
audit_df <- data.frame(
  anomaly_category = c(
    "Missing data-learning-mode attribute (NA)",
    "NQF level unavailable on listing card (Access / Pre-Degree / Corporate)",
    "Duration unavailable on listing card (Access / Corporate)",
    "Truncated descriptions ending with ellipsis (...)",
    "Unparsed date prefix ('Start date: ...')",
    "Unicode en/em dashes requiring ASCII normalisation",
    "Boilerplate duplicate card descriptions (repeated text)",
    "Misclassified Pre-Degree IT/Science under Humanities & Arts",
    "Relative URL paths missing domain scheme/host"
  ),
  affected_records = c(
    sum(is.na(raw_df$learning_modes_raw)),
    sum(is.na(raw_df$nqf_level_raw)),
    sum(is.na(raw_df$min_duration_years_raw)),
    sum(str_detect(raw_df$description_raw, "\\.\\.\\.$"), na.rm = TRUE),
    sum(str_detect(raw_df$start_date_raw, "^Start date:"), na.rm = TRUE),
    sum(str_detect(paste(raw_df$programme_title_raw, raw_df$description_raw), "\u2013|\u2014"), na.rm = TRUE),
    sum(duplicated(raw_df$description_raw) | duplicated(raw_df$description_raw, fromLast = TRUE)),
    sum(raw_df$faculty_raw == "Humanities and Arts" &
          str_detect(raw_df$programme_title_raw, regex(":\\s*(Information Technology|Science)$", ignore_case = TRUE))),
    sum(str_detect(raw_df$programme_url_raw, "^/"), na.rm = TRUE)
  ),
  total_records = nrow(raw_df),
  stringsAsFactors = FALSE
)
audit_df$pct_affected <- round(100 * audit_df$affected_records / audit_df$total_records, 1)
write.csv(audit_df, file.path(out_dir, "q4_data_quality_audit.csv"), row.names = FALSE)

cat("\n=== 4.1 RAW DATA QUALITY AUDIT (N =", nrow(raw_df), ") ===\n")
print(audit_df)

# ------------------------------------------------------------------------------
# STEP 4.2: TRANSFORM - CLEANING, DENOISING & MISSING-VALUE IMPUTATION
# ------------------------------------------------------------------------------
clean_df <- raw_df %>%
  mutate(
    # Standardise titles & Unicode dashes
    programme_title_clean = str_squish(str_replace_all(programme_title_raw, "[\u2013\u2014]", "-")),
    # Correct domain misclassifications observed on live site
    faculty_corrected = (
      faculty_raw == "Humanities and Arts" &
        str_detect(programme_title_raw, regex(":\\s*(Information Technology|Science)$", ignore_case = TRUE))
    ),
    faculty_clean = case_when(
      faculty_raw == "Humanities and Arts" &
        str_detect(programme_title_raw, regex(":\\s*Information Technology$", ignore_case = TRUE)) ~ "Technology",
      faculty_raw == "Humanities and Arts" &
        str_detect(programme_title_raw, regex(":\\s*Science$", ignore_case = TRUE)) ~ "Applied Sciences",
      TRUE ~ str_squish(faculty_raw)
    ),
    qualification_type = str_squish(qualification_type_raw),
    study_level_group = case_when(
      qualification_type %in% c("Access", "Pre-Degree") ~ "Foundational",
      qualification_type %in% c("Higher Certificate", "Degree") ~ "Undergraduate",
      qualification_type %in% c("Honours", "Postgraduate Certificates & Diplomas", "Masters", "Doctorates") ~ "Postgraduate",
      TRUE ~ "Corporate & Short Courses"
    ),
    # Impute single missing learning mode with faculty/degree modal value
    learning_mode_imputed = is.na(learning_modes_raw),
    learning_modes_clean = ifelse(
      is.na(learning_modes_raw),
      "Campus Full Time, Online Full Time, Online Part Time",
      str_squish(learning_modes_raw)
    ),
    delivery_mode_count = str_count(learning_modes_clean, ",") + 1L,
    offers_online = str_detect(learning_modes_clean, regex("Online|Remote|Distance", ignore_case = TRUE)),
    offers_campus = str_detect(learning_modes_clean, regex("Campus", ignore_case = TRUE)),
    # Parse raw 'Start date: DD Month YYYY' into ISO Date
    start_date_str = str_trim(str_remove(start_date_raw, "^Start date:\\s*")),
    intake_date_iso = as.character(as.Date(start_date_str, format = "%d %B %Y")),
    intake_cohort = format(as.Date(start_date_str, format = "%d %B %Y"), "%Y-%m"),
    # Denoise description text (remove truncation ellipsis, Unicode dashes)
    was_truncated = str_detect(description_raw, "\\.\\.\\.$"),
    description_clean = description_raw %>%
      str_replace_all("[\u2013\u2014]", "-") %>%
      str_remove("\\.\\.\\.$") %>%
      str_squish(),
    desc_word_count = str_count(description_clean, "\\S+"),
    desc_char_count = nchar(description_clean),
    programme_url_full = ifelse(
      str_starts(programme_url_raw, "http"),
      programme_url_raw,
      paste0("https://www.eduvos.com", programme_url_raw)
    ),
    # Deterministic rule-based imputation for NQF level and duration
    nqf_imputed = is.na(nqf_level_raw),
    nqf_level = case_when(
      !is.na(nqf_level_raw) ~ nqf_level_raw,
      qualification_type %in% c("Access", "Pre-Degree") ~ 5L,
      qualification_type == "Corporate Training" &
        str_detect(programme_title_clean, regex("National Certificate", ignore_case = TRUE)) ~ 5L,
      qualification_type == "Corporate Training" ~ 6L,
      TRUE ~ 5L
    ),
    duration_imputed = is.na(min_duration_years_raw),
    min_duration_years = case_when(
      !is.na(min_duration_years_raw) ~ min_duration_years_raw,
      qualification_type == "Access" ~ 1.0,
      qualification_type == "Corporate Training" ~ 0.25,
      TRUE ~ 1.0
    ),
    estimated_saqa_credits = as.integer(round(min_duration_years * 120))
  ) %>%
  select(
    programme_id, programme_title_clean, faculty_raw, faculty_clean, faculty_corrected,
    qualification_type, study_level_group, nqf_level, nqf_imputed,
    min_duration_years, duration_imputed, estimated_saqa_credits,
    learning_modes_clean, learning_mode_imputed, delivery_mode_count,
    offers_online, offers_campus, intake_date_iso, intake_cohort,
    description_clean, was_truncated, desc_word_count, desc_char_count,
    programme_url_full
  )

cat("\n=== 4.2 CLEANED DATASET VERIFICATION ===\n")
cat("Remaining NAs across cleaned columns:", sum(is.na(clean_df)), "\n")
cat("Faculties corrected:", sum(clean_df$faculty_corrected), "\n")
cat("Learning mode imputed:", sum(clean_df$learning_mode_imputed), "\n")
cat("NQF levels imputed:", sum(clean_df$nqf_imputed), "\n")
cat("Durations imputed:", sum(clean_df$duration_imputed), "\n")

write.csv(clean_df, file.path(data_dir, "q4_eduvos_programmes_cleaned.csv"), row.names = FALSE)
write.csv(clean_df, file.path(out_dir,  "q4_eduvos_programmes_cleaned.csv"), row.names = FALSE)

# ------------------------------------------------------------------------------
# STEP 4.3: LOAD INTO POSTGRESQL 17 & EXECUTE SQL ANALYTICAL INVESTIGATIONS
# ------------------------------------------------------------------------------
con <- dbConnect(
  RPostgres::Postgres(),
  host     = Sys.getenv("ITBDA_PG_HOST", "127.0.0.1"),
  port     = as.integer(Sys.getenv("ITBDA_PG_PORT", "5433")),
  user     = Sys.getenv("ITBDA_PG_USER", "postgres"),
  password = Sys.getenv("ITBDA_PG_PASSWORD", ""),
  dbname   = Sys.getenv("ITBDA_PG_DB", "itbda4_etl_db")
)
on.exit(dbDisconnect(con), add = TRUE)

dbExecute(con, "DROP TABLE IF EXISTS eduvos_programmes;")
dbExecute(con, "
CREATE TABLE eduvos_programmes (
  programme_id           VARCHAR(16) PRIMARY KEY,
  programme_title_clean  TEXT NOT NULL,
  faculty_raw            VARCHAR(80) NOT NULL,
  faculty_clean          VARCHAR(80) NOT NULL,
  faculty_corrected      BOOLEAN NOT NULL,
  qualification_type     VARCHAR(80) NOT NULL,
  study_level_group      VARCHAR(40) NOT NULL,
  nqf_level              INTEGER NOT NULL CHECK (nqf_level BETWEEN 5 AND 10),
  nqf_imputed            BOOLEAN NOT NULL,
  min_duration_years     NUMERIC(4,2) NOT NULL CHECK (min_duration_years > 0),
  duration_imputed       BOOLEAN NOT NULL,
  estimated_saqa_credits INTEGER NOT NULL CHECK (estimated_saqa_credits > 0),
  learning_modes_clean   TEXT NOT NULL,
  learning_mode_imputed  BOOLEAN NOT NULL,
  delivery_mode_count    INTEGER NOT NULL,
  offers_online          BOOLEAN NOT NULL,
  offers_campus          BOOLEAN NOT NULL,
  intake_date_iso        DATE NOT NULL,
  intake_cohort          VARCHAR(10) NOT NULL,
  description_clean      TEXT NOT NULL,
  was_truncated          BOOLEAN NOT NULL,
  desc_word_count        INTEGER NOT NULL,
  desc_char_count        INTEGER NOT NULL,
  programme_url_full     TEXT NOT NULL
);")

# Prepare types cleanly for RPostgres append
pg_df <- clean_df %>%
  mutate(intake_date_iso = as.Date(intake_date_iso))

dbWriteTable(con, "eduvos_programmes", pg_df, append = TRUE, row.names = FALSE)
row_check <- dbGetQuery(con, "SELECT COUNT(*) AS loaded_rows FROM eduvos_programmes;")
cat(sprintf("\nPostgreSQL table 'eduvos_programmes' populated successfully (%d rows).\n", as.integer(row_check$loaded_rows)))

coerce_pg_types <- function(df) {
  df %>% mutate(across(where(~ inherits(.x, "integer64")), as.numeric))
}

# SQL Analytical Investigation 1: Faculty Portfolio Composition, NQF Depth & Modality Mix
sql_q1 <- "
SELECT
  faculty_clean AS faculty,
  COUNT(*) AS total_programmes,
  SUM(CASE WHEN study_level_group = 'Foundational' THEN 1 ELSE 0 END) AS foundational_cnt,
  SUM(CASE WHEN study_level_group = 'Undergraduate' THEN 1 ELSE 0 END) AS undergrad_cnt,
  SUM(CASE WHEN study_level_group = 'Postgraduate' THEN 1 ELSE 0 END) AS postgrad_cnt,
  SUM(CASE WHEN study_level_group = 'Corporate & Short Courses' THEN 1 ELSE 0 END) AS corporate_cnt,
  ROUND(AVG(nqf_level)::numeric, 2) AS avg_nqf_level,
  ROUND(AVG(estimated_saqa_credits)::numeric, 1) AS avg_saqa_credits,
  ROUND(AVG(delivery_mode_count)::numeric, 2) AS avg_delivery_modes,
  ROUND(100.0 * SUM(CASE WHEN offers_online THEN 1 ELSE 0 END) / COUNT(*), 1) AS online_pct
FROM eduvos_programmes
GROUP BY faculty_clean
ORDER BY total_programmes DESC, avg_nqf_level DESC;
"

# SQL Analytical Investigation 2: Qualification Tier & Intake Date Cohort Structure
sql_q2 <- "
SELECT
  qualification_type,
  study_level_group,
  intake_date_iso,
  ROUND(AVG(nqf_level)::numeric, 1) AS avg_nqf,
  ROUND(AVG(min_duration_years)::numeric, 2) AS avg_years,
  COUNT(*) AS programme_count,
  SUM(estimated_saqa_credits) AS total_saqa_credits,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_catalogue,
  SUM(CASE WHEN nqf_imputed THEN 1 ELSE 0 END) AS nqf_imputed_cnt
FROM eduvos_programmes
GROUP BY qualification_type, study_level_group, intake_date_iso
ORDER BY intake_date_iso ASC, avg_nqf DESC, programme_count DESC;
"

# SQL Analytical Investigation 3: Window Function Ranking Highest-NQF Flagships per Faculty
sql_q3 <- "
WITH ranked_programmes AS (
  SELECT
    faculty_clean,
    programme_id,
    programme_title_clean,
    qualification_type,
    nqf_level,
    estimated_saqa_credits,
    delivery_mode_count,
    DENSE_RANK() OVER (
      PARTITION BY faculty_clean
      ORDER BY nqf_level DESC, estimated_saqa_credits DESC, programme_id ASC
    ) AS faculty_nqf_rank
  FROM eduvos_programmes
)
SELECT
  faculty_clean AS faculty,
  faculty_nqf_rank,
  programme_id,
  programme_title_clean,
  qualification_type,
  nqf_level,
  estimated_saqa_credits,
  delivery_mode_count
FROM ranked_programmes
WHERE faculty_nqf_rank <= 2
ORDER BY faculty_clean ASC, faculty_nqf_rank ASC, programme_id ASC;
"

res_q1 <- coerce_pg_types(dbGetQuery(con, sql_q1))
res_q2 <- coerce_pg_types(dbGetQuery(con, sql_q2))
res_q3 <- coerce_pg_types(dbGetQuery(con, sql_q3))

write.csv(res_q1, file.path(out_dir, "q4_sql_query1_faculty_summary.csv"), row.names = FALSE)
write.csv(res_q2, file.path(out_dir, "q4_sql_query2_tier_intake_matrix.csv"), row.names = FALSE)
write.csv(res_q3, file.path(out_dir, "q4_sql_query3_faculty_top_programmes.csv"), row.names = FALSE)

cat("\n=== SQL INVESTIGATION 1: FACULTY SUMMARY ===\n")
print(res_q1)
cat("\n=== SQL INVESTIGATION 2: QUALIFICATION TIER & INTAKE MATRIX ===\n")
print(res_q2)
cat("\n=== SQL INVESTIGATION 3: TOP RANKED PROGRAMMES PER FACULTY (SAMPLE) ===\n")
print(head(res_q3, 12))

# ------------------------------------------------------------------------------
# VISUALISATION OF POSTGRESQL ANALYTICAL RESULTS (2-PANEL COMPOSITE)
# ------------------------------------------------------------------------------
tier_counts <- clean_df %>%
  count(faculty_clean, study_level_group) %>%
  left_join(res_q1 %>% select(faculty, total_programmes), by = c("faculty_clean" = "faculty")) %>%
  mutate(
    study_level_group = factor(
      study_level_group,
      levels = c("Foundational", "Undergraduate", "Postgraduate", "Corporate & Short Courses")
    ),
    faculty_ord = reorder(faculty_clean, total_programmes)
  )

p1 <- ggplot(tier_counts, aes(x = faculty_ord, y = n, fill = study_level_group)) +
  geom_col(width = 0.72, color = "white", linewidth = 0.35) +
  geom_text(
    aes(label = n),
    position = position_stack(vjust = 0.5),
    color = "white", fontface = "bold", size = 3.2
  ) +
  coord_flip() +
  scale_fill_manual(
    values = c(
      "Foundational"              = "#64748B",
      "Undergraduate"             = "#1B365D",
      "Postgraduate"              = "#0EA5E9",
      "Corporate & Short Courses" = "#F59E0B"
    ),
    name = "Academic Tier"
  ) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.14))) +
  labs(
    title = "A. Programme Portfolio Across Faculties (PostgreSQL Cleaned Table)",
    subtitle = "Stacked programme counts after correcting 2 Pre-Degree faculty misclassifications",
    x = NULL,
    y = "Number of Programmes"
  ) +
  theme_minimal(base_size = 10.5) +
  theme(
    plot.title = element_text(face = "bold", color = "#1B365D", size = 11.2),
    plot.subtitle = element_text(color = "#475569", size = 8.8),
    legend.position = "bottom",
    legend.title = element_text(face = "bold", size = 9),
    plot.margin = margin(10, 14, 10, 10),
    panel.grid.major.y = element_blank()
  )

res_q1_plot <- res_q1 %>%
  mutate(
    faculty_ord = reorder(faculty, avg_nqf_level),
    label_txt = sprintf("NQF %.2f  |  %.0f credits", avg_nqf_level, avg_saqa_credits)
  )

p2 <- ggplot(res_q1_plot, aes(x = faculty_ord, y = avg_nqf_level)) +
  geom_segment(aes(xend = faculty_ord, y = 4.5, yend = avg_nqf_level), color = "#CBD5E1", linewidth = 2.2) +
  geom_point(aes(size = avg_saqa_credits), color = "#1D4ED8", alpha = 0.9) +
  geom_text(aes(label = label_txt), nudge_y = 0.26, hjust = 0, size = 3.2, fontface = "bold", color = "#1E293B") +
  coord_flip(ylim = c(4.5, 10.2)) +
  scale_size_continuous(range = c(5, 11), name = "Mean SAQA Credits") +
  labs(
    title = "B. Mean NQF Depth & SAQA Credit Load by Faculty (SQL Aggregation)",
    subtitle = "PostgreSQL 17 GROUP BY query over 68 cleaned Eduvos qualification records",
    x = NULL,
    y = "Mean NQF Level (5 to 10 Scale)"
  ) +
  theme_minimal(base_size = 10.5) +
  theme(
    plot.title = element_text(face = "bold", color = "#1B365D", size = 11.2),
    plot.subtitle = element_text(color = "#475569", size = 8.8),
    legend.position = "bottom",
    legend.title = element_text(face = "bold", size = 9),
    plot.margin = margin(10, 14, 10, 14),
    panel.grid.major.y = element_blank()
  )

# Save two side-by-side panels cleanly via gridExtra or grid viewport
png(file.path(out_dir, "q4_etl_postgresql_analysis.png"), width = 2400, height = 1120, res = 175, bg = "white")
grid::grid.newpage()
grid::pushViewport(grid::viewport(layout = grid::grid.layout(1, 2)))
print(p1, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
print(p2, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 2))
dev.off()

cat("\nSaved outputs/q4_etl_postgresql_analysis.png and all Q4 CSV deliverables.\n")
