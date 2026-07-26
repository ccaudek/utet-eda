#!/usr/bin/env bash
# =============================================================
#  Deploy del sito Quarto UTET EDA.
#
#  Flusso:
#    1. verifica repository, configurazione e strumenti;
#    2. legge dall'_quarto.yml tutte le pagine configurate;
#    3. pulisce completamente l'output precedente;
#    4. esegue il rendering Quarto;
#    5. verifica che tutte le pagine previste siano state create;
#    6. controlla i link interni;
#    7. esegue commit/push e pubblica su gh-pages.
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MSG="${1:-aggiornamento del sito utet-eda}"

EXPECTED_SLUG="utet-eda"
EXPECTED_SITE_URL="https://ccaudek.github.io/utet-eda/"
EXPECTED_REPO_FRAGMENT="ccaudek/utet-eda"
EXPECTED_TITLE="Analisi esplorativa dei dati in psicologia"

YML="_quarto.yml"
INDEX="index.qmd"
LINK_CHECK="R/check_link.R"

fail() {
  printf 'ERRORE: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "comando richiesto non trovato: $1"
}

read_yaml_scalar() {
  local key="$1"

  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
      sub("^[^:]*:[[:space:]]*", "", $0)
      gsub(/[\047\042]/, "", $0)
      sub(/[[:space:]]+#.*$/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$YML"
}

printf '→ verifica ambiente e identità del progetto\n'

need_cmd quarto
need_cmd Rscript
need_cmd git
need_cmd ghp-import
need_cmd awk
need_cmd sed
need_cmd grep
need_cmd find

test -f "$YML" ||
  fail "manca $YML"

test -f "$INDEX" ||
  fail "manca $INDEX"

test -f "$LINK_CHECK" ||
  fail "manca $LINK_CHECK"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail "la directory non è un repository Git"

SITE_URL="$(read_yaml_scalar site-url)"
REPO_URL="$(read_yaml_scalar repo-url)"
OUT="$(read_yaml_scalar output-dir)"
OUT="${OUT:-docs}"

case "$OUT" in
  ""|"/"|"."|".."|../*|/*)
    fail "output-dir non sicura: '$OUT'"
    ;;
esac

[[ "$SITE_URL" == "$EXPECTED_SITE_URL" ]] ||
  fail "site-url inatteso: '${SITE_URL:-assente}'"

[[ "$REPO_URL" == *"$EXPECTED_REPO_FRAGMENT"* ]] ||
  fail "repo-url non coerente con $EXPECTED_SLUG: '${REPO_URL:-assente}'"

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"

[[ -n "$ORIGIN_URL" ]] ||
  fail "remote Git 'origin' non configurato"

[[ "$ORIGIN_URL" == *"$EXPECTED_REPO_FRAGMENT"* ]] ||
  fail "remote origin non coerente con $EXPECTED_SLUG: '$ORIGIN_URL'"

grep -Fq "$EXPECTED_TITLE" "$INDEX" ||
  fail "index.qmd non sembra appartenere al sito $EXPECTED_SLUG"

grep -Fqi "Inferenza bayesiana in psicologia" "$INDEX" ||
  fail "index.qmd non contiene il raccordo con il manuale"

printf '→ lettura delle pagine configurate\n'

QMD_FILES=()

while IFS= read -r qmd_file; do
  QMD_FILES[${#QMD_FILES[@]}]="$qmd_file"
done < <(
  sed 's/[[:space:]]*#.*$//' "$YML" |
    grep -Eo '[[:alnum:]_./-]+\.qmd' |
    awk '!seen[$0]++'
)

(( ${#QMD_FILES[@]} > 0 )) ||
  fail "nessuna pagina .qmd trovata nella configurazione"

for sorgente in "${QMD_FILES[@]}"; do
  test -f "$sorgente" ||
    fail "pagina configurata ma assente: $sorgente"
done

printf '  %d pagine Quarto configurate\n' "${#QMD_FILES[@]}"

printf '→ pulizia completa di %s\n' "$OUT"
rm -rf -- "$OUT"

printf '→ render\n'
quarto render --clean

printf '→ verifica output\n'

test -d "$OUT" ||
  fail "Quarto non ha creato la directory $OUT"

for sorgente in "${QMD_FILES[@]}"; do
  destinazione="$OUT/${sorgente%.qmd}.html"

  test -f "$destinazione" ||
    fail "pagina attesa non generata: $destinazione"
done

test -f "$OUT/index.html" ||
  fail "manca la homepage generata: $OUT/index.html"

grep -Fqi "$EXPECTED_TITLE" "$OUT/index.html" ||
  fail "la homepage generata non contiene il titolo atteso"

# 04_r_programming.qmd è attualmente escluso dallo YAML.
# Dopo una pulizia completa, la vecchia pagina non deve sopravvivere.
if ! printf '%s\n' "${QMD_FILES[@]}" |
  grep -qx 'chapters/R/04_r_programming.qmd'; then

  test ! -e "$OUT/chapters/R/04_r_programming.html" ||
    fail "è rimasta una pagina obsoleta esclusa dallo YAML"
fi

touch "$OUT/.nojekyll"

printf '→ controllo link interni\n'
Rscript "$LINK_CHECK"

HTML_COUNT="$(
  find "$OUT" -type f -name '*.html' |
    wc -l |
    tr -d '[:space:]'
)"

[[ "$HTML_COUNT" =~ ^[0-9]+$ ]] ||
  fail "impossibile contare le pagine HTML"

(( HTML_COUNT >= ${#QMD_FILES[@]} )) ||
  fail "output incompleto: trovate $HTML_COUNT pagine HTML"

printf '  %s pagine HTML verificate\n' "$HTML_COUNT"

printf '→ commit dei sorgenti e dell’output\n'
git add -A

if git diff --cached --quiet; then
  printf '  (niente da committare)\n'
else
  git commit -m "$MSG"
fi

git push

printf '→ pubblicazione di %s su gh-pages\n' "$OUT"
ghp-import -n -p -f "$OUT"

printf 'Fatto. Pubblicato %s.\n' "$EXPECTED_SLUG"
