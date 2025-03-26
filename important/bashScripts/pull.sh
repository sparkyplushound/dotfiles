#!/bin/bash

echo "enter the url of the repo: "

read url

git pull "$url"

echo "repo downloaded. don't break anything."
