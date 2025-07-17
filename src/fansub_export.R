library(tidyverse)
library(fs)

root_dir <- "E:/z_project_extract"
ffprobe_path <- "ffprobe"

get_video_metadata <- function(file_path) {
  file_path_norm <- normalizePath(file_path, winslash = "/")
  cmd_video <- sprintf('ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 "%s"', file_path_norm)
  video_info <- system(cmd_video, intern = TRUE)
  vcodec <- str_match(video_info, "codec_name=([^\r\n]+)")[,2] |> na.omit() |> first()
  width <- as.integer(str_match(video_info, "width=(\\d+)")[,2] |> na.omit() |> first())
  height <- as.integer(str_match(video_info, "height=(\\d+)")[,2] |> na.omit() |> first())
  cmd_audio <- sprintf('ffprobe -v error -select_streams a -show_entries stream=codec_name -of default=noprint_wrappers=1 "%s"', file_path_norm)
  audio_info <- system(cmd_audio, intern = TRUE)
  acodecs <- str_match(audio_info, "codec_name=([^\r\n]+)")[,2] |> na.omit() |> unique() |> paste(collapse = ", ")
  cmd_tags <- sprintf('ffprobe -v error -show_entries stream_tags -of default=noprint_wrappers=1 "%s"', file_path_norm)
  tags <- system(cmd_tags, intern = TRUE)
  duration_line <- tags[grepl("^TAG:DURATION-eng=", tags)]
  if (length(duration_line) > 0) {
    duration <- sub("^TAG:DURATION-eng=", "", duration_line[1])
  } else {
    cmd_duration <- sprintf('ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%s"', file_path_norm)
    duration_sec <- as.numeric(system(cmd_duration, intern = TRUE))
    if (!is.na(duration_sec) && duration_sec > 0) {
      h <- floor(duration_sec / 3600)
      m <- floor((duration_sec %% 3600) / 60)
      s <- duration_sec %% 60
      duration <- sprintf("%02d:%02d:%06.3f", h, m, s)
    } else {
      duration <- NA
    }
  }
  tibble(
    file_path = file_path,
    file_name = basename(file_path),
    container = tools::file_ext(file_path),
    video_codec = vcodec,
    audio_codec = acodecs,
    resolution_x = width,
    resolution_y = height,
    duration = duration
  )
}

parse_path_info <- function(path) {
  fname <- basename(path)
  matches <- regexec("S(\\d+)_E(\\d+)", fname)
  parts <- regmatches(fname, matches)
  if (length(parts[[1]]) == 3) {
    season <- as.integer(parts[[1]][2])
    episode <- as.integer(parts[[1]][3])
  } else {
    season <- NA
    episode <- NA
  }
  list(
    path = path,
    filename = fname,
    season = season,
    episode = episode
  )
}

count_ass_lines <- function(file_path) {
  lines <- readLines(file_path, warn = FALSE)
  events_idx <- which(trimws(lines) == "[Events]")
  if (length(events_idx) == 0) return(0)
  dialogue_lines <- lines[(events_idx + 1):length(lines)]
  sum(startsWith(trimws(dialogue_lines), "Dialogue:"))
}

count_srt_lines <- function(file_path) {
  lines <- readLines(file_path, warn = FALSE)
  lines <- trimws(lines)
  lines <- lines[lines != ""]
  lines <- lines[!grepl("^\\d+$", lines)]
  lines <- lines[!grepl("^\\d{2}:\\d{2}:\\d{2},\\d{3} -->", lines)]
  length(lines)
}

all_files <- dir_ls(root_dir, recurse = TRUE, type = "file")

get_series_name <- function(path) {
  parts <- strsplit(path, "[/\\\\]")[[1]]
  idx <- which(grepl("(?i)season|movies|ova", parts))
  if (length(idx) > 0 && idx[1] > 1) {
    return(parts[idx[1] - 1])
  } else if (length(parts) > 1) {
    return(parts[1])
  } else {
    return(NA)
  }
}

video_files <- all_files[str_detect(all_files, regex("\\.(mp4|mkv)$", ignore_case = TRUE))]
video_data <- map_dfr(video_files, function(f) {
  meta <- get_video_metadata(f)
  info <- parse_path_info(f)
  bind_cols(meta, as_tibble(info)) |>
    mutate(series = get_series_name(f))
})

ass_files <- all_files[str_detect(all_files, regex("\\.ass$", ignore_case = TRUE))]
subtitles_data <- map_dfr(ass_files, function(f) {
  info <- parse_path_info(f)
  tibble(
    file_path = f,
    file_name = basename(f),
    lines = count_ass_lines(f),
    type = "ass"
  ) |>
    bind_cols(as_tibble(info)) |>
    mutate(series = get_series_name(f))
})

srt_files <- all_files[str_detect(all_files, regex("\\.srt$", ignore_case = TRUE))]
timings_data <- map_dfr(srt_files, function(f) {
  info <- parse_path_info(f)
  tibble(
    file_path = f,
    file_name = basename(f),
    lines = count_srt_lines(f),
    type = "srt"
  ) |>
    bind_cols(as_tibble(info)) |>
    mutate(series = get_series_name(f))
})

txt_files <- all_files[str_detect(all_files, regex("\\.txt$", ignore_case = TRUE))]
translations_data <- map_dfr(txt_files, function(f) {
  info <- parse_path_info(f)
  tibble(
    file_path = f,
    file_name = basename(f),
    lines = length(readLines(f, warn = FALSE)),
    type = "txt"
  ) |>
    bind_cols(as_tibble(info)) |>
    mutate(series = get_series_name(f))
})

write_csv(video_data, "video_metadata.csv")
write_csv(subtitles_data, "subtitles.csv")
write_csv(timings_data, "timings.csv")
write_csv(translations_data, "translations.csv")
