library(tidyverse)
library(DBI)
library(RSQLite)

con <- dbConnect(SQLite(), "subbing.db")

tables <- c(
  "series", "seasons", "episodes",
  "status_types", "status_names", "statuses",
  "status_history", "files", "video_metadata",
  "subtitle_metadata", "script_metadata"
)
for (tbl in tables) {
  dbExecute(con, paste0("DROP TABLE IF EXISTS ", tbl))
}

dbExecute(con, "
CREATE TABLE series (
  series_id INTEGER PRIMARY KEY,
  title TEXT UNIQUE
);")
dbExecute(con, "
CREATE TABLE seasons (
  season_id INTEGER PRIMARY KEY,
  series_id INTEGER,
  season_number INTEGER,
  FOREIGN KEY (series_id) REFERENCES series(series_id)
);")
dbExecute(con, "
CREATE TABLE episodes (
  episode_id INTEGER PRIMARY KEY,
  season_id INTEGER,
  series_id INTEGER,
  episode_number INTEGER,
  FOREIGN KEY (season_id) REFERENCES seasons(season_id),
  FOREIGN KEY (series_id) REFERENCES series(series_id)
);")
dbExecute(con, "
CREATE TABLE statuses (
  status_id INTEGER PRIMARY KEY,
  status_type TEXT,
  status_name TEXT
);")
dbExecute(con, "
CREATE TABLE status_history (
  history_id INTEGER PRIMARY KEY,
  file_id INTEGER,
  status_id INTEGER,
  changed_at TIMESTAMP,
  FOREIGN KEY (file_id) REFERENCES files(file_id),
  FOREIGN KEY (status_id) REFERENCES statuses(status_id)
);")
dbExecute(con, "
CREATE TABLE files (
  file_id INTEGER PRIMARY KEY,
  file_type TEXT,
  file_name TEXT,
  episode_id INTEGER,
  FOREIGN KEY (episode_id) REFERENCES episodes(episode_id)
);")
dbExecute(con, "
CREATE TABLE video_metadata (
  file_id INTEGER PRIMARY KEY,
  container TEXT,
  video_codec TEXT,
  audio_codec TEXT,
  resolution_x INTEGER,
  resolution_y INTEGER,
  duration TIME,
  FOREIGN KEY (file_id) REFERENCES files(file_id)
);")
dbExecute(con, "
CREATE TABLE subtitle_metadata (
  file_id INTEGER PRIMARY KEY,
  line_count INTEGER,
  FOREIGN KEY (file_id) REFERENCES files(file_id)
);")
dbExecute(con, "
CREATE TABLE script_metadata (
  file_id INTEGER PRIMARY KEY,
  line_count INTEGER,
  FOREIGN KEY (file_id) REFERENCES files(file_id)
);")

subtitles <- read_csv("subtitles.csv")
timings <- read_csv("timings.csv")
translations <- read_csv("translations.csv")
video_csv <- read_csv("video_metadata.csv")

series_tbl <-
  bind_rows(subtitles, timings, translations, video_csv) |>
  distinct(series) |>
  arrange(series) |>
  mutate(series_id = row_number(), title = series) |>
  select(series_id, title)
dbWriteTable(con, "series", series_tbl, append = TRUE)

seasons_tbl <-
  bind_rows(subtitles, timings, translations, video_csv) |>
  distinct(series, season) |>
  left_join(series_tbl, by = c("series" = "title")) |>
  rename(season_number = season) |>
  arrange(series_id, season_number) |>
  mutate(season_id = row_number()) |>
  select(season_id, series_id, season_number)
dbWriteTable(con, "seasons", seasons_tbl, append = TRUE)

episodes_tbl <-
  bind_rows(subtitles, timings, translations, video_csv) |>
  distinct(series, season, episode) |>
  left_join(series_tbl, by = c("series" = "title")) |>
  left_join(seasons_tbl, by = c("series_id", "season" = "season_number")) |>
  arrange(series_id, season, episode) |>
  mutate(
    episode_id = row_number(),
    episode_number = episode
  ) |>
  select(episode_id, season_id, series_id, episode_number)
dbWriteTable(con, "episodes", episodes_tbl, append = TRUE)

statuses_tbl <-
  tribble(
    ~status_id, ~status_type,   ~status_name,
    1,          "all",          "all",
    2,          "revision",     "in progress",
    3,          "revision",     "all",
    4,          "translation",  "in progress",
    5,          "translation",  "all",
    6,          "all",          "in progress"
  )
dbWriteTable(con, "statuses", statuses_tbl, append = TRUE)

process_files <- function(df, file_type) {
  df |>
    distinct(file_name, .keep_all = TRUE) |>
    mutate(file_type = file_type) |>
    select(file_type, file_name, series, season, episode)
}
files_all <- bind_rows(
  process_files(subtitles, "subtitle"),
  process_files(timings, "timing"),
  process_files(translations, "translation"),
  process_files(video_csv, "video")
) |>
  mutate(file_id = row_number()) |>
  left_join(series_tbl, by = c("series" = "title")) |>
  left_join(seasons_tbl, by = c("series_id", "season" = "season_number")) |>
  left_join(episodes_tbl, by = c("season_id", "episode" = "episode_number")) |>
  select(
    file_id, file_type, file_name,
    series_id = series_id.x,
    season_id,
    episode_id,
    series, season, episode
  )
dbWriteTable(
  con,
  "files",
  files_all |> select(file_id, file_type, file_name, episode_id),
  append = TRUE
)

# Custom time initialization
status_data <- tribble(
  ~series, ~season, ~status_id, ~changed_at,
  "To Be Hero", 1, 1, "4/2/2018 6:14 AM",
  "The Outcast", 1, 1, "1/20/2021 9:47 AM",
  "The Outcast", 1, 2, "2/23/2025 3:23 AM",
  "The Outcast", 2, 4, "2/8/2025 12:57 PM",
  "The Outcast", 3, 1, "3/14/2020 2:49 PM",
  "The Outcast", 4, 1, "11/30/2022 1:49 PM",
  "The Outcast", 4, 3, "2/12/2025 10:48 PM",
  "The Outcast", 5, 1, "6/23/2024 11:23 AM"
) |>
  mutate(changed_at = mdy_hm(changed_at)) |>
  left_join(series_tbl, by = c("series" = "title")) |>
  left_join(seasons_tbl, by = c("series_id", "season" = "season_number")) |>
  left_join(
    files_all |> filter(file_type == "subtitle") |>
      select(file_id, season_id, episode_id),
    by = c("season_id")
  ) |>
  filter(!is.na(file_id) & !is.na(status_id)) |>
  mutate(history_id = row_number()) |>
  mutate(changed_at = format(as.POSIXct(changed_at), "%Y-%m-%d %H:%M:%S")) |>
  select(history_id, file_id, status_id, changed_at)
dbWriteTable(con, "status_history", status_data, append = TRUE)

subtitle_metadata <-
  subtitles |>
  select(file_name, lines) |>
  inner_join(files_all |> filter(file_type == "subtitle"), by = "file_name") |>
  transmute(file_id, line_count = lines)
dbWriteTable(con, "subtitle_metadata", subtitle_metadata, append = TRUE)

script_metadata <-
  translations |>
  select(file_name, lines) |>
  inner_join(files_all |> filter(file_type == "translation"), by = "file_name") |>
  transmute(file_id, line_count = lines)
dbWriteTable(con, "script_metadata", script_metadata, append = TRUE)

video_metadata <-
  video_csv |>
  inner_join(files_all |> filter(file_type == "video"), by = "file_name") |>
  transmute(
    file_id,
    container,
    video_codec,
    audio_codec,
    resolution_x,
    resolution_y,
    duration = as.character(duration)
  )
dbWriteTable(con, "video_metadata", video_metadata, append = TRUE)

dbDisconnect(con)
