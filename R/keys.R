## shell2tlf -- keys.R
## ---------------------------------------------------------------------------
## Session-only LLM key handling. We NEVER write the user's key to .Renviron
## or disk -- it lives only in this R session's environment, so a cloned/shared
## app cannot leak it. Supports Anthropic (Claude), OpenAI, and Gemini, matching
## the providers arsbridge::spec_to_ars() accepts.

PROVIDERS <- list(
  anthropic = list(
    label   = "Anthropic (Claude)",
    env     = "ANTHROPIC_API_KEY",
    default = "claude-sonnet-4-6",
    models  = c("claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-8"),
    chat    = function(model, key) ellmer::chat_anthropic(model = model, api_key = key),
    hint    = "Key starts with 'sk-ant-'. Get one at console.anthropic.com."
  ),
  openai = list(
    label   = "OpenAI (GPT)",
    env     = "OPENAI_API_KEY",
    default = "gpt-4o",
    models  = c("gpt-4o-mini", "gpt-4o", "gpt-4.1"),
    chat    = function(model, key) ellmer::chat_openai(model = model, api_key = key),
    hint    = "Key starts with 'sk-'. Get one at platform.openai.com."
  ),
  gemini = list(
    label   = "Google (Gemini)",
    env     = "GEMINI_API_KEY",
    default = "gemini-1.5-pro",
    models  = c("gemini-1.5-flash", "gemini-1.5-pro", "gemini-2.0-flash"),
    chat    = function(model, key) ellmer::chat_google_gemini(model = model, api_key = key),
    hint    = "Get one at aistudio.google.com/apikey."
  )
)

provider_choices <- function() {
  stats::setNames(names(PROVIDERS), vapply(PROVIDERS, `[[`, character(1), "label"))
}

mask_key <- function(key) {
  key <- as.character(key %||% "")
  n <- nchar(key)
  if (n == 0) return("(none)")
  if (n <= 8) return(strrep("*", n))
  paste0(substr(key, 1, 4), strrep("*", max(0, n - 8)), substr(key, n - 3, n))
}

## Put the key in the session env + mark the active provider so any arsbridge
## code that reads the environment picks it up. Returns the provider invisibly.
set_session_key <- function(provider, key, model = NULL) {
  provider <- match.arg(provider, names(PROVIDERS))
  p <- PROVIDERS[[provider]]
  args <- list(key); names(args) <- p$env
  do.call(Sys.setenv, args)
  Sys.setenv(ARS_LLM_PROVIDER = provider)
  options(ars.llm.provider = provider)
  invisible(provider)
}

clear_session_keys <- function() {
  for (p in PROVIDERS) try(Sys.unsetenv(p$env), silent = TRUE)
  Sys.unsetenv("ARS_LLM_PROVIDER")
  options(ars.llm.provider = NULL)
}

#' Lightweight liveness check: one tiny round-trip to the provider.
#' @return list(ok = logical, message = character).
test_key <- function(provider, key, model = NULL) {
  provider <- match.arg(provider, names(PROVIDERS))
  p <- PROVIDERS[[provider]]
  key <- as.character(key %||% "")
  if (!nzchar(key)) return(list(ok = FALSE, message = "No key entered."))
  model <- model %||% p$default
  tryCatch({
    chat <- p$chat(model, key)
    ans  <- chat$chat("Reply with the single word: OK")
    list(ok = TRUE, message = sprintf("%s reachable (model %s).", p$label, model))
  }, error = function(e) {
    list(ok = FALSE, message = conditionMessage(e))
  })
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
