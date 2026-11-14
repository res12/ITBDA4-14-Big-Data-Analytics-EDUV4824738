-- ============================================================================
-- ITBDA4-14 Question 4.3: PostgreSQL Relational Analytics Script
-- Database: itbda4_etl_db | Table: eduvos_programmes (68 cleaned records)
-- ============================================================================

-- Verify PostgreSQL version and loaded table row count
SELECT version();
SELECT COUNT(*) AS total_loaded_programmes FROM eduvos_programmes;

-- Investigation 1: Faculty Portfolio Composition, NQF Depth, and Online Accessibility
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

-- Investigation 2: Qualification Tier, Intake Schedule, and Imputation Impact Analysis
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

-- Investigation 3: Window Function Ranking Highest-NQF Flagship Programmes per Faculty
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
