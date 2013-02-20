#!/bin/bash

# flags
debug=1

# tools
debug()
{
    if [ -n "$debug" ]; then
        echo "$@" >&2
    fi
}

#overload arguments

# git cloc 
#   --since, --after        the beginning date, "2012-01-01"
#   --until,--before        the end date, "2012-02-01"
#   --author|--committer    (no effect)the author and user, "Kael". 
#                               default(or "*") to all user. use -u instead of -a to avoid misunderstanding of "all"; 
#   -b, --branch            (no effect)default to "master", if "*" will count lines of all branches without duplication
#   -r, --recursive         recursively search all sub directories of the specified working directory
#   -c, --cwd               cwd
after=
before=
author=
branch=master
recursive=
recurse_depth=10
this_month=
cwd="$PWD"


while [[ $# -gt 0 ]]; do
    opt="$1"
    shift
    case "$opt" in
        --since|--after)
            after="$1"; debug "after: $after"
            shift
            ;;

        --until|--before)
            before="$1"; debug "before: $before"
            shift
            ;;

        # TODO -> BUG
        --author|--committer)
            author="$1"; debug "author: $author"
            shift
            ;;

        -b|--branch)
            branch="$1"; debug "branch: $branch"
            shift
            ;;

        -r|--recursive)
            recursive=1; debug "recursive: on"
            # no shift
            ;;

        --recurse-depth)
            recurse_depth="$1"; debug "recurse depth: $recurse_depth"
            shift
            ;;

        # TODO
        --this-month)
            this_month=1; debug "this month: yes"
            ;;

        -c|--cwd)
            cwd="$1"; debug "cwd: $cwd"
            shift
            ;;

        --)
            break
            ;;

        *)
            echo "Unexpected option: $opt"
            exit 1
            ;;
    esac
done

# generate git log query
log_query="git log"

if [[ -n "$author" ]]; then
    log_query=`echo "$log_query --author $author"`
fi

if [[ -n "$after" ]]; then
    log_query=`echo "$log_query --after $after"`
fi

if [[ -n "$before" ]]; then
    log_query=`echo "$log_query --before $before"`
fi

if [[ -n "$branch" ]]; then
    : # log_query=`echo "$log_query --branches $branch"`
fi

debug "git log query: $log_query"


# @param {string} $1 directory
# @param {int} $2 depth
git_repos(){
    # debug "seaching git repos in: $1"

    local current_depth="$2"
    local sub_depth=

    # or `expr` will throw a syntax error
    if [[ ! -n "$current_depth" ]]; then
        current_depth=0
    fi

    for file in $1/*
    do
        if [[ -d "$file" ]]; then
            if [[ -d "$file/.git" ]]; then
                # debug "git repo found: $file"
                cloc $file
            else
                if [[ "$current_depth" -gt "$recurse_depth" ]]; then
                    continue
                fi

                sub_depth=`expr $current_depth + 1`
                git_repos $file $sub_depth
            fi
        fi
    done
}


cloc_counter=0
result_array=()

cloc(){
    cd $1

    local last_commit=$(eval "$log_query --pretty=format:'%H' -1")

    # use `echo` to convert the stdout into a single line
    # cut the first part
    local first_commit=`echo $(eval "$log_query --pretty=format:'%H' --reverse") | cut -d ' ' -f1`
    local diff_result=
    local repo=`basename $1`

    # debug "first commit: $first_commit"
    # debug "last commit: $last_commit"

    # test if `first_commit` is already the earlist commit
    if git diff "$first_commit^1" "$last_commit" --shortstat 2> /dev/null; then
        first_commit=`echo "$first_commit^1"`
    fi

    if [[ -n "$last_commit" && -n "$first_commit" ]]; then
        diff_result=`git diff "$first_commit" "$last_commit" --shortstat`

        if [[ -n "$diff_result" ]]; then
            echo "git repo: $repo"
            echo "   $diff_result"

            result_array[$cloc_counter]="$diff_result"
            (( cloc_counter += 1 ))
        fi
    fi
}


summary(){
    local count=${#result_array[@]}

    local result=
    local result_i=0

    local info=
    local info_len=

    local slice=
    local slice_i=
    local slice_i_plus_one=

    local files=0
    local insertions=0
    local deletions=0

    while [[ $result_i -lt $count ]]; do

        result=${result_array[$result_i]}
        (( result_i += 1 ))

        info=( $result )
        info_len=${#info[@]}

        slice_i=0
        while [[ $slice_i -lt $info_len ]]; do

            slice=${info[$slice_i]}
            slice_i_plus_one=`expr $slice_i + 1`
            (( slice_i += 1 ))

            if [[ $slice_i_plus_one -ge $info_len ]]; then
                continue
            fi

            case ${info[$slice_i_plus_one]} in

                # file or files
                file* )
                    (( files += $slice )); # debug "files add $slice"
                    (( slice_i += 1 ))
                    ;;

                # insertions
                insertion* )
                    (( insertions += $slice )); # debug "insertions add $slice"
                    (( slice_i += 1 ))
                    ;;

                # deletions
                deletion* )
                    (( deletions += $slice )); # debug "deletions add $slice"
                    (( slice_i += 1 ))
                    ;;

                * )
                    ;;
            esac
        done # end while slice_i

    done # end while result_i

    echo
    echo "total:--------------------"
    echo "          repos: $count"
    echo "  changed files: $files"
    echo "     insertions: $insertions"
    echo "      deletions: $deletions"
}


if [[ -n "$recursive" ]]; then
    git_repos $cwd
else
    if [[ -d "$cwd/.git" ]]; then
        cloc $cwd
    else
        # TODO:
        # support sub directories of a git repo
        # (or any of the parent directories)
        echo "fatal: Not a git repository: .git"
        echo "Use '-r' option, if you wanna recursively search all git repos"
        exit 1
    fi
fi

summary

exit 0
