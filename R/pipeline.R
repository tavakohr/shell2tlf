## shell2tlf -- pipeline.R
## ---------------------------------------------------------------------------
## Thin, logger-aware wrappers around the four arsbridge stages so the Shiny
## wizard can show progress and surface each artifact. Every wrapper takes a
## `log = function(text)` callback; messages/warnings emitted by arsbridge are
## streamed to it so the user sees "what is going on" live.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

## Run `expr`, streaming any message()/cli/warning text to `log`.
with_log <- function(expr, log = NULL) {
  if (is.null(log)) return(force(expr))
  withCallingHandlers(
    force(expr),
    message = function(m) { log(sub("\n$", "", conditionMessage(m))); invokeRestart("muffleMessage") },
    warning = function(w) { log(paste0("WARNING: ", conditionMessage(w))); invokeRestart("muffleWarning") }
  )
}

## Copy `src` -> `dir/as_name`, failing loudly if the source is missing or the
## copy does not land. Returns the destination path. Use everywhere an input is
## staged so a bad copy surfaces here, not as a cryptic error two steps later.
copy_in <- function(src, dir, as_name, what = as_name) {
  if (length(src) != 1 || is.na(src) || !nzchar(src))
    stop(sprintf("%s: no source path (is arsbridge installed correctly?).", what))
  if (!file.exists(src))
    stop(sprintf("%s: source not found at %s", what, src))
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(dir, as_name)
  if (!isTRUE(file.copy(src, dest, overwrite = TRUE)) || !file.exists(dest))
    stop(sprintf("%s: failed to copy into %s", what, dir))
  dest
}

## Copy a Shiny upload (datapath + name) to `dir`, preserving the real name.
stash_upload <- function(upload, dir, as_name = NULL) {
  if (is.null(upload)) return(NULL)
  copy_in(upload$datapath, dir, as_name %||% upload$name, what = upload$name)
}

## Unzip an ADaM data archive and return the directory that holds the datasets.
prepare_adam_dir <- function(zip_path, dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  utils::unzip(zip_path, exdir = dir)
  hits <- list.files(dir, pattern = "\\.(xpt|csv)$", recursive = TRUE,
                     full.names = TRUE, ignore.case = TRUE)
  if (!length(hits)) stop("No .xpt or .csv datasets found in the ADaM archive.")
  dirname(hits[1])
}

## ---- Stage 2: Generate ARS JSON + validate --------------------------------
run_generate_ars <- function(shell_path, adam_spec_path, provider, api_key,
                             model = NULL, study_id = "STUDY-001",
                             study_name = NULL, out_dir = tempdir(), log = NULL) {
  ars_path    <- file.path(out_dir, "reporting_event.json")
  report_path <- file.path(out_dir, "spec_validation_report.xlsx")
  if (!is.null(log)) log(sprintf("Generating ARS with %s (model %s)...",
                                 provider, model %||% "default"))
  res <- with_log(
    arsbridge::spec_to_ars(
      shell_path     = shell_path,
      adam_spec_path = adam_spec_path,
      output_path    = ars_path,
      report_path    = report_path,
      study_id       = study_id,
      study_name     = study_name %||% study_id,
      provider       = provider,
      api_key        = api_key,
      model          = model
    ), log = log)
  list(
    ars_path    = ars_path,
    report_path = report_path,
    validation  = res$validation,
    n_tlfs      = res$n_tlfs %||% NA_integer_,
    n_analyses  = res$n_analyses %||% NA_integer_,
    n_warnings  = res$n_warnings %||% NA_integer_,
    result      = res
  )
}

## ---- Stage 3: Execute ARS -> tidy ARD -------------------------------------
run_execute_ard <- function(ars_path, adam_dir, log = NULL) {
  if (!is.null(log)) log("Executing ARS analyses against ADaM data...")
  ard <- with_log(arsbridge::ars_to_ard(ars_path, adam_dir), log = log)
  diagnostics <- tryCatch(arsbridge::ars_diagnostics(), error = function(e) NULL)
  flat <- function(col) vapply(col, function(x)
    if (length(x)) as.character(x[[1]]) else NA_character_, character(1))
  out_ids <- if (!is.null(ard)) unique(stats::na.omit(flat(ard[["output_id"]]))) else character(0)
  list(ard = ard, diagnostics = diagnostics, output_ids = out_ids,
       n_rows = if (is.null(ard)) 0L else nrow(ard))
}

## ---- Stage 4: Render TLFs -> Word ------------------------------------------
## (render_tlfs_docx lives in render_docx.R)
run_render_tlfs <- function(ars_path, ard, file, output_ids = NULL, log = NULL,
                            progress = NULL) {
  if (!is.null(log)) log("Rendering formatted TLF tables to Word...")
  res <- render_tlfs_docx(ars_path, ard, file, output_ids = output_ids,
                          progress = progress)
  rendered <- attr(res, "rendered")
  if (!is.null(log)) log(sprintf("Rendered %d table(s) into %s",
                                 length(rendered), basename(file)))
  list(file = file, rendered = rendered)
}

## List every output in the ARS spec with its kind + label, for the picker.
list_spec_outputs <- function(ars_path) {
  spec <- jsonlite::fromJSON(ars_path, simplifyVector = FALSE)
  sc <- function(x) if (is.null(x)) NA_character_ else as.character(unlist(x)[1])
  kind <- function(id, ot) {
    ot <- toupper(ot %||% "")
    if (ot == "LISTING" || grepl("^L", id)) return("listing")
    if (ot == "FIGURE"  || grepl("^F", id)) return("figure")
    "table"
  }
  do.call(rbind, lapply(spec[["outputs"]], function(o) {
    id <- sc(o[["id"]])
    data.frame(id = id, type = kind(id, sc(o[["outputType"]])),
               label = sc(o[["label"]]) %||% id, stringsAsFactors = FALSE)
  }))
}

## ---- Stage 4 (full): render ALL outputs via arsbridge::ars_render_all -------
## Tables + listings + figures into one Word document, returning the coverage
## manifest. Requires adam_dir (for listings/figures).
run_render_all <- function(ars_path, ard, adam_dir, file, output_ids = NULL,
                           log = NULL, progress = NULL) {
  if (!is.null(log)) log("Rendering selected outputs (tables + listings + figures) to Word...")
  manifest <- arsbridge::ars_render_all(ars_path, ard, adam_dir = adam_dir,
                                        file = file, output_ids = output_ids,
                                        progress = progress)
  n_ok <- sum(manifest$status == "rendered")
  if (!is.null(log)) log(sprintf("Rendered %d of %d outputs into %s",
                                 n_ok, nrow(manifest), basename(file)))
  list(file = file, manifest = manifest)
}
