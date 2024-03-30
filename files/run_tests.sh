#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

debug() {
    echo -e "${YELLOW}[DEBUG] $1${NC}"
}

info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

        # append_testcase "$SERVICE_TYPE" "$i" "$ELAPSED_TIME"
# echo "<testsuite name=\"$TESTSUITE_NAME\" errors=\"0\" failures=\"0\" skipped=\"0\" tests=\"$TEST_COUNT\" time=\"$TESTSUITE_TIME\" timestamp=\"$TESTSUITE_TIMESTAMP\" hostname=\"$TESTSUITE_HOSTNAME\">" >> $REPORT_FILE
   # echo "<testcase classname=\"$SERVICE_TYPE\" name=\"$i\" time=\"$ELAPSED_TIME\"/>" >> "$REPORT_FILE"

mkdir -p results/{weather,currency}

TESTCASES_DIR="/testcases"
PYTHON_FILE=`find . -name "main.py" -type f`
GO_FILE=`find . -name "main.go" -type f`
MAIN_FILE=""
COMMAND=""

if [ -z "$PYTHON_FILE" ] && [ -z "$GO_FILE" ]; then
    error "Both PYTHON_FILE and GO_FILE are empty. Exiting the program."
    exit 1
fi

if [ -n "$PYTHON_FILE" ] && [ -f "$PYTHON_FILE" ]; then
    debug "Found Python application..."
    MAIN_FILE="$PYTHON_FILE"
    # Check if requirements.txt exists in the current directory
    if [ -f requirements.txt ]; then
        debug "requirements.txt found. Installing dependencies with pip..."
        pip install -r requirements.txt
    fi
    # Check if pyproject.toml exists in the current directory
    if [ -f pyproject.toml ]; then
        debug "pyproject.toml found. Installing dependencies with Poetry..."
        if ! command -v poetry &> /dev/null; then
            error "Poetry not found. Exiting..."
        fi
        poetry install
    else
        error "Neither requirements.txt nor pyproject.toml found. Skipping installation."
        exit 1
    fi
    COMMAND=""
fi

if [ -n "$GO_FILE" ] && [ -f "$GO_FILE" ]; then
    debug "Found Go application..."
    go mod tidy
    if [ $? -ne 0 ]; then
        error "Could not install Go dependencies"
        exit 1
    fi
    info "Project dependencies installed..."

    go build -o student_app $GO_FILE
    if [ $? -ne 0 ]; then
        error "Could not build Go application"
        exit 1
    fi
    info "App built successfully..."
    MAIN_FILE=`realpath ./student_app`
    COMMAND="$MAIN_FILE"
fi

export PORT=$(shuf -i 8181-9191 -n 1)

debug "Allocating port $PORT"

BASE_URL="http://localhost:$PORT"

# nohup let's us quit process's terminal without stopping it
nohup $COMMAND &
sleep 2

info "Figuring out which service type..."

curl -X GET $BASE_URL/info/ -o results/info.json >/dev/null 2>/dev/null

SERVICE_TYPE=`jq -r '.service' results/info.json`

if [ -z "$SERVICE_TYPE" ]; then
    error "No service type provided"
    exit 1
fi

debug "SERVICE_TYPE=$SERVICE_TYPE"


info "Generating test cases"

# TODO

info "Running tests..."

# Generating report
REPORT_FILE="report.xml"
TESTSUITE_NAME="Leha aboba"
TESTSUITE_TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S.%3N") # Текущая дата и время
TESTSUITE_HOSTNAME="DevOps"

TESTS_FAILED=0
TEST_COUNT=`ls $TESTCASES_DIR/$SERVICE_TYPE/answer* | wc -l`

echo '<?xml version="1.0" encoding="UTF-8"?>' > $REPORT_FILE
echo "<testsuites>" >> $REPORT_FILE
echo "<testsuite name=\"$TESTSUITE_NAME\" errors=\"0\" failures=\"0\" skipped=\"0\" tests=\"$TEST_COUNT\" time=\"0.0\" timestamp=\"$TESTSUITE_TIMESTAMP\" hostname=\"$TESTSUITE_HOSTNAME\">" >> $REPORT_FILE

append_testcase() {
    echo "    <testcase classname=\"$SERVICE_TYPE\" name=\"test_case_$i\" time=\"$ELAPSED_TIME\"/>" >> "$REPORT_FILE"
}

append_failed_testcase() {
    echo "    <testcase classname=\"$SERVICE_TYPE\" name=\"test_case_$i\" time=\"$ELAPSED_TIME\">" >> "$REPORT_FILE"
    echo "        <failure message=\"$ERROR_MESSAGE\"/>" >> "$REPORT_FILE"
    echo "    </testcase>" >> "$REPORT_FILE"
}

# START_TIME=$SECONDS
START_TIME=$(date +%s%N)

for ((i=1; i<=$TEST_COUNT; i++))
do
    PARAMS=`cat $TESTCASES_DIR/$SERVICE_TYPE/$i.params`
    # curl -X GET https://devopscourseapp-production.up.railway.app/info/$SERVICE_TYPE?$PARAMS -o results/$SERVICE_TYPE/response_$i.json >/dev/null 2>/dev/null

    # Измерение времени выполнения curl и сохранение результата в переменную
    TIME_RESULT=$( { time curl -X GET $BASE_URL/info/$SERVICE_TYPE?$PARAMS -o results/$SERVICE_TYPE/response_$i.json >/dev/null 2>&1; } 2>&1 )
    ELAPSED_TIME=$(echo "$TIME_RESULT" | grep 'real' | awk '{print $2}' | sed 's/s//g' | sed 's/0m//g' )
    TESTCASE_NAME="test_case_$i"

    echo "URL:        $BASE_URL/info/$SERVICE_TYPE?$PARAMS"
    echo "Parameters: $PARAMS"
    echo "Output:"
    jq . results/$SERVICE_TYPE/response_$i.json

    ERROR_MESSAGE=`python $TESTCASES_DIR/compare_results.py $SERVICE_TYPE $TESTCASES_DIR/$SERVICE_TYPE/answer_$i.json results/$SERVICE_TYPE/response_$i.json`
    if [ $? -ne 0 ]; then
        error "TEST $i FAILED"
        TESTS_FAILED=$TESTS_FAILED+1
        append_failed_testcase "$SERVICE_TYPE" "$i" "$ELAPSED_TIME" "$ERROR_MESSAGE"

        # kill $(pgrep -f `realpath "$MAIN_FILE"`)
        # exit 1
    else
        info "TEST $i PASSED"
        append_testcase "$SERVICE_TYPE" "$i" "$ELAPSED_TIME"
    fi
    echo "Real time: $ELAPSED_TIME"
done

END_TIME=$(date +%s%N)
TOTAL_TIME=$(echo "scale=3; ($END_TIME - $START_TIME)/1000000000" | bc)

debug $TOTAL_TIME_STRING

echo "</testsuite>" >> $REPORT_FILE
echo "</testsuites>" >> $REPORT_FILE

xmlstarlet ed --inplace -u "//testsuite/@failures" -x "$TESTS_FAILED" $REPORT_FILE
xmlstarlet ed --inplace -u "//testsuite/@time" -x "$TOTAL_TIME" $REPORT_FILE

info "JUnit report generated: $REPORT_FILE"

debug "Stopping server"

kill $(pgrep -f `realpath "$MAIN_FILE"`)
