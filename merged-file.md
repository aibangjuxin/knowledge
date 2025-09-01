bash
`{ for file in *.sh; do echo "## \`$file\`"; echo; echo '```bash'; cat "$file"; echo; echo '```'; echo; done; } > script.md`
```shell
{ for file in \*.sh; do echo "## \`$file\`"; echo; echo '```bash'; cat "$file"; echo; echo '```'; echo; done; } > script.md
```
