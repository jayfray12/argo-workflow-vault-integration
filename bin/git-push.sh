
echo ${1}

git config user.name "Argo"
git config user.email "you@example.com"

echo "Hello World! Argo Vault example" >> output.txt
git add .
git commit -m "Added my Argo Output"
git push ${1}