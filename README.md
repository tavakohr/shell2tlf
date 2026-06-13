# shell2tlf

**Annotated Word shell → ARS JSON → tidy ARD → publication-ready Word TLFs — in one guided Shiny app.**

`shell2tlf` is the interactive front end for the [`arsbridge`](https://github.com/tavakohr/arsbridge)
pipeline. A new user uploads their basic study documents, sets their own LLM API
key, and the app walks them through four stages — showing what is happening at
each step — until it produces formatted clinical tables as a Word (`.docx`) file.

```
1. Upload inputs        annotated shell + ADaM spec + ADaM data
2. Configure LLM key    Claude / OpenAI / Gemini  (session only, never written to disk)
3. Generate ARS + validate     arsbridge::spec_to_ars()
4. Execute ARS -> tidy ARD     arsbridge::ars_to_ard()
5. Render formatted TLFs -> Word   arsbridge::ars_render_tlf() + flextable/officer
```

No study of your own? Click **"Load bundled example"** on Step 1 to use the
APX-DRM-301 training shell, ADaM spec, and simulated data shipped with
`arsbridge` (you still supply your own LLM key).

---

## Quick start (clone and run)

Requires **R ≥ 4.2** and an LLM API key (Anthropic, OpenAI, or Google).

```bash
git clone https://github.com/<you>/shell2tlf.git
cd shell2tlf
```

```r
# 1. Restore the exact package versions (first run downloads them)
install.packages("renv")          # if you don't have it
renv::restore()

# 2. Launch the app
shiny::runApp()
```

The app opens in your browser. Work top-to-bottom through the five steps in the
sidebar.

---

## What you need to provide

| Input | Required | Used by |
|---|---|---|
| **Annotated TLF shell** (`.docx`) | ✅ | `spec_to_ars()` — variable→row ground truth |
| **ADaM spec** (`.xlsx`/`.xls` or define.xml) | ✅ | `spec_to_ars()` — validates annotations |
| **ADaM data** (`.zip` of `.xpt`/`.csv`) | ✅ | `ars_to_ard()` — computes the statistics |
| SAP (`.docx`/`.pdf`) | optional | reference only (not parsed) |
| Empty shell (`.docx`) | optional | reference only (not parsed) |
| **LLM API key** | ✅ | semantic enrichment, one call per TLF section |

> The ADaM **spec** describes the variables; the ADaM **data** holds the values.
> You need both — the spec alone cannot populate a table with numbers.

### Your API key is session-only

The key you paste is set in the running R session's environment and used to build
the ARS. It is **never** written to `.Renviron` or any file, and `.gitignore`
excludes secrets. Close the app and it is gone.

---

## Current coverage (honest status)

`shell2tlf` renders every **table** output that `arsbridge` can currently
execute. On the bundled 40-output example that is the supported summary tables
(disposition, demographics, exposure, AE, efficacy counts). Known gaps, tracked
as the `arsbridge` roadmap:

- **Some table shells produce no rows** — a few analyses are skipped in
  `ars_to_ard()` (variable-not-found / unsupported shapes).
- **By-visit / by-parameter continuous tables** can show blank cells — row
  grouping in `ars_to_tfrmt()` does not yet split rows by analysis/subset.
- **Listings (`L_*`)** and **figures (`F_*`)** are not yet rendered — they need
  dedicated renderers.

The app reports exactly which outputs it rendered after Step 5.

---

## Project layout

```
shell2tlf/
  app.R              Shiny wizard (UI + server)
  R/
    keys.R           LLM provider / session-key handling
    pipeline.R       logger-aware wrappers for the four stages
    render_docx.R    ARD/GT tables -> landscape Word via flextable + officer
  renv.lock          pinned package versions for reproducible restore
  README.md
```

---

## Notes

- Step 3 calls the LLM across every TLF section — for the bundled example this is
  ~40 calls and takes several minutes. Keep the browser tab open.
- Output is a single landscape `.docx` with one table per page; download it from
  Step 5.
- `arsbridge` is installed from GitHub via `renv` — see `renv.lock`.
