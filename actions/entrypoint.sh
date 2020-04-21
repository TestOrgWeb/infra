#!/bin/sh -l

echo "Repository name: ${NAME}"

#Setting up bot name
git config --global user.email "backport@amazon.com"
git config --global user.name "Backport Bot"

git fetch

#setting up workflow URL
workflowUrl=https://github.com/TestOrgWeb/infra/actions/runs/${GITHUB_RUN_ID}

#Branches where changes need to be backported
echo "Regex specified: ${BRANCH}"
git branch -r | sed 's/origin\///' >> regex
backportingBranches=`grep "^  ${BRANCH}" regex`
rm regex
echo "------------Branch/es where changes are to be backported-----------"
echo $backportingBranches

echo "----------------Backporting now----------------"
for i in $backportingBranches; do
    echo "Current branch in process: ${i} "
    git checkout ${i}

    echo "--------creating a temp autobackport branch for raising PR-------------"
    dt=`date +"%y%m%dT%H%M"`
    autobranch=autoBackport-${i}-$dt 
    git checkout -b $autobranch origin/${i}

    echo "----------Cherry picking the commit-------------------"
    git cherry-pick ${COMMIT_SHA}
    if [ `echo $?` -ne 0 ] #failure scenario
    then
    git add .
    git commit -m "Merge Conflicts here!"
    git push origin $autobranch
    echo "BACKPORTING FAILED FOR BRANCH $i!!!!! NEED MANUAL INTERVENTION TO RESOLVE CONFLICTS"

    # Creating PR  with conflicts now
    echo "---------Creating merge conflict PR----------------"
    response=$(curl -X POST https://api.github.com/repos/${NAME}/pulls \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d "{
         \"title\":\"Backporting PR with conflicts\", 
         \"body\":\"This PR has merge conflicts. Please refer to the files changed tab, resolve and then merge\", 
         \"head\":\"$autobranch\",
         \"base\":\"${i}\"
         }")
    pull_url=$(echo "$response" | jq .html_url | sed 's/\"//g')

    # Informing the user via PR comment that it failed
    echo `curl -X POST ${COMMENT_URL} -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d "{ 
        \"body\" : \"Backporting attempted at ${COMMENTTIME} failed for branch $i!! [Workflow]($workflowUrl)\
        Manual intervention required to resolve the conflicts\n\
        [Check new PR]($pull_url) \"
        }"`

    else #success scenario
    echo "--------Push the branch to upstream-------------"
    git push origin $autobranch

    # Creating PR now
    echo "---------Creating PR----------------"
    res=$(curl -X POST https://api.github.com/repos/${NAME}/pulls \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d "{
         \"title\":\"Backporting PR\", 
         \"body\":\"Backporting the changes to previous version\", 
         \"head\":\"$autobranch\",
         \"base\":\"${i}\"
         }")
    new_pr=$(echo "$res" | jq .html_url | sed 's/\"//g')
    echo "Backporting successful for branch: $i"

    # Informing the user via PR comment that it succeeded
    echo `curl -X POST ${COMMENT_URL} -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d "{ 
        \"body\" : \"Backporting attempted at ${COMMENTTIME} successful for branch $i\
        [Workflow]($workflowUrl)\n\
        [Check new PR]($new_pr)\" 
        }"`

    fi

done