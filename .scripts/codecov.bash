#!/bin/bash

set -e

VERSION="ed00ab8"

url="https://codecov.io"
verbose="0"
silent="0"
env=""
token=""
pr_o=""
pr=""
job=""
build_url=""
service=""
build_o=""
commit_o=""
branch_o=""
slug_o=""
dump="0"
files=""
gcov_ignore=""
ft_gcov="1"
ft_coveragepy="1"
_git_root=$(git rev-parse --show-toplevel || hg root || echo $PWD)
git_root="$_git_root"
if [ "$git_root" = "$PWD" ];
then
  git_root="."
fi
proj_root="$git_root"
gcov_exe="gcov"
gcov_arg=""

show_help() {
cat << EOF
Codecov $VERSION
Usage: ${0##*/} [-hv] [-f COVERAGE]
Upload reports to Codecov

    -h           Display this help and exit
    -f COVERAGE  Reference a specific file only to upload
                 When not specified commonly known coverage files will found
    -t TOKEN     Set the private repo token
                 (or) set environment variable CODECOV_TOKEN=:uuid
    -e ENV       Specify environment variables to be included with this build
                 ex. codecov -e VAR,VAR2
                 (or) set environment variable CODECOV_ENV=VAR,VAR2
    -X feature   Disable functionalities, accepting: 'gcov', 'coveragepy'
    -s silent    Enable silent mode

    -- Override CI Environment Variables --
       These variables are automatically detected by popular CI providers
    -B branch    Specify the branch name
    -C sha       Specify the commit sha
    -P pr        Specify the pull request number
    -b build     Specify the build number

    -- Debugging --
    -v           Verbose Mode
    -d           Dont upload and dump to stdin

    -- gcov --
    -g GLOB      Paths to ignore during gcov gathering
    -p dir       Project root directory (default: PWD, WORKSPACE, or TRAVIS_BUILD_DIR)
                 Also used when preparing gcov
    -x gcovexe   gcov executable to run. Defaults to 'gcov'
    -a gcovargs  extra arguments to pass to gcov

    -- Enterprise customers --
    -u URL       Set the target url for Enterprise customers [default https://codecov.io]
                 (or) set environment variable CODECOV_URL=https://my-hosted-codecov.com
    -r           owner/repo slug used instead of the private repo token in Enterprise
                 (or) set environment variable CODECOV_SLUG=:owner/:repo

Contribute and source at https://github.com/codecov/codecov-bash
EOF
}

say() {
  if [ "$silent" = "0" ];
  then
    echo "$1"
  fi
}

urlencode() {
  echo "$1" | curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "" | cut -c 3- | sed -e 's/%0A//'
}

if [ $# != 0 ];
then
  while getopts "svdhu:t:f:r:e:g:p:X:x:a:b:C:B:P:" o
  do
    case "$o" in
      "v")
        verbose="1"
        ;;
      "s")
        silent="1"
        ;;
      "d")
        dump="1"
        ;;
      "C")
        commit_o="$OPTARG"
        ;;
      "B")
        branch_o="$OPTARG"
        ;;
      "P")
        pr_o="$OPTARG"
        ;;
      "b")
        build_o="$OPTARG"
        ;;
      "h")
        show_help
        exit 0;
        ;;
      "u")
        url=$(echo "$OPTARG" | sed -e 's/\/$//')
        ;;
      "t")
        token="&token=$OPTARG"
        ;;
      "f")
        if [ "$files" = "" ];
        then
          files="$OPTARG"
        else
          files="$files $OPTARG"
        fi
        ;;
      "p")
        proj_root="$OPTARG"
        ;;
      "r")
        slug_o="$OPTARG"
        ;;
      "X")
        if [ "$OPTARG" = "gcov" ];
        then
          ft_gcov="0"
        elif [ "$OPTARG" = "coveragepy" ];
        then
          ft_coveragepy="0"
        fi
        ;;
      "g")
        gcov_ignore="$gcov_ignore -not -path '$OPTARG'"
        ;;
      "x")
        gcov_exe=$OPTARG
        ;;
      "a")
        gcov_arg=$OPTARG
        ;;
      "e")
        if [ "$env" = "" ];
        then
          env="$OPTARG"
        else
          env="$env,$OPTARG"
        fi
        ;;
    esac
  done
fi

say "Codecov"
say "(version) $VERSION"

if [ "$CODECOV_URL" != "" ];
then
  say "--> url set from env"
  url=$(echo "$CODECOV_URL" | sed -e 's/\/$//')
fi

say "(url) $url"
say "(git root) $git_root"

if [ "$CODECOV_TOKEN" != "" ];
then
  say "--> token set from env"
  token="&token=$CODECOV_TOKEN"
fi

if [ "$CODECOV_SLUG" != "" ];
then
  say "--> slug set from env"
  slug_o="$CODECOV_SLUG"
fi


if [ "$JENKINS_URL" != "" ];
then
  say "==> Jenkins CI detected."
  # https://wiki.jenkins-ci.org/display/JENKINS/Building+a+software+project
  # https://wiki.jenkins-ci.org/display/JENKINS/GitHub+pull+request+builder+plugin#GitHubpullrequestbuilderplugin-EnvironmentVariables
  service="jenkins"
  branch=$([ ! -z "$ghprbSourceBranch" ] && echo "$ghprbSourceBranch" || echo "$GIT_BRANCH")
  commit=$([ ! -z "$ghprbActualCommit" ] && echo "$ghprbActualCommit" || echo "$GIT_COMMIT")
  build="$BUILD_NUMBER"
  pr="$ghprbPullId"
  build_url=$(urlencode "$BUILD_URL")

elif [ "$CI" = "true" ] && [ "$TRAVIS" = "true" ];
then
  say "==> Travis CI detected."
  # http://docs.travis-ci.com/user/ci-environment/#Environment-variables
  service="travis-org"
  branch="$TRAVIS_BRANCH"
  commit="$TRAVIS_COMMIT"
  build="$TRAVIS_JOB_NUMBER"
  pr="$TRAVIS_PULL_REQUEST"
  job="$TRAVIS_JOB_ID"
  slug="$TRAVIS_REPO_SLUG"

elif [ "$CI" = "true" ] && [ "$BUILDKITE" = "true" ];
then
  say "==> BuildKite CI detected."
  # http://docs.travis-ci.com/user/ci-environment/#Environment-variables
#  service="buildkite"
  branch="$BUILDKITE_BRANCH"
  commit="$BUILDKITE_COMMIT"
#  build="$BUILDKITE_BUILD_NUMBER"
#  pr="$BUILDKITE_PULL_REQUEST"
#  job="$BUILDKITE_BUILD_ID"
#  slug="$BUILDKITE_PROJECT_SLUG"

elif [ "$CI" = "true" ] && [ "$CI_NAME" = "codeship" ];
then
  say "==> Codeship CI detected."
  # https://www.codeship.io/documentation/continuous-integration/set-environment-variables/
  service="codeship"
  branch="$CI_BRANCH"
  build="$CI_BUILD_NUMBER"
  build_url=$(urlencode "$CI_BUILD_URL")
  commit="$CI_COMMIT_ID"

elif [ "$CI" = "true" ] && [ "$CIRCLECI" = "true" ];
then
  say "==> Circle CI detected."
  # https://circleci.com/docs/environment-variables
  service="circleci"
  branch="$CIRCLE_BRANCH"
  build="$CIRCLE_BUILD_NUM.$CIRCLE_NODE_INDEX"
  slug="$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME"
  pr="$CIRCLE_PR_NUMBER"
  commit="$CIRCLE_SHA1"

elif [ "$CI" = "true" ] && [ "$SEMAPHORE" = "true" ];
then
  say "==> Semaphore CI detected."
  # https://semaphoreapp.com/docs/available-environment-variables.html
  service="semaphore"
  branch="$BRANCH_NAME"
  build="$SEMAPHORE_BUILD_NUMBER.$SEMAPHORE_CURRENT_THREAD"
  slug="$SEMAPHORE_REPO_SLUG"
  commit="$REVISION"

elif [ "$CI" = "true" ] && [ "$DRONE" = "true" ];
then
  say "==> Drone CI detected."
  # http://docs.drone.io/env.html
  # drone commits are not full shas
  service="drone.io"
  branch="$DRONE_BRANCH"
  build="$DRONE_BUILD_NUMBER"
  build_url=$(urlencode "$DRONE_BUILD_URL")
  commit=$(git rev-parse HEAD || hg id -i --debug | tr -d '+')

elif [ "$CI" = "True" ] && [ "$APPVEYOR" = "True" ];
then
  say "==> Appveyor CI detected."
  # http://www.appveyor.com/docs/environment-variables
  service="appveyor"
  branch="$APPVEYOR_REPO_BRANCH"
  build="$APPVEYOR_JOB_ID"
  pr="$APPVEYOR_PULL_REQUEST_NUMBER"
  job="$APPVEYOR_ACCOUNT_NAME/$APPVEYOR_PROJECT_SLUG/$APPVEYOR_BUILD_VERSION"
  slug="$APPVEYOR_REPO_NAME"
  commit="$APPVEYOR_REPO_COMMIT"

elif [ "$CI" = "true" ] && [ "$WERCKER_GIT_BRANCH" != "" ];
then
  say "==> Wercker CI detected."
  # http://devcenter.wercker.com/articles/steps/variables.html
  service="wercker"
  branch="$WERCKER_GIT_BRANCH"
  build="$WERCKER_MAIN_PIPELINE_STARTED"
  slug="$WERCKER_GIT_OWNER/$WERCKER_GIT_REPOSITORY"
  commit="$WERCKER_GIT_COMMIT"

elif [ "$CI" = "true" ] && [ "$MAGNUM" = "true" ];
then
  say "==> Magnum CI detected."
  # https://magnum-ci.com/docs/environment
  service="magnum"
  branch="$CI_BRANCH"
  build="$CI_BUILD_NUMBER"
  commit="$CI_COMMIT"

elif [ "$CI" = "true" ] && [ "$SNAP_CI" = "true" ];
then
  say "==> Snap CI detected."
  # https://docs.snap-ci.com/environment-variables/
  service="snap"
  branch=$([ "$SNAP_BRANCH" != "" ] && echo "$SNAP_BRANCH" || echo "$SNAP_UPSTREAM_BRANCH")
  build="$SNAP_PIPELINE_COUNTER"
  pr="$SNAP_PULL_REQUEST_NUMBER"
  commit=$([ "$SNAP_COMMIT" != "" ] && echo "$SNAP_COMMIT" || echo "$SNAP_UPSTREAM_COMMIT")

elif [ "$SHIPPABLE" = "true" ];
then
  say "==> Shippable CI detected."
  # http://docs.shippable.com/en/latest/config.html#common-environment-variables
  service="shippable"
  branch="$BRANCH"
  build="$BUILD_NUMBER"
  build_url=$(urlencode "$BUILD_URL")
  pr="$PULL_REQUEST"
  slug="$REPO_NAME"
  commit="$COMMIT"

elif [ "$CI_SERVER_NAME" = "GitLab CI" ];
then
  say "==> GitLab CI detected."
  # http://doc.gitlab.com/ci/examples/README.html#environmental-variables
  # https://gitlab.com/gitlab-org/gitlab-ci-runner/blob/master/lib/build.rb#L96
  service="gitlab"
  branch="$CI_BUILD_REF_NAME"
  build="$CI_BUILD_ID"
  slug=$(echo "$CI_BUILD_REPO" | cut -d'/' -f4-5 | sed -e 's/.git//')
  commit="$CI_BUILD_REF"


else
  # find branch, commit, repo from git command
  say "==> No CI detected, using git/mercurial for branch and commit sha."
  if [ "$GIT_BRANCH" != "" ];
  then
    branch="$GIT_BRANCH"
  else
    branch=$(git rev-parse --abbrev-ref HEAD || hg branch)
    if [ "$branch" = "HEAD" ]; then branch=""; fi
  fi

  if [ "$GIT_COMMIT" != "" ];
  then
    commit="$GIT_COMMIT"
  else
    commit=$(git rev-parse HEAD || hg id -i --debug | tr -d '+')
  fi

fi

query="branch=$([ "$branch_o" = "" ] && echo "$branch" || echo "$branch_o")\
       &commit=$([ "$commit_o" = "" ] && echo "$commit" || echo "$commit_o")\
       &build=$([ "$build_o" = "" ] && echo "$build" || echo "$build_o")\
       &build_url=$build_url\
       &slug=$([ "$slug_o" = "" ] && echo "$slug" || echo "$slug_o")\
       &service=$service\
       &pr=$([ "$pr_o" = "" ] && echo "$pr" || echo "$pr_o")\
       &job=$job"

# detect bower comoponents location
bower_components="bower_components"
bower_rc=$(find "$git_root" -name .bowerrc)
if [ "$bower_rc" != "" ];
then
  bower_components=$(cat "$bower_rc" | tr -d '\n' | grep '"directory"' | cut -d'"' -f4 | sed -e 's/\/$//')
  if [ "$bower_components" = "" ];
  then
    bower_components="bower_components"
  fi
fi

# find all the reports
if [ "$files" != "" ];
then
  say "==> Targeting specific file(s)"

else

  if [ "$ft_gcov" = "1" ];
  then

      # xcode 7 profdata
      profdata=$(find $proj_root -name 'Coverage.profdata' | head -1)
      if [ -f "$profdata" ];
      then
        _dir=$(dirname "$profdata")
        for _type in app framework xctest
        do
          _file=$(find "$_dir" -name "*.$_type" | head -1)
          if [ "$_file" != "" ];
          then
            _proj=${_file##*/}
            _proj=${_proj%."$_type"}
            xcrun llvm-cov show -instr-profile "$profdata" "$_file/$_proj" > "$_type.coverage.txt" || true
          fi
        done
      fi

    say "    Searching for gcov via (find $proj_root -type f -name '*.gcno' $gcov_ignore -exec $gcov_exe $gcov_arg {} +)"

    # all other gcov
    bash -c "find $proj_root -type f -name '*.gcno' $gcov_ignore -exec $gcov_exe $gcov_arg {} +" || true

  else
    say '**> gcov disable'
  fi

  say "==> Searching for coverage reports"
  files=$(find "$git_root" -type f \( -name '*coverage.*' \
                     -or -name 'nosetests.xml' \
                     -or -name 'jacoco*.xml' \
                     -or -name 'clover.xml' \
                     -or -name 'report.xml' \
                     -or -name 'cobertura.xml' \
                     -or -name 'luacov.report.out' \
                     -or -name 'lcov.info' \
                     -or -name '*.lcov' \
                     -or -name 'gcov.info' \
                     -or -name '*.gcov' \
                     -or -name '*.lst' \) \
                    -not -name '*.sh' \
                    -not -name '*.py' \
                    -not -name 'Coverage.profdata' \
                    -not -name 'phpunit-code-coverage.xml' \
                    -not -name 'coverage.serialized' \
                    -not -name '*.pyc' \
                    -not -name '*.cfg' \
                    -not -name '*.egg' \
                    -not -name '*.whl' \
                    -not -name '*.html' \
                    -not -name '*.js' \
                    -not -name '*.cpp' \
                    -not -name 'coverage.jade' \
                    -not -name 'include.lst' \
                    -not -name 'inputFiles.lst' \
                    -not -name 'createdFiles.lst' \
                    -not -name 'coverage.html' \
                    -not -name 'scoverage.measurements.*' \
                    -not -name 'test_*_coverage.txt' \
                    -not -path '*/vendor/*' \
                    -not -path '*/htmlcov/*' \
                    -not -path '*/home/cainus/*' \
                    -not -path '*/virtualenv/*' \
                    -not -path '*/js/generated/coverage/*' \
                    -not -path '*/.virtualenv/*' \
                    -not -path '*/virtualenvs/*' \
                    -not -path '*/.virtualenvs/*' \
                    -not -path '*/.env/*' \
                    -not -path '*/.envs/*' \
                    -not -path '*/env/*' \
                    -not -path '*/envs/*' \
                    -not -path '*/.venv/*' \
                    -not -path '*/.venvs/*' \
                    -not -path '*/venv/*' \
                    -not -path '*/venvs/*' \
                    -not -path '*/.git/*' \
                    -not -path '*/.hg/*' \
                    -not -path '*/.tox/*' \
                    -not -path '*/__pycache__/*' \
                    -not -path '*/.egg-info*' \
                    -not -path "*/$bower_components/*" \
                    -not -path '*/node_modules/*' \
                    -not -path '*/conftest_*.c.gcov')

  # Python coveragepy generation
  if [ "$ft_coveragepy" = "1" ];
  then
    if which coverage >/dev/null 2>&1;
    then
      say "==> Python coveragepy exists (disable via -X coveragepy)"

      # find the .coverage
      if [ "$verbose" = "1" ];
      then
        say "    -> Searching for .coverage file"
        find "$git_root" \( -name '.coverage' -or -name '.coverage.*' \) -not -path '.coveragerc'
      fi
      dotcoverage=$(find "$git_root" \( -name '.coverage' -or -name '.coverage.*' \) -not -path '.coveragerc' | head -1)
      say "    -> $dotcoverage"
      cd "$(dirname "$dotcoverage")"
      if [ "$dotcoverage" != "" ];
      then
        say "    Running coverage xml"
        if [ "$(coverage xml -i)" != "No data to report." ];
        then
          files="$files
coverage.xml"
        else
          say "    No data to report."
        fi
      else
        say "    No .coverage file found."
      fi
    else
      say "**> Python coverage not found"
    fi
  else
    say "**> Python coverage disabled"
  fi
fi

# no files found
if [ "$files" = "" ];
then
  say "**> No coverage report found."
  exit 1;
fi

say "==> Detecting git/mercurial file structure"
upload="$(cd "$git_root" && git ls-files || hg locate)
<<<<<< network"

# Append Environment Variables
if [ "$env" != "" ] || [ "$CODECOV_ENV" != "" ];
then
  inc_env=""
  say "==> Appending build variables"
  if [ "$CODECOV_ENV" != "" ];
  then
    for e in $(echo "$CODECOV_ENV" | tr ',' ' ')
    do
      say "    + $e"
      inc_env="$inc_env$e=$(eval echo "\$$e")
"
    done
  fi

  if [ "$env" != "" ];
  then
    for e in $(echo "$env" | tr ',' ' ')
    do
      say "    + $e"
      inc_env="$inc_env$e=$(eval echo "\$$e")
"
    done
  fi

  upload="$inc_env<<<<<< ENV
$upload"
fi

# Append Reports
say "==> Reading reports"
for file in $files
do
  # escape file paths
  file=$(echo "$file" | sed -e 's/ /\\ /')
  # read the coverage file
  if [ -f "$file" ];
  then
    report=$(cat "$file")
    say "    + $file bytes=${#report}"
    # append to to upload
    upload="$upload
# path=$(echo "$file" | sed "s|^$_git_root/||")
$report
<<<<<< EOF"
  else
    say "    -> File not found at $file"
  fi
done

# trim whitespace from query
query=$(echo "package=bash-$VERSION&$query$token" | tr -d ' ')
say "(query) $query"

if [ "$dump" != "0" ];
then
  echo "$url/upload/v2?$query"
  echo "$upload"
else
  say "==> Uploading reports"
  res=$(curl -sX POST "$url/upload/v3?$query")
  s3=$(echo "$upload" | \
       curl -isX PUT --data-binary @- \
            -H 'Content-Type: plain/text' -H 'x-amz-acl: public-read' \
            "$(echo "$res" | sed -n 2p)" | grep 'HTTP/1.1 ' | tail -1 | cut -d' ' -f2)
  if [ "$s3" != "200" ];
  then
    # just incase, try traditional upload FUTURE ^s3=$s3
    res=$(echo "$upload" | curl -sX POST --data-binary @- "$url/upload/v2?$query")
    say "    $res"
  else
    say "    Finished"
    say "    $(echo "$res" | sed -n 1p)"
  fi

fi

# EOF
