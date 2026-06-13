## shell2tlf -- app.R
## ---------------------------------------------------------------------------
## A guided Shiny wizard that walks a new user through the full arsbridge
## pipeline -- from basic study documents to publication-ready Word TLFs:
##
##   1. Upload inputs        (annotated shell + ADaM spec + ADaM data)
##   2. Configure LLM key    (Claude / OpenAI / Gemini -- session only)
##   3. Generate ARS + validate     (spec_to_ars)
##   4. Execute ARS -> tidy ARD     (ars_to_ard)
##   5. Render formatted TLFs -> Word (.docx)
##
## Clone, `renv::restore()`, then `shiny::runApp()`. No study of your own?
## Click "Load bundled example" on Step 1.

library(shiny)
library(bslib)
library(DT)
library(arsbridge)

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

STEPS <- c("1. Upload", "2. LLM Key", "3. Generate ARS",
           "4. Execute ARD", "5. Render TLFs")

ui <- page_sidebar(
  title = tagList(strong("shell2tlf"),
                  span(class = "text-muted",
                       " — annotated shell → ARS → ARD → Word TLF")),
  theme = bs_theme(version = 5, primary = "#2C6E9B"),
  sidebar = sidebar(
    width = 290,
    h6("Pipeline progress"),
    uiOutput("progress_list"),
    hr(),
    actionButton("load_example", "Load bundled example",
                 icon = icon("flask"), class = "btn-outline-secondary btn-sm w-100"),
    div(class = "small text-muted mt-2",
        "Uses the APX-DRM-301 training shell, ADaM spec, and simulated data ",
        "bundled with arsbridge. You still set your own LLM key."),
    hr(),
    uiOutput("status_badges")
  ),
  navset_hidden(
    id = "wizard",

    ## ---- Step 1: Upload ---------------------------------------------------
    nav_panel("s1", value = "s1",
      card(card_header("Step 1 — Upload your study documents"),
        card_body(
          layout_columns(col_widths = c(6, 6),
            div(
              fileInput("up_shell", "Annotated TLF shell (.docx) ★",
                        accept = c(".docx")),
              fileInput("up_spec", "ADaM spec (.xlsx / .xls / .xml) ★",
                        accept = c(".xlsx", ".xls", ".xml")),
              fileInput("up_data", "ADaM data (.zip of .xpt/.csv) ★",
                        accept = c(".zip"))
            ),
            div(
              fileInput("up_sap", "SAP (.docx / .pdf) — reference only",
                        accept = c(".docx", ".pdf")),
              fileInput("up_empty", "Empty shell (.docx) — reference only",
                        accept = c(".docx")),
              div(class = "small text-muted",
                  strong("★ = required."), " The SAP and empty shell are ",
                  "stored for your reference; arsbridge reads the annotated ",
                  "shell and ADaM spec to build the ARS, and the ADaM data to ",
                  "compute the statistics.")
            )
          ),
          uiOutput("upload_summary")
        )
      ),
      actionButton("to_s2", "Next: LLM key →", class = "btn-primary")
    ),

    ## ---- Step 2: LLM key --------------------------------------------------
    nav_panel("s2", value = "s2",
      card(card_header("Step 2 — Configure your LLM API key"),
        card_body(
          p("arsbridge calls an LLM once per TLF section for light semantic ",
            "enrichment. Pick your provider and paste your key. ",
            strong("The key stays in this session only"), " — it is never ",
            "written to disk."),
          layout_columns(col_widths = c(5, 7),
            selectInput("provider", "Provider", choices = provider_choices()),
            textInput("model", "Model (optional)", placeholder = "provider default")
          ),
          passwordInput("api_key", "API key", width = "100%"),
          uiOutput("key_hint"),
          div(class = "mt-2",
            actionButton("test_key", "Test key", icon = icon("plug"),
                         class = "btn-outline-primary"),
            actionButton("save_key", "Save key for session", icon = icon("check"),
                         class = "btn-primary")),
          uiOutput("key_status")
        )
      ),
      div(actionButton("back_s1", "← Back"),
          actionButton("to_s3", "Next: Generate ARS →", class = "btn-primary"))
    ),

    ## ---- Step 3: Generate ARS --------------------------------------------
    nav_panel("s3", value = "s3",
      card(card_header("Step 3 — Generate ARS JSON & validate the spec"),
        card_body(
          layout_columns(col_widths = c(6, 6),
            textInput("study_id", "Study ID", value = "STUDY-001"),
            textInput("study_name", "Study name", value = "")),
          div(class = "alert alert-warning small",
              icon("clock"), " This runs the LLM across every TLF section ",
              "(~6 minutes / ~40 calls for the bundled example). Keep the tab open."),
          actionButton("run_ars", "Generate ARS JSON",
                       icon = icon("gears"), class = "btn-primary"),
          downloadButton("dl_ars", "Download ARS JSON", class = "btn-outline-secondary"),
          hr(),
          h6("Validation report"),
          DT::DTOutput("validation_tbl")
        )
      ),
      div(actionButton("back_s2", "← Back"),
          actionButton("to_s4", "Next: Execute ARD →", class = "btn-primary"))
    ),

    ## ---- Step 4: Execute ARD ---------------------------------------------
    nav_panel("s4", value = "s4",
      card(card_header("Step 4 — Execute ARS into a tidy ARD"),
        card_body(
          p("Runs the ARS analyses natively with {cards} against your ADaM ",
            "data, producing one tidy Analysis Results Dataset."),
          actionButton("run_ard", "Execute ARS → ARD",
                       icon = icon("table"), class = "btn-primary"),
          uiOutput("ard_summary"),
          hr(),
          navset_tab(
            nav_panel("ARD preview", DT::DTOutput("ard_tbl")),
            nav_panel("Execution diagnostics", DT::DTOutput("diag_tbl"))
          )
        )
      ),
      div(actionButton("back_s3", "← Back"),
          actionButton("to_s5", "Next: Render TLFs →", class = "btn-primary"))
    ),

    ## ---- Step 5: Render TLFs ---------------------------------------------
    nav_panel("s5", value = "s5",
      card(card_header("Step 5 — Render formatted TLFs to Word"),
        card_body(
          uiOutput("output_picker"),
          div(class = "mt-2",
            actionButton("run_render", "Render selected TLFs → .docx",
                         icon = icon("file-word"), class = "btn-primary"),
            downloadButton("dl_docx", "Download Word document",
                           class = "btn-success")),
          hr(),
          h6("Preview (first selected output)"),
          uiOutput("tlf_preview")
        )
      ),
      actionButton("back_s4", "← Back")
    )
  ),
  ## Shared activity log.
  card(card_header("Activity log"),
       card_body(max_height = 220, verbatimTextOutput("log")))
)

server <- function(input, output, session) {
  work <- file.path(tempdir(), paste0("s2t_", session$token))
  in_dir  <- file.path(work, "inputs")
  out_dir <- file.path(work, "outputs")
  dir.create(in_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  rv <- reactiveValues(
    shell = NULL, spec = NULL, data_zip = NULL, sap = NULL, empty = NULL,
    adam_dir = NULL, key_ok = FALSE, ars_path = NULL, validation = NULL,
    ard = NULL, exec = NULL, output_ids = NULL, docx = NULL, rendered = NULL,
    log = character(0), step = 1L
  )
  addlog <- function(...) {
    rv$log <- c(rv$log, unlist(list(...)))
  }

  ## ---- progress sidebar ----
  output$progress_list <- renderUI({
    done <- c(
      !is.null(rv$shell) && !is.null(rv$spec) && !is.null(rv$data_zip),
      isTRUE(rv$key_ok),
      !is.null(rv$ars_path),
      !is.null(rv$ard),
      !is.null(rv$docx)
    )
    tags$ul(class = "list-unstyled",
      lapply(seq_along(STEPS), function(i) {
        mark <- if (done[i]) "✅" else if (i == rv$step) "➡️" else "⬜"
        tags$li(class = if (i == rv$step) "fw-bold" else "", paste(mark, STEPS[i]))
      })
    )
  })

  output$status_badges <- renderUI({
    tagList(
      div(class = "small",
        "Inputs: ", if (!is.null(rv$shell) && !is.null(rv$spec) && !is.null(rv$data_zip))
          span(class = "badge bg-success", "ready") else span(class = "badge bg-secondary", "incomplete")),
      div(class = "small mt-1",
        "LLM key: ", if (isTRUE(rv$key_ok)) span(class = "badge bg-success", "set")
          else span(class = "badge bg-secondary", "not set"))
    )
  })

  output$log <- renderText(paste(rv$log, collapse = "\n"))

  ## ---- navigation ----
  go <- function(step) { rv$step <- step; nav_select("wizard", paste0("s", step)) }
  observeEvent(input$to_s2, go(2));  observeEvent(input$back_s1, go(1))
  observeEvent(input$to_s3, go(3));  observeEvent(input$back_s2, go(2))
  observeEvent(input$to_s4, go(4));  observeEvent(input$back_s3, go(3))
  observeEvent(input$to_s5, go(5));  observeEvent(input$back_s4, go(4))

  ## ---- uploads ----
  observeEvent(input$up_shell, rv$shell <- stash_upload(input$up_shell, in_dir))
  observeEvent(input$up_spec,  rv$spec  <- stash_upload(input$up_spec,  in_dir))
  observeEvent(input$up_data,  rv$data_zip <- stash_upload(input$up_data, in_dir))
  observeEvent(input$up_sap,   rv$sap   <- stash_upload(input$up_sap,   in_dir))
  observeEvent(input$up_empty, rv$empty <- stash_upload(input$up_empty, in_dir))

  observeEvent(input$load_example, {
    rv$shell    <- file.copy(arsbridge_example("annotated_shell.docx"),
                             file.path(in_dir, "annotated_shell.docx"), overwrite = TRUE) |>
                   (\(x) file.path(in_dir, "annotated_shell.docx"))()
    rv$spec     <- { file.copy(arsbridge_example("adam_spec.xlsx"),
                               file.path(in_dir, "adam_spec.xlsx"), overwrite = TRUE)
                     file.path(in_dir, "adam_spec.xlsx") }
    rv$data_zip <- { file.copy(arsbridge_example("ADaM.zip"),
                               file.path(in_dir, "ADaM.zip"), overwrite = TRUE)
                     file.path(in_dir, "ADaM.zip") }
    updateTextInput(session, "study_id", value = "APX-DRM-301")
    updateTextInput(session, "study_name",
                    value = "PROSVALIN Phase 3 in Atopic Dermatitis (training example)")
    addlog("Loaded bundled APX-DRM-301 example (shell + ADaM spec + ADaM data).")
    showNotification("Bundled example loaded. Set your LLM key on Step 2.",
                     type = "message")
  })

  output$upload_summary <- renderUI({
    row <- function(label, path) div(class = "small",
      if (!is.null(path)) "✅ " else "⬜ ", strong(label), ": ",
      if (!is.null(path)) basename(path) else span(class = "text-muted", "not uploaded"))
    tagList(hr(),
      row("Annotated shell", rv$shell), row("ADaM spec", rv$spec),
      row("ADaM data", rv$data_zip), row("SAP (reference)", rv$sap),
      row("Empty shell (reference)", rv$empty))
  })

  ## ---- LLM key ----
  output$key_hint <- renderUI(div(class = "form-text", PROVIDERS[[input$provider]]$hint))

  observeEvent(input$test_key, {
    res <- NULL
    withProgress(message = "Testing key...", {
      res <- test_key(input$provider, input$api_key,
                      if (nzchar(input$model)) input$model else NULL)
    })
    output$key_status <- renderUI(div(
      class = if (res$ok) "alert alert-success small mt-2" else "alert alert-danger small mt-2",
      res$message))
    if (res$ok) addlog(paste("Key test OK:", res$message))
  })

  observeEvent(input$save_key, {
    if (!nzchar(input$api_key)) {
      showNotification("Enter a key first.", type = "error"); return()
    }
    set_session_key(input$provider, input$api_key,
                    if (nzchar(input$model)) input$model else NULL)
    rv$key_ok <- TRUE
    addlog(sprintf("Saved %s key for session (%s).",
                   input$provider, mask_key(input$api_key)))
    output$key_status <- renderUI(div(class = "alert alert-success small mt-2",
      sprintf("Key set for session: %s", mask_key(input$api_key))))
  })

  ## ---- Stage 2: generate ARS ----
  observeEvent(input$run_ars, {
    req(rv$shell, rv$spec)
    if (!isTRUE(rv$key_ok)) { showNotification("Set your LLM key on Step 2 first.", type = "error"); return() }
    withProgress(message = "Generating ARS JSON (LLM enrichment)...", value = 0.1, {
      tryCatch({
        gen <- run_generate_ars(
          shell_path = rv$shell, adam_spec_path = rv$spec,
          provider = input$provider, api_key = input$api_key,
          model = if (nzchar(input$model)) input$model else NULL,
          study_id = input$study_id, study_name = input$study_name,
          out_dir = out_dir, log = addlog)
        rv$ars_path   <- gen$ars_path
        rv$validation <- gen$validation
        addlog(sprintf("ARS ready: %s TLFs, %s analyses, %s warnings.",
                       gen$n_tlfs, gen$n_analyses, gen$n_warnings))
        showNotification("ARS JSON generated.", type = "message")
      }, error = function(e) { addlog(paste("ERROR:", conditionMessage(e)))
        showNotification(paste("ARS generation failed:", conditionMessage(e)), type = "error") })
    })
  })

  output$validation_tbl <- DT::renderDT({
    req(rv$validation); DT::datatable(rv$validation, options = list(pageLength = 8, scrollX = TRUE))
  })
  output$dl_ars <- downloadHandler(
    filename = function() "reporting_event.json",
    content = function(file) { req(rv$ars_path); file.copy(rv$ars_path, file) })

  ## ---- Stage 3: execute ARD ----
  observeEvent(input$run_ard, {
    req(rv$ars_path, rv$data_zip)
    withProgress(message = "Executing ARS into ARD...", value = 0.2, {
      tryCatch({
        rv$adam_dir <- prepare_adam_dir(rv$data_zip, file.path(work, "adam"))
        exec <- run_execute_ard(rv$ars_path, rv$adam_dir, log = addlog)
        rv$ard <- exec$ard; rv$exec <- exec; rv$output_ids <- exec$output_ids
        addlog(sprintf("ARD built: %s rows across %s outputs.",
                       exec$n_rows, length(exec$output_ids)))
        showNotification("ARD generated.", type = "message")
      }, error = function(e) { addlog(paste("ERROR:", conditionMessage(e)))
        showNotification(paste("ARD execution failed:", conditionMessage(e)), type = "error") })
    })
  })

  output$ard_summary <- renderUI({
    req(rv$exec)
    div(class = "alert alert-info small mt-2",
        sprintf("%s ARD rows across %s output(s): %s", rv$exec$n_rows,
                length(rv$exec$output_ids), paste(rv$exec$output_ids, collapse = ", ")))
  })
  output$ard_tbl <- DT::renderDT({
    req(rv$ard)
    df <- as.data.frame(rv$ard)
    df <- df[, intersect(c("output_id","group1_level","variable","variable_level",
                           "stat_name","stat","method_id"), names(df))]
    df[] <- lapply(df, function(c) vapply(c, function(x)
      if (length(x)) as.character(x[[1]]) else NA_character_, character(1)))
    DT::datatable(utils::head(df, 200), options = list(pageLength = 10, scrollX = TRUE))
  })
  output$diag_tbl <- DT::renderDT({
    req(rv$exec$diagnostics); DT::datatable(rv$exec$diagnostics, options = list(pageLength = 8, scrollX = TRUE))
  })

  ## ---- Stage 4: render TLFs ----
  output$output_picker <- renderUI({
    req(rv$output_ids)
    tbl_ids <- rv$output_ids[grepl("^T", rv$output_ids, ignore.case = TRUE)]
    checkboxGroupInput("pick_outputs", "Table outputs to render",
                       choices = tbl_ids, selected = tbl_ids, inline = TRUE)
  })

  observeEvent(input$run_render, {
    req(rv$ars_path, rv$ard, input$pick_outputs)
    file <- file.path(out_dir, "shell2tlf_tables.docx")
    withProgress(message = "Rendering TLFs to Word...", value = 0, {
      tryCatch({
        n <- length(input$pick_outputs)
        res <- run_render_tlfs(rv$ars_path, rv$ard, file,
          output_ids = input$pick_outputs, log = addlog,
          progress = function(i, total, oid)
            setProgress(i / total, detail = sprintf("%s (%d/%d)", oid, i, total)))
        rv$docx <- res$file; rv$rendered <- res$rendered
        showNotification(sprintf("Rendered %d table(s) to Word.", length(res$rendered)),
                         type = "message")
      }, error = function(e) { addlog(paste("ERROR:", conditionMessage(e)))
        showNotification(paste("Render failed:", conditionMessage(e)), type = "error") })
    })
  })

  output$tlf_preview <- renderUI({
    req(rv$ars_path, rv$ard, input$pick_outputs)
    oid <- input$pick_outputs[1]
    gt_tbl <- tryCatch(arsbridge::ars_render_tlf(rv$ars_path, rv$ard, oid),
                       error = function(e) NULL)
    if (is.null(gt_tbl)) return(div(class = "text-muted small", "No preview available."))
    HTML(as.character(gt::as_raw_html(gt_tbl)))
  })

  output$dl_docx <- downloadHandler(
    filename = function() "shell2tlf_tables.docx",
    content = function(file) { req(rv$docx); file.copy(rv$docx, file) })
}

shinyApp(ui, server)
