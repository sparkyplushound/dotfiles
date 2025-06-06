#!/bin/bash
read -p "Enter Git username: " User
read -p "Enter Git email: " 
git config --global user.name "$User"
git config --global user.email "$Email"
echo "Finished. username set to $User and email set to $Email"
