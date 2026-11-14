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
- **Architecture:** Implemented in both Apache Hadoop Java (`KeywordSearchMapper`, `KeywordSearchReducer`, `KeywordSearchDriver` + `core-site.xml`, `hdfs-site.xml`, `mapred-site.xml` + standalone JDK 21 executor `HadoopStandaloneRunner`) and R (`src/r/q1_mapreduce_keyword_search.R`).
- **Dynamic Configuration:** Target keyword is passed via runtime CLI argument / Hadoop `Configuration` (`search.keyword`) and compiled with `Pattern.CASE_INSENSITIVE`.
- **Demonstration Result (`keyword = "africa"`):** Identified **22 case-insensitive occurrences** across 4 of the 7 documents (`doc1.txt`: 3, `doc2.txt`: 5, `doc3.txt`: 9, `doc5.txt`: 5; `doc4.txt`/`doc6.txt`/`doc7.txt`: 0), reporting exact 1-based row indices, character offsets, and word column indices (`12` exact whole-word + `10` inflected forms such as `African` / `Africa’s`).

### Question 2 (20 Marks): Latent Dirichlet Allocation (LDA) Topic Modelling
- **Preprocessing (`tm`):** Loaded all 10 articles from `news.zip` into `data.frame(file_name, content)` and removed between 41.5% and 49.8% noise per file, yielding a `10 x 1,086` Document-Term Matrix (87.5% sparsity).
- **Topic Discovery (`topicmodels`, Gibbs `k = 4`):**
  1. **Topic 1 — Coalition Politics & Governance** (`government`, `coalition`, `governments`, `role`, `relationships`) -> Dominant in `news_8.txt` (96.1%).
  2. **Topic 2 — Severe Weather, Crime & Security** (`police`, `cape`, `cold`, `expected`, `weather`) -> Dominant in `news_4.txt` (92.5%), `news_5.txt` (93.5%), `news_10.txt` (80.6%).
  3. **Topic 3 — Labour, Public Service & Integrity** (`public`, `south`, `africa`, `department`, `psc`) -> Dominant in `news_3.txt` (76.2%), `news_7.txt` (86.8%), `news_9.txt` (86.5%).
  4. **Topic 4 — Education, Eskom & Accountability** (`invoices`, `service`, `days`, `national`, `departments`) -> Dominant in `news_1.txt` (73.0%), `news_2.txt` (99.5%), `news_6.txt` (94.4%).
- **Visualisations:** Multi-topic Beta bar grid (`q2_lda_top_terms_faceted.png`), Document-Topic Gamma heatmap (`q2_lda_doc_topic_heatmap.png`), and 4-panel word clouds (`q2_lda_topic_wordclouds.png`).

### Question 3 (30 Marks): WebText API & Extractive Text Summarisation
- **Fair-Use Extraction (`rvest` / `httr`):** Scraped *Can language become environmental data?* (Eurac Research, CC BY 4.0) with transparent user-agent headers into a structured R object (`19 sentences`, `511 raw words -> 313 clean tokens`, `38.7%` noise stripped).
- **Dual Extractive Summarisation:**
  - **Graph TextRank (`igraph`):** Selected Sentences 4, 6, 8, 14, 19 (`177 / 511` words, 65.4% compression, 46.7% top-15 TF-IDF keyword coverage).
  - **TF-IDF Weighted Scoring:** Selected Sentences 6, 7, 10, 17, 18 (`84 / 511` words, 83.6% compression, 93.3% top-15 TF-IDF keyword coverage). Sentence 6 was jointly prioritised by both models.

### Question 4 (25 Marks): End-to-End ETL in R & PostgreSQL 17
- **Use Case & Extraction (`4.1`):** Scraped **68 live Eduvos qualification cards** from `https://www.eduvos.com/qualifications/` (`robots.txt` `Allow: /`) using CSS selectors and regex, capturing authentic data anomalies: 1 missing `data-learning-mode` attribute, 20 records lacking explicit NQF tiers, 15 lacking explicit durations, 67 truncated ellipsis descriptions, 68 unparsed `"Start date: ..."` strings, 6 Unicode dashes, and 2 misplaced Pre-Degree programmes (`Information Technology` and `Science`) listed under `Humanities and Arts`.
- **Transformation & Imputation (`4.2`):** Applied Unicode/whitespace denoising, corrected the 2 faculty misclassifications, parsed ISO `YYYY-MM-DD` intake dates, deterministically imputed all missing NQF levels, durations, SAQA credits, and delivery modes (`0` remaining NAs), and exported `data/q4_eduvos_programmes_cleaned.csv`.
- **PostgreSQL 17 Analytics (`4.3`):** Loaded all 68 cleaned rows into `eduvos_programmes` (`itbda4_etl_db`) and executed three SQL investigations: Faculty portfolio & online accessibility aggregation (`Technology` leads with 21 programmes at 100% online availability; `Law` leads academic depth at NQF 8.00 / 360 credits), Qualification tier & intake cohort distribution (`2027-02-15` accounts for 56 of 68 programmes), and `DENSE_RANK()` flagship identification per faculty.

---

## Reproducibility Guide

```powershell
# 1. Question 1 (Java MapReduce + R implementation)
javac src/java/HadoopStandaloneRunner.java
java -cp src/java HadoopStandaloneRunner data/map_reduce_test_docs outputs/q1_java_mapreduce_output.txt africa
Rscript src/r/q1_mapreduce_keyword_search.R africa

# 2. Question 2 & Question 3
Rscript src/r/q2_lda_topic_modelling.R
Rscript src/r/q3_webtext_api.R

# 3. Question 4 (PostgreSQL 17 on port 5433 -> R ETL -> psql verification)
Rscript src/r/q4_etl_postgres.R
psql -h 127.0.0.1 -p 5433 -U postgres -d itbda4_etl_db -f src/sql/q4_analytics.sql
```
