bash
`{ for file in *.sh; do echo "## \`$file\`"; echo; echo '```bash'; cat "$file"; echo; echo '```'; echo; done; } > script.md`

{ for file in \*.sh; do echo "## \`$file\`"; echo; echo '```bash'; cat "$file"; echo; echo '```'; echo; done; } > script.md
