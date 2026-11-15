# ITBDA4-14 Big Data Analytics — Project Portfolio (EDUV4824738)

**Student:** Resego Ngwenya (`EDUV4824738`)  
**Module:** ITBDA4-14 — Big Data Analytics (NQF Level 8)  
**Lecturer:** Mr. G. Lekula (Online / Pretoria)  
**Submission Date:** 14 November 2026  

---

## Repository Structure

```text
├── data/                         # Original datasets, caches, raw & cleaned CSVs
│   ├── map_reduce_test_docs/     # Question 1 corpus (doc1.txt - doc7.txt)
│   ├── sa_news/                  # Question 2 corpus (news_1.txt - news_10.txt)
│   ├── q3_eurac_scraped_paragraphs.csv
│   ├── q4_eduvos_programmes_raw.csv
│   └── q4_eduvos_programmes_cleaned.csv
├── docs/                         # Formal project documentation (PDF & Markdown)
├── notebooks/                    # Complete & per-question analytics notebooks (.ipynb)
│   ├── ITBDA4-14_Complete_Analytics_Flow.ipynb
│   ├── Q1_MapReduce_Keyword_Search.ipynb
│   ├── Q2_LDA_Topic_Modelling.ipynb
│   ├── Q3_WebText_API_Summarisation.ipynb
│   └── Q4_ETL_R_PostgreSQL.ipynb
├── outputs/                      # Verified CSV tables, psql logs & high-DPI PNG figures
├── src/
│   ├── java/                     # Hadoop MapReduce Mapper, Reducer, Driver, XML conf & JDK runner
│   ├── r/                        # R implementations for Questions 1, 2, 3, and 4
│   └── sql/                      # PostgreSQL 17 analytical queries (q4_analytics.sql)
└── README.md
```

---

## Executive Summary of Analytical Results (Questions 1–4)

### Question 1 (25 Marks): Dynamic Distributed MapReduce Keyword Search
- **Architecture:** The R MapReduce-style program and standalone Java runner were tested locally. Hadoop Mapper, Reducer, Driver and XML files are provided as a cluster implementation; no Hadoop cluster execution is claimed.
- **Dynamic Configuration:** Target keyword is passed via runtime CLI argument / Hadoop `Configuration` (`search.keyword`) and compiled with `Pattern.CASE_INSENSITIVE`.
- **Demonstration Result (`keyword = "africa"`):** Found **22 case-insensitive substring matches** across 4 of the 7 documents (`doc1.txt`: 3, `doc2.txt`: 5, `doc3.txt`: 9, `doc5.txt`: 5; the others: 0), reporting 1-based row, character and word positions. Twelve are exact words; ten occur within longer or possessive forms.

### Question 2 (20 Marks): Latent Dirichlet Allocation (LDA) Topic Modelling
- **Preprocessing (`tm`):** Loaded all 10 articles from `news.zip` into `data.frame(file_name, content)` and removed between 41.5% and 49.8% noise per file, yielding a `10 x 1,086` Document-Term Matrix (87.5% sparsity).
- **Topic Discovery (`topicmodels`, Gibbs `k = 4`):**
  1. **Topic 1 — Coalition Politics & Governance** (`government`, `coalition`, `governments`, `role`, `relationships`) -> Dominant in `news_8.txt` (96.1%).
  2. **Topic 2 — Severe Weather, Crime & Security** (`police`, `cape`, `cold`, `expected`, `weather`) -> Dominant in `news_4.txt` (92.5%), `news_5.txt` (93.5%), `news_10.txt` (80.6%).
  3. **Topic 3 — Labour, Public Service & Integrity** (`public`, `south`, `africa`, `department`, `psc`) -> Dominant in `news_3.txt` (76.2%), `news_7.txt` (86.8%), `news_9.txt` (86.5%).
  4. **Topic 4 — Education, Eskom & Accountability** (`invoices`, `service`, `days`, `national`, `departments`) -> Dominant in `news_1.txt` (73.0%), `news_2.txt` (99.5%), `news_6.txt` (94.4%).
- **Visualisations:** Multi-topic Beta bar grid (`q2_lda_top_terms_faceted.png`), Document-Topic Gamma heatmap (`q2_lda_doc_topic_heatmap.png`), and 4-panel word clouds (`q2_lda_topic_wordclouds.png`).

### Question 3 (30 Marks): WebText API & Extractive Text Summarisation
- **Article extraction (`rvest` / `httr`):** Retrieved *Can language become environmental data?* (Eurac Research, CC BY 4.0) into a named R list (`19 sentences`, `511 raw words -> 313 clean tokens`, `38.7%` removed by preprocessing). The script records whether the text was fetched live or read from its local cache.
- **Dual Extractive Summarisation:**
  - **Graph TextRank (`igraph`):** Selected Sentences 4, 6, 8, 14, 19 (`177 / 511` words, 65.4% compression, 46.7% top-15 TF-IDF keyword coverage).
  - **TF-IDF Weighted Scoring:** Selected Sentences 6, 7, 10, 17, 18 (`84 / 511` words, 83.6% compression, 93.3% top-15 TF-IDF keyword coverage). Sentence 6 was jointly prioritised by both models.

### Question 4 (25 Marks): End-to-End ETL in R & PostgreSQL 17
- **Use Case & Extraction (`4.1`):** Parsed **68 Eduvos qualification cards** from a cached copy of `https://www.eduvos.com/qualifications/` using CSS selectors and regex. The listing had one missing study-mode attribute, 67 truncated descriptions and dates requiring parsing. NQF and duration values for 20 and 15 cards respectively were inferred from qualification types because the listing cards did not supply them.
- **Transformation & Imputation (`4.2`):** Normalised text, corrected two faculty labels, parsed intake dates and filled selected missing values with documented assumptions. The `estimated_saqa_credits` field is a duration-based proxy, **not official SAQA credit data**. Imputation flags remain in `data/q4_eduvos_programmes_cleaned.csv`.
- **PostgreSQL 17 Analytics (`4.3`):** Loaded all 68 cleaned rows into `eduvos_programmes` (`itbda4_etl_db`) and ran three SQL investigations covering faculty counts and study modes, qualification types and listed intake dates, and within-faculty ranking. The 15 February 2027 date appears on 56 of 68 saved records.

---

## Reproducibility Guide

Keep the project folder in Documents and run the commands below from its root. The R scripts resolve the project from their own location. The notebooks resolve it from either the project root or the `notebooks` folder; no personal absolute path is required.

```powershell
# 1. Question 1 (Java MapReduce + R implementation)
javac src/java/HadoopStandaloneRunner.java
java -cp src/java HadoopStandaloneRunner data/map_reduce_test_docs outputs/q1_java_mapreduce_output.txt africa
Rscript src/r/q1_mapreduce_keyword_search.R africa

# 2. Question 2 & Question 3
Rscript src/r/q2_lda_topic_modelling.R
Rscript src/r/q3_webtext_api.R

# 3. Question 4 (create a local PostgreSQL 17 database first)
# Default connection: 127.0.0.1:5433, postgres, database itbda4_etl_db.
# Override with ITBDA_PG_HOST, ITBDA_PG_PORT, ITBDA_PG_USER,
# ITBDA_PG_PASSWORD and ITBDA_PG_DB as needed.
Rscript src/r/q4_etl_postgres.R
psql -h 127.0.0.1 -p 5433 -U postgres -d itbda4_etl_db -f src/sql/q4_analytics.sql
```
