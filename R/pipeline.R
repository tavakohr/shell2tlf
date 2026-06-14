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

## Persistent local output folder for a study (survives restarts, unlike
## tempdir()). Returns <root>/outputs/<sanitised study id>/, created.
local_output_dir <- function(study_id = NULL, root = getwd()) {
  sub <- gsub("[^A-Za-z0-9._-]+", "_", study_id %||% "study")
  d <- file.path(root, "outputs", sub)
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  d
}

## Per-artifact subfolders for a study: ars/ (spec), ard/ (datasets), code/
## (pure-{cards} deliverables), output/ (Word). Created under the study's
## persistent output dir. Returns the four paths plus `root`.
study_dirs <- function(study_id = NULL, root = getwd()) {
  base <- local_output_dir(study_id, root)
  d <- list(
    root   = base,
    ars    = file.path(base, "ars"),
    ard    = file.path(base, "ard"),
    code   = file.path(base, "code"),
    output = file.path(base, "output")
  )
  for (p in c(d$ars, d$ard, d$code, d$output)) {
    dir.create(p, showWarnings = FALSE, recursive = TRUE)
  }
  d
}

## Pretty-print the generated ARS JSON for the in-app spec inspector. This is
## the teaching surface: it shows exactly what arsbridge built from the shell,
## so a wrong table (e.g. a flag used as a grouping instead of a where-filter)
## is visible in the spec, not just in the rendered output.
read_ars_pretty <- function(ars_path) {
  if (is.null(ars_path) || !file.exists(ars_path))
    return("(no ARS spec yet -- run Step 3)")
  txt <- tryCatch(jsonlite::prettify(paste(readLines(ars_path, warn = FALSE),
                                            collapse = "\n")),
                  error = function(e) paste(readLines(ars_path, warn = FALSE),
                                            collapse = "\n"))
  as.character(txt)
}

## --- teaching "code lab" -----------------------------------------------------
## Run a user-edited arsbridge snippet in a sandbox env where the pipeline
## objects (ars_path, adam_dir, ard, ...) are predefined, capturing console
## output, the returned value, and any error. Local tutorial use only -- this
## evaluates arbitrary R the user typed, by design, so they can learn the API.
run_code_console <- function(code, vars = list()) {
  env <- new.env(parent = globalenv())
  for (nm in names(vars)) assign(nm, vars[[nm]], envir = env)
  out <- list(value = NULL, console = character(0), error = NULL)
  tryCatch(
    out$console <- utils::capture.output(
      out$value <- withVisible(eval(parse(text = code), envir = env))$value),
    error = function(e) out$error <<- conditionMessage(e))
  out
}

## Output ids present in an ARD's output_id column.
run_execute_ard_ids <- function(ard) {
  if (is.null(ard)) return(NULL)
  unique(stats::na.omit(vapply(ard[["output_id"]],
    function(x) if (length(x)) as.character(x[[1]]) else NA_character_,
    character(1))))
}

## Format a run_code_console() result for display in a verbatim box.
summarise_run <- function(res) {
  if (!is.null(res$error)) return(paste0("ERROR: ", res$error))
  v <- res$value
  vsum <-
    if (is.data.frame(v)) sprintf("<data.frame: %d rows x %d cols>",
                                  nrow(v), ncol(v))
    else if (inherits(v, c("gt_tbl", "gtable"))) "<gt table object>"
    else if (is.character(v) && length(v) == 1) v
    else if (is.null(v)) "(NULL / invisible)"
    else paste(utils::capture.output(utils::str(v, max.level = 1)),
               collapse = "\n")
  out <- res$console
  paste(c(if (length(out)) out, "", paste0("=> returned: ", vsum)),
        collapse = "\n")
}

## Pretty one-line R vector literal, e.g. c("T-14-1-1", "T-14-2-1") or NULL.
r_char_vec <- function(x) {
  if (is.null(x) || !length(x)) return("NULL")
  sprintf("c(%s)", paste0("\"", x, "\"", collapse = ", "))
}

## Write one CSV per output_id (table/listing/figure) from the combined ARD,
## into <dir>/ard/<output_id>.csv. Returns the files written.
save_ard_per_output <- function(ard, dir, log = NULL) {
  ids <- run_execute_ard_ids(ard)
  if (!length(ids)) return(character(0))
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  oid_col <- vapply(ard[["output_id"]], function(x)
    if (length(x)) as.character(x[[1]]) else NA_character_, character(1))
  written <- character(0)
  for (oid in ids) {
    sub <- ard[which(oid_col == oid), , drop = FALSE]
    f <- file.path(dir, paste0(gsub("[^A-Za-z0-9._-]+", "_", oid), ".csv"))
    utils::write.csv(flatten_ard(sub), f, row.names = FALSE)
    written <- c(written, f)
    if (!is.null(log)) log(sprintf("Saved per-output ARD: ard/%s", basename(f)))
  }
  written
}

## Flatten an ARS ARD (list-columns) to a plain data.frame for CSV export.
## cards ARDs carry function-valued list-columns (e.g. fmt_fn) and nested
## warning/error cells, so each value is rendered defensively to a string.
flatten_ard <- function(ard) {
  df <- as.data.frame(ard, stringsAsFactors = FALSE)
  cell <- function(x) {
    if (is.null(x) || !length(x)) return(NA_character_)
    if (is.function(x)) return("<fn>")
    tryCatch(paste(unlist(x, use.names = FALSE), collapse = "; "),
             error = function(e) "<unprintable>")
  }
  df[] <- lapply(df, function(col) vapply(col, cell, character(1)))
  df
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
                             study_name = NULL, out_dir = tempdir(),
                             sap_path = NULL, code_dir = NULL, log = NULL) {
  ars_path    <- file.path(out_dir, "reporting_event.json")
  report_path <- file.path(out_dir, "spec_validation_report.xlsx")
  ## Only a .docx SAP is parseable; ignore other formats gracefully.
  if (!is.null(sap_path) && !grepl("\\.docx$", sap_path, ignore.case = TRUE)) {
    sap_path <- NULL
  }
  if (!is.null(log)) {
    log(sprintf("Generating ARS with %s (model %s)...",
                provider, model %||% "default"))
    log(sprintf(paste0("# R code running now:\n",
                       "arsbridge::spec_to_ars(\n",
                       "  shell_path     = \"%s\",\n",
                       "  adam_spec_path = \"%s\",\n",
                       "  provider       = \"%s\", model = %s,\n",
                       "  study_id       = \"%s\")"),
                basename(shell_path), basename(adam_spec_path), provider,
                if (is.null(model)) "NULL" else paste0("\"", model, "\""),
                study_id))
  }
  res <- with_log(
    arsbridge::spec_to_ars(
      shell_path     = shell_path,
      adam_spec_path = adam_spec_path,
      sap_path       = sap_path,
      output_path    = ars_path,
      report_path    = report_path,
      code_dir       = code_dir,
      study_id       = study_id,
      study_name     = study_name %||% study_id,
      provider       = provider,
      api_key        = api_key,
      model          = model
    ), log = log)
  list(
    ars_path    = ars_path,
    report_path = report_path,
    code_dir    = res$code_dir,
    code_paths  = res$code_paths,
    validation  = res$validation,
    n_tlfs      = res$n_tlfs %||% NA_integer_,
    n_analyses  = res$n_analyses %||% NA_integer_,
    n_warnings  = res$n_warnings %||% NA_integer_,
    result      = res
  )
}

## ---- Stage 3: Execute ARS -> tidy ARD -------------------------------------
run_execute_ard <- function(ars_path, adam_dir, log = NULL) {
  if (!is.null(log)) {
    log("Executing ARS analyses against ADaM data...")
    log(sprintf(paste0("# R code running now:\n",
                       "arsbridge::ars_to_ard(\n",
                       "  ars_path = \"%s\",\n",
                       "  adam_dir = \"%s\")"),
                basename(ars_path), adam_dir))
  }
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

## ---- Step 6: combine selected TLFs into a timestamped bundle ---------------
## Writes a combined {cards} script, a combined ARD CSV, and a combined Word doc
## for the chosen outputs into outputs/<study>/combined_<stamp>/. Reuses the
## per-TLF code/ deliverables emitted at Step 3.
combine_selected_tlfs <- function(study_id, ars_path, ard, adam_dir, output_ids,
                                  root = getwd(), log = NULL) {
  if (!length(output_ids)) stop("Select at least one output to combine.")
  dirs  <- study_dirs(study_id, root)
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  cdir  <- file.path(dirs$root, paste0("combined_", stamp))
  dir.create(cdir, showWarnings = FALSE, recursive = TRUE)
  files <- character(0)

  ## 1. Combined {cards} script: concatenate the per-TLF deliverables.
  combo_R <- file.path(cdir, "combined_cards.R")
  banner <- c(
    sprintf("## Combined {cards} analysis -- %d TLF(s), generated %s",
            length(output_ids), stamp),
    sprintf("## Outputs: %s", paste(output_ids, collapse = ", ")), "")
  body <- unlist(lapply(output_ids, function(oid) {
    f <- file.path(dirs$code, paste0(make.names(oid), ".R"))
    if (file.exists(f)) {
      c(sprintf("\n## ---- %s ----", oid), readLines(f, warn = FALSE))
    } else {
      sprintf("\n## ---- %s (no emitted script found) ----", oid)
    }
  }))
  writeLines(c(banner, body), combo_R)
  files <- c(files, combo_R)
  if (!is.null(log)) log(sprintf("Wrote %s", basename(combo_R)))

  ## 2. Combined ARD: subset to the selected outputs, flattened to CSV.
  combo_ard <- file.path(cdir, "combined_ard.csv")
  oid_col <- vapply(ard[["output_id"]], function(x)
    if (length(x)) as.character(x[[1]]) else NA_character_, character(1))
  sub <- ard[which(oid_col %in% output_ids), , drop = FALSE]
  utils::write.csv(flatten_ard(sub), combo_ard, row.names = FALSE)
  files <- c(files, combo_ard)
  if (!is.null(log)) {
    log(sprintf("Wrote %s (%d rows)", basename(combo_ard), nrow(sub)))
  }

  ## 3. Combined Word document for the selection.
  combo_docx <- file.path(cdir, "combined.docx")
  tryCatch({
    run_render_all(ars_path, ard, adam_dir, combo_docx,
                   output_ids = output_ids, log = log)
    files <- c(files, combo_docx)
  }, error = function(e) {
    if (!is.null(log)) log(paste("Combined docx failed:", conditionMessage(e)))
  })

  list(dir = cdir, files = files)
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
  if (!is.null(log)) {
    log("Rendering selected outputs (tables + listings + figures) to Word...")
    log(sprintf(paste0("# R code running now:\n",
                       "arsbridge::ars_render_all(\n",
                       "  ars_path = \"%s\", ard = <ARD>,\n",
                       "  adam_dir = \"%s\",\n",
                       "  file = \"%s\",\n",
                       "  output_ids = c(%s))"),
                basename(ars_path), adam_dir, basename(file),
                paste0("\"", output_ids %||% "all", "\"", collapse = ", ")))
  }
  manifest <- arsbridge::ars_render_all(ars_path, ard, adam_dir = adam_dir,
                                        file = file, output_ids = output_ids,
                                        progress = progress)
  n_ok <- sum(manifest$status == "rendered")
  if (!is.null(log)) log(sprintf("Rendered %d of %d outputs into %s",
                                 n_ok, nrow(manifest), basename(file)))
  list(file = file, manifest = manifest)
}
