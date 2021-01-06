#!/bin/bash

echo "Hello World! Argo Vault example" >> output.txt
git add .
git commit -m "Added my Argo Output"
git push ${1}