-- ====================================================================
-- odspro Subs Workflow Management - SQL Queries
-- Database Project Demonstration
-- Author: Oliver D Siu
-- ====================================================================
-- 
-- This script contains all SQL queries from the 167_proj_demo.Rmd report.
-- Database: subbing.db (SQLite)
-- 
-- To execute this script:
-- 1. Ensure subbing.db is in the same directory
-- 2. Run with SQLite: sqlite3 subbing.db < queries.sql
-- 3. Or execute queries individually in your preferred SQL client
-- 
-- ====================================================================

-- ====================================================================
-- Query 1: Which episodes have not been subtitled?
-- ====================================================================
-- Query to count total episodes and missing subtitles by series and season
-- Uses LEFT JOIN to identify episodes without subtitle files

SELECT
    s.title AS series,
    se.season_number,
    COUNT(e.episode_id) AS total_episodes,
    COUNT(
        CASE
            WHEN f.file_id IS NULL THEN 1
        END
    ) AS missing_subtitles
FROM episodes AS e
JOIN seasons AS se
    ON e.season_id = se.season_id
JOIN series AS s
    ON se.series_id = s.series_id
LEFT JOIN files AS f
    ON f.episode_id = e.episode_id AND f.file_type = 'subtitle'
GROUP BY s.title, se.season_number
ORDER BY s.title, se.season_number;

-- ====================================================================
-- Query 2: Which are the 10 most recent status updates for subtitle files?
-- ====================================================================
-- Query to get the latest status updates for subtitle files
-- Uses CTE with ROW_NUMBER() to find most recent status per file

WITH latest_status AS (
    SELECT
        f.file_id,
        st.status_type,
        st.status_name,
        sh.changed_at,
        f.file_type,
        ROW_NUMBER() OVER (
            PARTITION BY f.file_id
            ORDER BY sh.changed_at DESC
        ) AS rn
    FROM files AS f
    JOIN status_history AS sh
        ON f.file_id = sh.file_id
    JOIN statuses AS st
        ON sh.status_id = st.status_id
    WHERE f.file_type = 'subtitle'
)
SELECT
    s.title AS series,
    se.season_number,
    e.episode_number,
    ls.file_type AS table_source,
    ls.status_type,
    ls.status_name,
    ls.changed_at
FROM latest_status AS ls
JOIN episodes AS e
    ON ls.file_id = e.episode_id
JOIN seasons AS se
    ON e.season_id = se.season_id
JOIN series AS s
    ON se.series_id = s.series_id
WHERE ls.rn = 1
ORDER BY s.title, se.season_number, e.episode_number
LIMIT 10;

-- ====================================================================
-- Query 3: Has video resolution increased with each season of The Outcast?
-- ====================================================================
-- Query to find the highest video resolution for each season of 'The Outcast'
-- Uses CTE with ROW_NUMBER() to rank resolutions by total pixel count

WITH season_resolutions AS (
    SELECT
        s.title AS series,
        se.season_number,
        vm.resolution_x,
        vm.resolution_y,
        (vm.resolution_x * vm.resolution_y) AS resolution_total,
        ROW_NUMBER() OVER (
            PARTITION BY se.season_number
            ORDER BY (vm.resolution_x * vm.resolution_y) DESC
        ) AS rn
    FROM series AS s
    JOIN seasons AS se
        ON s.series_id = se.series_id
    JOIN episodes AS e
        ON se.season_id = e.season_id
    JOIN files AS f
        ON e.episode_id = f.episode_id AND f.file_type = 'video'
    JOIN video_metadata AS vm
        ON f.file_id = vm.file_id
    WHERE s.title = 'The Outcast'
)
SELECT
    series,
    season_number,
    resolution_x,
    resolution_y,
    resolution_total
FROM season_resolutions
WHERE rn = 1
ORDER BY season_number;

-- ====================================================================
-- Query 4: Is there a correlation between subtitle line counts and video durations?
-- ====================================================================
-- Query to compare subtitle line counts with video durations
-- Uses two CTEs to join subtitle and video metadata, converts duration to seconds

WITH
    subtitle AS (
        SELECT
            e.episode_id,
            sm.line_count
        FROM episodes AS e
        JOIN files AS f
            ON e.episode_id = f.episode_id AND f.file_type = 'subtitle'
        JOIN subtitle_metadata AS sm
            ON f.file_id = sm.file_id
    ),
    video AS (
        SELECT
            e.episode_id,
            vm.duration
        FROM episodes AS e
        JOIN files f
            ON e.episode_id = f.episode_id AND f.file_type = 'video'
        JOIN video_metadata vm
            ON f.file_id = vm.file_id
    )
SELECT
    s.title AS series,
    se.season_number,
    e.episode_number,
    subtitle.line_count AS subtitle_lines,
    (CAST(SUBSTR(video.duration, 1, 2) AS INTEGER) * 3600 +
     CAST(SUBSTR(video.duration, 4, 2) AS INTEGER) * 60 +
     CAST(SUBSTR(video.duration, 7, 2) AS INTEGER)) AS video_duration_seconds
FROM series AS s
JOIN seasons AS se
    ON s.series_id = se.series_id
JOIN episodes AS e
    ON se.season_id = e.season_id
JOIN subtitle
    ON e.episode_id = subtitle.episode_id
LEFT JOIN video
    ON e.episode_id = video.episode_id
ORDER BY s.title, se.season_number, e.episode_number;

-- ====================================================================
-- Query 5: How long are the episodes of The Outcast? Are there any outliers?
-- ====================================================================
-- Query to analyze episode durations for 'The Outcast' series
-- Converts HH:MM:SS duration format to seconds for easier analysis

SELECT
    se.season_number,
    e.episode_number,
    vm.duration,
    (CAST(SUBSTR(vm.duration, 1, 2) AS INTEGER) * 3600 +
     CAST(SUBSTR(vm.duration, 4, 2) AS INTEGER) * 60 +
     CAST(SUBSTR(vm.duration, 7, 2) AS FLOAT)) AS duration_seconds
FROM series AS s
JOIN seasons AS se
    ON s.series_id = se.series_id
JOIN episodes AS e
    ON se.season_id = e.season_id
JOIN files AS f
    ON e.episode_id = f.episode_id AND f.file_type = 'video'
JOIN video_metadata AS vm
    ON f.file_id = vm.file_id
WHERE s.title = 'The Outcast'
ORDER BY duration_seconds DESC;

-- ====================================================================
-- Query 6: When did episodes receive their first revision? How long did it take?
-- ====================================================================
-- Query to calculate time between episode completion and first revision
-- Uses multiple CTEs and window functions to track status changes over time

WITH episode_status_times AS (
    SELECT
        f.episode_id,
        e.episode_number,
        se.season_number,
        s.title AS series,
        sh.changed_at,
        st.status_type,
        ROW_NUMBER() OVER (
            PARTITION BY f.episode_id, st.status_type
            ORDER BY sh.changed_at DESC
        ) AS rn_all,
        ROW_NUMBER() OVER (
            PARTITION BY f.episode_id, st.status_type
            ORDER BY sh.changed_at
        ) AS rn_revision
    FROM status_history AS sh
    JOIN statuses AS st
        ON sh.status_id = st.status_id
    JOIN files AS f
        ON sh.file_id = f.file_id
    JOIN episodes AS e
        ON f.episode_id = e.episode_id
    JOIN seasons AS se
        ON e.season_id = se.season_id
    JOIN series AS s
        ON se.series_id = s.series_id
    WHERE st.status_type IN ('all', 'revision')
)
SELECT
    series,
    season_number,
    episode_number,
    MAX(
        CASE
            WHEN status_type = 'all'
            AND rn_all = 1
            THEN changed_at
        END
    ) AS all_complete_time,
    MIN(
        CASE
            WHEN status_type = 'revision'
            AND rn_revision = 1
            THEN changed_at
        END
    ) AS revision_time,
    ROUND(
        JULIANDAY(
            MIN(
                CASE
                    WHEN status_type = 'revision'
                    AND rn_revision = 1
                    THEN changed_at
                END
            )
        ) -
        JULIANDAY(
            MAX(
                CASE
                    WHEN status_type = 'all'
                    AND rn_all = 1
                    THEN changed_at
                END
            )
        ),
        2
    ) AS days_between
FROM episode_status_times
GROUP BY series, season_number, episode_number
HAVING all_complete_time IS NOT NULL AND revision_time IS NOT NULL
ORDER BY days_between DESC
LIMIT 10;
