## shell2tlf -- render_docx.R
## ---------------------------------------------------------------------------
## Renders arsbridge TLF tables to regulatory-style Word (.docx) using
## flextable + officer. Reuses arsbridge::ars_render_tlf() for all cell
## formatting (n (p%), Mean (SD), percentage scaling, row grouping) and
## re-targets the rendered wide table from GT to a Word flextable so we get
## landscape orientation, page breaks per output, and repeating headers.

`%||%` <- function(a, b) if (is.null(a)) b else a

.s2t_sc <- function(x) {
  if (is.null(x)) return(NA_character_)
  v <- unlist(x); if (length(v) == 0) return(NA_character_); as.character(v[1])
}

.s2t_find_output <- function(spec, output_id) {
  tgt <- tolower(trimws(output_id))
  for (o in spec[["outputs"]]) {
    if (identical(tolower(trimws(.s2t_sc(o[["id"]]))),   tgt)) return(o)
    if (identical(tolower(trimws(.s2t_sc(o[["name"]]))), tgt)) return(o)
  }
  NULL
}

.s2t_title <- function(out_obj) {
  if (is.null(out_obj)) return("")
  lab <- .s2t_sc(out_obj[["label"]])
  if (!is.na(lab) && nzchar(lab)) return(lab)
  d <- out_obj[["displays"]]
  if (length(d)) {
    dt <- .s2t_sc(d[[1]][["displayTitle"]])
    if (!is.na(dt) && nzchar(dt)) return(dt)
  }
  .s2t_sc(out_obj[["name"]]) %||% ""
}

.s2t_footnotes <- function(out_obj) {
  if (is.null(out_obj)) return(character(0))
  d <- out_obj[["displays"]]; if (!length(d)) return(character(0))
  notes <- character(0)
  for (s in d[[1]][["displaySections"]]) {
    if (!identical(tolower(.s2t_sc(s[["sectionType"]])), "footnote")) next
    for (ss in s[["subSections"]]) {
      t <- .s2t_sc(ss[["text"]]); if (!is.na(t) && nzchar(t)) notes <- c(notes, t)
    }
  }
  notes
}

## --- one rendered output -> a Word flextable -------------------------------

#' Build a regulatory-style flextable for one ARS output.
#' @return A flextable, or NULL if the output has no renderable rows.
output_to_flextable <- function(ars_path, ard, output_id, spec) {
  gt_tbl <- tryCatch(
    arsbridge::ars_render_tlf(ars_path, ard, output_id),
    error = function(e) NULL
  )
  if (is.null(gt_tbl)) return(NULL)

  d <- as.data.frame(gt_tbl[["_data"]], stringsAsFactors = FALSE,
                     check.names = FALSE)
  grp_col  <- intersect(c("..tfrmt_row_grp_lbl", ".tfrmt_row_grp_lbl"), names(d))
  grp_flag <- if (length(grp_col)) as.logical(d[[grp_col[1]]]) else rep(FALSE, nrow(d))
  grp_flag[is.na(grp_flag)] <- FALSE
  d <- d[, !names(d) %in% c("..tfrmt_row_grp_lbl", ".tfrmt_row_grp_lbl"),
         drop = FALSE]
  if (!ncol(d) || !nrow(d)) return(NULL)

  label_col <- names(d)[1]
  trt_cols  <- names(d)[-1]

  ## Indent category/stat rows; group-header rows stay flush-left + bold.
  lbl <- as.character(d[[label_col]])
  lbl[!grp_flag] <- paste0("    ", lbl[!grp_flag])
  d[[label_col]] <- lbl
  for (cc in trt_cols) {
    v <- as.character(d[[cc]]); v[is.na(v)] <- ""; d[[cc]] <- v
  }

  out_obj   <- .s2t_find_output(spec, output_id)
  title     <- .s2t_title(out_obj)
  footnotes <- .s2t_footnotes(out_obj)
  oid_name  <- .s2t_sc(out_obj[["name"]]); if (is.na(oid_name)) oid_name <- output_id
  thin      <- officer::fp_border(width = 1)

  ft <- flextable::flextable(d)
  ft <- flextable::set_header_labels(ft, values = stats::setNames(
    as.list(c("", trt_cols)), c(label_col, trt_cols)))
  ft <- flextable::add_header_lines(ft, values = c(oid_name, title))
  if (length(footnotes)) {
    ft <- flextable::add_footer_lines(ft, values = footnotes)
    ft <- flextable::fontsize(ft, size = 8, part = "footer")
    ft <- flextable::italic(ft, part = "footer")
  }
  if (any(grp_flag)) ft <- flextable::bold(ft, i = which(grp_flag), j = 1, part = "body")
  ft <- flextable::font(ft, fontname = "Times New Roman", part = "all")
  ft <- flextable::fontsize(ft, size = 9, part = "body")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::align(ft, j = trt_cols, align = "center", part = "all")
  ft <- flextable::align(ft, j = 1, align = "left", part = "all")
  ft <- flextable::border_remove(ft)
  ft <- flextable::hline_top(ft, part = "header", border = thin)
  ft <- flextable::hline_bottom(ft, part = "header", border = thin)
  ft <- flextable::hline_bottom(ft, part = "body", border = thin)
  ft <- flextable::autofit(ft)
  ft
}

## --- many outputs -> one landscape Word document ----------------------------

#' Render the table outputs of an ARS reporting event into one .docx.
#' @param output_ids Optional subset; default = all table outputs (ids ~ "T*")
#'   present in the ARD.
#' @param progress Optional function(i, n, oid) for Shiny progress.
#' @return `file`, invisibly; attr "rendered" lists the output ids written.
render_tlfs_docx <- function(ars_path, ard, file, output_ids = NULL,
                             progress = NULL) {
  spec    <- jsonlite::fromJSON(ars_path, simplifyVector = FALSE)
  ard_ids <- unique(stats::na.omit(vapply(ard[["output_id"]],
              function(x) if (length(x)) as.character(x[[1]]) else NA_character_,
              character(1))))
  if (is.null(output_ids)) {
    output_ids <- ard_ids[grepl("^t", ard_ids, ignore.case = TRUE)]
  } else {
    output_ids <- intersect(output_ids, ard_ids)
  }
  spec_order <- vapply(spec[["outputs"]], function(o) .s2t_sc(o[["id"]]), character(1))
  output_ids <- spec_order[spec_order %in% output_ids]

  doc <- officer::read_docx()
  doc <- officer::body_set_default_section(doc, officer::prop_section(
    page_size = officer::page_size(orient = "landscape"),
    type = "continuous"))

  rendered <- character(0)
  n <- length(output_ids)
  for (i in seq_along(output_ids)) {
    oid <- output_ids[i]
    if (!is.null(progress)) progress(i, n, oid)
    ft <- output_to_flextable(ars_path, ard, oid, spec)
    if (is.null(ft)) next
    if (length(rendered)) doc <- officer::body_add_break(doc)
    doc <- flextable::body_add_flextable(doc, ft, align = "left")
    rendered <- c(rendered, oid)
  }
  print(doc, target = file)
  attr(file, "rendered") <- rendered
  invisible(file)
}

## --- one .docx per table output (for a local archive) -----------------------

#' Write each output (table, listing, OR figure) to its own `<output_id>.docx`
#' via arsbridge::ars_render_all, so every individual TLF is archived in the
#' same regulatory format as the combined document. Needs `adam_dir` for
#' listings/figures.
#' @return character vector of the per-output files written.
render_each_output_docx <- function(ars_path, ard, adam_dir, dir,
                                    output_ids = NULL, log = NULL) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  ids <- output_ids %||% run_execute_ard_ids(ard)
  written <- character(0)
  for (oid in ids) {
    f <- file.path(dir, paste0(gsub("[^A-Za-z0-9._-]+", "_", oid), ".docx"))
    ok <- tryCatch({
      arsbridge::ars_render_all(ars_path, ard, adam_dir = adam_dir,
                                file = f, output_ids = oid)
      file.exists(f)
    }, error = function(e) FALSE)
    if (isTRUE(ok)) {
      written <- c(written, f)
      if (!is.null(log)) log(sprintf("Saved individual output: %s", basename(f)))
    }
  }
  written
}

#' Write each table output to its own `<output_id>.docx` in `dir`.
#' Tables only — listings/figures stay in the combined arsbridge document.
#' @return character vector of the per-table files written.
render_each_table_docx <- function(ars_path, ard, dir, output_ids = NULL,
                                   log = NULL) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  spec    <- jsonlite::fromJSON(ars_path, simplifyVector = FALSE)
  ard_ids <- unique(stats::na.omit(vapply(ard[["output_id"]],
              function(x) if (length(x)) as.character(x[[1]]) else NA_character_,
              character(1))))
  ids <- if (is.null(output_ids)) ard_ids else intersect(output_ids, ard_ids)
  ids <- ids[grepl("^t", ids, ignore.case = TRUE)]   # tables only

  written <- character(0)
  for (oid in ids) {
    f <- file.path(dir, paste0(gsub("[^A-Za-z0-9._-]+", "_", oid), ".docx"))
    one <- tryCatch(render_tlfs_docx(ars_path, ard, f, output_ids = oid),
                    error = function(e) NULL)
    if (!is.null(one) && length(attr(one, "rendered"))) {
      written <- c(written, f)
      if (!is.null(log)) log(sprintf("Saved individual table: %s", basename(f)))
    }
  }
  written
}
