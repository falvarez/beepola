#!/usr/bin/env bash
set -u
MAX=50
i=0
while grep -q '^- \[ \]' TASKS.md && [ $i -lt $MAX ]; do
  i=$((i+1))
  before=$(git rev-parse HEAD)
  echo "=== Iteración $i: $(grep -m1 '^- \[ \]' TASKS.md)"

  claude -p "Lee docs/PLAN.md y TASKS.md. Trabaja SOLO en la primera tarea
marcada '- [ ]'. Impleméntala y verifícala con su criterio de prueba.
Si la verificación pasa: cámbiala a '- [x]' en TASKS.md y haz un único
git commit con el código y TASKS.md, con un mensaje descriptivo.
Si no consigues que pase, no hagas commit, añade debajo de la tarea una
línea 'BLOQUEADA: <motivo>' y termina." \
    --permission-mode acceptEdits \
    --allowedTools "Bash(git add:*)" "Bash(git commit:*)" "Bash(make:*)"

  if [ "$(git rev-parse HEAD)" = "$before" ]; then
    echo "Sin commit en esta iteración; paro para que revises."
    break
  fi
done
