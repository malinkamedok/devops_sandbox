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

send_telegram_alert() {
    ### debug. all data should be taken from env
    # BOT_API_TOKEN="000000000:gegrergervreRGVFWERVevervEEWV"
    # CHAT_ID="-22822822822822"
    # CI_PROJECT_NAME="p.solovev"

    if [ -n "$BOT_API_TOKEN" ]; then
        curl -X POST "https://api.telegram.org/bot$BOT_API_TOKEN/sendMessage" -d "chat_id=$CHAT_ID&text=$MESSAGE" >/dev/null 2>/dev/null
        echo
    fi
}

prepare_artifacts() {
    debug "Preparing job artifacts"
    mv nohup.out server.log
    mv -r results/$SERVICE_TYPE responses
}

mkdir -p results/{weather,currency}

TESTCASES_DIR="/testcases"
PYTHON_FILE=$(find . -name "main.py" -type f | grep -v 'venv')
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
        debug "requirements.txt found. Installing dependencies via pip..."
        rm -rf venv
        python -m venv venv
        source ./venv/bin/activate
        pip install -r requirements.txt
    # Check if pyproject.toml exists in the current directory
    elif [ -f pyproject.toml ]; then
        debug "pyproject.toml found. Installing dependencies via Poetry..."
        if ! command -v poetry &> /dev/null; then
            error "Poetry not found. Exiting..."
            exit 1
        fi
        poetry install
    else
        error "Neither requirements.txt nor pyproject.toml found. Skipping installation."
        exit 1
    fi
    COMMAND="python $MAIN_FILE"
    MAIN_FILE=`realpath $PYTHON_FILE`
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

stop_server() {
    END_TIME=$(date +%s%N)
    TOTAL_TIME=$(echo "scale=3; ($END_TIME - $START_TIME)/1000000000" | bc)

    echo "</testsuite>" >> $REPORT_FILE
    echo "</testsuites>" >> $REPORT_FILE

    xmlstarlet ed --inplace -u "//testsuite/@failures" -x "$TESTS_FAILED" $REPORT_FILE
    xmlstarlet ed --inplace -u "//testsuite/@time" -x "$TOTAL_TIME" $REPORT_FILE
    xmlstarlet ed --inplace -u "//testsuite/@tests" -x "$TEST_COUNT" $REPORT_FILE

    info "JUnit report generated: $REPORT_FILE"

    debug "Stopping server"

    kill $(pgrep -f "$COMMAND")

    MESSAGE=$(echo -e "Student: $CI_PROJECT_NAME\nService: $SERVICE_TYPE\nTests failed: $TESTS_FAILED.\n" | jq -sRr @uri)
    send_telegram_alert

    prepare_artifacts
}

export PORT=$(shuf -i 8181-9191 -n 1)

debug "Allocating port $PORT"

BASE_URL="http://localhost:$PORT"

# nohup let's us quit process's terminal without stopping it
nohup $COMMAND &

sleep 5

info "Figuring out which service type..."
debug "curl -X GET $BASE_URL/info -o results/info.json"

curl -X GET $BASE_URL/info -o results/info.json >/dev/null 2>/dev/null

jq . results/info.json || (cat results/info.json && echo)


SERVICE_TYPE=`jq -r '.service' results/info.json`
debug "SERVICE_TYPE=$SERVICE_TYPE"
if [ "$SERVICE_TYPE" != "weather" ] && [ "$SERVICE_TYPE" != "currency" ]; then
    error "Wrong or empty service type provided"
    exit 1
fi


if [ $SERVICE_TYPE == "weather" ] && [ -z "$API_KEY" ]; then
    error "Environment variable API_KEY must not be empty. Add it to Settings > CI/CD > Variables"
    exit 1
fi

info "Running static tests..."

# Generating report
REPORT_FILE="report.xml"
TESTSUITE_TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S.%3N") # Текущая дата и время
TESTSUITE_HOSTNAME="DevOps"

TESTS_FAILED=0
TEST_COUNT=0
STATIC_TEST_COUNT=`ls $TESTCASES_DIR/$SERVICE_TYPE/answer* | wc -l`

echo '<?xml version="1.0" encoding="UTF-8"?>' > $REPORT_FILE
echo "<testsuites>" >> $REPORT_FILE
echo "<testsuite name=\"$SERVICE_TYPE\" errors=\"0\" failures=\"0\" skipped=\"0\" tests=\"$TEST_COUNT\" time=\"0.0\" timestamp=\"$TESTSUITE_TIMESTAMP\" hostname=\"$TESTSUITE_HOSTNAME\">" >> $REPORT_FILE

append_testcase() {
    echo "    <testcase classname=\"$SERVICE_TYPE\" name=\"$TESTCASE_NAME\" time=\"$ELAPSED_TIME\"/>" >> "$REPORT_FILE"
}

append_failed_testcase() {
    echo "    <testcase classname=\"$SERVICE_TYPE\" name=\"$TESTCASE_NAME\" time=\"$ELAPSED_TIME\">" >> "$REPORT_FILE"
    echo "        <failure message=\"$ERROR_MESSAGE\"/>" >> "$REPORT_FILE"
    echo "    </testcase>" >> "$REPORT_FILE"
}

START_TIME=$(date +%s%N)

for ((i=1; i<=$STATIC_TEST_COUNT; i++))
do
    TEST_COUNT=$((TEST_COUNT+1))
    PARAMS=`cat $TESTCASES_DIR/$SERVICE_TYPE/$i.params`

    TIME_RESULT=$( { time curl -X GET $BASE_URL/info/$SERVICE_TYPE?$PARAMS -o results/$SERVICE_TYPE/response_$i.json >/dev/null 2>&1; } 2>&1 )
    ELAPSED_TIME=$(echo "$TIME_RESULT" | grep 'real' | awk '{print $2}' | sed 's/s//g' | sed 's/0m//g' )
    TESTCASE_NAME="test_case_$i"

    echo "URL:        $BASE_URL/info/$SERVICE_TYPE?$PARAMS"
    echo "Parameters: $PARAMS"
    echo "Output:"
    jq . results/$SERVICE_TYPE/response_$i.json 2>/dev/null || cat results/$SERVICE_TYPE/response_$i.json
    echo

    ERROR_MESSAGE=`python $TESTCASES_DIR/compare_results.py $SERVICE_TYPE $TESTCASES_DIR/$SERVICE_TYPE/answer_$i.json results/$SERVICE_TYPE/response_$i.json`
    if [ $? -ne 0 ]; then
        error "TEST $i FAILED"
        TESTS_FAILED=$((TESTS_FAILED+1))
        append_failed_testcase "$SERVICE_TYPE" "$TESTCASE_NAME" "$ELAPSED_TIME" "$ERROR_MESSAGE"
    else
        info "TEST $i PASSED"
        append_testcase "$SERVICE_TYPE" "$TESTCASE_NAME" "$ELAPSED_TIME"
    fi
    echo "Real time: $ELAPSED_TIME"
done

if [ "$TESTS_FAILED" -ne 0 ]; then
    stop_server
    exit 1
fi

info "Static tests ended. Generating live tests..."

for i in {1..2}
do
    YYYY=$(shuf -i 2017-2023 -n 1)
    MM=$(printf "%02d" $(shuf -i 1-12 -n 1))
    DD=$(shuf -i 1-26 -n 1)
    DD_TO=$(printf "%02d" $((DD + $(shuf -i 1-2 -n 1))))
    DD=$(printf "%02d" $DD)

    PARAMS=`cat $TESTCASES_DIR/$SERVICE_TYPE/$i.params.live`

    if [ "$SERVICE_TYPE" == "currency" ]; then
        curl -X GET https://devopscourseapp-production.up.railway.app/info/$SERVICE_TYPE?$PARAMS$YYYY-$MM-$DD -o $TESTCASES_DIR/$SERVICE_TYPE/live_answer_$i.json >/dev/null 2>/dev/null

        TIME_RESULT=$( { time curl -X GET $BASE_URL/info/$SERVICE_TYPE?$PARAMS$YYYY-$MM-$DD -o results/$SERVICE_TYPE/live_response_$i.json >/dev/null 2>&1; } 2>&1 )

        echo "URL:        $BASE_URL/info/$SERVICE_TYPE?$PARAMS$YYYY-$MM-$DD"
        echo "Parameters: $PARAMS$YYYY-$MM-$DD"
    else
        ADDITIONAL=`cat $TESTCASES_DIR/$SERVICE_TYPE/additional.live`
        RESPONSE_FILE="results/$SERVICE_TYPE/live_answer_$i.json"
        MAX_ATTEMPTS=7

        for ((j=1; j<=MAX_ATTEMPTS; j++)); do
            curl -X GET "https://devopscourseapp-production.up.railway.app/info/$SERVICE_TYPE?$PARAMS$YYYY-$MM-$DD$ADDITIONAL$YYYY-$MM-$DD_TO" -o $RESPONSE_FILE >/dev/null 2>/dev/null

            # if echo curl -f != 0
            if jq -e '.error == "You have exceeded the maximum number of daily result records for your account. Please add a credit card to continue retrieving results."' $RESPONSE_FILE >/dev/null; then
                echo "API key for the verification process has been exceeded. Attempt $j of $MAX_ATTEMPTS. Trying another one..."
            else
                break
            fi

            if [ $j -eq $MAX_ATTEMPTS ]; then
                echo "Maximum number of attempts have been reached. Please try again tomorrow."

                MESSAGE=$(echo -e "Student: $CI_PROJECT_NAME\nService: $SERVICE_TYPE\nTests failed: $TESTS_FAILED.\nAll API keys have exceeded. Tried $j times.\n" | jq -sRr @uri)
                send_telegram_alert

                stop_server
                exit 1
            fi
        done

        TIME_RESULT=$( { time curl -X GET $BASE_URL/info/$SERVICE_TYPE?$PARAMS$YYYY-$MM-$DD$ADDITIONAL$YYYY-$MM-$DD_TO -o results/$SERVICE_TYPE/live_response_$i.json >/dev/null 2>&1; } 2>&1 )

        TEST_COUNT=$((TEST_COUNT+1))

        echo "URL:        $BASE_URL/info/$SERVICE_TYPE?$PARAMS$YYYY-$MM-$DD$ADDITIONAL$YYYY-$MM-$DD_TO"
        echo "Parameters: $PARAMS$YYYY-$MM-$DD$ADDITIONAL$YYYY-$MM-$DD_TO"
    fi

    ELAPSED_TIME=$(echo "$TIME_RESULT" | grep 'real' | awk '{print $2}' | sed 's/s//g' | sed 's/0m//g' )
    TESTCASE_NAME="live_test_case_$i"

    echo "Output:"
    jq . results/$SERVICE_TYPE/live_response_$i.json 2>/dev/null || cat results/$SERVICE_TYPE/live_response_$i.json
    echo

    ERROR_MESSAGE=`python $TESTCASES_DIR/compare_results.py $SERVICE_TYPE $TESTCASES_DIR/$SERVICE_TYPE/live_answer_$i.json results/$SERVICE_TYPE/live_response_$i.json`
    if [ $? -ne 0 ]; then
        error "LIVE TEST $i FAILED"
        TESTS_FAILED=$((TESTS_FAILED+1))
        append_failed_testcase "$SERVICE_TYPE" "$TESTCASE_NAME" "$ELAPSED_TIME" "$ERROR_MESSAGE"
    else
        info "LIVE TEST $i PASSED"
        append_testcase "$SERVICE_TYPE" "$TESTCASE_NAME" "$ELAPSED_TIME"
    fi
    echo "Real time: $ELAPSED_TIME"
done

if [ $TESTS_FAILED -eq 0 ]; then
    info "Congratulations! All tests passed!"
else
    echo -e "${RED}Not all tests were passed. Keep going!${NC}"
fi

stop_server
