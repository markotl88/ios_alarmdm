#!/usr/bin/env bash
# Builds Senior_iOS_Interview_Guide.pdf from guide.md.
# Needs pandoc and xelatex (both present on this machine via MacTeX).
set -euo pipefail

cd "$(dirname "$0")"

pandoc guide.md \
  --from=markdown+pipe_tables+fenced_code_blocks+backtick_code_blocks+raw_tex \
  --output=Senior_iOS_Interview_Guide.pdf \
  --pdf-engine=xelatex \
  --toc --toc-depth=2 \
  --highlight-style=tango \
  --syntax-definition=swift.xml \
  -V documentclass=report \
  -V papersize=a4 \
  -V geometry:margin=2.2cm \
  -V fontsize=10pt \
  -V linkcolor=RoyalBlue \
  -V urlcolor=RoyalBlue \
  -V toccolor=black \
  -V colorlinks=true \
  -V mainfont="Lato" \
  -V monofont="DejaVu Sans Mono" \
  -V monofontoptions="Scale=0.78" \
  --include-in-header=header.tex

echo "built: $(pwd)/Senior_iOS_Interview_Guide.pdf"
