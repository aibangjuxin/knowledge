find . -name '.![0-9]*!*' -exec ls -la {} \;
find . -type f -name '.![0-9]*!*' -exec xattr -c {} \; -exec rm -f {} \;

