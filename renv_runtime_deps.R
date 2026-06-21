# Runtime dependencies that arsbridge uses only as Suggests, but that shell2tlf
# needs installed for the inferential statistics to COMPUTE rather than fall
# back to manual-derivation placeholders. Listed here (not executed) so that
# renv keeps them in renv.lock and `renv::restore()` installs them.
#
#   * cardx -- exact (Clopper-Pearson) confidence intervals.
#
# This file is never sourced; it exists purely for renv's dependency scan.
library(cardx)
