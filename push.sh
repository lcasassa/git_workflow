#!/bin/bash

set -e

usage()
{
cat << EOF
usage: $0 [-h] [-p] [-f] [-d]

This script configure and launches Squish tests.

OPTIONS:
 -h  Show this message and exits.
 -p Do push.
 -f Do force push.
 -g Do not fetch.
 -d Show debug messages.
 -s Show what to do but don't do it.
EOF
}


DO_PUSH=0
DO_FORCE_PUSH=0
DO_FETCH=1
DO_GIT=1
DEBUG=0

while getopts ":hpfgsd" optname
  do
    case "$optname" in
      "p")
        #echo "Option $optname is specified"
        DO_PUSH=1
        ;;
      "f")
        #echo "Option $optname is specified"
        DO_FORCE_PUSH=1
        ;;
      "g")
        #echo "Option $optname is specified"
        DO_FETCH=0
        ;;
      "s")
        #echo "Option $optname is specified"
        DO_GIT=0
        ;;
      "d")
        #echo "Option $optname is specified"
        DEBUG=1
        ;;
      "h")
        #echo "Option $optname is specified"
        usage 
        exit
        ;;
      "?")
        echo "Unknown option $OPTARG"
        ;;
      ":")
        echo "No argument value for option $OPTARG"
        ;;
      *)
      # Should not occur
        echo "Unknown error while processing options"
        ;;
    esac
    #echo "OPTIND is now $OPTIND"
  done


if [[ $DO_FETCH -eq 1 ]]
then
    echo "$ git fetch"
    if  [[ $DO_GIT -eq 1 ]]
    then
        git fetch
    else
        echo "Run this script again if ´git fetch´ does any update."
    fi
fi

BRANCH=$(git symbolic-ref -q HEAD)
BRANCH=${BRANCH##refs/heads/}
BRANCH=${BRANCH:-HEAD}

set +e

# Checking if we need to update branch to master.
git rev-list $BRANCH | grep $(git rev-parse origin/master) > /dev/null
UPDATE=$?

# Checking if we already pushed.
git rev-list origin/$BRANCH | grep $(git rev-parse $BRANCH) > /dev/null
UPDATED=$?

# Checking if we can fast forward origin/branch to branch
git rev-list $BRANCH | grep $(git rev-parse origin/$BRANCH) > /dev/null
FORCE_PUSH=$?

# Checking if jenkins already merged the changes to to master
git rev-list origin/master|grep $(git rev-parse $BRANCH) > /dev/null
JENKINS=$?

# Checking if we can fast forward origin/master to branch
git rev-list $BRANCH|grep $(git rev-parse origin/master) > /dev/null
PUSH=$?

# Checking if we can rebase branch to include changes in master
git rev-list origin/master|grep $(git rev-parse origin/$BRANCH) > /dev/null
MERGE=$?

# Checking if there are local changes (we need git stash in some cases)
git diff --quiet
LOCAL_CHANGES=$?

# Checking if a git push will only afect current branch or not.
PUSH_ONE_BRANCH=$(git config push.default)

if [[ $DEBUG -eq 1 ]]
then
    echo "UPDATE = $UPDATE"
    echo "UPDATED = $UPDATED"
    echo "FORCE_PUSH = $FORCE_PUSH"
    echo "JENKINS = $JENKINS"
    echo "PUSH = $PUSH"
    echo "MERGE = $MERGE"
    echo "LOCAL_CHANGES = $LOCAL_CHANGES"
    echo "PUSH_ONE_BRANCH = $PUSH_ONE_BRANCH"
    #set -x
fi

set -e

if [[ $UPDATED -eq 0 ]] && [[ $UPDATE -ne 0 ]] && [[ $JENKINS -ne 0 ]]
then
    echo "Already pushed."
    if [[ $JENKINS -eq 0 ]] 
    then
        echo "Jenkins already merged this commit $(git rev-parse --short $BRANCH) to Master branch."
    else
        echo "Jenkins is testing or tests failed."
        echo "Please check: http://139.181.167.200/view/JD/job/JD_Commit/"
        echo "And look for build $BRANCH $(git rev-parse --short origin/$BRANCH)"
    fi
else

    if [[ $PUSH -eq 0 ]]
    then
        if [[ $FORCE_PUSH -ne 0 ]]
        then
            echo "Force Push!"
        else
            echo "Push!"
        fi
    else
        if [[ $LOCAL_CHANGES -ne 0 ]]
        then
            echo "$ git stash"
            if  [[ $DO_GIT -eq 1 ]]
            then
                git stash
            fi
        fi

        if [[ $MERGE -ne 0 ]] && [[ $FORCE_PUSH -eq 0 ]]
        then
            echo "Merge!"
            echo "$ git merge origin/master"
            if  [[ $DO_GIT -eq 1 ]]
            then
                git merge origin/master
            fi
        else
            echo "Rebase!"
            echo "$ git rebase origin/master"
            if  [[ $DO_GIT -eq 1 ]]
            then
                git rebase origin/master
            fi

            # Checking if we can fast forward origin/branch to branch
            # Example case where force push can change:
            #   If you squash two or more commits that are in origin/master and
            #   run this script whey will be automatically unsquashed and force
            #   will not be needed
            set +e
            git rev-list $BRANCH | grep $(git rev-parse origin/$BRANCH) > /dev/null
            FORCE_PUSH=$?
            set -e

            if [[ $DEBUG -eq 1 ]]
            then
                echo "FORCE_PUSH = $FORCE_PUSH"
            fi

            if [[ $FORCE_PUSH -ne 0 ]]
            then
                echo "Force Push!"
            fi
        fi

        if [[ $LOCAL_CHANGES -ne 0 ]]
        then
            echo "$ git stash pop"
            if  [[ $DO_GIT -eq 1 ]]
            then
                git stash pop -q
            fi
        fi
    fi

    if [[ $DO_PUSH -eq 1 ]]
    then
        if [[ $PUSH_ONE_BRANCH != "simple" ]]
        then
            echo "Please configure git to do a simple push."
            echo "run: git config push.default simple"
        else
            if [[ $FORCE_PUSH -ne 0 ]]
            then
                if [[ $DO_FORCE_PUSH -eq 1 ]]
                then
                    echo "$ git push -f"
                    if  [[ $DO_GIT -eq 1 ]]
                    then
                        git push -f
                    fi
                else
                    echo "Need to do a force push. Use ${0} -f"
                fi
            else
                echo "$ git push"
                if  [[ $DO_GIT -eq 1 ]]
                then
                    git push
                fi
            fi
        fi
    fi
fi

exit 0

